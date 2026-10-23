using System.Net.Sockets;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
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
        Mostra(StatoVisivo.NessunTelefono);

        iconaTray = new IconaTray(apri: MostraFinestra, esci: Esci);
        AppWindow.Closing += (_, evento) =>
        {
            if (uscita) return;
            evento.Cancel = true;
            AppWindow.Hide();
        };
        Closed += async (_, _) =>
        {
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
            telefono = ciao;
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
        telefono = null;
        statoTelefono = null;
        statistiche = null;
        anteprima.Ferma();
        PannelloComandi.Visibility = Visibility.Collapsed;
        AzzeraComandi();
        Video.SetMediaPlayer(null);
        Video.Visibility = Visibility.Collapsed;
        Segnaposto.Opacity = 1;
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

    private void AggiornaTelefono()
    {
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

        TestoStatistiche.Text = statistiche is { Larghezza: > 0 } s
            ? $"{s.Larghezza}×{s.Altezza} · {s.Fps} fps · {(s.Codec == Codec.Hevc ? "HEVC" : "H.264")} · {s.MegabitAlSecondo:0.0} Mbit/s · latenza {(s.LatenzaMs is int l ? $"{l} ms" : "—")}"
            : "Collegato, in attesa del video";

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

    private async Task MostraQRAsync()
    {
        var indirizzi = IndirizziLocali.Ipv4();
        if (indirizzi.Count == 0)
        {
            IndirizzoScritto.Text = "Il PC non è collegato a una rete: collegalo al Wi-Fi o al cavo.";
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

    private void MostraComandi(Capacita capacita)
    {
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
            aggiornoComandi = true;
            CursoreZoom.Value = 1;
            aggiornoComandi = false;
            Comanda(new Comando(Obiettivo: obiettivo));
        }
    }

    private void SuZoom(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Zoom: e.NewValue));

    private void SuEsposizione(object sender, RangeBaseValueChangedEventArgs e) => Comanda(new Comando(Esposizione: Math.Round(e.NewValue, 1)));

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
