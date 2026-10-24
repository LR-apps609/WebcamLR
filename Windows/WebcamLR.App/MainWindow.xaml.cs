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
    /// <summary>Collegamento sicuro (0.10): la chiave del PC e i telefoni fidati.</summary>
    private readonly Abbinamento abbinamento;
    private readonly AnnuncioWindows annuncio;
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
    private StatoCollegamento statoCollegamento;
    private Ciao? telefono;
    private StatoTelefono? statoTelefono;
    private Statistiche? statistiche;
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

        ascoltatore = new Ascoltatore();
        ascoltatore.NuovoTelefono += presa => coda.TryEnqueue(() => Accetta(presa));
        annuncio = new AnnuncioWindows((ushort)ascoltatore.Porta);
        _ = MostraQRAsync();
        // Cambio di Wi-Fi o cavo collegato: il QR deve avere gli indirizzi nuovi.
        System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += SuCambioRete;
        Mostra(StatoCollegamento.NessunTelefono);

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
            iconaTray.Dispose();
            notifiche.Dispose();
            annuncio.Dispose();
            ascoltatore.Dispose();
            anteprima.Dispose();
            if (sessione is not null) await sessione.DisposeAsync();
        };
    }

    // Un telefono alla volta: un nuovo collegamento sostituisce il precedente.
    private void Accetta(Socket presa)
    {
        // Un collegamento nuovo resta in attesa finché non è accettato (stretta di mano, prova, fiducia):
        // solo allora prende il posto del telefono attuale. Così nessuno sulla rete può farlo cadere.
        var nuova = new SessioneComputer(presa, Environment.MachineName, abbinamento);
        void SuInterfaccia(Action azione) => coda.TryEnqueue(() => { if (sessione == nuova) azione(); });

        // Sul thread di rete, prima del benvenuto: il formato e il video che seguono trovano già la sessione.
        nuova.Salutato += accettato =>
        {
            var vecchia = Interlocked.Exchange(ref sessione, nuova);
            if (vecchia is not null && vecchia != nuova) _ = vecchia.DisposeAsync().AsTask();
        };
        nuova.Salutato += ciao => SuInterfaccia(() =>
        {
            if (telefono is not null && telefono.Nome == ciao.Nome)
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
            var lettore = anteprima.Avvia(formato.Larghezza, formato.Altezza, formato.Codec);
            // Senza decodificatore (di solito HEVC senza l'estensione dello Store) la finestra resterebbe nera.
            lettore.MediaFailed += (_, _) => SuInterfaccia(() =>
            {
                if (sessione != nuova) return;
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
        nuova.Silenzio += () => SuInterfaccia(() => Mostra(StatoCollegamento.Riconnessione));
        nuova.Ripresa += () => SuInterfaccia(() => Mostra(StatoCollegamento.Collegato));
        nuova.Chiusa += () => SuInterfaccia(() =>
        {
            sessione = null;
            if (telefono is null) { Mostra(StatoCollegamento.NessunTelefono); return; }
            Mostra(StatoCollegamento.Riconnessione);
            _ = DimenticaSeNonTornaAsync();
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
        coda.TryEnqueue(async () =>
        {
            try
            {
                MostraFinestra();
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
        });
        return risposta.Task;
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

    private async Task DimenticaSeNonTornaAsync()
    {
        await Task.Delay(AttesaRiconnessione);
        if (sessione is not null || telefono is not { } perso) return;
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
        var chiusa = sessione;
        sessione = null;
        Dimentica();
        if (chiusa is null) return;
        try
        {
            await chiusa.ChiudiAsync();
            await chiusa.DisposeAsync();
        }
        // Un errore di rete qui non deve chiudere l'app.
        catch (Exception) { }
    }

    private void Dimentica()
    {
        telefono = null;
        statoTelefono = null;
        statistiche = null;
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
    }

    private static Brush Pennello(string nome) => (Brush)Application.Current.Resources[nome];

    private void AggiornaTelefono()
    {
        AggiornaQualita();
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
        var parti = new List<string> { "Wi-Fi", statistiche?.LatenzaMs is int ms ? $"{ms} ms" : "— ms" };
        if (statoTelefono is { Batteria: >= 0 } stato) parti.Add($"{stato.Batteria}%");
        DettagliTelefono.Text = string.Join(" · ", parti);

        TestoStatistiche.Inlines.Clear();
        if (statistiche is { Larghezza: > 0 } s)
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
            TestoStatistiche.Text = "Collegato, in attesa del video";
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
        SuggerimentoQualita.Content = $"Latenza {ms} ms\nUltimi 60 s: media {storiaLatenza.Media} ms, massima {storiaLatenza.Massima} ms";
        AutomationProperties.SetName(ChipQualita, $"Collegamento {qualita.Testo().ToLowerInvariant()}, {ms} millisecondi");
        ChipQualita.Visibility = Visibility.Visible;
    }

    private void AggiornaGrafico()
    {
        var punti = storiaLatenza.Punti(GraficoLatenza.Width, GraficoLatenza.Height);
        if (telefono is null || punti.Count < 2)
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

    private void SuCambioRete(object? origine, EventArgs evento) => coda.TryEnqueue(() => _ = MostraQRAsync());

    private async Task MostraQRAsync()
    {
        // Lo stesso nome che l'iPhone vede nell'elenco (AnnuncioWindows annuncia il nome del computer).
        TestoTerzoPasso.Text = $"Tocca «{Environment.MachineName}» nell'elenco, oppure «Inquadra il QR code del computer» e inquadra questo codice.";
        var indirizzi = IndirizziLocali.Ipv4();
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
            EsposizioneManuale.Visibility = Visibility.Visible;
        }
        else
        {
            EsposizioneManuale.Visibility = Visibility.Collapsed;
            EsposizioneManuale.IsOn = false;
        }
        PannelloManuale.Visibility = EsposizioneManuale.IsOn ? Visibility.Visible : Visibility.Collapsed;
        PannelloComandi.Visibility = Visibility.Visible;
        aggiornoComandi = false;
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
            AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            // Si torna alla finestra normale di prima (ultimaPosizione non cambia durante il mini), massimizzata se lo era.
            if (ultimaPosizione is { } r) AppWindow.MoveAndResize(new RectInt32(r.X, r.Y, r.Larghezza, r.Altezza));
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
        CursoreEsposizione.Visibility = Visibility.Visible;
        EsposizioneManuale.IsOn = false;
        PannelloManuale.Visibility = Visibility.Collapsed;
        BiancoAutomatico.IsOn = true;
        CursoreBianco.Visibility = Visibility.Collapsed;
        PulsanteTorcia.IsChecked = false;
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
        salva.Click += async (_, _) => await ChiediNomeProfiloAsync();
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
        CursoreBianco.Visibility = profilo.BiancoAutomatico ? Visibility.Collapsed : Visibility.Visible;
        EsposizioneManuale.IsOn = manuale;
        CursoreIso.Value = Math.Clamp(profilo.Iso, CursoreIso.Minimum, CursoreIso.Maximum);
        SceltaTempo.SelectedItem = SceltaTempo.Items.OfType<ComboBoxItem>().FirstOrDefault(voce => (string)voce.Tag == profilo.Tempo.ToString())
            ?? SceltaTempo.SelectedItem;
        PannelloManuale.Visibility = manuale ? Visibility.Visible : Visibility.Collapsed;
        CursoreEsposizione.Visibility = manuale ? Visibility.Collapsed : Visibility.Visible;
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
        PannelloManuale.Visibility = manuale ? Visibility.Visible : Visibility.Collapsed;
        CursoreEsposizione.Visibility = manuale ? Visibility.Collapsed : Visibility.Visible;
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
        CursoreBianco.Visibility = BiancoAutomatico.IsOn ? Visibility.Collapsed : Visibility.Visible;
        Comanda(new Comando(Bianco: BiancoAutomatico.IsOn ? 0 : (int)CursoreBianco.Value));
    }

    private void SuBianco(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Bianco: (int)e.NewValue));

    private void SuTorcia(object sender, RoutedEventArgs e) => Comanda(new Comando(Torcia: PulsanteTorcia.IsChecked == true));

    private void SuFuoco(object sender, RoutedEventArgs e) => Comanda(new Comando(Fuoco: "continuo"));
}
