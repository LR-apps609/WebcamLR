using System.Net.Sockets;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using Windows.Storage.Streams;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Collega la finestra al ricevitore: annuncio in rete, QR code, telefono collegato, latenza.
/// Il video si vede in finestra (AnteprimaVideo); la webcam virtuale arriva con il round 3.
/// La logica di rete è in WebcamLR.Ricevitore, provata con i test.
/// </summary>
public sealed partial class MainWindow : Window
{
    private static readonly TimeSpan AttesaRiconnessione = TimeSpan.FromSeconds(15);

    private readonly DispatcherQueue coda;
    private readonly Ascoltatore ascoltatore;
    /// <summary>Il cavo USB (1.7), attraverso il servizio di Apple dell'app «Dispositivi Apple».</summary>
    private readonly ClienteUsbmux cavo = new();
    /// Vero dopo che l'utente ha chiuso il suggerimento per il cavo: non torna fino al prossimo avvio.
    private bool suggerimentoCavoChiuso;
    /// <summary>Registro del collegamento (1.5): gli ultimi 50 eventi, solo in memoria, visibile in modalità avanzata.</summary>
    private readonly RegistroCollegamento registro = new();
    private bool modalitaAvanzata;
    /// <summary>Diagnosi (1.3): cosa impedisce il collegamento, dal più grave.</summary>
    private IReadOnlyList<ProblemaCollegamento> problemi = [];
    private readonly DispatcherQueueTimer controlloDiagnosi;
    /// <summary>Riparte a ogni avviso di cambio rete: scatta quando gli avvisi smettono di arrivare.</summary>
    private readonly DispatcherQueueTimer reteAssestata;
    /// Cresce a ogni controllo: un controllo più vecchio che finisce dopo non rimette la situazione di prima.
    private int richiesteDiagnosi;
    /// <summary>Collegamento sicuro (0.10): la chiave del PC e i telefoni fidati.</summary>
    private readonly Abbinamento abbinamento;
    /// <summary>Si rinnova dopo un cambio di rete, il risveglio o l'ascolto riaperto (1.12).</summary>
    private AnnuncioWindows annuncio;
    /// <summary>L'avviso di Windows al risveglio dallo stop; il controllo dell'orologio fa da riserva.</summary>
    private readonly RisveglioWindows risveglio = new();
    private readonly SorveglianzaRisveglio sorveglianzaRisveglio = new();
    private readonly DispatcherQueueTimer controlloRisveglio;
    /// <summary>Unisce gli avvisi di risveglio (Windows ne manda due, e c'è anche l'orologio) in uno solo.</summary>
    private readonly DispatcherQueueTimer risveglioAssestato;
    private readonly AnteprimaVideo anteprima = new();
    private readonly IconaTray iconaTray;
    private readonly Notifiche notifiche;
    private readonly SorveglianzaAvvisi sorveglianzaAvvisi = new();
    /// Le notifiche servono solo quando la finestra non è davanti: altrimenti basta quello che si vede.
    private bool inPrimoPiano;
    /// Null solo se Windows non dice dov'è l'exe: allora l'interruttore resta spento e disattivato.
    private readonly AvvioConWindows? avvioConWindows =
        Environment.ProcessPath is { } percorso ? new AvvioConWindows(new RegistroWindows(), percorso) : null;
    private bool aggiornoAvvio;
    /// Vero solo quando si sceglie «Esci»: altrimenti chiudere la finestra la nasconde.
    private bool uscita;
    private SessioneComputer? sessione;
    /// Tiene insieme il controllo della precedenza del cavo e lo scambio della sessione (thread di rete).
    private readonly object sceltaSessione = new();
    private StatoCollegamento statoCollegamento;
    private Ciao? telefono;
    /// Il codice di sicurezza del telefono mostrato: «lo stesso telefono» si decide da questo, non dal nome
    /// (due telefoni chiamati entrambi «iPhone» sono telefoni diversi; Documenti/Protocollo.md, «Riconoscere il telefono»).
    private string? improntaTelefono;
    /// Come è collegato il telefono mostrato (1.2); null se non si sa.
    private TipoCollegamento? collegamento;
    private StatoTelefono? statoTelefono;
    private Statistiche? statistiche;
    /// «Avvio: 0,9 s» della sessione mostrata (1.11); null finché il primo fotogramma non è a schermo.
    private string? testoAvvio;
    /// La latenza degli ultimi 60 secondi, per il grafico accanto alle statistiche.
    private readonly StoriaLatenza storiaLatenza = new();
    /// Vero mentre la finestra imposta i comandi da codice: in quel caso non si manda nulla al telefono.
    private bool aggiornoComandi;

    public MainWindow()
    {
        InitializeComponent();
        // Aspetto di Windows 11 (round 2, funzione 50): sfondo Mica dietro la colonna di sinistra,
        // le altre restano sui pannelli. Su Windows 10 Mica non c'è e resta il fondo pieno.
        if (Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported())
        {
            SystemBackdrop = new MicaBackdrop();
            Radice.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        }
        RipristinaPosizione();
        AppWindow.SetIcon("Assets/WebcamLR.ico");
        coda = DispatcherQueue.GetForCurrentThread();

        abbinamento = new Abbinamento(Preferenze.Identita(), Preferenze.TelefoniFidati,
            fidati => Preferenze.TelefoniFidati = new Dictionary<string, string>(fidati));
        // Gettone usato da un telefono: il QR code ne mostra subito uno nuovo.
        abbinamento.GettoneCambiato += () => coda.TryEnqueue(() => _ = MostraQRAsync());
        abbinamento.ChiediConferma = ChiediConfermaAsync;

        // Le schede di rete lette una volta in anticipo: la prima connessione non le aspetta (1.11).
        _ = Task.Run(Collegamenti.AggiornaSchede);
        ascoltatore = new Ascoltatore();
        // L'ascolto caduto si riapre da solo (1.12): annuncio e QR con la porta di adesso.
        ascoltatore.Riaperto += porta => coda.TryEnqueue(() =>
        {
            registro.Aggiungi($"Ascolto riaperto sulla porta {porta}");
            _ = RiannunciaAsync();
            _ = MostraQRAsync();
            AggiornaTelefono();
        });
        // Accettata subito sul thread di rete, senza aspettare il thread dell'interfaccia (1.11): se la finestra
        // è occupata (si sta disegnando, una finestra di dialogo si apre) la stretta di mano non resta ferma.
        ascoltatore.NuovoTelefono += presa => Accetta(presa, viaCavo: false, Orologio.Adesso());
        // Il cavo dà connessioni come quelle del Wi-Fi: stessa accettazione, stessa sicurezza.
        cavo.TelefonoViaCavo += presa => Accetta(presa, viaCavo: true, Orologio.Adesso());
        // Il primo fotogramma a schermo chiude la misura dell'avvio (1.11) della sessione attuale.
        anteprima.PrimaImmagine += () =>
        {
            if (Volatile.Read(ref sessione) is not { } attuale || !attuale.Avvio.Mostrato()) return;
            if (attuale.Avvio.Riga is { } riga) registro.Aggiungi(riga);
            var testo = attuale.Avvio.Testo;
            coda.TryEnqueue(() =>
            {
                if (sessione != attuale) return;
                testoAvvio = testo;
                AggiornaTelefono();
            });
        };
        cavo.StatoCambiato += stato =>
        {
            registro.Aggiungi(stato switch
            {
                StatoCavo.Collegato => "Cavo USB: collegato",
                StatoCavo.InAscolto => "Cavo USB: in ascolto",
                _ => "Cavo USB: servizio di Apple assente",
            });
            coda.TryEnqueue(() => _ = AggiornaDiagnosiAsync());
        };
        cavo.Evento += testo =>
        {
            registro.Aggiungi(testo);
            coda.TryEnqueue(() => _ = AggiornaDiagnosiAsync());
        };
        registro.Cambiato += () => coda.TryEnqueue(MostraRegistro);
        BarraCavo.CloseButtonClick += (_, _) => suggerimentoCavoChiuso = true;
        // Il permesso del firewall o il profilo della rete cambiano senza avvisare: senza telefono si ricontrolla.
        controlloDiagnosi = coda.CreateTimer();
        controlloDiagnosi.Interval = TimeSpan.FromSeconds(10);
        controlloDiagnosi.Tick += (_, _) => { if (statoCollegamento == StatoCollegamento.NessunTelefono) _ = AggiornaDiagnosiAsync(); };
        controlloDiagnosi.Start();
        reteAssestata = coda.CreateTimer();
        reteAssestata.Interval = TimeSpan.FromSeconds(1.5);
        reteAssestata.IsRepeating = false;
        reteAssestata.Tick += (_, _) => _ = DopoCambioReteAsync();
        risveglioAssestato = coda.CreateTimer();
        risveglioAssestato.Interval = TimeSpan.FromSeconds(1);
        risveglioAssestato.IsRepeating = false;
        risveglioAssestato.Tick += (_, _) => DopoRisveglio();
        risveglio.Risvegliato += () => coda.TryEnqueue(SuRisveglio);
        controlloRisveglio = coda.CreateTimer();
        controlloRisveglio.Interval = TimeSpan.FromSeconds(5);
        controlloRisveglio.Tick += (_, _) => { if (sorveglianzaRisveglio.Controlla(DateTime.UtcNow)) SuRisveglio(); };
        controlloRisveglio.Start();
        cavo.Avvia();
        annuncio = new AnnuncioWindows((ushort)ascoltatore.Porta);
        _ = MostraQRAsync();
        // Cambio di Wi-Fi o cavo collegato: il QR deve avere gli indirizzi nuovi.
        System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += SuCambioRete;
        registro.Aggiungi($"WebcamLR avviata · porta {ascoltatore.Porta}");
        Mostra(StatoCollegamento.NessunTelefono);
        _ = AggiornaDiagnosiAsync();
        ImpostaModalitaAvanzata(Preferenze.ModalitaAvanzata, salva: false);

        AggiungiScorciatoie();
        AppWindow.Changed += SuCambioFinestra;
        ScorrimentoAnteprima.SizeChanged += SuDimensioniAnteprima;
        PulsanteSpecchia.IsChecked = Preferenze.Specchia;
        Specchio.ScaleX = Preferenze.Specchia ? -1 : 1;
        MostraAvvioConWindows();

        iconaTray = new IconaTray(apri: MostraFinestra, mini: ApriMini, scollega: () => _ = ScollegaAsync(), esci: Esci);
        notifiche = new Notifiche(clic: () => coda.TryEnqueue(MostraFinestra));
        Activated += (_, evento) => inPrimoPiano = evento.WindowActivationState != WindowActivationState.Deactivated;
        AppWindow.Closing += (_, evento) =>
        {
            SalvaPosizione();
            if (uscita) return;
            evento.Cancel = true;
            AppWindow.Hide();
        };
        Closed += async (_, _) =>
        {
            System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged -= SuCambioRete;
            controlloDiagnosi.Stop();
            reteAssestata.Stop();
            risveglioAssestato.Stop();
            controlloRisveglio.Stop();
            risveglio.Dispose();
            iconaTray.Dispose();
            notifiche.Dispose();
            annuncio.Dispose();
            ascoltatore.Dispose();
            await cavo.DisposeAsync();
            anteprima.Dispose();
            if (sessione is not null) await sessione.DisposeAsync();
        };
    }

