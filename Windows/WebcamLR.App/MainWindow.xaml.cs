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
    private enum StatoVisivo { NessunTelefono, Collegato, Riconnessione }

    private static readonly TimeSpan AttesaRiconnessione = TimeSpan.FromSeconds(15);

    private readonly DispatcherQueue coda;
    private readonly Ascoltatore ascoltatore;
    private readonly AnnuncioWindows annuncio;
    private readonly AnteprimaVideo anteprima = new();
    private readonly IconaTray iconaTray;
    /// Vero solo quando si sceglie «Esci»: altrimenti chiudere la finestra la nasconde.
    private bool uscita;
    private SessioneComputer? sessione;
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
        AppWindow.Resize(new SizeInt32(1280, 800));
        AppWindow.SetIcon("Assets/WebcamLR.ico");
        coda = DispatcherQueue.GetForCurrentThread();

        ascoltatore = new Ascoltatore();
        ascoltatore.NuovoTelefono += presa => coda.TryEnqueue(() => Accetta(presa));
        annuncio = new AnnuncioWindows((ushort)ascoltatore.Porta);
        _ = MostraQRAsync();
        // Cambio di Wi-Fi o cavo collegato: il QR deve avere gli indirizzi nuovi.
        System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged += SuCambioRete;
        Mostra(StatoVisivo.NessunTelefono);

        AggiungiScorciatoie();
        PulsanteSpecchia.IsChecked = Preferenze.Specchia;
        Specchio.ScaleX = Preferenze.Specchia ? -1 : 1;

        iconaTray = new IconaTray(apri: MostraFinestra, esci: Esci);
        AppWindow.Closing += (_, evento) =>
        {
            if (uscita) return;
            evento.Cancel = true;
            AppWindow.Hide();
        };
        Closed += async (_, _) =>
        {
            System.Net.NetworkInformation.NetworkChange.NetworkAddressChanged -= SuCambioRete;
            iconaTray.Dispose();
            annuncio.Dispose();
            ascoltatore.Dispose();
            anteprima.Dispose();
            if (sessione is not null) await sessione.DisposeAsync();
        };
    }

    // Un telefono alla volta: un nuovo collegamento sostituisce il precedente.
    private void Accetta(Socket presa)
    {
        var vecchia = sessione;
        if (vecchia is not null) _ = vecchia.DisposeAsync().AsTask();

        var nuova = new SessioneComputer(presa, Environment.MachineName);
        void SuInterfaccia(Action azione) => coda.TryEnqueue(() => { if (sessione == nuova) azione(); });

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
            else if (telefono is not null)
            {
                AzzeraComandi();
            }
            telefono = ciao;
            PulsanteScollega.Visibility = Visibility.Visible;
            Mostra(StatoVisivo.Collegato);
        });
        nuova.StatoRicevuto += stato => SuInterfaccia(() =>
        {
            statoTelefono = stato;
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
        nuova.Silenzio += () => SuInterfaccia(() => Mostra(StatoVisivo.Riconnessione));
        nuova.Ripresa += () => SuInterfaccia(() => Mostra(StatoVisivo.Collegato));
        nuova.Chiusa += () => SuInterfaccia(() =>
        {
            sessione = null;
            if (telefono is null) { Mostra(StatoVisivo.NessunTelefono); return; }
            Mostra(StatoVisivo.Riconnessione);
            _ = DimenticaSeNonTornaAsync();
        });

        sessione = nuova;
        nuova.Avvia();
    }

    private void MostraFinestra()
    {
        AppWindow.Show();
        Activate();
    }

    private void Esci()
    {
        uscita = true;
        Close();
        Application.Current.Exit();
    }

    private async Task DimenticaSeNonTornaAsync()
    {
        await Task.Delay(AttesaRiconnessione);
        if (sessione is not null) return;
        Dimentica();
    }

    /// <summary>Chiusura voluta: il telefono riceve l'arrivederci e la finestra torna all'attesa subito.</summary>
    private async void SuScollega(object sender, RoutedEventArgs e)
    {
        if (sessione is not { } chiusa) return;
        sessione = null;
        Dimentica();
        try
        {
            await chiusa.ChiudiAsync();
            await chiusa.DisposeAsync();
        }
        // async void: un errore di rete qui non deve chiudere l'app.
        catch (Exception) { }
    }

    private void Dimentica()
    {
        telefono = null;
        statoTelefono = null;
        statistiche = null;
        storiaLatenza.Azzera();
        anteprima.Ferma();
        PannelloComandi.Visibility = Visibility.Collapsed;
        AzzeraComandi();
        Video.SetMediaPlayer(null);
        Video.Visibility = Visibility.Collapsed;
        Segnaposto.Opacity = 1;
        PulsanteScollega.Visibility = Visibility.Collapsed;
        Mostra(StatoVisivo.NessunTelefono);
    }

    private void Mostra(StatoVisivo stato)
    {
        var verde = new SolidColorBrush(ColorHelper.FromArgb(255, 0x6F, 0xC2, 0x8C));
        var ambra = new SolidColorBrush(ColorHelper.FromArgb(255, 0xE2, 0xA5, 0x4B));
        var secondario = (Brush)Application.Current.Resources["TestoSecondario"];
        iconaTray?.Descrivi(stato switch
        {
            StatoVisivo.Collegato => "collegato",
            StatoVisivo.Riconnessione => "riconnessione",
            _ => "nessun telefono",
        });
        switch (stato)
        {
            case StatoVisivo.Collegato:
                TestoStato.Text = "COLLEGATO · PRONTA";
                TestoStato.Foreground = (Brush)Application.Current.Resources["Testo"];
                PuntoStato.Fill = verde;
                PuntoStato.Stroke = null;
                PillolaStato.Background = new SolidColorBrush(ColorHelper.FromArgb(255, 0x23, 0x2D, 0x2A));
                PillolaStato.BorderThickness = new Thickness(0);
                MessaggioAnteprima.Text = "Collegato: in attesa del video…";
                break;
            case StatoVisivo.Riconnessione:
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
                MessaggioAnteprima.Text = "Apri WebcamLR sull'iPhone e scegli questo PC";
                break;
        }
        AggiornaTelefono();
    }

    private static Brush Pennello(string nome) => (Brush)Application.Current.Resources[nome];

    private void AggiornaTelefono()
    {
        AggiornaQualita();
        AggiornaGrafico();
        if (telefono is null)
        {
            NomeTelefono.Text = "In attesa di un telefono";
            DettagliTelefono.Text = $"Visibile in rete · porta {ascoltatore.Porta}";
            TestoStatistiche.Text = "Nessun telefono collegato";
            DettagliFotocamera.Text = "I controlli si attivano quando un telefono è collegato (round 4).";
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
        var indirizzi = IndirizziLocali.Ipv4();
        if (indirizzi.Count == 0)
        {
            IndirizzoScritto.Text = "Il PC non è collegato a una rete: collegalo al Wi-Fi o al cavo.";
            ImmagineQR.Source = null;
            return;
        }
        var porta = (ushort)ascoltatore.Porta;
        var associazione = new Associazione(indirizzi, porta, Environment.MachineName);
        IndirizzoScritto.Text = $"Oppure scrivi: {indirizzi[0]}{(porta == Servizio.PortaPredefinita ? "" : $":{porta}")}";

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

    private void SuSpecchia(object sender, RoutedEventArgs e)
    {
        var specchia = PulsanteSpecchia.IsChecked == true;
        Specchio.ScaleX = specchia ? -1 : 1;
        Preferenze.Specchia = specchia;
    }

    /// <summary>F11 entra ed esce dallo schermo intero, Esc ne esce: come nei browser.</summary>
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
            if (AppWindow.Presenter.Kind != AppWindowPresenterKind.FullScreen) return;
            AppWindow.SetPresenter(AppWindowPresenterKind.Overlapped);
            evento.Handled = true;
        };
        radice.KeyboardAccelerators.Add(f11);
        radice.KeyboardAccelerators.Add(esc);
        // Senza questo, Windows mostrerebbe un suggerimento «F11» su ogni controllo.
        radice.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
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
