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
    /// Vero solo quando si esce davvero (EsciAsync): altrimenti chiudere la finestra la nasconde.
    private bool uscita;
    /// Lo stato del telefono nella webcam (P21: con due telefoni, quello scelto).
    private FaseCollegamento statoCollegamento;
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
        // Beta 4: Mica e una barra del titolo sola, l'intestazione (MainWindow.Finestra.cs).
        PreparaFinestra();
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
            registro.Aggiungi(Testi.T("Registro_AscoltoRiaperto", porta));
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
                StatoCavo.Collegato => Testi.T("Registro_CavoCollegato"),
                StatoCavo.InAscolto => Testi.T("Registro_CavoInAscolto"),
                _ => Testi.T("Registro_CavoServizioAssente"),
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
        FinestraApp.Registro = registro;
        BarraCavo.CloseButtonClick += (_, _) => suggerimentoCavoChiuso = true;
        // Il permesso del firewall o il profilo della rete cambiano senza avvisare: senza telefono si ricontrolla.
        controlloDiagnosi = coda.CreateTimer();
        controlloDiagnosi.Interval = TimeSpan.FromSeconds(10);
        controlloDiagnosi.Tick += (_, _) => { if (statoCollegamento == FaseCollegamento.NessunTelefono) _ = AggiornaDiagnosiAsync(); };
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
        registro.Aggiungi(Testi.T("Registro_Avviata", ascoltatore.Porta));
        InizializzaMicrofono();
        InizializzaFotocamera();
        MostraObiettiviDiEsempio();
        Mostra(FaseCollegamento.NessunTelefono);
        _ = AggiornaDiagnosiAsync();

        AggiungiScorciatoie();
        InizializzaMenu();
        InizializzaViste();
        AppWindow.Changed += SuCambioFinestra;
        MostraAvvioConWindows();
        InizializzaWebcam();
        InizializzaMotoreEffetti();
        InizializzaEffetti();
        InizializzaPausa();
        InizializzaAppInUso();
        InizializzaAggiornamenti();
        MostraAccount();
        InizializzaAttesa();
        MostraRegistrazione();
        MostraTimer();
        InizializzaAvvisi();

        try
        {
            iconaTray = new IconaTray(apri: MostraFinestra, mini: ApriMini, scollega: collegato => ChiediScollega(collegato, dallIcona: true),
                fermaRegistrazione: () => _ = FermaRegistrazioneAsync(), esci: ChiediEsci);
            AggiornaIcona();
        }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
            registro.Aggiungi(Testi.T("Registro_SenzaIcona"));
        }
        notifiche = new Notifiche(clic: () => coda.TryEnqueue(MostraFinestra));
        Activated += (_, evento) => inPrimoPiano = evento.WindowActivationState != WindowActivationState.Deactivated;
        // X e Alt+F4: la finestra si nasconde accanto all'orologio e l'app resta attiva (1.2); senza icona, come «Esci»
        // (con la domanda se qualcosa è in corso). La chiusura vera passa da EsciAsync, che alla fine mette
        // «chiudiDavvero»; mentre EsciAsync chiude la registrazione, la X non fa nulla.
        AppWindow.Closing += (_, evento) =>
        {
            SalvaPosizione();
            if (chiudiDavvero) return;
            evento.Cancel = true;
            if (uscita) return;
            NascondiFinestra();
        };
        Closed += async (_, _) =>
        {
            // async void: un errore nella chiusura non deve diventare un crash all'uscita.
            try
            {
                // Prima di tutto: la registrazione si chiude bene anche se l'app sta uscendo. Di solito l'ha già chiusa
                // EsciAsync; qui resta solo il caso di una chiusura arrivata da Windows. Si aspetta senza bloccare.
                await ChiudiRipreseAsync();
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
                motoreVideo.Dispose();
                ChiudiMicrofono();
                await ChiudiTuttiAsync();
            }
            catch (Exception) { }
        };
    }

    /// <summary>
    /// Un telefono nuovo, senza il QR code: si chiede all'utente, con il codice che il telefono mostra.
    /// Chiamata da un thread di rete; la finestra si apre sul thread dell'interfaccia.
    /// </summary>
    private Task<bool> ChiediConfermaAsync(string nomeTelefono, string codice, CancellationToken scaduto)
    {
        var risposta = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        // Da quando la sessione aspetta la risposta: per distinguere il tempo scaduto dal telefono andato via.
        var aperta = System.Diagnostics.Stopwatch.StartNew();
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
                Notifica(Testi.T("Conferma_NotificaTitolo"), Testi.T("Conferma_Notifica", nomeTelefono));
                MostraFinestra();
                await PreparaDialogoAsync();
                if (scaduto.IsCancellationRequested) return;
                var finestra = new ContentDialog
                {
                    XamlRoot = Content.XamlRoot,
                    Title = Testi.T("Conferma_Titolo", nomeTelefono),
                    Content = new StackPanel
                    {
                        Spacing = Token.SpazioPiccolo,
                        Children =
                        {
                            new TextBlock { Text = Testi.T("Conferma_Controlla"), TextWrapping = TextWrapping.Wrap },
                            new TextBlock
                            {
                                Text = string.Join(" ", codice.ToCharArray()),
                                // Lo stile «codice» comune (numeriEvidenti 46), uguale su ogni piattaforma.
                                FontFamily = (FontFamily)Application.Current.Resources["NumeriEvidenti"],
                                FontSize = Token.MisuraCodice,
                                HorizontalAlignment = HorizontalAlignment.Center,
                                Foreground = Pennello("Accento"),
                            },
                            new TextBlock
                            {
                                Text = Testi.T("Conferma_Avviso"),
                                TextWrapping = TextWrapping.Wrap,
                                Foreground = Pennello("TestoSecondario"),
                            },
                        },
                    },
                    PrimaryButtonText = Testi.T("Conferma_Consenti"),
                    CloseButtonText = Testi.T("Conferma_NonConsentire"),
                    DefaultButton = ContentDialogButton.Close,
                };
                // Scaduto il tempo, o telefono andato via: la domanda sparisce da sola.
                using var registrazione = scaduto.Register(() => coda.TryEnqueue(finestra.Hide));
                var esito = await finestra.ShowAsync();
                risposta.TrySetResult(esito == ContentDialogResult.Primary && !scaduto.IsCancellationRequested);
                // Scaduto il tempo (non il telefono andato via prima): lo si dice, e resta finché non lo si chiude (windows.md 2.16).
                if (scaduto.IsCancellationRequested && Conferme.TempoScaduto(aperta.Elapsed))
                    MostraErrore(Conferme.CodiceScaduto(nomeTelefono), severita: InfoBarSeverity.Warning);
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

    /// <summary>
    /// La X, Alt+F4 e Ctrl+W (passo 8): la finestra si nasconde accanto all'orologio, con l'avviso del passo 2 se qualcosa
    /// è in corso; senza icona, come «Esci».
    /// </summary>
    private void NascondiFinestra()
    {
        if (iconaTray is null)
        {
            ChiediEsci();
            return;
        }
        AppWindow.Hide();
        AvvisaFinestraNascosta();
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

    private void Notifica(string titolo, string testo)
    {
        if (inPrimoPiano && AppWindow.IsVisible) return;
        notifiche.Mostra(titolo, testo);
    }

    /// <summary>
    /// La barra sopra il video segue lo stato del telefono (la percentuale si aggiorna); se l'avviso è nuovo arriva una
    /// notifica. Resta finché la causa c'è (windows.md 2.1): non si chiude con la X. Inizio e fine vanno nel registro
    /// (StatoRicevuto in MainWindow.Telefoni.cs, SorveglianzaAvvisi.RigaRegistro).
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
        BarraAvvisoTelefono.IsOpen = true;
        if (nuovo is null) return;
        Notifica(titolo, messaggio);
    }

    /// <summary>
    /// La pillola in alto segue lo stato, come PillolaStato di Stile (beta 4): piena solo «in onda» (corallo), ambra tenue
    /// con il bordo ambra in riconnessione e (passo 8) «In pausa» quando un'app tiene la webcam ma il telefono è in pausa,
    /// solo il contorno dei controlli da collegato (punto verde) e senza telefono (DescrizioneStato.Pillola).
    /// </summary>
    private void Mostra(FaseCollegamento stato)
    {
        statoCollegamento = stato;
        var aspetto = DescrizioneStato.Pillola(stato, inOnda, InPausa);
        // In pausa l'app vede la schermata di attesa: niente bordo corallo.
        var inOndaOra = aspetto == AspettoPillola.InOnda;
        switch (aspetto)
        {
            case AspettoPillola.InPausa:
                // Un'app tiene la webcam ma il telefono non manda video: in ambra, come un problema da guardare.
                TestoStato.Text = Testi.T("Stato_InPausaPillola");
                TestoStato.Foreground = Pennello("AmbraTesto");
                PuntoStato.Fill = Pennello("Ambra");
                PuntoStato.Stroke = null;
                PillolaStato.Background = Pennello("AmbraTenue");
                PillolaStato.BorderBrush = Pennello("Ambra");
                MessaggioAnteprima.Text = Testi.T("Stato_InAttesaVideo");
                break;
            case AspettoPillola.InOnda:
                // Il video va a un'app (Zoom, Teams…): l'unico caso di corallo, come sul Mac e sul telefono.
                TestoStato.Text = Testi.T("Stato_InOnda");
                TestoStato.Foreground = Pennello("TestoInOnda");
                PuntoStato.Fill = Pennello("TestoInOnda");
                PuntoStato.Stroke = null;
                PillolaStato.Background = Pennello("TallyPieno");
                PillolaStato.BorderBrush = Pennello("TallyPieno");
                MessaggioAnteprima.Text = Testi.T("Stato_InAttesaVideo");
                break;
            case AspettoPillola.Collegato:
                // In pausa: calmo, come «collegato» (il corallo resta solo per «in onda» e la registrazione).
                // Accanto a «Collegato» la strada (prova del 27 ottobre): Wi-Fi (anche hotspot, Wi-Fi diretto, rete) o USB.
                TestoStato.Text = InPausa ? Testi.T("Stato_CollegatoInPausa")
                    : ContrattoCollegamento.ViaCavo(statoTelefono, Scelto?.Collegamento) switch
                    {
                        true => Testi.T("Stato_CollegatoUsb"),
                        false => Testi.T("Stato_CollegatoWiFi"),
                        null => Testi.T("Stato_Collegato"),
                    };
                TestoStato.Foreground = Pennello("Testo");
                PuntoStato.Fill = Pennello("Verde");
                PuntoStato.Stroke = null;
                PillolaStato.Background = null;
                PillolaStato.BorderBrush = Pennello("ContornoControllo");
                MessaggioAnteprima.Text = Testi.T("Stato_InAttesaVideo");
                break;
            case AspettoPillola.Riconnessione:
                TestoStato.Text = Testi.T("Stato_Riconnessione");
                TestoStato.Foreground = Pennello("AmbraTesto");
                PuntoStato.Fill = Pennello("Ambra");
                PuntoStato.Stroke = null;
                PillolaStato.Background = Pennello("AmbraTenue");
                PillolaStato.BorderBrush = Pennello("Ambra");
                MessaggioAnteprima.Text = Testi.T("Stato_CollegamentoPerso");
                break;
            default:
                TestoStato.Text = Testi.T("Stato_NessunTelefono");
                TestoStato.Foreground = Pennello("TestoTenue");
                PuntoStato.Fill = null;
                PuntoStato.Stroke = Pennello("TestoTenue");
                PillolaStato.Background = null;
                PillolaStato.BorderBrush = Pennello("ContornoControllo");
                MessaggioAnteprima.Text = "";
                break;
        }
        // In onda: la barra tally sul bordo alto del video (beta 4, al posto del bordo corallo), anche nella finestra mini;
        // il bordo del video resta la linea del pannello.
        BarraTally.Visibility = Visibile(inOndaOra);
        BordoVideo.BorderThickness = new Thickness(SoloVideo ? 0 : 1);
        var senzaTelefono = stato == FaseCollegamento.NessunTelefono;
        MostraAttesaAlCentro();
        PannelloMessaggio.Visibility = Visibile(!senzaTelefono);
        PannelloAttesa.Visibility = Visibile(senzaTelefono);
        // «Collegamento interrotto» lo dice la schermata di attesa sopra il video (MostraPausa), come nelle app.
        PillolaRiconnessione.Visibility = Visibility.Collapsed;
        // «Scollega» sta nella scheda del telefono (beta 4): la scheda c'è solo con un telefono; con due, ogni scheda ha il suo.
        if (telefono is { } collegatoOra)
        {
            ToolTipService.SetToolTip(PulsanteScollega, Testi.T("Telefoni_ScollegaSpiegazione", collegatoOra.Nome));
            AutomationProperties.SetName(PulsanteScollega, Testi.T("Telefoni_ScollegaNome", collegatoOra.Nome));
        }
        AdattaLayout();
        AggiornaTelefono();
        MostraDiagnosi();
        MostraPausa();
        // P21: il video grande, il riquadro piccolo e le schede dei telefoni.
        MostraVideo();
        MostraTelefoni();
    }

    /// <summary>
    /// Senza telefono, al centro: con la colonna di sinistra a vista (e il suo QR) la schermata che vedono le app, con
    /// l'invito a collegarsi; nella finestra stretta, senza colonna, il QR grande e i tre passi (round 2, funzione 46).
    /// </summary>
    private void MostraAttesaAlCentro()
    {
        var senzaTelefono = statoCollegamento == FaseCollegamento.NessunTelefono;
        var colonnaSinistra = ColonnaSinistra.Width.Value > 0;
        PrimoAvvio.Visibility = Visibile(senzaTelefono && !colonnaSinistra);
        PannelloNessuno.Visibility = Visibile(senzaTelefono && colonnaSinistra);
    }

    private static Brush Pennello(string nome) => (Brush)Application.Current.Resources[nome];

    private static Visibility Visibile(bool visibile) => visibile ? Visibility.Visible : Visibility.Collapsed;

    private void AggiornaTelefono()
    {
        AggiornaChip();
        AggiornaPillolaTelefono();
        AggiornaConnessione();
        // Nel costruttore la prima chiamata arriva prima che l'icona esista.
        AggiornaIcona();
        iconaTray?.MostraTelefoni(telefoni.Telefoni);
        AggiornaDisponibilita();
        TestoRete.Text = Testi.T("Stato_Pronto");
        TestoRete.Visibility = Visibile(telefono is null && !BarraDiagnosi.IsOpen);
        // Con un telefono la strada è sulla sua scheda e nell'etichetta sul video (con la scelta): qui servono senza.
        SezioneConnessione.Visibility = Visibile(telefono is null);

        // Perché i comandi sono grigi. Durante la riconnessione il telefono c'è ancora: non si chiede di collegarne uno.
        DettagliFotocamera.Text = telefono is null ? Testi.T("Comandi_SiAttivano")
            : statoCollegamento == FaseCollegamento.Riconnessione ? Testi.T("Comandi_MiRicollego")
            : capacitaAttuali is null ? Testi.T("Comandi_TraUnAttimo")
            : "";
        DettagliFotocamera.Visibility = Visibile(DettagliFotocamera.Text.Length > 0);
        // P21: con due telefoni si dice per quale valgono i comandi a destra.
        TelefonoDeiComandi.Visibility = Visibile(telefoni.Conteggio > 1 && telefono is not null);
        NomeTelefonoDeiComandi.Text = telefono?.Nome ?? "";
        ToolTipService.SetToolTip(TelefonoDeiComandi, Testi.T("Comandi_ValgonoPer", telefono?.Nome));

        if (telefono is null || Scelto is not { } scelto) return;
        NomeTelefono.Text = scelto.Nome;
        PuntoTelefono.Fill = Pennello(scelto.InRiconnessione ? "Ambra" : "Verde");
        DettagliTelefono.Text = DettagliScheda(scelto);
        MostraBatteria(BatteriaTelefono, scelto.Stato);
        MostraCaldo(CaldoTelefono, scelto.Stato);
        AutomationProperties.SetName(SchedaTelefono, scelto.InRiconnessione
            ? Testi.T("Accessibilita_TelefonoInRiconnessione", scelto.Nome) : Testi.T("Accessibilita_TelefonoCollegato", scelto.Nome));
    }

    /// <summary>«Wi-Fi · 38 ms · Avvio: 0,9 s», oppure cosa sta succedendo (riconnessione, pausa), come la scheda del Mac.</summary>
    private static string DettagliScheda(TelefonoCollegato collegato)
    {
        if (collegato.InRiconnessione) return Testi.T("Telefoni_MiRicollegoA", collegato.Nome);
        var parti = new List<string> { collegato.Collegamento?.Testo() ?? "—" };
        if (collegato.InPausa) parti.Add(Testi.T("Stato_InPausa"));
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
        AutomationProperties.SetName(testo, s.InCarica ? Testi.T("Batteria_InCarica", s.Batteria) : Testi.T("Batteria", s.Batteria));
    }

    /// <summary>«Telefono caldo», in ambra da «molto caldo» in su; niente se è normale.</summary>
    private static void MostraCaldo(TextBlock testo, StatoTelefono? stato)
    {
        testo.Text = stato?.Temperatura switch
        {
            Temperatura.Calda => Testi.T("Caldo_Caldo"),
            Temperatura.MoltoCalda => Testi.T("Caldo_MoltoCaldo"),
            Temperatura.Critica => Testi.T("Caldo_TroppoCaldo"),
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
        var visibili = telefono is not null && statoCollegamento == FaseCollegamento.Collegato && statistiche is { Larghezza: > 0 }
            && !vistaPulita && !InSchermoIntero && !InPausa;
        ChipVideo.Visibility = Visibile(visibili);
        MostraEtichettaCam(visibili && !InMini);
        if (!visibili || statistiche is not { } s)
        {
            if (FinestraNumeri.IsOpen) FinestraNumeri.Hide();
            if (FinestraCollegamento.IsOpen) FinestraCollegamento.Hide();
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
            AutomationProperties.SetName(ChipQualita, Testi.T("Qualita_Descrizione", qualita.Testo().ToLowerInvariant(), ms));
        }
        else
        {
            foreach (var tacca in new[] { Tacca1, Tacca2, Tacca3 }) tacca.Fill = Pennello("Linea");
            TestoQualita.Text = Testi.T("Qualita_Misuro");
            TestoQualita.Foreground = Pennello("Testo");
        }
        // «Ottima · 720p 30», come nel disegno; il codec solo se è HEVC (H.264 è quello di sempre). Se il telefono manda
        // meno di quanto chiesto, anche il perché («· ridotta dal telefono: è caldo»).
        var corto = Math.Min(s.Larghezza, s.Altezza);
        var nome = OpzioneQualita.NomeRisoluzione(corto);
        TestoFormatoVideo.Text = s.Codec == Codec.Hevc ? $"· {nome} {s.Fps} · HEVC" : $"· {nome} {s.Fps}";
        if (Scelto is { } scelto && OpzioneQualita.MotivoRiduzione(scelto.Formato, scelto.FormatoChiesto, statoTelefono, ProAttivo) is { } motivo)
            TestoFormatoVideo.Text += $" · {motivo}";
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
            // Più strade e un telefono che sa cambiare: l'etichetta apre la scelta (MainWindow.Etichette.cs).
            var scegliere = StradaSceglibile;
            FrecciaCollegamento.Visibility = Visibile(scegliere);
            ToolTipService.SetToolTip(ChipCollegamento, scegliere ? Testi.T("Collegamento_ScegliStrada")
                : tipo.Consiglio() ?? Testi.T("Collegamento_CavoStabile"));
            AutomationProperties.SetName(ChipCollegamento, Testi.T("Collegamento_Tipo", tipo.Testo()));
            ChipCollegamento.Visibility = Visibility.Visible;
            if (!scegliere && FinestraCollegamento.IsOpen) FinestraCollegamento.Hide();
        }
        else
        {
            ChipCollegamento.Visibility = Visibility.Collapsed;
        }
        // Anche nella pagina «Qualità e collegamento» delle impostazioni, che mostra gli stessi menu.
        var inPagina = PaginaAttuale == PaginaImpostazioni.Qualita;
        if (FinestraNumeri.IsOpen || inPagina)
        {
            MostraNumeri();
            MostraQualita();
        }
        if (FinestraCollegamento.IsOpen || inPagina) MostraMenuCollegamento();
        if (inPagina) ContenutoCollegamento.Visibility = Visibile(StradaSceglibile);
    }

    /// <summary>I numeri di sempre, a un clic dal chip della qualità (funzioni 28 e 31), con il grafico dell'ultimo minuto.</summary>
    private void MostraNumeri()
    {
        if (statistiche is not { } s) return;
        var righe = new List<string>
        {
            Testi.T("Numeri_Risoluzione", s.Larghezza, s.Altezza),
            Testi.T("Numeri_Fotogrammi", s.Fps),
            Testi.T("Numeri_Formato", (s.Codec == Codec.Hevc ? "HEVC" : "H.264")),
            Testi.T("Numeri_Velocita", s.MegabitAlSecondo),
            Testi.T("Numeri_Latenza", (s.LatenzaMs is int l ? $"{l} ms" : "—")),
        };
        // Le tappe da vetro a uscita (Protocollo.md, «Latenza»): la latenza qui sopra è l'ultima che c'è.
        if (s.AnteprimaMs is not null || s.WebcamMs is not null)
            righe.Add(Testi.T("Numeri_Tappe", RitardoNelRegistro.Testo(s.ArrivoMs), RitardoNelRegistro.Testo(s.AnteprimaMs),
                RitardoNelRegistro.Testo(s.WebcamMs)));
        // Il motore effetti del PC (già compreso nell'anteprima e nella webcam qui sopra).
        if (RigaNumeriEffetti() is { } effettiRiga) righe.Add(effettiRiga);
        if (storiaLatenza.Media is int media) righe.Add(Testi.T("Numeri_Media", media, storiaLatenza.Massima));
        if (testoAvvio is { } avvio) righe.Add(Testi.T("Numeri_Avvio", avvio.Split(':', 2).Last().Trim()));
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
        var statoWifi = inUso.Contains(TipoCollegamento.Hotspot) ? Testi.T("Connessione_InUsoHotspot")
            : inUso.Contains(TipoCollegamento.WiFi) ? Testi.T("Connessione_InUso")
            : indirizziRete == 0 ? Testi.T("Connessione_NessunaRete")
            : Testi.T("Connessione_Pronto");
        MostraRiga(RigaWifi, IconaWifi, NomeWifi, StatoWifi, statoWifi, wifi);
        var usb = inUso.Contains(TipoCollegamento.CavoUsb);
        var statoCavo = usb ? Testi.T("Connessione_InUso")
            : !cavo.Verificato ? "…"
            : cavo.Stato switch
            {
                StatoCavo.Collegato => Testi.T("Connessione_Collegato"),
                StatoCavo.ServizioAssente => Testi.T("Connessione_NonDisponibile"),
                _ => cavo.IPhoneAlCavo ? Testi.T("Connessione_ApriApp") : Testi.T("Connessione_NessunIPhone"),
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
                registro.Aggiungi(Testi.T("Registro_Diagnosi", nuovo.Titolo));
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
        var senzaTelefono = statoCollegamento == FaseCollegamento.NessunTelefono;
        var grave = senzaTelefono ? problemi.FirstOrDefault(p => p.Grave) : null;
        MostraProblema(BarraDiagnosi, AzioneDiagnosi, RispostaDiagnosi, grave);
        MostraFirewallNonRiuscito(grave);
        var suggerimento = problemi.FirstOrDefault(p => !p.Grave);
        var daMostrare = suggerimento is not null && !suggerimentoCavoChiuso && (senzaTelefono || suggerimento.Id == "servizio-assente");
        MostraProblema(BarraCavo, AzioneCavo, RispostaCavo, daMostrare ? suggerimento : null);
        TestoRete.Visibility = Visibile(telefono is null && !BarraDiagnosi.IsOpen);
        // Nella vista Essenziale la diagnosi si vede dalla pillola del telefono (passo 7).
        AggiornaPillolaTelefono();
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

    /// <summary>Impostazioni di Windows, firewall o Microsoft Store, secondo il problema; «Sistema» scrive la regola del firewall.</summary>
    private async void SuAzioneDiagnosi(object sender, RoutedEventArgs e)
    {
        // async void: un errore qui non deve chiudere l'app.
        try
        {
            if (sender is not Button { Tag: string indirizzo } pulsante) return;
            if (indirizzo == Diagnosi.SistemaFirewall)
            {
                await SistemaFirewallAsync(pulsante);
                return;
            }
            if (Uri.TryCreate(indirizzo, UriKind.Absolute, out var uri))
                await Windows.System.Launcher.LaunchUriAsync(uri);
        }
        catch (Exception errore) { App.ScriviErrore(errore); }
    }

    /// <summary>«Apri le impostazioni Wi-Fi» sotto il QR, quando il PC non è su nessuna rete (passo 7).</summary>
    private async void SuApriWiFi(object sender, RoutedEventArgs e)
    {
        try { await Windows.System.Launcher.LaunchUriAsync(new Uri(Diagnosi.ImpostazioniWiFi)); }
        catch (Exception) { }
    }

    /// <summary>Apre «App e assistenza» sulla risposta giusta delle domande frequenti.</summary>
    private async void SuRispostaDiagnosi(object sender, RoutedEventArgs e)
    {
        try
        {
            if (sender is not FrameworkElement { Tag: string domanda }) return;
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), domanda);
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
                registro.Aggiungi(indirizzi.Count == 0 ? Testi.T("Registro_ReteCambiataNessuna") : Testi.T("Registro_ReteCambiata", testo));
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
        registro.Aggiungi(Testi.T("Registro_Risveglio"));
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
            TestoTerzoPasso.Text = Testi.T("QR_Spiegazione", Environment.MachineName);
            // Tutti gli indirizzi utili, il più probabile per primo (1.10): il telefono li prova insieme.
            // Leggere le schede di rete può richiedere decine di millisecondi: fuori dal thread dell'interfaccia.
            var indirizzi = await Task.Run(IndirizziLocali.Ipv4);
            if (richiesta != richiesteQR) return;
            indirizziRete = indirizzi.Count;
            AggiornaConnessione();
            // Senza rete, sotto il QR (colonna e primo avvio) anche il pulsante per il Wi-Fi (passo 7, windows.md 2.14).
            PulsanteWiFi.Visibility = Visibile(indirizzi.Count == 0);
            PulsanteWiFiGrande.Visibility = Visibile(indirizzi.Count == 0);
            if (indirizzi.Count == 0)
            {
                IndirizzoScritto.Text = Testi.T("QR_SenzaRete");
                IndirizzoScrittoGrande.Text = IndirizzoScritto.Text;
                ImmagineQR.Source = null;
                ImmagineQRGrande.Source = null;
                CorniceQR.Visibility = Visibility.Collapsed;
                CorniceQRGrande.Visibility = Visibility.Collapsed;
                return;
            }
            var porta = (ushort)ascoltatore.Porta;
            // Versione 2: l'impronta del PC e il gettone per abbinarsi senza conferma.
            var associazione = new Associazione(indirizzi, porta, Environment.MachineName,
                Impronta: abbinamento.Identita.Impronta, Gettone: abbinamento.Gettone);
            IndirizzoScritto.Text = Testi.T("QR_OppureScrivi", indirizzi[0], (porta == Servizio.PortaPredefinita ? "" : $":{porta}"));
            IndirizzoScrittoGrande.Text = Testi.T("QR_OppureScriviIndirizzo", indirizzi[0], (porta == Servizio.PortaPredefinita ? "" : $":{porta}"));

            // Il PNG del QR si prepara fuori dal thread dell'interfaccia.
            var png = await Task.Run(() => IndirizziLocali.QRCodePng(associazione));
            if (png is null || richiesta != richiesteQR) return;
            var immagine = await ImmagineDaPngAsync(png);
            if (richiesta != richiesteQR) return;
            ImmagineQR.Source = immagine;
            ImmagineQRGrande.Source = immagine;
            CorniceQR.Visibility = Visibility.Visible;
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

    /// <summary>
    /// Un link con un riquadro (FlyoutBase.AttachedFlyout), come «Non hai ancora l'app? Scaricala»: il clic lo apre.
    /// HyperlinkButton non ha la proprietà Flyout di Button.
    /// </summary>
    private void SuApriMenuAllegato(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement elemento) FlyoutBase.ShowAttachedFlyout(elemento);
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
        MostraPulsantiVideo();
        AbilitaEffetti();
        AggiornaDisponibilitaRiprese();
        AggiornaPro();
        AggiornaCoperture();
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
        MostraNotaSpenta(copertura, e.GetPosition(copertura));
        e.Handled = true;
    }

    /// <summary>
    /// La nota sopra il comando spento: con il clic dove si è cliccato, con Invio o Spazio (windows.md 2.13) sopra il
    /// comando. Il testo è <see cref="MotivoSpento"/>.
    /// </summary>
    private void MostraNotaSpenta(FrameworkElement copertura, Windows.Foundation.Point? posizione)
    {
        var testo = MotivoSpento(copertura);
        notaTelefono ??= new Flyout
        {
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = Token.SpazioStretto,
                Children =
                {
                    new FontIcon { Glyph = "", FontSize = Token.MisuraCorpoGrande, Foreground = Pennello("Accento") },
                    new TextBlock { VerticalAlignment = VerticalAlignment.Center },
                },
            },
        };
        if (notaTelefono.Content is StackPanel { Children: [_, TextBlock riga] }) riga.Text = testo;
        notaTelefono.ShowAt(copertura, new FlyoutShowOptions { Position = posizione, Placement = FlyoutPlacementMode.Top });
    }

    // MARK: registro (1.5)

    /// <summary>Il registro si aggiorna solo quando si vede: i più recenti in cima.</summary>
    private void MostraRegistro()
    {
        if (!FinestraRegistro.IsOpen && PaginaAttuale != PaginaImpostazioni.Registro) return;
        var testo = registro.Testo(recentiPrima: true);
        TestoRegistro.Text = testo.Length > 0 ? testo : Testi.T("Registro_Vuoto");
    }

    private void SuAperturaRegistro(object? sender, object e)
    {
        if (sender is not null) RidaiAlMenu();
        var testo = registro.Testo(recentiPrima: true);
        TestoRegistro.Text = testo.Length > 0 ? testo : Testi.T("Registro_Vuoto");
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
    private void SuAiuto(object sender, RoutedEventArgs e) => ApriGuida();

    /// <summary>«Aiuto» e F1. Con la finestra già aperta F1 non la riapre.</summary>
    private async void ApriGuida()
    {
        // async void: un errore qui non deve chiudere l'app.
        if (guidaAperta) return;
        guidaAperta = true;
        try
        {
            MenuAccount.Hide();
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), pagina: PaginaApp.Guida);
        }
        catch (Exception) { }
        finally
        {
            guidaAperta = false;
        }
    }

    /// Vero mentre «App e assistenza» è aperta da «Aiuto» o da F1.
    private bool guidaAperta;

    /// <summary>Per la pagina «WebcamLR Pro»: il telefono nella webcam e le sue capacità.</summary>
    private (string? Nome, Capacita? Capacita) StatoPro() => (telefono?.Nome, sessione is null ? null : capacitaAttuali);

    /// <summary>Per «Segnala un bug»: solo dati tecnici, nessun dato personale oltre al nome del telefono.</summary>
    private List<(string Nome, string Valore)> DatiTecnici()
    {
        var dati = new List<(string, string)>
        {
            ("App", Testi.T("Dati_VersioneApp", VersioneApp)),
            (Testi.T("Dati_Sistema"), Environment.OSVersion.VersionString),
        };
        if (telefono is { } ciao) dati.Add((Testi.T("Dati_Telefono"), Testi.T("Dati_PiattaformaApp", DescrizioneStato.NomePiattaforma(ciao.Piattaforma), ciao.VersioneApp)));
        if (capacitaAttuali is { } capacita) dati.Add(("WebcamLR Pro", RegolePro.Attivo(capacita) ? Testi.T("Dati_Si") : "no"));
        if (telefoni.Conteggio > 1) dati.Add((Testi.T("Dati_TelefoniCollegati"), $"{telefoni.Conteggio}"));
        if (telefono is not null) dati.Add((Testi.T("Dati_Collegamento"), collegamento?.Testo() ?? "—"));
        dati.Add((Testi.T("Dati_CavoUsb"), cavo.Stato switch
        {
            StatoCavo.Collegato => Testi.T("Dati_Collegato"),
            StatoCavo.InAscolto => Testi.T("Dati_ServizioApplePresente"),
            _ => Testi.T("Dati_ServizioAppleAssente"),
        }));
        if (statistiche is { } s)
        {
            dati.Add(("Video", Testi.T("Dati_Video", s.Larghezza, s.Altezza, s.Fps, s.Codec, s.MegabitAlSecondo)));
            dati.Add((Testi.T("Dati_Latenza"), s.LatenzaMs is int ms ? $"{ms} ms" : "—"));
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
            // Prima il pannello delle impostazioni, poi lo schermo intero (che torna alla vista di prima), poi il resto.
            if (impostazioniAperte)
            {
                ChiudiImpostazioni();
                evento.Handled = true;
                return;
            }
            if (InSchermoIntero)
            {
                AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
                evento.Handled = true;
                return;
            }
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
        // Passo 8 (windows.md 2.8, §5): F1 apre la Guida, come in ogni app di Windows; vale anche nella vista pulita.
        var f1 = new KeyboardAccelerator { Key = Windows.System.VirtualKey.F1 };
        f1.Invoked += (_, evento) =>
        {
            ApriGuida();
            evento.Handled = true;
        };
        radice.KeyboardAccelerators.Add(f1);
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
        // Passo 4: Ctrl+Z annulla «Azzera» finché c'è «Regolazioni azzerate · Annulla».
        Aggiungi(Windows.System.VirtualKey.Z, AnnullaDaTastiera, ctrl);
        // Come ⇧⌘P e ⇧⌘M sul Mac: vista pulita e finestra mini.
        Aggiungi(Windows.System.VirtualKey.P, () => { ImpostaVistaPulita(!vistaPulita); return true; }, ctrl | maiusc);
        Aggiungi(Windows.System.VirtualKey.M, () => { ImpostaMini(!InMini); return true; }, ctrl | maiusc);
        // Le viste (27 ottobre), come ⌘1 e ⌘2 sul Mac; F11 è lo schermo intero.
        Aggiungi(Windows.System.VirtualKey.Number1, () => { ImpostaVista(true); return true; }, ctrl);
        Aggiungi(Windows.System.VirtualKey.Number2, () => { ImpostaVista(false); return true; }, ctrl);
        // Passo 8: Ctrl+, apre il pannello «Impostazioni» (188 è il tasto della virgola, VK_OEM_COMMA); Ctrl+W nasconde la
        // finestra come la X.
        Aggiungi((Windows.System.VirtualKey)188, () =>
        {
            if (SoloVideo) return false;
            ApriImpostazioni();
            return true;
        }, ctrl);
        Aggiungi(Windows.System.VirtualKey.W, () =>
        {
            SalvaPosizione();
            if (!uscita) NascondiFinestra();
            return true;
        }, ctrl);

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
        // I tasti stanno tutti sulla radice, così valgono in ogni vista (anche con la barra o le colonne nascoste): senza
        // questo Windows mostrerebbe un suggerimento «F11» su ogni controllo. Per questo i tasti si scrivono nei
        // suggerimenti dei pulsanti e nei menu (KeyboardAcceleratorTextOverride, MainWindow.Menu.cs).
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

    private bool InMini => AppWindow.Presenter.Kind == AppWindowPresenterKind.CompactOverlay;

    /// <summary>Il video in una finestrella sempre in primo piano (sovrapposizione compatta di Windows).</summary>
    private void ImpostaMini(bool mini)
    {
        if (mini == InMini) return;
        if (mini)
        {
            ChiudiImpostazioni(subito: true);
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

    /// <summary>
    /// Schermo intero (27 ottobre): solo il video, niente altro; «Esci» compare per qualche secondo muovendo il mouse o
    /// premendo un tasto. Uscendo si torna alla vista di prima (Essenziale o Completo).
    /// </summary>
    private void AlternaSchermoIntero()
    {
        var intero = InSchermoIntero;
        if (!intero) ChiudiImpostazioni(subito: true);
        AppWindow.SetPresenter(intero ? AppWindowPresenterKind.Overlapped : AppWindowPresenterKind.FullScreen);
    }

    private void SuSchermoIntero(object sender, RoutedEventArgs e)
    {
        MenuSchermo.Hide();
        AlternaSchermoIntero();
    }

    private void ImpostaVistaPulita(bool pulita)
    {
        if (vistaPulita == pulita) return;
        vistaPulita = pulita;
        AggiornaModalita();
        Mostra(statoCollegamento);
    }

    /// <summary>«Riempi l'inquadratura»: vale solo per l'anteprima qui; le altre app ricevono il video intero.</summary>
    private void SuRiempi(object sender, RoutedEventArgs e)
    {
        var riempi = InterruttoreRiempi.IsOn;
        Preferenze.Riempi = riempi;
        Video.Stretch = riempi ? Stretch.UniformToFill : Stretch.Uniform;
        VideoElaborato.Stretch = Video.Stretch;
    }

    /// <summary>
    /// Nella finestra mini, nella vista pulita e nello schermo intero spariscono intestazione, colonne e barra: resta il
    /// video, intero.
    /// </summary>
    private void AggiornaModalita()
    {
        var solo = SoloVideo;
        if (solo) ChiudiImpostazioni(subito: true);
        var nascosto = Visibile(!solo);
        Intestazione.Visibility = nascosto;
        RigaIntestazione.Height = new GridLength(solo ? 0 : 48);
        // Senza intestazione torna la barra del titolo di sistema (MainWindow.Finestra.cs).
        AggiornaBarraDelTitolo();
        if (solo)
        {
            ColonnaSinistra.Width = new GridLength(0);
            ColonnaDestra.Width = new GridLength(0);
        }
        PannelloSinistro.Visibility = nascosto;
        PannelloDestroScorrimento.Visibility = nascosto;
        BarraAzioni.Visibility = nascosto;
        Centro.Padding = new Thickness(solo ? 0 : Token.SpazioMedio);
        Centro.RowSpacing = solo ? 0 : Token.SpazioPiccolo;
        // La radice resta trasparente per la Mica dell'intestazione: il fondo è delle colonne.
        Colonne.Background = Pennello(solo ? "Nero" : "Fondo");
        BordoVideo.BorderThickness = new Thickness(solo ? 0 : 1);
        BordoVideo.CornerRadius = new CornerRadius(solo ? 0 : Token.RaggioScheda);
        RiquadroVideo.CornerRadius = new CornerRadius(solo ? 0 : Token.RaggioVideoInterno);
        // «Esci» in alto al centro nello schermo intero e nella vista pulita; nella finestra mini l'icona in alto a destra.
        var intero = InSchermoIntero && !InMini;
        TestoTornaFinestra.Visibility = Visibile((vistaPulita || intero) && !InMini);
        TestoTornaFinestra.Text = intero ? Testi.T("Esci") : Testi.T("Vista_EsciPulita");
        PulsanteTornaFinestra.HorizontalAlignment = InMini ? HorizontalAlignment.Right : HorizontalAlignment.Center;
        AutomationProperties.SetName(PulsanteTornaFinestra, intero ? Testi.T("Vista_EsciSchermoIntero")
            : vistaPulita ? Testi.T("Vista_EsciPulita") : Testi.T("Vista_TornaFinestra"));
        ToolTipService.SetToolTip(PulsanteTornaFinestra, intero ? Testi.T("Vista_EsciSchermoInteroTasto")
            : vistaPulita ? Testi.T("Vista_EsciPulitaTasto") : Testi.T("Vista_TornaFinestraTasto"));
        // Entrando si vede per qualche secondo, così si sa che c'è.
        if (solo) MostraEsciPerUnPo();
        MostraPulsanteTorna();
        // Tornando alla finestra normale colonne e intestazione si rifanno per la larghezza di adesso, con la vista scelta.
        if (!solo) MostraVista();
        else
        {
            RigaSotto.Visibility = Visibility.Collapsed;
            PillolaTelefono.Visibility = Visibility.Collapsed;
        }
        AdattaVideo();
        // P21: nella finestra mini resta solo il telefono nella webcam, senza il riquadro piccolo.
        MostraVideo();
        AggiornaChip();
    }

    /// <summary>
    /// Nella finestra mini il pulsante per tornare c'è sempre; nello schermo intero e nella vista pulita per qualche secondo
    /// dopo un movimento del mouse o un tasto (MostraEsciPerUnPo).
    /// </summary>
    private void MostraPulsanteTorna() =>
        PulsanteTornaFinestra.Visibility = Visibile(InMini || ((vistaPulita || InSchermoIntero) && esciVisibile));

    private void SuPuntatoreSulVideo(object sender, PointerRoutedEventArgs e) => MostraEsciPerUnPo();

    private void SuPuntatoreFuoriVideo(object sender, PointerRoutedEventArgs e) => MostraPulsanteTorna();

    // MARK: finestra stretta

    private void SuDimensioniRadice(object sender, SizeChangedEventArgs e) => AdattaLayout();

    private void SuDimensioniVideo(object sender, SizeChangedEventArgs e) => AdattaVideo();

    /// <summary>Il video a 16:9 nello spazio che ha; nella finestra mini e nella vista pulita riempie tutto.</summary>
    private void AdattaVideo()
    {
        var larghezza = SpazioVideo.ActualWidth;
        var altezza = SpazioVideo.ActualHeight;
        if (larghezza <= 0 || altezza <= 0) return;
        if (SoloVideo)
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
    /// per l'Assistente vocale); il primo avvio si adatta da sé.
    /// </summary>
    private void AdattaLayout()
    {
        if (SoloVideo) return;
        var larghezza = Radice.ActualWidth;
        if (larghezza <= 0) return;
        // Il video più largo (disegno finale): colonne laterali più strette; sotto i 960 punti la colonna di sinistra lascia
        // il posto al video, e senza telefono il QR torna grande al centro. Nella vista «Essenziale» niente colonne: nel
        // passaggio si aprono o si chiudono un po' alla volta (aperturaColonne), sfumando.
        var (pieneSinistra, pieneDestra) = larghezza >= 1180 ? (240, 290) : larghezza >= 960 ? (220, 260) : (0, 260);
        var sinistra = Math.Round(pieneSinistra * aperturaColonne);
        var destra = Math.Round(pieneDestra * aperturaColonne);
        ColonnaSinistra.Width = new GridLength(sinistra);
        ColonnaDestra.Width = new GridLength(destra);
        PannelloSinistro.Visibility = Visibile(sinistra > 0);
        PannelloDestroScorrimento.Visibility = Visibile(destra > 0);
        PannelloSinistro.Opacity = aperturaColonne * aperturaColonne;
        PannelloDestroScorrimento.Opacity = aperturaColonne * aperturaColonne;

        MostraAttesaAlCentro();
        // Lo spazio del video, senza i margini.
        var centro = larghezza - sinistra - destra - 32;

        TestoPulsanteAiuto.Visibility = Visibile(centro >= 560);
        TestoAggiornamento.Visibility = Visibile(centro >= 560);
        TestoAccount.Visibility = Visibile(centro >= 560);
        TestoImpostazioni.Visibility = Visibile(centro >= 560);
        // I tasti sotto il video restano con icona e nome; nella finestra stretta si stringono.
        var compatta = centro < 600;
        foreach (var tasto in new FrameworkElement[] { PulsanteSpecchia, PulsanteSfondoVideo, PulsanteFoto, PulsanteRegistra, PulsanteSchermo })
            tasto.Width = compatta ? 66 : 80;
        // L'avviso dello spazio sul disco, in alto: nella finestra stretta solo l'icona.
        if (registraCompatto != compatta)
        {
            registraCompatto = compatta;
            MostraRegistrazione();
        }
        // Il primo avvio (QR e tre passi) si adatta da sé: testi a misura fissa, solo il QR nel Viewbox (passo 7).
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

    /// <summary>Il pulsante «Schermo intero» del menu «Schermo» dice cosa fa adesso; il suggerimento anche il tasto (F11).</summary>
    private void AggiornaSchermoIntero()
    {
        var intero = AppWindow.Presenter.Kind == AppWindowPresenterKind.FullScreen;
        IconaSchermoIntero.Glyph = intero ? "" : "";
        TestoSchermoIntero.Text = intero ? Testi.T("Esci") : Testi.T("SchermoIntero");
        AutomationProperties.SetName(PulsanteSchermoIntero, intero ? Testi.T("SchermoIntero_Esci") : Testi.T("SchermoIntero"));
        ToolTipService.SetToolTip(PulsanteSchermoIntero, intero ? Testi.T("SchermoIntero_EsciTasto") : Testi.T("SchermoIntero_Tasto"));
    }

    // MARK: dimensione e posizione (round 2, funzione 47)

    /// L'ultima posizione della finestra normale (in pixel): né massimizzata, né mini, né a schermo intero.
    private Rettangolo? ultimaPosizione;
    /// La scala di Windows dello schermo di <see cref="ultimaPosizione"/>: la misura si salva in DIP (passo 7).
    private double ultimaScala = 1;
    private bool massimizzaAllaPrimaApertura;
    /// Tiene la finestra sopra i 960×600 DIP (passo 7): vivo quanto la finestra.
    private MisuraMinimaFinestra? misuraMinima;

    /// <summary>
    /// Passo 7 (windows.md 2.2): misure in DIP. La prima apertura è 1360×840 DIP con la scala dello schermo (a 150 %
    /// 2040×1260 pixel, non 907×560 DIP come prima), al centro; una posizione salvata torna con la sua misura in DIP
    /// convertita con la scala dello schermo su cui cade. Sotto i 960×600 DIP la finestra non si stringe.
    /// </summary>
    private void RipristinaPosizione()
    {
        var finestra = WinRT.Interop.WindowNative.GetWindowHandle(this);
        // Solo la finestra normale: la finestra mini (sempre in primo piano) è piccola di proposito.
        misuraMinima = new MisuraMinimaFinestra(finestra, () => AppWindow.Presenter.Kind == AppWindowPresenterKind.Overlapped);
        if (Preferenze.Finestra is { } salvata)
        {
            // La scala dello schermo dove torna la barra del titolo.
            var scala = ScalaFinestra.InPunto(salvata.Rettangolo.X + PosizioneFinestra.BarraVisibileLarghezza / 2,
                salvata.Rettangolo.Y + PosizioneFinestra.BarraVisibileAltezza / 2);
            if (salvata.Su(AreeDegliSchermi(), scala) is { } r)
            {
                AppWindow.MoveAndResize(new RectInt32(r.X, r.Y, r.Larghezza, r.Altezza));
                massimizzaAllaPrimaApertura = salvata.Massimizzata;
                ultimaPosizione = r;
                ultimaScala = scala;
                return;
            }
        }
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var iniziale = PosizioneFinestra.Iniziale(new Rettangolo(area.X, area.Y, area.Width, area.Height), ScalaFinestra.Di(finestra));
        AppWindow.MoveAndResize(new RectInt32(iniziale.X, iniziale.Y, iniziale.Larghezza, iniziale.Altezza));
    }

    private void RicordaPosizione()
    {
        if (!AppWindow.IsVisible || AppWindow.Presenter is not OverlappedPresenter { State: OverlappedPresenterState.Restored }) return;
        ultimaPosizione = new Rettangolo(AppWindow.Position.X, AppWindow.Position.Y, AppWindow.Size.Width, AppWindow.Size.Height);
        ultimaScala = ScalaFinestra.Di(WinRT.Interop.WindowNative.GetWindowHandle(this));
    }

    private void SalvaPosizione()
    {
        RicordaPosizione();
        if (ultimaPosizione is not { } r) return;
        var massimizzata = AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Maximized };
        Preferenze.Finestra = PosizioneFinestra.DaPixel(r, ultimaScala, massimizzata);
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

    private void SuFinestraMini(object sender, RoutedEventArgs e)
    {
        MenuSchermo.Hide();
        ImpostaMini(true);
    }

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
