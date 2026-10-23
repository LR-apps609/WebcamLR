using System.Net.Sockets;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
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
    private SessioneComputer? sessione;
    private Ciao? telefono;
    private StatoTelefono? statoTelefono;
    private Statistiche? statistiche;

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.Resize(new SizeInt32(1280, 800));
        coda = DispatcherQueue.GetForCurrentThread();

        ascoltatore = new Ascoltatore();
        ascoltatore.NuovoTelefono += presa => coda.TryEnqueue(() => Accetta(presa));
        annuncio = new AnnuncioWindows((ushort)ascoltatore.Porta);
        _ = MostraQRAsync();
        Mostra(StatoVisivo.NessunTelefono);

        Closed += async (_, _) =>
        {
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
            var lettore = anteprima.Avvia(formato.Larghezza, formato.Altezza);
            SuInterfaccia(() =>
            {
                Video.SetMediaPlayer(lettore);
                Video.Visibility = Visibility.Visible;
                Segnaposto.Opacity = 0;
            });
        };
        nuova.FotogrammaRicevuto += fotogramma => anteprima.Accoda(fotogramma);
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

    private async Task DimenticaSeNonTornaAsync()
    {
        await Task.Delay(AttesaRiconnessione);
        if (sessione is not null) return;
        telefono = null;
        statoTelefono = null;
        statistiche = null;
        anteprima.Ferma();
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
            ? $"{s.Larghezza}×{s.Altezza} · {s.Fps} fps · H.264 · {s.MegabitAlSecondo:0.0} Mbit/s · latenza {(s.LatenzaMs is int l ? $"{l} ms" : "—")}"
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
}
