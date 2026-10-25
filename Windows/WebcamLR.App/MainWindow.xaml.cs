using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using Windows.Storage.Streams;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Collega la finestra al ricevitore: annuncio in rete, QR code, telefoni collegati (P21 in MainWindow.Telefoni.cs),
/// latenza. Tre colonne come sul Mac (Mac/Sorgenti/ContenutoPrincipale.swift): dispositivi, connessione e uscite a
/// sinistra; video e barra delle azioni al centro; profilo, fotocamera ed effetti a destra (MainWindow.Fotocamera.cs,
/// MainWindow.Effetti.cs). Il video si vede in finestra (AnteprimaVideo) e va alla webcam «WebcamLR» per le altre app
/// (UscitaWebcam, 1.24); foto e registrazioni in MainWindow.Riprese.cs (P18).
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
    /// <summary>Registro del collegamento (1.5): gli ultimi 50 eventi, solo in memoria, dal pulsante a sinistra.</summary>
    private readonly RegistroCollegamento registro = new();
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
    /// Null se Windows non ha creato l'icona: allora chiudere la finestra chiude l'app (non resterebbe modo di riaprirla).
    private readonly IconaTray? iconaTray;
    private readonly Notifiche notifiche;
    /// Le notifiche servono solo quando la finestra non è davanti: altrimenti basta quello che si vede.
    private bool inPrimoPiano;
    /// Null solo se Windows non dice dov'è l'exe: allora l'interruttore resta spento e disattivato.
    private readonly AvvioConWindows? avvioConWindows =
        Environment.ProcessPath is { } percorso ? new AvvioConWindows(new RegistroWindows(), percorso) : null;
    private bool aggiornoAvvio;
    /// Vero solo quando si sceglie «Esci»: altrimenti chiudere la finestra la nasconde.
    private bool uscita;
    /// Lo stato del telefono nella webcam (P21: con due telefoni, quello scelto).
    private StatoCollegamento statoCollegamento;
    /// Vero mentre la finestra imposta i comandi da codice: in quel caso non si manda nulla al telefono.
    private bool aggiornoComandi;
    /// <summary>Quanti indirizzi IPv4 ha il PC adesso (per «Wi-Fi: Nessuna rete»).</summary>
    private int indirizziRete = -1;

    public MainWindow()
    {
        InitializeComponent();
        RipristinaPosizione();
        // Percorso completo: lanciata da «Avvia con Windows» o da un'altra cartella, un percorso relativo non si trova.
        try { AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "WebcamLR.ico")); }
        catch (Exception) { }
        ColoraBarraDelTitolo();
        coda = DispatcherQueue.GetForCurrentThread();

        abbinamento = new Abbinamento(Preferenze.Identita(), Preferenze.TelefoniFidati,
            fidati => Preferenze.TelefoniFidati = new Dictionary<string, string>(fidati));
        // Gettone usato da un telefono: il QR code ne mostra subito uno nuovo; i telefoni noti a sinistra cambiano.
        abbinamento.GettoneCambiato += () => coda.TryEnqueue(() =>
        {
            _ = MostraQRAsync();
            MostraTelefoni();
        });
        abbinamento.ChiediConferma = ChiediConfermaAsync;
        // WebcamLR Pro: due telefoni insieme solo se quello nella webcam l'ha sbloccato (come sul Mac).
        telefoni.RichiedePro = true;

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
        cavo.StatoCambiato += stato =>
        {
            registro.Aggiungi(stato switch
            {
                StatoCavo.Collegato => "Cavo USB: collegato",
                StatoCavo.InAscolto => "Cavo USB: in ascolto",
                _ => "Cavo USB: servizio di Apple assente",
            });
            coda.TryEnqueue(() =>
            {
                AggiornaConnessione();
                _ = AggiornaDiagnosiAsync();
            });
        };
        cavo.Evento += testo =>
        {
            registro.Aggiungi(testo);
            coda.TryEnqueue(() =>
            {
                AggiornaConnessione();
                _ = AggiornaDiagnosiAsync();
            });
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
        _ = MostraQRAppAsync();
        CollegamentoDownload.NavigateUri = new Uri(InfoApp.Download);
        // Cambio di Wi-Fi o cavo collegato: il QR deve avere gli indirizzi nuovi.
        System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += SuCambioRete;
        registro.Aggiungi($"WebcamLR avviata · porta {ascoltatore.Porta}");
        CreaLivelloMicrofono();
        InizializzaFotocamera();
        MostraObiettiviDiEsempio();
        Mostra(StatoCollegamento.NessunTelefono);
        _ = AggiornaDiagnosiAsync();

        AggiungiScorciatoie();
        AppWindow.Changed += SuCambioFinestra;
        MostraAvvioConWindows();
        InizializzaWebcam();
        InizializzaEffetti();
        InizializzaPausa();
        InizializzaAppInUso();
        InizializzaAggiornamenti();
        InizializzaAttesa();
        MostraRegistrazione();
        MostraTimer();

        try { iconaTray = new IconaTray(apri: MostraFinestra, mini: ApriMini, scollega: () => _ = ScollegaAsync(), esci: Esci); }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
            registro.Aggiungi("Icona accanto all'orologio non disponibile: chiudere la finestra chiude WebcamLR");
        }
        notifiche = new Notifiche(clic: () => coda.TryEnqueue(MostraFinestra));
        Activated += (_, evento) => inPrimoPiano = evento.WindowActivationState != WindowActivationState.Deactivated;
        AppWindow.Closing += (_, evento) =>
        {
            SalvaPosizione();
            if (uscita) return;
            if (iconaTray is null)
            {
                Esci();
                return;
            }
            evento.Cancel = true;
            AppWindow.Hide();
        };
        Closed += async (_, _) =>
        {
            // async void: un errore nella chiusura non deve diventare un crash all'uscita.
            try
            {
                // Prima di tutto, e senza await: la registrazione si chiude bene anche se l'app sta uscendo.
                ChiudiRiprese();
                System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged -= SuCambioRete;
                controlloDiagnosi.Stop();
                reteAssestata.Stop();
                risveglioAssestato.Stop();
                controlloRisveglio.Stop();
                FermaPausa();
                FermaAppInUso();
                FermaAggiornamenti();
                finestraGobbo?.Chiudi();
                risveglio.Dispose();
                iconaTray?.Dispose();
                notifiche.Dispose();
                annuncio.Dispose();
                ascoltatore.Dispose();
                await cavo.DisposeAsync();
                uscitaWebcam.Dispose();
                await ChiudiTuttiAsync();
            }
            catch (Exception) { }
        };
    }

    /// <summary>
    /// La barra del titolo di Windows nei colori della finestra (verde scuro), così non resta una striscia grigia sopra
    /// l'intestazione. Su Windows 10 senza personalizzazione resta quella di sistema.
    /// </summary>
    private void ColoraBarraDelTitolo()
    {
        try
        {
            if (!AppWindowTitleBar.IsCustomizationSupported()) return;
            var barra = AppWindow.TitleBar;
            var fondo = ColorHelper.FromArgb(255, 0x15, 0x24, 0x1F);
            var testo = ColorHelper.FromArgb(255, 0xE6, 0xEE, 0xEA);
            var tenue = ColorHelper.FromArgb(255, 0x9D, 0xB0, 0xA7);
            barra.BackgroundColor = fondo;
            barra.InactiveBackgroundColor = fondo;
            barra.ForegroundColor = testo;
            barra.InactiveForegroundColor = tenue;
            barra.ButtonBackgroundColor = fondo;
            barra.ButtonInactiveBackgroundColor = fondo;
            barra.ButtonForegroundColor = testo;
            barra.ButtonInactiveForegroundColor = tenue;
            barra.ButtonHoverBackgroundColor = ColorHelper.FromArgb(255, 0x22, 0x35, 0x2F);
            barra.ButtonHoverForegroundColor = testo;
            barra.ButtonPressedBackgroundColor = ColorHelper.FromArgb(255, 0x2E, 0x44, 0x3D);
            barra.ButtonPressedForegroundColor = testo;
        }
        catch (Exception) { }
    }

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
                                Foreground = Pennello("Accento"),
                            },
                            new TextBlock
                            {
                                Text = "Se il codice è diverso, o non conosci questo telefono, non consentire.",
                                TextWrapping = TextWrapping.Wrap,
                                Foreground = Pennello("TestoSecondario"),
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

    /// <summary>Falso se l'icona accanto all'orologio non c'è: allora l'app non può partire nascosta.</summary>
    public bool HaIconaTray => iconaTray is not null;

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
        // La registrazione si chiude e si salva prima di tutto il resto (anche Close la chiuderebbe: una volta sola).
        ChiudiRiprese();
        Close();
        Application.Current.Exit();
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

    /// <summary>
    /// La pillola in alto segue lo stato, come PillolaStato di Stile: corallo pieno solo «in onda», verde salvia
    /// collegato, ambra riconnessione, contorno senza telefono.
    /// </summary>
    private void Mostra(StatoCollegamento stato)
    {
        statoCollegamento = stato;
        var inOndaOra = stato == StatoCollegamento.Collegato && inOnda;
        switch (stato)
        {
            case StatoCollegamento.Collegato when inOnda:
                // Il video va a un'app (Zoom, Teams…): l'unico caso di corallo, come sul Mac e sul telefono.
                TestoStato.Text = "IN ONDA";
                TestoStato.Foreground = new SolidColorBrush(Colors.White);
                PuntoStato.Fill = new SolidColorBrush(Colors.White);
                PuntoStato.Stroke = null;
                PillolaStato.Background = Pennello("TallyPieno");
                PillolaStato.BorderThickness = new Thickness(0);
                MessaggioAnteprima.Text = "Collegato: in attesa del video…";
                break;
            case StatoCollegamento.Collegato:
                // In pausa: calmo, come «collegato» (il corallo resta solo per «in onda» e la registrazione).
                TestoStato.Text = InPausa ? "COLLEGATO · IN PAUSA" : "COLLEGATO";
                TestoStato.Foreground = Pennello("Testo");
                PuntoStato.Fill = Pennello("Verde");
                PuntoStato.Stroke = null;
                PillolaStato.Background = Pennello("PannelloChiaro");
                PillolaStato.BorderThickness = new Thickness(0);
                MessaggioAnteprima.Text = "Collegato: in attesa del video…";
                break;
            case StatoCollegamento.Riconnessione:
                TestoStato.Text = "RICONNESSIONE";
                TestoStato.Foreground = Pennello("AmbraTesto");
                PuntoStato.Fill = Pennello("Ambra");
                PuntoStato.Stroke = null;
                PillolaStato.Background = Pennello("AmbraTenue");
                PillolaStato.BorderThickness = new Thickness(0);
                MessaggioAnteprima.Text = "Collegamento perso: aspetto che il telefono torni.";
                break;
            default:
                TestoStato.Text = "NESSUN TELEFONO";
                TestoStato.Foreground = Pennello("TestoTenue");
                PuntoStato.Fill = null;
                PuntoStato.Stroke = Pennello("TestoTenue");
                PillolaStato.Background = null;
                PillolaStato.BorderThickness = new Thickness(1);
                MessaggioAnteprima.Text = "";
                break;
        }
        // Il bordo del video: corallo quando è in onda (tally), altrimenti la linea del pannello.
        BordoVideo.BorderBrush = Pennello(inOndaOra ? "Tally" : "Linea");
        BordoVideo.BorderThickness = new Thickness(inOndaOra && !vistaPulita && !InMini ? 2 : vistaPulita || InMini ? 0 : 1);
        // Senza telefono: QR grande e tre passi al centro, al posto del messaggio (round 2, funzione 46).
        var senzaTelefono = stato == StatoCollegamento.NessunTelefono;
        PrimoAvvio.Visibility = Visibile(senzaTelefono);
        PannelloMessaggio.Visibility = Visibile(!senzaTelefono);
        PannelloAttesa.Visibility = Visibile(senzaTelefono);
        // «Collegamento interrotto» lo dice la schermata di attesa sopra il video (MostraPausa), come nelle app.
        PillolaRiconnessione.Visibility = Visibility.Collapsed;
        PulsanteScollega.Visibility = Visibile(!senzaTelefono);
        ToolTipService.SetToolTip(PulsanteScollega, telefoni.Conteggio > 1
            ? $"Scollega «{telefono?.Nome}», quello nella webcam: non si ricollega da solo"
            : "Scollega il telefono: non si ricollega da solo");
        AdattaLayout();
        AggiornaTelefono();
        MostraDiagnosi();
        MostraPausa();
        // P21: il video grande, il riquadro piccolo e le schede dei telefoni.
        MostraVideo();
        MostraTelefoni();
    }

    private static Brush Pennello(string nome) => (Brush)Application.Current.Resources[nome];

    private static Visibility Visibile(bool visibile) => visibile ? Visibility.Visible : Visibility.Collapsed;

    private void AggiornaTelefono()
    {
        AggiornaChip();
        AggiornaConnessione();
        // Nel costruttore la prima chiamata arriva prima che l'icona esista.
        iconaTray?.Aggiorna(statoCollegamento, telefono?.Nome, statistiche?.LatenzaMs);
        AggiornaDisponibilita();
        TestoRete.Text = $"Visibile in rete · porta {ascoltatore.Porta}";
        TestoRete.Visibility = Visibile(telefono is null && !BarraDiagnosi.IsOpen);

        // Perché i comandi sono grigi. Durante la riconnessione il telefono c'è ancora: non si chiede di collegarne uno.
        DettagliFotocamera.Text = telefono is null ? "Si attivano quando colleghi un telefono."
            : statoCollegamento == StatoCollegamento.Riconnessione ? "Mi ricollego al telefono: i comandi tornano appena il video riprende."
            : capacitaAttuali is null ? "Il telefono è collegato: i comandi arrivano tra un attimo."
            : "";
        DettagliFotocamera.Visibility = Visibile(DettagliFotocamera.Text.Length > 0);
        // P21: con due telefoni si dice per quale valgono i comandi a destra.
        TelefonoDeiComandi.Visibility = Visibile(telefoni.Conteggio > 1 && telefono is not null);
        NomeTelefonoDeiComandi.Text = telefono?.Nome ?? "";
        ToolTipService.SetToolTip(TelefonoDeiComandi, $"I comandi valgono per «{telefono?.Nome}», il telefono nella webcam");

        if (telefono is null || Scelto is not { } scelto) return;
        NomeTelefono.Text = scelto.Nome;
        PuntoTelefono.Fill = Pennello(scelto.InRiconnessione ? "Ambra" : "Verde");
        DettagliTelefono.Text = DettagliScheda(scelto);
        MostraBatteria(BatteriaTelefono, scelto.Stato);
        MostraCaldo(CaldoTelefono, scelto.Stato);
        AutomationProperties.SetName(SchedaTelefono, $"{scelto.Nome}, {(scelto.InRiconnessione ? "in riconnessione" : "collegato")}");
    }

    /// <summary>«Wi-Fi · 38 ms · Avvio: 0,9 s», oppure cosa sta succedendo (riconnessione, pausa), come la scheda del Mac.</summary>
    private static string DettagliScheda(TelefonoCollegato collegato)
    {
        if (collegato.InRiconnessione) return $"Mi ricollego a {collegato.Nome}…";
        var parti = new List<string> { collegato.Collegamento?.Testo() ?? "—" };
        if (collegato.InPausa) parti.Add("in pausa");
        parti.Add(collegato.Statistiche?.LatenzaMs is int ms ? $"{ms} ms" : "— ms");
        if (collegato.TestoAvvio is { } avvio) parti.Add(avvio);
        return string.Join(" · ", parti);
    }

    /// <summary>La batteria del telefono: percentuale, «in carica»; ambra sotto il 20% senza caricatore.</summary>
    private static void MostraBatteria(TextBlock testo, StatoTelefono? stato)
    {
        if (stato is not { Batteria: >= 0 } s)
        {
            testo.Text = "";
            return;
        }
        testo.Text = s.InCarica ? $"⚡{s.Batteria}%" : $"{s.Batteria}%";
        testo.Foreground = Pennello(s.Batteria <= 20 && !s.InCarica ? "Ambra" : "TestoSecondario");
        AutomationProperties.SetName(testo, s.InCarica ? $"Batteria del telefono: {s.Batteria}%, in carica" : $"Batteria del telefono: {s.Batteria}%");
    }

    /// <summary>«Telefono caldo», in ambra da «molto caldo» in su; niente se è normale.</summary>
    private static void MostraCaldo(TextBlock testo, StatoTelefono? stato)
    {
        testo.Text = stato?.Temperatura switch
        {
            Temperatura.Calda => "Telefono caldo",
            Temperatura.MoltoCalda => "Telefono molto caldo",
            Temperatura.Critica => "Telefono troppo caldo",
            _ => "",
        };
        testo.Foreground = Pennello(stato?.Temperatura == Temperatura.Calda ? "TestoSecondario" : "Ambra");
        testo.Visibility = Visibile(testo.Text.Length > 0);
    }

    // MARK: chip sul video (qualità, formato, strada) e numeri

    /// <summary>
    /// In basso a sinistra sul video, solo con il video che arriva: la qualità in parole con le tacche (un clic apre i
    /// numeri e il grafico della latenza), risoluzione · fps · formato e la strada del collegamento.
    /// </summary>
    private void AggiornaChip()
    {
        var visibili = telefono is not null && statoCollegamento == StatoCollegamento.Collegato && statistiche is { Larghezza: > 0 }
            && !vistaPulita && !InPausa;
        ChipVideo.Visibility = Visibile(visibili);
        if (!visibili || statistiche is not { } s)
        {
            if (FinestraNumeri.IsOpen) FinestraNumeri.Hide();
            return;
        }
        if (s.LatenzaMs is int ms)
        {
            var qualita = Qualita.Da(ms);
            var colore = Pennello(qualita switch
            {
                QualitaCollegamento.Ottima => "Verde",
                QualitaCollegamento.Buona => "AccentoChiaro",
                _ => "AmbraTesto",
            });
            var spenta = Pennello("Linea");
            var tacche = new[] { Tacca1, Tacca2, Tacca3 };
            for (var i = 0; i < tacche.Length; i++) tacche[i].Fill = i < qualita.Tacche() ? colore : spenta;
            TestoQualita.Text = qualita.Testo();
            TestoQualita.Foreground = colore;
            TestoLatenza.Text = $"{ms} ms";
            AutomationProperties.SetName(ChipQualita, $"Collegamento {qualita.Testo().ToLowerInvariant()}, {ms} millisecondi: mostra i numeri");
        }
        else
        {
            foreach (var tacca in new[] { Tacca1, Tacca2, Tacca3 }) tacca.Fill = Pennello("Linea");
            TestoQualita.Text = "Misuro il collegamento…";
            TestoQualita.Foreground = Pennello("Testo");
            TestoLatenza.Text = "";
        }
        var corto = Math.Min(s.Larghezza, s.Altezza);
        TestoFormatoVideo.Text = $"{corto}p · {s.Fps} fps · {(s.Codec == Codec.Hevc ? "HEVC" : "H.264")}";
        if (collegamento is { } tipo)
        {
            IconaCollegamento.Glyph = tipo switch
            {
                TipoCollegamento.CavoUsb => "",
                TipoCollegamento.CavoDiRete => "",
                TipoCollegamento.Hotspot => "",
                _ => "",
            };
            TestoCollegamento.Text = tipo.Testo();
            ToolTipService.SetToolTip(ChipCollegamento, tipo.Consiglio() ?? "Collegato con il cavo USB: il collegamento più stabile.");
            AutomationProperties.SetName(ChipCollegamento, $"Collegamento: {tipo.Testo()}");
            ChipCollegamento.Visibility = Visibility.Visible;
        }
        else
        {
            ChipCollegamento.Visibility = Visibility.Collapsed;
        }
        if (FinestraNumeri.IsOpen) MostraNumeri();
    }

    /// <summary>I numeri di sempre, a un clic dal chip della qualità (funzioni 28 e 31), con il grafico dell'ultimo minuto.</summary>
    private void MostraNumeri()
    {
        if (statistiche is not { } s) return;
        var righe = new List<string>
        {
            $"Risoluzione   {s.Larghezza}×{s.Altezza}",
            $"Fotogrammi    {s.Fps} al secondo",
            $"Formato       {(s.Codec == Codec.Hevc ? "HEVC" : "H.264")}",
            $"Velocità      {s.MegabitAlSecondo.ToString("0.0", System.Globalization.CultureInfo.GetCultureInfo("it-IT"))} Mbit/s",
            $"Latenza       {(s.LatenzaMs is int l ? $"{l} ms" : "—")}",
        };
        if (storiaLatenza.Media is int media) righe.Add($"Media 60 s    {media} ms (massima {storiaLatenza.Massima} ms)");
        if (testoAvvio is { } avvio) righe.Add($"Avvio         {avvio.Split(':', 2).Last().Trim()}");
        TestoNumeri.Text = string.Join("\n", righe);
        var punti = storiaLatenza.Punti(GraficoLatenza.Width, GraficoLatenza.Height);
        var linea = new PointCollection();
        foreach (var (x, y) in punti) linea.Add(new Windows.Foundation.Point(x, y));
        LineaLatenza.Points = linea;
        Guida100.Y1 = Guida100.Y2 = storiaLatenza.AltezzaDi(100, GraficoLatenza.Height);
        GraficoLatenza.Visibility = Visibile(punti.Count >= 2);
    }

    // MARK: connessione (colonna di sinistra)

    /// <summary>Come sono collegati i telefoni adesso (con due telefoni possono essere due strade diverse).</summary>
    private HashSet<TipoCollegamento> StradeInUso() =>
        telefoni.Telefoni.Where(t => !t.InRiconnessione && t.Collegamento is not null).Select(t => t.Collegamento!.Value).ToHashSet();

    /// <summary>Wi-Fi, cavo USB e cavo di rete, come «Connessione» sul Mac: quella in uso nell'accento, su un fondo leggero.</summary>
    private void AggiornaConnessione()
    {
        var inUso = StradeInUso();
        var wifi = inUso.Contains(TipoCollegamento.WiFi) || inUso.Contains(TipoCollegamento.Hotspot);
        var statoWifi = inUso.Contains(TipoCollegamento.Hotspot) ? "In uso · Hotspot"
            : inUso.Contains(TipoCollegamento.WiFi) ? "In uso"
            : indirizziRete == 0 ? "Nessuna rete"
            : "Pronto";
        MostraRiga(RigaWifi, IconaWifi, NomeWifi, StatoWifi, statoWifi, wifi);
        var usb = inUso.Contains(TipoCollegamento.CavoUsb);
        var statoCavo = usb ? "In uso"
            : !cavo.Verificato ? "…"
            : cavo.Stato switch
            {
                StatoCavo.Collegato => "Collegato",
                StatoCavo.ServizioAssente => "Non disponibile",
                _ => cavo.IPhoneAlCavo ? "Apri l'app" : "Nessun iPhone",
            };
        MostraRiga(RigaCavo, IconaCavo, NomeCavo, StatoCavoTesto, statoCavo, usb);
        RigaCavoRete.Visibility = Visibile(inUso.Contains(TipoCollegamento.CavoDiRete));
    }

    private static void MostraRiga(Border riga, FontIcon icona, TextBlock nome, TextBlock stato, string testo, bool attiva)
    {
        riga.Background = attiva ? Pennello("AccentoTenue") : null;
        icona.Foreground = Pennello(attiva ? "Accento" : "TestoSecondario");
        nome.Foreground = Pennello(attiva ? "Testo" : "TestoTenue");
        nome.FontFamily = (FontFamily)Application.Current.Resources[attiva ? "CorpoEvidente" : "Corpo"];
        stato.Text = testo;
        stato.Foreground = Pennello(attiva ? "Verde" : "TestoSecondario");
        AutomationProperties.SetName(riga, $"{nome.Text}: {testo}");
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
            var (haRete, profilo, tethering, firewall) = await Task.Run(() =>
            {
                var haRete = IndirizziLocali.Ipv4().Count > 0;
                // La rete del Tethering USB di Android a parte: nasce «Pubblica» anche quando il Wi-Fi è privato.
                var (profilo, tethering) = ReteWindows.Profili();
                return (haRete, profilo, tethering, ReteWindows.Firewall(profilo, porta));
            });
            if (richiesta != richiesteDiagnosi) return;
            var nuovi = Diagnosi.Problemi(new SituazioneRete(haRete, profilo, firewall,
                cavo.Verificato ? cavo.Stato : null, cavo.IPhoneAlCavo, tethering));
            foreach (var nuovo in nuovi.Where(n => n.Grave && problemi.All(p => p.Id != n.Id)))
                registro.Aggiungi($"Diagnosi: {nuovo.Titolo}");
            problemi = nuovi;
            MostraDiagnosi();
            AggiornaConnessione();
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Il problema più grave in «Connessione», solo senza telefono. Sotto, i suggerimenti sul cavo:
    /// quello per «Dispositivi Apple» resta anche con un telefono in Wi-Fi, finché non lo si chiude.
    /// </summary>
    private void MostraDiagnosi()
    {
        var senzaTelefono = statoCollegamento == StatoCollegamento.NessunTelefono;
        MostraProblema(BarraDiagnosi, AzioneDiagnosi, RispostaDiagnosi, senzaTelefono ? problemi.FirstOrDefault(p => p.Grave) : null);
        var suggerimento = problemi.FirstOrDefault(p => !p.Grave);
        var daMostrare = suggerimento is not null && !suggerimentoCavoChiuso && (senzaTelefono || suggerimento.Id == "servizio-assente");
        MostraProblema(BarraCavo, AzioneCavo, RispostaCavo, daMostrare ? suggerimento : null);
        TestoRete.Visibility = Visibile(telefono is null && !BarraDiagnosi.IsOpen);
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
        risposta.Visibility = problema.IdDomanda is null ? Visibility.Collapsed : Visibility.Visible;
        barra.IsOpen = true;
    }

    /// <summary>Impostazioni di Windows, firewall o Microsoft Store, secondo il problema.</summary>
    private async void SuAzioneDiagnosi(object sender, RoutedEventArgs e)
    {
        // async void: un errore qui non deve chiudere l'app.
        try
        {
            if (sender is Button { Tag: string indirizzo } && Uri.TryCreate(indirizzo, UriKind.Absolute, out var uri))
                await Windows.System.Launcher.LaunchUriAsync(uri);
        }
        catch (Exception) { }
    }

    /// <summary>Apre «App e assistenza» sulla risposta giusta delle domande frequenti.</summary>
    private async void SuRispostaDiagnosi(object sender, RoutedEventArgs e)
    {
        try
        {
            if (sender is not FrameworkElement { Tag: string domanda }) return;
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), abbinamento, StatoPro(), domanda);
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
        try
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
        catch (Exception) { }
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
        try
        {
            var richiesta = ++richiesteQR;
            // Lo stesso nome che il telefono vede nell'elenco (AnnuncioWindows annuncia il nome del computer).
            TestoTerzoPasso.Text = $"Tocca «{Environment.MachineName}» nell'elenco, oppure «Inquadra il QR code del computer» e inquadra questo codice.";
            // Tutti gli indirizzi utili, il più probabile per primo (1.10): il telefono li prova insieme.
            // Leggere le schede di rete può richiedere decine di millisecondi: fuori dal thread dell'interfaccia.
            var indirizzi = await Task.Run(IndirizziLocali.Ipv4);
            if (richiesta != richiesteQR) return;
            indirizziRete = indirizzi.Count;
            AggiornaConnessione();
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
            IndirizzoScrittoGrande.Text = $"Oppure, sul telefono, scrivi l'indirizzo: {indirizzi[0]}{(porta == Servizio.PortaPredefinita ? "" : $":{porta}")}";

            // Il PNG del QR si prepara fuori dal thread dell'interfaccia.
            var png = await Task.Run(() => IndirizziLocali.QRCodePng(associazione));
            if (png is null || richiesta != richiesteQR) return;
            var immagine = await ImmagineDaPngAsync(png);
            if (richiesta != richiesteQR) return;
            ImmagineQR.Source = immagine;
            ImmagineQRGrande.Source = immagine;
            CorniceQRGrande.Visibility = Visibility.Visible;
        }
        catch (Exception) { }
    }

    /// <summary>In fondo a sinistra: il QR per scaricare WebcamLR sul telefono (la pagina del sito), non per collegarsi.</summary>
    private async Task MostraQRAppAsync()
    {
        try
        {
            var png = await Task.Run(() => IndirizziLocali.QRCodePng(InfoApp.Download));
            if (png is not null) ImmagineQRApp.Source = await ImmagineDaPngAsync(png);
        }
        catch (Exception) { }
    }

    private static async Task<BitmapImage> ImmagineDaPngAsync(byte[] png)
    {
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
        return immagine;
    }

    // MARK: microfono del telefono

    /// <summary>
    /// Le dodici tacche del livello del microfono, come sul Mac. Su Windows l'audio del telefono non arriva ancora:
    /// restano vuote, così si vede dov'è e cosa arriverà.
    /// </summary>
    private void CreaLivelloMicrofono()
    {
        for (var i = 0; i < 12; i++)
        {
            LivelloMicrofono.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var tacca = new Microsoft.UI.Xaml.Shapes.Rectangle { RadiusX = 1.5, RadiusY = 1.5, Fill = Pennello("PannelloChiaro") };
            Grid.SetColumn(tacca, i);
            LivelloMicrofono.Children.Add(tacca);
        }
    }

    // MARK: comandi visibili ma grigi senza telefono

    /// <summary>
    /// Tutto a vista, niente nascosto: senza telefono i comandi restano visibili ma grigi; la copertura trasparente sopra
    /// riceve il clic e dice cosa fare. Con un telefono gratis i comandi di WebcamLR Pro restano con il segno «PRO».
    /// </summary>
    private void AggiornaDisponibilita()
    {
        var comandi = telefono is not null && sessione is not null && capacitaAttuali is not null;
        Abilita(PannelloComandi, comandi);
        CoperturaComandi.Visibility = Visibile(!comandi);
        Abilita(GrigliaProfili, comandi);
        PulsanteProfili.IsEnabled = comandi;
        CoperturaProfilo.Visibility = Visibile(!comandi);
        Abilita(PannelloRegoleFini, comandi);
        CoperturaRegoleFini.Visibility = Visibile(!comandi);
        SceltaQualita.IsEnabled = comandi;
        CoperturaQualita.Visibility = Visibile(!comandi);
        MostraPulsantiVideo();
        AbilitaEffetti();
        AggiornaDisponibilitaRiprese();
        AggiornaPro();
    }

    private static void Abilita(Panel pannello, bool attivo)
    {
        foreach (var figlio in pannello.Children)
        {
            if (figlio is Control controllo) controllo.IsEnabled = attivo;
            else if (figlio is Panel interno) Abilita(interno, attivo);
            else if (figlio is Border { Child: Panel dentro }) Abilita(dentro, attivo);
        }
    }

    private Flyout? notaTelefono;

    private void SuComandoSenzaTelefono(object sender, TappedRoutedEventArgs e)
    {
        if (sender is not FrameworkElement copertura) return;
        var testo = telefono is not null && statoCollegamento == StatoCollegamento.Riconnessione
            ? "Mi ricollego al telefono: i comandi tornano tra un attimo."
            : telefono is not null ? "Il telefono è collegato: i comandi arrivano tra un attimo."
            : "Collega un telefono per usarlo.";
        notaTelefono ??= new Flyout
        {
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                Children =
                {
                    new FontIcon { Glyph = "", FontSize = 16, Foreground = Pennello("Accento") },
                    new TextBlock { VerticalAlignment = VerticalAlignment.Center },
                },
            },
        };
        if (notaTelefono.Content is StackPanel { Children: [_, TextBlock riga] }) riga.Text = testo;
        notaTelefono.ShowAt(copertura, new FlyoutShowOptions { Position = e.GetPosition(copertura), Placement = FlyoutPlacementMode.Top });
        e.Handled = true;
    }

    // MARK: registro (1.5)

    /// <summary>Il registro si aggiorna solo quando si vede: i più recenti in cima.</summary>
    private void MostraRegistro()
    {
        if (!FinestraRegistro.IsOpen) return;
        var testo = registro.Testo(recentiPrima: true);
        TestoRegistro.Text = testo.Length > 0 ? testo : "Ancora nessun evento.";
    }

    private void SuAperturaRegistro(object? sender, object e)
    {
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

    // MARK: «App e assistenza»

    /// <summary>«Aiuto» in alto: la finestra di «App e assistenza», sulla guida.</summary>
    private async void SuAiuto(object sender, RoutedEventArgs e)
    {
        try
        {
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), abbinamento, StatoPro(), apriGuida: true);
        }
        catch (Exception) { }
    }

    private async void SuApp(object sender, RoutedEventArgs e)
    {
        // async void: un errore qui non deve chiudere l'app.
        try
        {
            FinestraImpostazioni.Hide();
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), abbinamento, StatoPro());
        }
        catch (Exception) { }
    }

    /// <summary>Per la pagina «WebcamLR Pro»: il telefono nella webcam e le sue capacità.</summary>
    private (string? Nome, Capacita? Capacita) StatoPro() => (telefono?.Nome, sessione is null ? null : capacitaAttuali);

    /// <summary>Per «Segnala un bug»: solo dati tecnici, nessun dato personale oltre al nome del telefono.</summary>
    private List<(string Nome, string Valore)> DatiTecnici()
    {
        var dati = new List<(string, string)>
        {
            ("App", $"WebcamLR per Windows {VersioneApp}"),
            ("Sistema", Environment.OSVersion.VersionString),
        };
        if (telefono is { } ciao) dati.Add(("Telefono", $"{DescrizioneStato.NomePiattaforma(ciao.Piattaforma)} · app {ciao.VersioneApp}"));
        if (capacitaAttuali is { } capacita) dati.Add(("WebcamLR Pro", RegolePro.Attivo(capacita) ? "sì" : "no"));
        if (telefoni.Conteggio > 1) dati.Add(("Telefoni collegati", $"{telefoni.Conteggio}"));
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

    private static string VersioneApp => typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? "0";

    // MARK: tastiera

    private void AggiungiScorciatoie()
    {
        if (Content is not UIElement radice) return;
        var f11 = new KeyboardAccelerator { Key = Windows.System.VirtualKey.F11 };
        f11.Invoked += (_, evento) =>
        {
            AlternaSchermoIntero();
            evento.Handled = true;
        };
        var esc = new KeyboardAccelerator { Key = Windows.System.VirtualKey.Escape };
        esc.Invoked += (_, evento) =>
        {
            if (vistaPulita)
            {
                ImpostaVistaPulita(false);
                evento.Handled = true;
                return;
            }
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

        // Round 2 (funzione 43): 1–4 per gli obiettivi, + e − per lo zoom, F messa a fuoco, sulla riga dei numeri e sul tastierino.
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
        Aggiungi(Windows.System.VirtualKey.F, FuocoDaTastiera);

        // P18, come ⌘T, ⇧⌘T, ⌘R e ⌘C sul Mac. Senza telefono il tasto passa oltre (Ctrl+C copia il testo selezionato).
        var ctrl = Windows.System.VirtualKeyModifiers.Control;
        var maiusc = Windows.System.VirtualKeyModifiers.Shift;
        Aggiungi(Windows.System.VirtualKey.T, FotoDaTastiera, ctrl);
        Aggiungi(Windows.System.VirtualKey.T, TimerDaTastiera, ctrl | maiusc);
        Aggiungi(Windows.System.VirtualKey.R, RegistraDaTastiera, ctrl);
        Aggiungi(Windows.System.VirtualKey.C, CopiaDaTastiera, ctrl);
        // Come ⇧⌘P e ⇧⌘M sul Mac: vista pulita e finestra mini.
        Aggiungi(Windows.System.VirtualKey.P, () => { ImpostaVistaPulita(!vistaPulita); return true; }, ctrl | maiusc);
        Aggiungi(Windows.System.VirtualKey.M, () => { ImpostaMini(!InMini); return true; }, ctrl | maiusc);

        void Aggiungi(Windows.System.VirtualKey tasto, Func<bool> azione,
            Windows.System.VirtualKeyModifiers modificatori = Windows.System.VirtualKeyModifiers.None)
        {
            var acceleratore = new KeyboardAccelerator { Key = tasto, Modifiers = modificatori };
            acceleratore.Invoked += (_, evento) =>
            {
                // Mentre si scrive o si sposta un cursore il tasto resta a quel controllo; con Ctrl solo mentre si scrive
                // (Ctrl+C in una casella copia il testo).
                if (modificatori.HasFlag(Windows.System.VirtualKeyModifiers.Control) ? TestoInScrittura() : TastieraOccupata()) return;
                evento.Handled = azione();
            };
            radice.KeyboardAccelerators.Add(acceleratore);
        }
        // Senza questo, Windows mostrerebbe un suggerimento «F11» su ogni controllo.
        radice.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
    }

    private bool TastieraOccupata() =>
        Content?.XamlRoot is { } xamlRoot
        && FocusManager.GetFocusedElement(xamlRoot) is TextBox or PasswordBox or RichEditBox or AutoSuggestBox or Slider or ComboBox;

    private bool TestoInScrittura() =>
        Content?.XamlRoot is { } xamlRoot
        && FocusManager.GetFocusedElement(xamlRoot) is TextBox or PasswordBox or RichEditBox or AutoSuggestBox;

    // MARK: finestra mini, schermo intero e vista pulita (round 2, funzioni 29 e 41)

    /// Tornando dalla finestra mini, la finestra si rimette dov'era (ultimaPosizione) e massimizzata se lo era.
    private bool massimizzataPrimaDelMini;
    /// <summary>Vista pulita (funzione 29): solo il video, senza intestazione, colonne e barra. Esc per uscire.</summary>
    private bool vistaPulita;
    private bool sopraVideo;

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

    private void AlternaSchermoIntero()
    {
        var intero = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen;
        AppWindow.SetPresenter(intero ? AppWindowPresenterKind.Overlapped : AppWindowPresenterKind.FullScreen);
    }

    private void SuSchermoIntero(object sender, RoutedEventArgs e) => AlternaSchermoIntero();

    private void SuVistaPulita(object sender, RoutedEventArgs e) => ImpostaVistaPulita(true);

    private void ImpostaVistaPulita(bool pulita)
    {
        if (vistaPulita == pulita) return;
        vistaPulita = pulita;
        AggiornaModalita();
        Mostra(statoCollegamento);
    }

    /// <summary>«Riempi il riquadro»: vale solo per l'anteprima qui; le altre app ricevono il video intero.</summary>
    private void SuRiempi(object sender, RoutedEventArgs e)
    {
        Preferenze.Riempi = VoceRiempi.IsChecked;
        Video.Stretch = VoceRiempi.IsChecked ? Stretch.UniformToFill : Stretch.Uniform;
    }

    /// <summary>Nella finestra mini e nella vista pulita spariscono intestazione, colonne e barra: resta il video, intero.</summary>
    private void AggiornaModalita()
    {
        var solo = InMini || vistaPulita;
        var nascosto = Visibile(!solo);
        Intestazione.Visibility = nascosto;
        RigaIntestazione.Height = new GridLength(solo ? 0 : 52);
        if (solo)
        {
            ColonnaSinistra.Width = new GridLength(0);
            ColonnaDestra.Width = new GridLength(0);
        }
        PannelloSinistro.Visibility = nascosto;
        PannelloDestroScorrimento.Visibility = nascosto;
        BarraAzioni.Visibility = nascosto;
        PannelloAppInUso.Visibility = Visibile(!solo && appInUsoVisibile);
        Centro.Padding = new Thickness(solo ? 0 : 16);
        Centro.RowSpacing = solo ? 0 : 12;
        Radice.Background = solo ? new SolidColorBrush(Colors.Black) : Pennello("Fondo");
        BordoVideo.CornerRadius = new CornerRadius(solo ? 0 : 12);
        RiquadroVideo.CornerRadius = new CornerRadius(solo ? 0 : 11);
        TestoTornaFinestra.Visibility = Visibile(vistaPulita && !InMini);
        AutomationProperties.SetName(PulsanteTornaFinestra, vistaPulita ? "Esci dalla vista pulita" : "Torna alla finestra intera");
        ToolTipService.SetToolTip(PulsanteTornaFinestra, vistaPulita ? "Esci dalla vista pulita (Esc)" : "Torna alla finestra intera (Esc)");
        MostraPulsanteTorna();
        // Tornando alla finestra normale colonne e intestazione si rifanno per la larghezza di adesso.
        if (!solo) AdattaLayout();
        AdattaVideo();
        // P21: nella finestra mini resta solo il telefono nella webcam, senza il riquadro piccolo.
        MostraVideo();
        AggiornaChip();
    }

    /// <summary>Nella finestra mini il pulsante per tornare c'è sempre; nella vista pulita solo con il puntatore sul video.</summary>
    private void MostraPulsanteTorna() =>
        PulsanteTornaFinestra.Visibility = Visibile(InMini || (vistaPulita && sopraVideo));

    private void SuPuntatoreSulVideo(object sender, PointerRoutedEventArgs e)
    {
        sopraVideo = true;
        MostraPulsanteTorna();
    }

    private void SuPuntatoreFuoriVideo(object sender, PointerRoutedEventArgs e)
    {
        sopraVideo = false;
        MostraPulsanteTorna();
    }

    // MARK: finestra stretta

    private void SuDimensioniRadice(object sender, SizeChangedEventArgs e) => AdattaLayout();

    private void SuDimensioniVideo(object sender, SizeChangedEventArgs e) => AdattaVideo();

    /// <summary>Il video a 16:9 nello spazio che ha; nella finestra mini e nella vista pulita riempie tutto.</summary>
    private void AdattaVideo()
    {
        var larghezza = SpazioVideo.ActualWidth;
        var altezza = SpazioVideo.ActualHeight;
        if (larghezza <= 0 || altezza <= 0) return;
        if (InMini || vistaPulita)
        {
            BordoVideo.Width = larghezza;
            BordoVideo.Height = altezza;
            BordoVideo.VerticalAlignment = VerticalAlignment.Stretch;
            return;
        }
        var w = Math.Min(larghezza, altezza * 16 / 9);
        BordoVideo.Width = Math.Max(0, w);
        BordoVideo.Height = Math.Max(0, w * 9 / 16);
        BordoVideo.VerticalAlignment = VerticalAlignment.Top;
    }

    /// <summary>
    /// Niente testi tagliati o pannelli che escono: sotto i 1180 punti le colonne laterali si stringono come sul Mac, sotto
    /// i 960 la colonna di sinistra lascia il posto al video; i pulsanti restano con la sola icona (il nome è nell'aiuto e
    /// per l'Assistente vocale), e i tre passi del primo avvio si mettono in colonna.
    /// </summary>
    private void AdattaLayout()
    {
        if (InMini || vistaPulita) return;
        var larghezza = Radice.ActualWidth;
        if (larghezza <= 0) return;
        var (sinistra, destra) = larghezza >= 1180 ? (272, 320) : larghezza >= 960 ? (236, 280) : (0, 270);
        ColonnaSinistra.Width = new GridLength(sinistra);
        ColonnaDestra.Width = new GridLength(destra);
        PannelloSinistro.Visibility = Visibile(sinistra > 0);
        // Lo spazio del video, senza i margini.
        var centro = larghezza - sinistra - destra - 32;

        TestoPulsanteAiuto.Visibility = Visibile(centro >= 560);
        TestoAggiornamento.Visibility = Visibile(centro >= 560);
        var compatta = centro < 860;
        foreach (var testo in new[] { TestoSpecchia, TestoSfoca, TestoPulsanteFoto, TestoMini, TestoSchermoIntero, TestoVista, TestoScollega })
            testo.Visibility = Visibile(!compatta);
        // «Registra»: nella finestra stretta solo l'icona (o il punto e il tempo), come sul Mac.
        if (registraCompatto != compatta)
        {
            registraCompatto = compatta;
            MostraRegistrazione();
        }

        // Primo avvio: QR sopra e passi sotto quando il video è stretto, così il testo resta leggibile.
        var colonna = centro < 720 && PrimoAvvio.Visibility == Visibility.Visible;
        PrimoAvvio.Orientation = colonna ? Orientation.Vertical : Orientation.Horizontal;
        PrimoAvvio.Spacing = colonna ? 48 : 96;
        CorniceQRGrande.HorizontalAlignment = colonna ? HorizontalAlignment.Center : HorizontalAlignment.Stretch;
        Segnaposto.Width = colonna ? 900 : 1600;
        Segnaposto.Height = colonna ? 1300 : 900;
    }

    private void SuCambioFinestra(AppWindow finestra, AppWindowChangedEventArgs cambio)
    {
        if (cambio.DidPresenterChange)
        {
            AggiornaModalita();
            AggiornaSchermoIntero();
        }
        if (cambio.DidPositionChange || cambio.DidSizeChange) RicordaPosizione();
    }

    /// <summary>Il pulsante «Schermo intero» dice cosa fa adesso.</summary>
    private void AggiornaSchermoIntero()
    {
        var intero = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen;
        IconaSchermoIntero.Glyph = intero ? "" : "";
        TestoSchermoIntero.Text = intero ? "Esci" : "Schermo intero";
        AutomationProperties.SetName(PulsanteSchermoIntero, intero ? "Esci dallo schermo intero" : "Schermo intero");
        ToolTipService.SetToolTip(PulsanteSchermoIntero, intero ? "Esci dallo schermo intero (F11 o Esc)" : "Schermo intero (F11)");
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
            AppWindow.Resize(new SizeInt32(1360, 840));
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

    private void SuFinestraMini(object sender, RoutedEventArgs e) => ImpostaMini(true);

    private void SuTornaFinestra(object sender, RoutedEventArgs e)
    {
        if (vistaPulita) ImpostaVistaPulita(false);
        else ImpostaMini(false);
    }

    private void SuDoppioToccoVideo(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (InMini) ImpostaMini(false);
        else if (vistaPulita) ImpostaVistaPulita(false);
    }

    /// <summary>Dal menu dell'icona: apre la finestra mini, anche se la finestra era nascosta.</summary>
    private void ApriMini()
    {
        MostraFinestra();
        ImpostaMini(true);
    }
}