    // Un telefono alla volta: un nuovo collegamento sostituisce il precedente.
    // Chiamata sul thread di rete (o del cavo): qui niente controlli della finestra, solo SuInterfaccia.
    private void Accetta(Socket presa, bool viaCavo, ulong arrivo)
    {
        // Un collegamento nuovo resta in attesa finché non è accettato (stretta di mano, prova, fiducia):
        // solo allora prende il posto del telefono attuale. Così nessuno sulla rete può farlo cadere.
        var nuova = new SessioneComputer(presa, Environment.MachineName, abbinamento, arrivo: arrivo)
        {
            Collegamento = Collegamenti.DellaPresa(presa, viaCavo),
        };
        void SuInterfaccia(Action azione) => coda.TryEnqueue(() => { if (sessione == nuova) azione(); });
        var tipo = nuova.Collegamento?.Testo() ?? "rete";
        string provenienza;
        try { provenienza = viaCavo ? "dal cavo USB" : $"da {presa.RemoteEndPoint} ({tipo})"; }
        catch (Exception) { provenienza = tipo; }
        registro.Aggiungi($"Nuova connessione {provenienza}");
        nuova.ConfermaInCorso += (nome, _) => registro.Aggiungi($"«{nome}» è nuovo: chiesta la conferma con il codice");

        // Sul thread di rete, prima del benvenuto: il formato e il video che seguono trovano già la sessione.
        nuova.Salutato += accettato =>
        {
            // Precedenza del cavo: lo stesso telefono già collegato con il cavo non passa al Wi-Fi
            // (il cavo si ricollegherebbe e i due collegamenti si caccerebbero a vicenda).
            // Il contrario sì: il cavo accettato prende il posto del Wi-Fi qui sotto, come sempre.
            // Controllo e scambio sotto lo stesso blocco: cavo e Wi-Fi dello stesso telefono arrivano spesso insieme
            // (app appena aperta) e senza il Wi-Fi potrebbe leggere la sessione prima del cavo e scavalcarlo.
            SessioneComputer? vecchia = null;
            bool restaIlCavo;
            lock (sceltaSessione)
            {
                restaIlCavo = !nuova.ViaCavo && Volatile.Read(ref sessione) is { ViaCavo: true, Terminata: false } suCavo
                    && suCavo.ImprontaTelefono == nuova.ImprontaTelefono;
                if (!restaIlCavo) vecchia = Interlocked.Exchange(ref sessione, nuova);
            }
            if (restaIlCavo)
            {
                registro.Aggiungi($"«{accettato.Nome}» anche in {tipo}: resta il cavo USB");
                _ = ChiudiSessioneAsync(nuova);
                return;
            }
            registro.Aggiungi($"«{accettato.Nome}» accettato · {tipo}");
            if (vecchia is not null && vecchia != nuova)
            {
                registro.Aggiungi(nuova.ViaCavo && vecchia.ImprontaTelefono == nuova.ImprontaTelefono
                    ? "Il cavo USB prende il posto del Wi-Fi"
                    : "Il collegamento precedente si chiude");
            }
            // Con l'arrivederci, come sul Mac: un altro telefono sostituito non si ricollega da solo
            // (altrimenti i due telefoni si caccerebbero a vicenda all'infinito).
            if (vecchia is not null && vecchia != nuova) _ = ChiudiSessioneAsync(vecchia);
        };
        nuova.Salutato += ciao => SuInterfaccia(() =>
        {
            if (telefono is not null && improntaTelefono is not null && improntaTelefono == nuova.ImprontaTelefono)
            {
                // Lo stesso telefono torna, forse con una sessione nuova ripartita in automatico:
                // gli si rimanda quello che la finestra mostra, così i due restano d'accordo.
                var manuale = EsposizioneManuale.IsOn;
                Comanda(new Comando(Zoom: CursoreZoom.Value, Torcia: PulsanteTorcia.IsChecked == true,
                    Esposizione: Math.Round(CursoreEsposizione.Value, 1),
                    Bianco: BiancoAutomatico.IsOn ? 0 : (int)CursoreBianco.Value,
                    Iso: manuale ? Math.Round(CursoreIso.Value) : 0, Tempo: manuale ? TempoScelto : 0));
            }
            else
            {
                if (telefono is not null) AzzeraComandi();
                sorveglianzaAvvisi.Azzera();
                BarraAvvisoTelefono.IsOpen = false;
                Notifica("Telefono collegato", $"{ciao.Nome} è collegato a questo PC.");
            }
            telefono = ciao;
            improntaTelefono = nuova.ImprontaTelefono;
            collegamento = nuova.Collegamento;
            // La misura dell'avvio è di questa sessione: arriva con il suo primo fotogramma a schermo.
            testoAvvio = nuova.Avvio.Testo;
            PulsanteScollega.Visibility = Visibility.Visible;
            Mostra(StatoCollegamento.Collegato);
        });
        nuova.StatoRicevuto += stato => SuInterfaccia(() =>
        {
            statoTelefono = stato;
            MostraAvviso(stato, sorveglianzaAvvisi.Aggiorna(stato));
            AggiornaTelefono();
        });
        nuova.StatisticheAggiornate += nuove => SuInterfaccia(() =>
        {
            statistiche = nuove;
            storiaLatenza.Aggiungi(nuove.LatenzaMs);
            AggiornaTelefono();
        });
        // Il lettore si crea subito sul thread di rete, così il primo fotogramma chiave non va perso.
        nuova.FormatoRicevuto += formato =>
        {
            if (sessione != nuova) return;
            registro.Aggiungi($"Formato: {formato.Larghezza}×{formato.Altezza} · {formato.Fps} fps · {(formato.Codec == Codec.Hevc ? "HEVC" : "H.264")}");
            var lettore = anteprima.Avvia(formato.Larghezza, formato.Altezza, formato.Codec);
            // Senza decodificatore (di solito HEVC senza l'estensione dello Store) la finestra resterebbe nera.
            lettore.MediaFailed += (_, _) => SuInterfaccia(() =>
            {
                if (sessione != nuova) return;
                registro.Aggiungi("Il video non si riesce a decodificare");
                Video.Visibility = Visibility.Collapsed;
                Segnaposto.Opacity = 1;
                MessaggioAnteprima.Text = formato.Codec == Codec.Hevc
                    ? "Questo PC non decodifica l'HEVC. Sull'iPhone scegli H.264 nelle impostazioni, oppure installa «Estensioni video HEVC» da Microsoft Store."
                    : "Il video non si riesce a mostrare. Scollega e ricollega l'iPhone.";
            });
            SuInterfaccia(() =>
            {
                Video.SetMediaPlayer(lettore);
                Video.Visibility = Visibility.Visible;
                Segnaposto.Opacity = 0;
            });
        };
        nuova.FotogrammaRicevuto += fotogramma => { if (sessione == nuova) anteprima.Accoda(fotogramma); };
        nuova.CapacitaRicevute += capacita => SuInterfaccia(() => MostraComandi(capacita));
        nuova.Silenzio += () => SuInterfaccia(() =>
        {
            registro.Aggiungi("Nessun dato da 3 secondi: riconnessione");
            Mostra(StatoCollegamento.Riconnessione);
        });
        nuova.Ripresa += () => SuInterfaccia(() =>
        {
            registro.Aggiungi("Dati ripresi");
            Mostra(StatoCollegamento.Collegato);
        });
        nuova.Chiusa += () => registro.Aggiungi(nuova.ChiusaDalComputer ? $"Collegamento chiuso dal PC ({tipo})" : $"Collegamento chiuso ({tipo})");
        // Chiusa dal computer (Scollega, rifiutato, sostituito da un altro telefono): sul cavo non si ricollega
        // da sola finché l'iPhone non viene staccato e ricollegato.
        if (viaCavo) nuova.Chiusa += () => { if (nuova.ChiusaDalComputer) cavo.Sospendi(presa); };
        // Accettata: il cavo funziona. Senza, una chiusura prima del «ciao» (il telefono rifiuta il cavo)
        // allunga l'attesa del prossimo tentativo, invece di riprovare ogni 2 secondi per sempre.
        if (viaCavo) nuova.Salutato += _ => cavo.StrettaRiuscita(presa);
        nuova.Chiusa += () => SuInterfaccia(() =>
        {
            // Nel frattempo il thread di rete può aver già messo al suo posto un telefono appena accettato.
            if (Interlocked.CompareExchange(ref sessione, null, nuova) != nuova) return;
            if (telefono is null) { Mostra(StatoCollegamento.NessunTelefono); return; }
            Mostra(StatoCollegamento.Riconnessione);
            _ = DimenticaSeNonTornaAsync(++perdite);
        });

        nuova.Avvia();
    }

    /// <summary>Anche da App all'avvio, tranne quando Windows lancia l'app all'accesso (--avvio).</summary>
    /// <summary>
    /// Un telefono nuovo, senza il QR code: si chiede all'utente, con il codice che il telefono mostra.
    /// Chiamata da un thread di rete; la finestra si apre sul thread dell'interfaccia.
    /// </summary>
    private Task<bool> ChiediConfermaAsync(string nomeTelefono, string codice, CancellationToken scaduto)
    {
        var risposta = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        // Se la finestra non arriva mai a chiedere (app in chiusura), allo scadere la risposta è no.
        var allaScadenza = scaduto.Register(() => risposta.TrySetResult(false));
        _ = risposta.Task.ContinueWith(_ => allaScadenza.Dispose(), TaskScheduler.Default);
        coda.TryEnqueue(async () =>
        {
            // Già una domanda aperta per un altro telefono: per sicurezza si rifiuta, come sul Mac,
            // così nessuno può cambiare la domanda sotto il cursore dell'utente.
            if (confermaAperta)
            {
                risposta.TrySetResult(false);
                return;
            }
            confermaAperta = true;
            try
            {
                Notifica("Nuovo telefono", $"«{nomeTelefono}» chiede di collegarsi: conferma su WebcamLR.");
                MostraFinestra();
                await PreparaDialogoAsync();
                if (scaduto.IsCancellationRequested) return;
                var finestra = new ContentDialog
                {
                    XamlRoot = Content.XamlRoot,
                    Title = $"Consentire «{nomeTelefono}»?",
                    Content = new StackPanel
                    {
                        Spacing = 12,
                        Children =
                        {
                            new TextBlock { Text = "Controlla che sul telefono compaia lo stesso codice:", TextWrapping = TextWrapping.Wrap },
                            new TextBlock
                            {
                                Text = string.Join(" ", codice.ToCharArray()),
                                FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
                                FontSize = 40,
                                HorizontalAlignment = HorizontalAlignment.Center,
                                Foreground = (Brush)Application.Current.Resources["Ciano"],
                            },
                            new TextBlock
                            {
                                Text = "Se il codice è diverso, o non conosci questo telefono, non consentire.",
                                TextWrapping = TextWrapping.Wrap,
                                Foreground = (Brush)Application.Current.Resources["TestoSecondario"],
                            },
                        },
                    },
                    PrimaryButtonText = "Consenti",
                    CloseButtonText = "Non consentire",
                    DefaultButton = ContentDialogButton.Close,
                };
                // Scaduto il tempo, o telefono andato via: la domanda sparisce da sola.
                using var registrazione = scaduto.Register(() => coda.TryEnqueue(finestra.Hide));
                var esito = await finestra.ShowAsync();
                risposta.TrySetResult(esito == ContentDialogResult.Primary && !scaduto.IsCancellationRequested);
            }
            catch (Exception)
            {
                // Per esempio un'altra finestra di dialogo già aperta: per sicurezza si rifiuta.
                risposta.TrySetResult(false);
            }
            finally
            {
                confermaAperta = false;
                risposta.TrySetResult(false);
            }
        });
        return risposta.Task;
    }

    /// Vero mentre la domanda «Consentire …?» è aperta.
    private bool confermaAperta;

    /// <summary>
    /// Prepara la domanda. La finestra partita nascosta all'accesso non ha XamlRoot finché non è caricata:
    /// si aspetta. WinUI mostra una sola ContentDialog alla volta: quella aperta (App, nuovo profilo) si chiude,
    /// aspettando che sia chiusa davvero (al massimo un secondo).
    /// </summary>
    private async Task PreparaDialogoAsync()
    {
        if (Content is FrameworkElement radice && radice.XamlRoot is null)
        {
            var caricata = new TaskCompletionSource();
            void SuCaricata(object origine, RoutedEventArgs evento) => caricata.TrySetResult();
            radice.Loaded += SuCaricata;
            await Task.WhenAny(caricata.Task, Task.Delay(2000));
            radice.Loaded -= SuCaricata;
        }
        if (Content.XamlRoot is not { } xamlRoot) return;
        foreach (var popup in VisualTreeHelper.GetOpenPopupsForXamlRoot(xamlRoot))
        {
            if (popup.Child is not ContentDialog aperta) continue;
            var chiusa = new TaskCompletionSource();
            aperta.Closed += (_, _) => chiusa.TrySetResult();
            aperta.Hide();
            await Task.WhenAny(chiusa.Task, Task.Delay(1000));
        }
    }

    public void MostraFinestra()
    {
        AppWindow.Show();
        if (massimizzaAllaPrimaApertura && AppWindow.Presenter is OverlappedPresenter presentatore)
        {
            massimizzaAllaPrimaApertura = false;
            presentatore.Maximize();
        }
        Activate();
    }

    private void Esci()
    {
        SalvaPosizione();
        uscita = true;
        Close();
        Application.Current.Exit();
    }

    /// <summary>
    /// Ogni perdita ha il suo numero: se il telefono torna e si perde di nuovo, conta solo l'attesa dell'ultima
    /// (altrimenti quella vecchia lo dimenticherebbe pochi secondi dopo la seconda perdita).
    /// </summary>
    private int perdite;

    private async Task DimenticaSeNonTornaAsync(int perdita)
    {
        await Task.Delay(AttesaRiconnessione);
        if (perdita != perdite || sessione is not null || telefono is not { } perso) return;
        registro.Aggiungi($"«{perso.Nome}» non è tornato in {AttesaRiconnessione.TotalSeconds:0} secondi");
        Dimentica();
        Notifica("Telefono perso", $"{perso.Nome} non risponde più. Riapri WebcamLR sull'iPhone per ricollegarlo.");
    }

    private void Notifica(string titolo, string testo)
    {
        if (inPrimoPiano && AppWindow.IsVisible) return;
        notifiche.Mostra(titolo, testo);
    }

    /// <summary>
    /// La barra sopra il video segue lo stato del telefono (la percentuale si aggiorna); se l'avviso è nuovo
    /// si riapre anche se era stata chiusa, e arriva una notifica.
    /// </summary>
    private void MostraAvviso(StatoTelefono stato, AvvisoTelefono? nuovo)
    {
        if (sorveglianzaAvvisi.Attuale == AvvisoTelefono.Nessuno)
        {
            BarraAvvisoTelefono.IsOpen = false;
            return;
        }
        var (titolo, messaggio) = SorveglianzaAvvisi.Testi(sorveglianzaAvvisi.Attuale, stato);
        BarraAvvisoTelefono.Title = titolo;
        BarraAvvisoTelefono.Message = messaggio;
        if (nuovo is null) return;
        BarraAvvisoTelefono.IsOpen = true;
        Notifica(titolo, messaggio);
    }

    /// <summary>Chiusura voluta: il telefono riceve l'arrivederci e la finestra torna all'attesa subito.</summary>
    private void SuScollega(object sender, RoutedEventArgs e) => _ = ScollegaAsync();

    /// <summary>Dal pulsante o dal menu dell'icona. Durante la riconnessione la sessione non c'è più: si dimentica e basta.</summary>
    private async Task ScollegaAsync()
    {
        var chiusa = Interlocked.Exchange(ref sessione, null);
        if (telefono is not null) registro.Aggiungi("Scollegato dal PC");
        Dimentica();
        if (chiusa is not null) await ChiudiSessioneAsync(chiusa);
    }

    /// <summary>Arrivederci al telefono, poi chiusura. Un errore di rete qui non deve chiudere l'app.</summary>
    private static async Task ChiudiSessioneAsync(SessioneComputer chiusa)
    {
        try
        {
            await chiusa.ChiudiAsync();
            await chiusa.DisposeAsync();
        }
        catch (Exception) { }
    }

    private void Dimentica()
    {
        telefono = null;
        improntaTelefono = null;
        collegamento = null;
        statoTelefono = null;
        statistiche = null;
        testoAvvio = null;
        storiaLatenza.Azzera();
        sorveglianzaAvvisi.Azzera();
        BarraAvvisoTelefono.IsOpen = false;
        anteprima.Ferma();
        PannelloComandi.Visibility = Visibility.Collapsed;
        AzzeraComandi();
        Video.SetMediaPlayer(null);
        Video.Visibility = Visibility.Collapsed;
        Segnaposto.Opacity = 1;
        PulsanteScollega.Visibility = Visibility.Collapsed;
        Mostra(StatoCollegamento.NessunTelefono);
    }

    private void Mostra(StatoCollegamento stato)
    {
        var verde = new SolidColorBrush(ColorHelper.FromArgb(255, 0x6F, 0xC2, 0x8C));
        var ambra = new SolidColorBrush(ColorHelper.FromArgb(255, 0xE2, 0xA5, 0x4B));
        var secondario = (Brush)Application.Current.Resources["TestoSecondario"];
        statoCollegamento = stato;
        switch (stato)
        {
            case StatoCollegamento.Collegato:
                TestoStato.Text = "COLLEGATO · PRONTA";
                TestoStato.Foreground = (Brush)Application.Current.Resources["Testo"];
                PuntoStato.Fill = verde;
                PuntoStato.Stroke = null;
                PillolaStato.Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0x23, 0x2D, 0x2A));
                PillolaStato.BorderThickness = new Thickness(0);
                MessaggioAnteprima.Text = "Collegato: in attesa del video…";
                break;
            case StatoCollegamento.Riconnessione:
                TestoStato.Text = "RICONNESSIONE";
                TestoStato.Foreground = new SolidColorBrush(ColorHelper.FromArgb(255, 0xF0, 0xC2, 0x7A));
                PuntoStato.Fill = ambra;
                PuntoStato.Stroke = null;
                PillolaStato.Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0x3A, 0x2E, 0x1A));
                PillolaStato.BorderThickness = new Thickness(0);
                MessaggioAnteprima.Text = "Collegamento perso: aspetto che il telefono torni.";
                break;
            default:
                TestoStato.Text = "NESSUN TELEFONO";
                TestoStato.Foreground = secondario;
                PuntoStato.Fill = null;
                PuntoStato.Stroke = secondario;
                PillolaStato.Background = null;
                PillolaStato.BorderThickness = new Thickness(1);
                MessaggioAnteprima.Text = "";
                break;
        }
        // Senza telefono: QR grande e tre passi al centro, al posto del messaggio (round 2, funzione 46).
        var senzaTelefono = stato == StatoCollegamento.NessunTelefono;
        PrimoAvvio.Visibility = senzaTelefono ? Visibility.Visible : Visibility.Collapsed;
        PannelloMessaggio.Visibility = senzaTelefono ? Visibility.Collapsed : Visibility.Visible;
        SchedaNuovoTelefono.Visibility = senzaTelefono ? Visibility.Collapsed : Visibility.Visible;
        AggiornaTelefono();
        MostraDiagnosi();
    }

    private static Brush Pennello(string nome) => (Brush)Application.Current.Resources[nome];

    private void AggiornaTelefono()
    {
        AggiornaQualita();
        AggiornaCollegamento();
        AggiornaGrafico();
        // Nel costruttore la prima chiamata arriva prima che l'icona esista.
        iconaTray?.Aggiorna(statoCollegamento, telefono?.Nome, statistiche?.LatenzaMs);
        if (telefono is null)
        {
            NomeTelefono.Text = "In attesa di un telefono";
            DettagliTelefono.Text = $"Visibile in rete · porta {ascoltatore.Porta}";
            TestoStatistiche.Text = "Nessun telefono collegato";
            DettagliFotocamera.Text = "I comandi della fotocamera compaiono quando un telefono è collegato.";
            return;
        }

        NomeTelefono.Text = telefono.Nome;
        var parti = new List<string>();
        if (collegamento is { } tipo) parti.Add(tipo.Testo());
        // I millisecondi solo in modalità avanzata: di serie basta la qualità in parole.
        if (modalitaAvanzata) parti.Add(statistiche?.LatenzaMs is int ms ? $"{ms} ms" : "— ms");
        // Avvio rapido misurato (1.11): dall'accettazione al primo fotogramma a schermo, solo in modalità avanzata.
        if (modalitaAvanzata && testoAvvio is { } avvio) parti.Add(avvio);
        if (statoTelefono is { Batteria: >= 0 } stato) parti.Add($"{stato.Batteria}%");
        DettagliTelefono.Text = string.Join(" · ", parti);

        TestoStatistiche.Inlines.Clear();
        if (!modalitaAvanzata)
        {
            // Modalità semplice (1.5): niente numeri, solo se il video arriva.
            TestoStatistiche.Text = statistiche is { Fps: > 0 } ? "Video in arrivo dall'iPhone" : "Collegato: in attesa del video…";
        }
        else if (statistiche is { Larghezza: > 0 } s)
        {
            TestoStatistiche.Inlines.Add(new Run { Text = $"{s.Larghezza}×{s.Altezza} · {s.Fps} fps · {(s.Codec == Codec.Hevc ? "HEVC" : "H.264")} · {s.MegabitAlSecondo:0.0} Mbit/s · " });
            // Come sul Mac: ciano sotto i 100 ms (l'obiettivo del round 1), ambra sopra.
            TestoStatistiche.Inlines.Add(new Run
            {
                Text = $"latenza {(s.LatenzaMs is int l ? $"{l} ms" : "—")}",
                Foreground = (Brush)Application.Current.Resources[s.LatenzaMs is >= 100 ? "Ambra" : "Ciano"],
            });
        }
        else
        {
            TestoStatistiche.Text = "Collegato: in attesa del video…";
        }

        if (statoTelefono is { } st)
        {
            var temperatura = st.Temperatura switch
            {
                Temperatura.Normale => "normale",
                Temperatura.Calda => "calda",
                Temperatura.MoltoCalda => "molto calda",
                _ => "critica",
            };
            DettagliFotocamera.Text = $"Obiettivo: {st.Obiettivo}\nBatteria: {(st.Batteria >= 0 ? $"{st.Batteria}%" : "—")}{(st.InCarica ? " · in carica" : "")}\nTemperatura: {temperatura}";
        }
    }

    /// <summary>Tacche e parola, come sul Mac: verde, ciano chiaro, ambra. I numeri restano nell'aiuto.</summary>
    private void AggiornaQualita()
    {
        if (telefono is null || statistiche?.LatenzaMs is not int ms)
        {
            ChipQualita.Visibility = Visibility.Collapsed;
            return;
        }
        var qualita = Qualita.Da(ms);
        var colore = Pennello(qualita switch
        {
            QualitaCollegamento.Ottima => "Verde",
            QualitaCollegamento.Buona => "CianoChiaro",
            _ => "AmbraTesto",
        });
        var spenta = Pennello("Linea");
        var tacche = new[] { Tacca1, Tacca2, Tacca3 };
        for (var i = 0; i < tacche.Length; i++) tacche[i].Fill = i < qualita.Tacche() ? colore : spenta;
        TestoQualita.Text = qualita.Testo();
        TestoQualita.Foreground = colore;
        SuggerimentoQualita.Content = modalitaAvanzata
            ? $"Latenza {ms} ms\nUltimi 60 s: media {storiaLatenza.Media} ms, massima {storiaLatenza.Massima} ms"
            : qualita switch
            {
                QualitaCollegamento.Ottima => "Ritardo minimo: perfetto per le chiamate.",
                QualitaCollegamento.Buona => "Ritardo basso: va bene per le chiamate.",
                _ => "Ritardo alto: avvicinati al router o usa il cavo USB.",
            };
        AutomationProperties.SetName(ChipQualita, modalitaAvanzata
            ? $"Collegamento {qualita.Testo().ToLowerInvariant()}, {ms} millisecondi"
            : $"Collegamento {qualita.Testo().ToLowerInvariant()}");
        ChipQualita.Visibility = Visibility.Visible;
    }

    /// <summary>«Wi-Fi», «Cavo USB», «Cavo di rete» o «Hotspot» accanto alla qualità (1.2), con un consiglio al passaggio.</summary>
    private void AggiornaCollegamento()
    {
        if (telefono is null || collegamento is not { } tipo)
        {
            ChipCollegamento.Visibility = Visibility.Collapsed;
            return;
        }
        IconaCollegamento.Glyph = tipo switch
        {
            TipoCollegamento.CavoUsb => "\uE88E",
            TipoCollegamento.CavoDiRete => "\uE839",
            TipoCollegamento.Hotspot => "\uE704",
            _ => "\uE701",
        };
        TestoCollegamento.Text = tipo.Testo();
        ToolTipService.SetToolTip(ChipCollegamento, tipo.Consiglio() ?? "Collegato con il cavo USB: il collegamento più stabile.");
        AutomationProperties.SetName(ChipCollegamento, $"Collegamento: {tipo.Testo()}");
        ChipCollegamento.Visibility = Visibility.Visible;
    }

    private void AggiornaGrafico()
    {
        var punti = storiaLatenza.Punti(GraficoLatenza.Width, GraficoLatenza.Height);
        if (telefono is null || punti.Count < 2 || !modalitaAvanzata)
        {
            GraficoLatenza.Visibility = Visibility.Collapsed;
            return;
        }
        var linea = new PointCollection();
        foreach (var (x, y) in punti) linea.Add(new Windows.Foundation.Point(x, y));
        LineaLatenza.Points = linea;
        Guida100.Y1 = Guida100.Y2 = storiaLatenza.AltezzaDi(100, GraficoLatenza.Height);
        ToolTipService.SetToolTip(GraficoLatenza, $"Ultimi 60 secondi: media {storiaLatenza.Media} ms, massima {storiaLatenza.Massima} ms. Tratteggio: 100 ms");
        GraficoLatenza.Visibility = Visibility.Visible;
    }

    // MARK: diagnosi (1.3)

    /// <summary>
    /// Raccoglie la situazione (rete, profilo, firewall, cavo) e decide con Diagnosi.Problemi.
    /// Profilo e firewall si leggono fuori dal thread dell'interfaccia.
    /// </summary>
    private async Task AggiornaDiagnosiAsync()
    {
        try
        {
            var richiesta = ++richiesteDiagnosi;
            var porta = ascoltatore.Porta;
            var (haRete, profilo, firewall) = await Task.Run(() =>
            {
                var haRete = IndirizziLocali.Ipv4().Count > 0;
                var profilo = ReteWindows.Profilo();
                return (haRete, profilo, ReteWindows.Firewall(profilo, porta));
            });
            if (richiesta != richiesteDiagnosi) return;
            var nuovi = Diagnosi.Problemi(new SituazioneRete(haRete, profilo, firewall,
                cavo.Verificato ? cavo.Stato : null, cavo.IPhoneAlCavo));
            foreach (var nuovo in nuovi.Where(n => n.Grave && problemi.All(p => p.Id != n.Id)))
                registro.Aggiungi($"Diagnosi: {nuovo.Titolo}");
            problemi = nuovi;
            MostraDiagnosi();
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Il problema più grave sopra il video, solo senza telefono. Sotto, i suggerimenti sul cavo:
    /// quello per «Dispositivi Apple» resta anche con un telefono in Wi-Fi, finché non lo si chiude.
    /// </summary>
    private void MostraDiagnosi()
    {
        var senzaTelefono = statoCollegamento == StatoCollegamento.NessunTelefono;
        MostraProblema(BarraDiagnosi, AzioneDiagnosi, RispostaDiagnosi, senzaTelefono ? problemi.FirstOrDefault(p => p.Grave) : null);
        var suggerimento = problemi.FirstOrDefault(p => !p.Grave);
        var daMostrare = suggerimento is not null && !suggerimentoCavoChiuso && (senzaTelefono || suggerimento.Id == "servizio-assente");
        MostraProblema(BarraCavo, AzioneCavo, RispostaCavo, daMostrare ? suggerimento : null);
    }

    private static void MostraProblema(InfoBar barra, Button azione, HyperlinkButton risposta, ProblemaCollegamento? problema)
    {
        if (problema is null)
        {
            barra.IsOpen = false;
            return;
        }
        barra.Title = problema.Titolo;
        barra.Message = problema.Messaggio;
        azione.Content = problema.Azione?.Testo;
        azione.Tag = problema.Azione?.Indirizzo;
        azione.Visibility = problema.Azione is null ? Visibility.Collapsed : Visibility.Visible;
        risposta.Tag = problema.IdDomanda;
        barra.IsOpen = true;
    }

    /// <summary>Impostazioni di Windows, firewall o Microsoft Store, secondo il problema.</summary>
    private async void SuAzioneDiagnosi(object sender, RoutedEventArgs e)
    {
        // async void: un errore qui non deve chiudere l'app.
        try
        {
            if (sender is Button { Tag: string indirizzo }) await Windows.System.Launcher.LaunchUriAsync(new Uri(indirizzo));
        }
        catch (Exception) { }
    }

    /// <summary>Apre «App e assistenza» sulla risposta giusta delle domande frequenti.</summary>
    private async void SuRispostaDiagnosi(object sender, RoutedEventArgs e)
    {
        try
        {
            if (sender is FrameworkElement { Tag: string domanda })
                await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), abbinamento, domanda);
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Cambio di Wi-Fi, cavo collegato, VPN accesa (1.10): il QR si rifà subito con gli indirizzi nuovi, e di nuovo
    /// quando la rete si è assestata (Windows manda più avvisi di fila e l'indirizzo dal router arriva dopo).
    /// </summary>
    private void SuCambioRete(object? origine, EventArgs evento) => coda.TryEnqueue(() =>
    {
        // Le schede rilette subito: il telefono che arriva dalla rete nuova non le aspetta (1.11).
        _ = Task.Run(Collegamenti.AggiornaSchede);
        _ = MostraQRAsync();
        reteAssestata.Stop();
        reteAssestata.Start();
    });

    /// <summary>Un attimo dopo l'ultimo avviso di cambio rete: QR, registro e diagnosi con la rete definitiva.</summary>
    private async Task DopoCambioReteAsync()
    {
        var indirizzi = await Task.Run(IndirizziLocali.Ipv4);
        var testo = string.Join(", ", indirizzi);
        // Se l'ascolto è caduto con la rete vecchia, si riapre adesso invece di aspettare il prossimo tentativo.
        ascoltatore.Controlla();
        if (testo != ultimiIndirizzi)
        {
            ultimiIndirizzi = testo;
            registro.Aggiungi(indirizzi.Count == 0 ? "Rete cambiata: nessuna rete" : $"Rete cambiata: {testo}");
            // Un telefono che sta già cercando trova subito il PC sulla rete nuova (1.12).
            if (indirizzi.Count > 0) _ = RiannunciaAsync();
        }
        _ = MostraQRAsync();
        _ = AggiornaDiagnosiAsync();
    }

    /// <summary>Dall'avviso di Windows o dal controllo dell'orologio: si aspetta un attimo e si fa una volta sola.</summary>
    private void SuRisveglio()
    {
        risveglioAssestato.Stop();
        risveglioAssestato.Start();
    }

    /// <summary>
    /// Risveglio dallo stop (1.12): ascolto, annuncio in rete, QR e cavo ripartono subito, così il telefono
    /// che aspetta (o che si riapre adesso) ritrova il PC senza fare nulla.
    /// </summary>
    private void DopoRisveglio()
    {
        registro.Aggiungi("Risveglio dallo stop: ascolto, annuncio e cavo ripartono");
        ascoltatore.Controlla();
        cavo.Riprendi();
        _ = Task.Run(Collegamenti.AggiornaSchede);
        _ = RiannunciaAsync();
        _ = MostraQRAsync();
        _ = AggiornaDiagnosiAsync();
    }

    /// Cresce a ogni rinnovo: se ne arriva un altro mentre il vecchio annuncio si chiude, crea il nuovo solo l'ultimo.
    private int richiesteAnnuncio;

    /// <summary>Toglie l'annuncio mDNS e ne pubblica uno nuovo, con la porta di adesso.</summary>
    private async Task RiannunciaAsync()
    {
        var richiesta = ++richiesteAnnuncio;
        try
        {
            await annuncio.ChiudiAsync();
            if (richiesta != richiesteAnnuncio || uscita) return;
            annuncio = new AnnuncioWindows((ushort)ascoltatore.Porta);
        }
        catch (Exception) { }
    }

    /// Gli indirizzi scritti l'ultima volta nel registro: una riga sola per ogni cambio vero.
    private string? ultimiIndirizzi;

    /// Cresce a ogni richiesta di QR: una richiesta più vecchia (rete cambiata) che finisce dopo
    /// non rimette il gettone già usato o gli indirizzi di prima.
    private int richiesteQR;

    private async Task MostraQRAsync()
    {
        var richiesta = ++richiesteQR;
        // Lo stesso nome che l'iPhone vede nell'elenco (AnnuncioWindows annuncia il nome del computer).
        TestoTerzoPasso.Text = $"Tocca «{Environment.MachineName}» nell'elenco, oppure «Inquadra il QR code del computer» e inquadra questo codice.";
        // Tutti gli indirizzi utili, il più probabile per primo (1.10): il telefono li prova insieme.
        // Leggere le schede di rete può richiedere decine di millisecondi: fuori dal thread dell'interfaccia.
        var indirizzi = await Task.Run(IndirizziLocali.Ipv4);
        if (richiesta != richiesteQR) return;
        if (indirizzi.Count == 0)
        {
            IndirizzoScritto.Text = "Il PC non è collegato a una rete: collegalo al Wi-Fi o al cavo.";
            IndirizzoScrittoGrande.Text = IndirizzoScritto.Text;
            ImmagineQR.Source = null;
            ImmagineQRGrande.Source = null;
            CorniceQRGrande.Visibility = Visibility.Collapsed;
            return;
        }
        var porta = (ushort)ascoltatore.Porta;
        // Versione 2: l'impronta del PC e il gettone per abbinarsi senza conferma.
        var associazione = new Associazione(indirizzi, porta, Environment.MachineName,
            Impronta: abbinamento.Identita.Impronta, Gettone: abbinamento.Gettone);
        IndirizzoScritto.Text = $"Oppure scrivi: {indirizzi[0]}{(porta == Servizio.PortaPredefinita ? "" : $":{porta}")}";
        IndirizzoScrittoGrande.Text = $"Oppure, sull'iPhone, scrivi l'indirizzo: {indirizzi[0]}{(porta == Servizio.PortaPredefinita ? "" : $":{porta}")}";

        var png = IndirizziLocali.QRCodePng(associazione);
        if (png is null) return;
        using var flusso = new InMemoryRandomAccessStream();
        using (var scrittore = new DataWriter(flusso))
        {
            scrittore.WriteBytes(png);
            await scrittore.StoreAsync();
            scrittore.DetachStream();
        }
        flusso.Seek(0);
        var immagine = new BitmapImage();
        await immagine.SetSourceAsync(flusso);
        if (richiesta != richiesteQR) return;
        ImmagineQR.Source = immagine;
        ImmagineQRGrande.Source = immagine;
        CorniceQRGrande.Visibility = Visibility.Visible;
    }

    // MARK: comandi della fotocamera (round 4)

    private static readonly Dictionary<string, string> NomiObiettivi = new()
    {
        ["grandangolo"] = "Grandangolo 0,5×",
        ["principale"] = "Principale 1×",
        ["tele"] = "Tele",
        ["frontale"] = "Frontale",
    };

    private Capacita? capacitaAttuali;

    private void MostraComandi(Capacita capacita)
    {
        capacitaAttuali = capacita;
        aggiornoComandi = true;
        SceltaObiettivo.Items.Clear();
        foreach (var obiettivo in capacita.Obiettivi)
        {
            SceltaObiettivo.Items.Add(new ComboBoxItem { Content = NomiObiettivi.GetValueOrDefault(obiettivo, obiettivo), Tag = obiettivo });
        }
        var attuale = statoTelefono?.Obiettivo;
        SceltaObiettivo.SelectedIndex = Math.Max(0, capacita.Obiettivi.ToList().IndexOf(attuale ?? ""));
        CursoreZoom.Maximum = Math.Max(1, capacita.ZoomMassimo);
        CursoreZoom.Visibility = capacita.ZoomMassimo > 1 ? Visibility.Visible : Visibility.Collapsed;
        PulsanteTorcia.Visibility = capacita.Torcia ? Visibility.Visible : Visibility.Collapsed;
        // Esposizione manuale solo se il telefono dice i limiti ISO del suo obiettivo (funzione 19).
        if (capacita.IsoMinimo is double minimo && capacita.IsoMassimo is double massimo && massimo > minimo)
        {
            CursoreIso.Minimum = minimo;
            CursoreIso.Maximum = massimo;
            CursoreIso.Value = Math.Clamp(CursoreIso.Value, minimo, massimo);
        }
        else
        {
            EsposizioneManuale.IsOn = false;
        }
        MostraComandiAvanzati();
        PannelloComandi.Visibility = Visibility.Visible;
        aggiornoComandi = false;
    }

    // MARK: modalità avanzata (1.5)

    /// <summary>Esposizione manuale solo se il telefono dice i limiti ISO del suo obiettivo (funzione 19).</summary>
    private bool ManualeDisponibile => capacitaAttuali is { IsoMinimo: double minimo, IsoMassimo: double massimo } && massimo > minimo;

    private static Visibility Visibile(bool visibile) => visibile ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>
    /// Di serie restano obiettivo, zoom, esposizione, torcia e messa a fuoco; la modalità avanzata aggiunge
    /// profili, ISO e tempo manuali e bilanciamento del bianco. Unico posto che decide cosa si vede.
    /// </summary>
    private void MostraComandiAvanzati()
    {
        // Toggled può scattare mentre la finestra si sta ancora creando.
        if (PulsanteProfili is null || EsposizioneManuale is null || PannelloManuale is null || BiancoAutomatico is null || CursoreBianco is null) return;
        var manuale = modalitaAvanzata && EsposizioneManuale.IsOn;
        PulsanteProfili.Visibility = Visibile(modalitaAvanzata);
        EsposizioneManuale.Visibility = Visibile(modalitaAvanzata && ManualeDisponibile);
        PannelloManuale.Visibility = Visibile(manuale);
        CursoreEsposizione.Visibility = Visibile(!manuale);
        BiancoAutomatico.Visibility = Visibile(modalitaAvanzata);
        CursoreBianco.Visibility = Visibile(modalitaAvanzata && !BiancoAutomatico.IsOn);
    }

    private void SuModalitaAvanzata(object sender, RoutedEventArgs e)
    {
        if (InterruttoreAvanzata is null || InterruttoreAvanzata.IsOn == modalitaAvanzata) return;
        ImpostaModalitaAvanzata(InterruttoreAvanzata.IsOn, salva: true);
    }

    private void ImpostaModalitaAvanzata(bool avanzata, bool salva)
    {
        modalitaAvanzata = avanzata;
        if (salva) Preferenze.ModalitaAvanzata = avanzata;
        if (InterruttoreAvanzata.IsOn != avanzata) InterruttoreAvanzata.IsOn = avanzata;
        // Tornando alla modalità semplice i controlli manuali spariscono: si torna all'automatico,
        // così la fotocamera non resta regolata a mano senza che si veda perché.
        if (!avanzata && (EsposizioneManuale.IsOn || !BiancoAutomatico.IsOn))
        {
            var manuale = EsposizioneManuale.IsOn;
            var bianco = !BiancoAutomatico.IsOn;
            var prima = aggiornoComandi;
            aggiornoComandi = true;
            EsposizioneManuale.IsOn = false;
            BiancoAutomatico.IsOn = true;
            aggiornoComandi = prima;
            Comanda(new Comando(Iso: manuale ? 0 : null, Tempo: manuale ? 0 : null, Bianco: bianco ? 0 : null));
        }
        MostraComandiAvanzati();
        PannelloRegistro.Visibility = Visibile(avanzata);
        MostraRegistro();
        AggiornaTelefono();
    }

    /// <summary>Il registro si aggiorna solo quando si vede: i più recenti in cima.</summary>
    private void MostraRegistro()
    {
        if (!modalitaAvanzata) return;
        var testo = registro.Testo(recentiPrima: true);
        TestoRegistro.Text = testo.Length > 0 ? testo : "Ancora nessun evento.";
    }

    private void SuCopiaRegistro(object sender, RoutedEventArgs e)
    {
        try
        {
            var contenuto = new Windows.ApplicationModel.DataTransfer.DataPackage();
            contenuto.SetText(registro.Testo());
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(contenuto);
        }
        catch (Exception) { }
    }

    // MARK: avvia con Windows (round 2, funzione 40)

    /// <summary>L'interruttore mostra cosa c'è davvero nel registro, anche dopo un errore di scrittura.</summary>
    private void MostraAvvioConWindows()
    {
        aggiornoAvvio = true;
        InterruttoreAvvio.IsEnabled = avvioConWindows is not null;
        InterruttoreAvvio.IsOn = avvioConWindows?.Attivo ?? false;
        aggiornoAvvio = false;
    }

    private void SuAvvioConWindows(object sender, RoutedEventArgs e)
    {
        if (aggiornoAvvio || avvioConWindows is null) return;
        avvioConWindows.Imposta(InterruttoreAvvio.IsOn);
        MostraAvvioConWindows();
    }

    private void SuSpecchia(object sender, RoutedEventArgs e)
    {
        var specchia = PulsanteSpecchia.IsChecked == true;
        Specchio.ScaleX = specchia ? -1 : 1;
        Preferenze.Specchia = specchia;
    }

    /// <summary>F11 entra ed esce dallo schermo intero, Esc ne esce: come nei browser.</summary>
    private async void SuApp(object sender, RoutedEventArgs e)
    {
        // async void: un errore qui non deve chiudere l'app.
        try
        {
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), abbinamento);
        }
        catch (Exception) { }
    }

    /// <summary>Per «Segnala un bug»: solo dati tecnici, nessun dato personale oltre al nome del telefono.</summary>
    private List<(string Nome, string Valore)> DatiTecnici()
    {
        var dati = new List<(string, string)>
        {
            ("App", $"WebcamLR per Windows {typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? "—"}"),
            ("Sistema", Environment.OSVersion.VersionString),
        };
        if (telefono is { } ciao) dati.Add(("Telefono", $"{ciao.Piattaforma} · app {ciao.VersioneApp}"));
        if (telefono is not null) dati.Add(("Collegamento", collegamento?.Testo() ?? "—"));
        dati.Add(("Cavo USB", cavo.Stato switch
        {
            StatoCavo.Collegato => "collegato",
            StatoCavo.InAscolto => "servizio di Apple presente",
            _ => "servizio di Apple assente",
        }));
        if (statistiche is { } s)
        {
            dati.Add(("Video", $"{s.Larghezza}×{s.Altezza} · {s.Fps} fps · {s.Codec} · {s.MegabitAlSecondo:0.0} Mbit/s"));
            dati.Add(("Latenza", s.LatenzaMs is int ms ? $"{ms} ms" : "—"));
        }
        return dati;
    }

    private void AggiungiScorciatoie()
    {
        if (Content is not UIElement radice) return;
        var f11 = new KeyboardAccelerator { Key = Windows.System.VirtualKey.F11 };
        f11.Invoked += (_, evento) =>
        {
            var intero = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen;
            AppWindow.SetPresenter(intero ? AppWindowPresenterKind.Overlapped : AppWindowPresenterKind.FullScreen);
            evento.Handled = true;
        };
        var esc = new KeyboardAccelerator { Key = Windows.System.VirtualKey.Escape };
        esc.Invoked += (_, evento) =>
        {
            switch (AppWindow.Presenter.Kind)
            {
                case AppWindowPresenterKind.FullScreen:
                    AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
                    break;
                case AppWindowPresenterKind.CompactOverlay:
                    ImpostaMini(false);
                    break;
                default:
                    return;
            }
            evento.Handled = true;
        };
        radice.KeyboardAccelerators.Add(f11);
        radice.KeyboardAccelerators.Add(esc);

        // Round 2 (funzione 43): 1–4 per gli obiettivi, + e − per lo zoom, sulla riga dei numeri e sul tastierino.
        for (var numero = 1; numero <= Scorciatoie.ObiettiviConTasto; numero++)
        {
            var scelto = numero;
            Aggiungi((Windows.System.VirtualKey)((int)Windows.System.VirtualKey.Number0 + numero), () => ScegliObiettivo(scelto));
            Aggiungi((Windows.System.VirtualKey)((int)Windows.System.VirtualKey.NumberPad0 + numero), () => ScegliObiettivo(scelto));
        }
        // 187 e 189 sono i tasti + e − accanto allo Invio e al tasto destro delle maiuscole (VK_OEM_PLUS, VK_OEM_MINUS).
        Aggiungi(Windows.System.VirtualKey.Add, () => CambiaZoom(1));
        Aggiungi((Windows.System.VirtualKey)187, () => CambiaZoom(1));
        // Sulle tastiere americane il + è Maiusc più il tasto dell'uguale.
        Aggiungi((Windows.System.VirtualKey)187, () => CambiaZoom(1), Windows.System.VirtualKeyModifiers.Shift);
        Aggiungi(Windows.System.VirtualKey.Subtract, () => CambiaZoom(-1));
        Aggiungi((Windows.System.VirtualKey)189, () => CambiaZoom(-1));

        void Aggiungi(Windows.System.VirtualKey tasto, Func<bool> azione,
            Windows.System.VirtualKeyModifiers modificatori = Windows.System.VirtualKeyModifiers.None)
        {
            var acceleratore = new KeyboardAccelerator { Key = tasto, Modifiers = modificatori };
            acceleratore.Invoked += (_, evento) =>
            {
                // Mentre si scrive o si sposta un cursore il tasto resta a quel controllo.
                if (TastieraOccupata()) return;
                evento.Handled = azione();
            };
            radice.KeyboardAccelerators.Add(acceleratore);
        }
        // Senza questo, Windows mostrerebbe un suggerimento «F11» su ogni controllo.
        radice.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
    }

    private bool TastieraOccupata() =>
        Content?.XamlRoot is { } xamlRoot
        && FocusManager.GetFocusedElement(xamlRoot) is TextBox or PasswordBox or RichEditBox or AutoSuggestBox or Slider;

    /// <summary>Restituisce vero se il tasto è servito: senza telefono o senza quell'obiettivo il tasto passa oltre.</summary>
    private bool ScegliObiettivo(int numero)
    {
        if (sessione is null || PannelloComandi.Visibility != Visibility.Visible) return false;
        if (Scorciatoie.Obiettivo(numero, SceltaObiettivo.Items.Count) is not int indice) return false;
        // SuObiettivo manda il comando al telefono, come scegliendo dall'elenco.
        SceltaObiettivo.SelectedIndex = indice;
        return true;
    }

    private bool CambiaZoom(int verso)
    {
        if (sessione is null || PannelloComandi.Visibility != Visibility.Visible || CursoreZoom.Visibility != Visibility.Visible) return false;
        // SuZoom manda il comando al telefono.
        CursoreZoom.Value = Scorciatoie.Zoom(CursoreZoom.Value, CursoreZoom.Maximum, verso);
        return true;
    }

    // MARK: finestra mini (round 2, funzione 41)

    /// Tornando dalla finestra mini, la finestra si rimette dov'era (ultimaPosizione) e massimizzata se lo era.
    private bool massimizzataPrimaDelMini;

    private bool InMini => AppWindow.Presenter.Kind == AppWindowPresenterKind.CompactOverlay;

    /// <summary>Il video in una finestrella sempre in primo piano (sovrapposizione compatta di Windows).</summary>
    private void ImpostaMini(bool mini)
    {
        if (mini == InMini) return;
        if (mini)
        {
            RicordaPosizione();
            massimizzataPrimaDelMini = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Maximized };
            var presentatore = CompactOverlayPresenter.Create();
            presentatore.InitialSize = CompactOverlaySize.Medium;
            AppWindow.SetPresenter(presentatore);
        }
        else
        {
            // Si legge prima: cambiando presentatore la finestra è già «normale» con la misura del mini,
            // e SuCambioFinestra ricorderebbe quella al posto della finestra di prima.
            var prima = ultimaPosizione;
            AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            // Si torna alla finestra normale di prima, massimizzata se lo era.
            if (prima is { } r) AppWindow.MoveAndResize(new RectInt32(r.X, r.Y, r.Larghezza, r.Altezza));
            if (massimizzataPrimaDelMini && AppWindow.Presenter is OverlappedPresenter presentatore) presentatore.Maximize();
        }
    }

    /// <summary>Nella finestra mini spariscono colonne, titolo e statistiche: resta il video, intero.</summary>
    private void AggiornaModalita()
    {
        var mini = InMini;
        var nascosto = mini ? Visibility.Collapsed : Visibility.Visible;
        ColonnaSinistra.Width = new GridLength(mini ? 0 : 230);
        ColonnaDestra.Width = new GridLength(mini ? 0 : 300);
        PannelloSinistro.Visibility = nascosto;
        PannelloDestro.Visibility = nascosto;
        Intestazione.Visibility = nascosto;
        AvvisoMicrofono.Visibility = nascosto;
        BarraCavo.Visibility = nascosto;
        BarraDiagnosi.Visibility = nascosto;
        BarraStatistiche.Visibility = nascosto;
        PulsanteTornaFinestra.Visibility = mini ? Visibility.Visible : Visibility.Collapsed;
        PannelloAnteprima.Padding = new Thickness(mini ? 0 : 16);
        ScorrimentoAnteprima.BorderThickness = mini ? new Thickness(0) : new Thickness(1, 1, 1, 0);
        ScorrimentoAnteprima.CornerRadius = mini ? new CornerRadius(0) : new CornerRadius(8, 0, 0, 0);
        ScorrimentoAnteprima.VerticalScrollBarVisibility = mini ? ScrollBarVisibility.Disabled : ScrollBarVisibility.Auto;
        RiquadroVideo.CornerRadius = new CornerRadius(mini ? 0 : 8);
        RiquadroVideo.Height = mini ? ScorrimentoAnteprima.ActualHeight : double.NaN;
    }

    private void SuCambioFinestra(AppWindow finestra, AppWindowChangedEventArgs cambio)
    {
        if (cambio.DidPresenterChange) AggiornaModalita();
        if (cambio.DidPositionChange || cambio.DidSizeChange) RicordaPosizione();
    }

    // MARK: dimensione e posizione (round 2, funzione 47)

    /// L'ultima posizione della finestra normale: né massimizzata, né mini, né a schermo intero.
    private Rettangolo? ultimaPosizione;
    private bool massimizzaAllaPrimaApertura;

    private void RipristinaPosizione()
    {
        if (Preferenze.Finestra?.Su(AreeDegliSchermi()) is { } posizione)
        {
            var r = posizione.Rettangolo;
            AppWindow.MoveAndResize(new RectInt32(r.X, r.Y, r.Larghezza, r.Altezza));
            massimizzaAllaPrimaApertura = posizione.Massimizzata;
            ultimaPosizione = r;
        }
        else
        {
            AppWindow.Resize(new SizeInt32(1280, 800));
        }
    }

    private void RicordaPosizione()
    {
        if (!AppWindow.IsVisible || AppWindow.Presenter is not OverlappedPresenter { State: OverlappedPresenterState.Restored }) return;
        ultimaPosizione = new Rettangolo(AppWindow.Position.X, AppWindow.Position.Y, AppWindow.Size.Width, AppWindow.Size.Height);
    }

    private void SalvaPosizione()
    {
        RicordaPosizione();
        if (ultimaPosizione is not { } r) return;
        var massimizzata = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Maximized };
        Preferenze.Finestra = new PosizioneFinestra(r, massimizzata);
    }

    /// <summary>Le aree di lavoro degli schermi collegati adesso, senza la barra delle applicazioni.</summary>
    private static List<Rettangolo> AreeDegliSchermi()
    {
        var aree = new List<Rettangolo>();
        try
        {
            // Con l'indice e non con foreach: l'elenco di DisplayArea non sempre si lascia enumerare.
            var schermi = DisplayArea.FindAll();
            for (var i = 0; i < schermi.Count; i++)
            {
                var area = schermi[i].WorkArea;
                aree.Add(new Rettangolo(area.X, area.Y, area.Width, area.Height));
            }
        }
        catch (Exception)
        {
            var area = DisplayArea.Primary.WorkArea;
            aree.Add(new Rettangolo(area.X, area.Y, area.Width, area.Height));
        }
        return aree;
    }

    private void SuDimensioniAnteprima(object sender, SizeChangedEventArgs e)
    {
        if (InMini) RiquadroVideo.Height = e.NewSize.Height;
    }

    private void SuFinestraMini(object sender, RoutedEventArgs e) => ImpostaMini(true);

    private void SuTornaFinestra(object sender, RoutedEventArgs e) => ImpostaMini(false);

    private void SuDoppioToccoVideo(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (InMini) ImpostaMini(false);
    }

    /// <summary>Dal menu dell'icona: apre la finestra mini, anche se la finestra era nascosta.</summary>
    private void ApriMini()
    {
        MostraFinestra();
        ImpostaMini(true);
    }

    /// <summary>Un altro telefono parte in automatico: i comandi tornano come all'apertura, senza inviare nulla.</summary>
    private void AzzeraComandi()
    {
        aggiornoComandi = true;
        CursoreZoom.Value = 1;
        CursoreEsposizione.Value = 0;
        EsposizioneManuale.IsOn = false;
        BiancoAutomatico.IsOn = true;
        PulsanteTorcia.IsChecked = false;
        MostraComandiAvanzati();
        aggiornoComandi = false;
    }

    private void Comanda(Comando comando)
    {
        if (aggiornoComandi || sessione is not { } attiva) return;
        _ = attiva.ComandaAsync(comando);
    }

    private void SuObiettivo(object sender, SelectionChangedEventArgs e)
    {
        if (SceltaObiettivo.SelectedItem is ComboBoxItem { Tag: string obiettivo })
        {
            // Può arrivare mentre si applica un profilo: il flag torna com'era.
            var prima = aggiornoComandi;
            aggiornoComandi = true;
            CursoreZoom.Value = 1;
            aggiornoComandi = prima;
            Comanda(new Comando(Obiettivo: obiettivo));
        }
    }

    private void SuZoom(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Zoom: e.NewValue));

    private void SuEsposizione(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Esposizione: Math.Round(e.NewValue, 1)));

    // MARK: profili della fotocamera (funzione 23)

    private void SuAperturaProfili(object? sender, object e)
    {
        MenuProfili.Items.Clear();
        var profili = Preferenze.Profili;
        foreach (var nome in profili.Keys.Order())
        {
            var voce = new MenuFlyoutItem { Text = nome };
            voce.Click += (_, _) => ApplicaProfilo(profili[nome]);
            MenuProfili.Items.Add(voce);
        }
        if (profili.Count > 0) MenuProfili.Items.Add(new MenuFlyoutSeparator());
        var salva = new MenuFlyoutItem { Text = "Salva i comandi attuali…" };
        salva.Click += async (_, _) =>
        {
            // async void: se c'è già una finestra di dialogo aperta, ShowAsync fallisce e non deve chiudere l'app.
            try { await ChiediNomeProfiloAsync(); }
            catch (Exception) { }
        };
        MenuProfili.Items.Add(salva);
        if (profili.Count == 0) return;
        var elimina = new MenuFlyoutSubItem { Text = "Elimina" };
        foreach (var nome in profili.Keys.Order())
        {
            var voce = new MenuFlyoutItem { Text = nome };
            voce.Click += (_, _) =>
            {
                var rimasti = Preferenze.Profili;
                rimasti.Remove(nome);
                Preferenze.Profili = rimasti;
            };
            elimina.Items.Add(voce);
        }
        MenuProfili.Items.Add(elimina);
    }

    private async Task ChiediNomeProfiloAsync()
    {
        var casella = new TextBox { PlaceholderText = "Nome, per esempio «Riunione»" };
        var finestra = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Nuovo profilo",
            Content = new StackPanel
            {
                Spacing = 8,
                Children =
                {
                    new TextBlock { Text = "Obiettivo, zoom, esposizione, bianco e torcia di adesso. Con lo stesso nome il profilo si sovrascrive.", TextWrapping = TextWrapping.Wrap },
                    casella,
                },
            },
            PrimaryButtonText = "Salva",
            CloseButtonText = "Annulla",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await finestra.ShowAsync() != ContentDialogResult.Primary) return;
        var nome = casella.Text.Trim();
        if (nome.Length == 0) return;
        var profili = Preferenze.Profili;
        profili[nome] = new ProfiloFotocamera(
            SceltaObiettivo.SelectedItem is ComboBoxItem { Tag: string obiettivo } ? obiettivo : null,
            CursoreZoom.Value, PulsanteTorcia.IsChecked == true, CursoreEsposizione.Value,
            BiancoAutomatico.IsOn, CursoreBianco.Value, EsposizioneManuale.IsOn, CursoreIso.Value, TempoScelto);
        Preferenze.Profili = profili;
    }

    /// <summary>Mette i comandi come nel profilo e li manda al telefono in un solo messaggio.</summary>
    private void ApplicaProfilo(ProfiloFotocamera profilo)
    {
        if (capacitaAttuali is not { } capacita) return;
        var obiettivo = profilo.Obiettivo is { } scelto && capacita.Obiettivi.Contains(scelto) ? scelto : null;
        var manuale = profilo.EsposizioneManuale && capacita.IsoMinimo is not null;

        aggiornoComandi = true;
        if (obiettivo is not null)
        {
            SceltaObiettivo.SelectedItem = SceltaObiettivo.Items.OfType<ComboBoxItem>().FirstOrDefault(voce => (string)voce.Tag == obiettivo);
        }
        CursoreZoom.Value = Math.Clamp(profilo.Zoom, CursoreZoom.Minimum, CursoreZoom.Maximum);
        PulsanteTorcia.IsChecked = capacita.Torcia && profilo.Torcia;
        CursoreEsposizione.Value = profilo.Esposizione;
        BiancoAutomatico.IsOn = profilo.BiancoAutomatico;
        CursoreBianco.Value = profilo.Bianco;
        EsposizioneManuale.IsOn = manuale;
        CursoreIso.Value = Math.Clamp(profilo.Iso, CursoreIso.Minimum, CursoreIso.Maximum);
        SceltaTempo.SelectedItem = SceltaTempo.Items.OfType<ComboBoxItem>().FirstOrDefault(voce => (string)voce.Tag == profilo.Tempo.ToString())
            ?? SceltaTempo.SelectedItem;
        MostraComandiAvanzati();
        aggiornoComandi = false;

        Comanda(new Comando(Obiettivo: obiettivo, Zoom: CursoreZoom.Value,
            Torcia: capacita.Torcia ? profilo.Torcia : null,
            Esposizione: profilo.Esposizione,
            Bianco: profilo.BiancoAutomatico ? 0 : (int)profilo.Bianco,
            Iso: manuale ? Math.Round(CursoreIso.Value) : 0, Tempo: manuale ? profilo.Tempo : 0));
    }

    private int TempoScelto => SceltaTempo.SelectedItem is ComboBoxItem { Tag: string testo } ? int.Parse(testo) : 60;

    private void SuEsposizioneManuale(object sender, RoutedEventArgs e)
    {
        if (PannelloManuale is null) return;
        var manuale = EsposizioneManuale.IsOn;
        MostraComandiAvanzati();
        Comanda(manuale ? new Comando(Iso: Math.Round(CursoreIso.Value), Tempo: TempoScelto) : new Comando(Iso: 0, Tempo: 0));
    }

    private void SuIso(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Iso: Math.Round(e.NewValue)));

    private void SuTempo(object sender, SelectionChangedEventArgs e)
    {
        if (EsposizioneManuale is null) return;
        Comanda(new Comando(Tempo: TempoScelto));
    }

    private void SuBiancoAutomatico(object sender, RoutedEventArgs e)
    {
        // Toggled può scattare mentre la finestra si sta ancora creando.
        if (CursoreBianco is null) return;
        MostraComandiAvanzati();
        Comanda(new Comando(Bianco: BiancoAutomatico.IsOn ? 0 : (int)CursoreBianco.Value));
    }

    private void SuBianco(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Bianco: (int)e.NewValue));

    private void SuTorcia(object sender, RoutedEventArgs e) => Comanda(new Comando(Torcia: PulsanteTorcia.IsChecked == true));

    private void SuFuoco(object sender, RoutedEventArgs e) => Comanda(new Comando(Fuoco: "continuo"));
}
