using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Win32;
using WebcamLR.Ricevitore;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// In fondo sotto il video, nelle viste «Completo» ed «Essenziale», una riga sola come sul Mac (RigaAppWebcam):
/// «Disponibile per Zoom · Slack · OBS · Meet e tanti altri», ogni nome con un segno neutro; mentre la webcam è in onda,
/// in corallo, «In uso da Zoom» con le app che la stanno usando (lette dalle impostazioni della privacy di Windows,
/// fuori dal thread dell'interfaccia, ogni 3 secondi). I nomi in AppWebcam (WebcamLR.Ricevitore), provati con i test.
/// Il suggerimento della riga dice cosa serve (installare o riparare la webcam in «Uscite», sceglierla nell'app); nella
/// pagina «Uscite» lo stesso aiuto è scritto sotto la riga.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>
    /// Un'app nominata nella riga. Niente loghi ufficiali: sono marchi delle rispettive aziende e per usarli serve il loro
    /// permesso. Al loro posto un glifo di Segoe Fluent Icons o un'iniziale, in salvia chiaro. Se arriva il permesso:
    /// l'immagine va in Assets (per esempio «Assets/App/LogoZoom.png», 14 × 14 px a 100%) e qui basta scriverne
    /// l'indirizzo in <c>Immagine</c> («ms-appx:///Assets/App/LogoZoom.png»): la riga la mostra al posto del segno.
    /// </summary>
    private sealed record AppNellaRiga(string Nome, string? Glifo = null, string? Iniziale = null, string? Immagine = null);

    /// <summary>
    /// Le app nominate nella riga, in quest'ordine (le altre sono «e tanti altri»). I nomi sono marchi: non si traducono.
    /// I segni non sono glifi che nella finestra vogliono dire altro (beta 4): Zoom la videochiamata (non più E714, il
    /// video), OBS lo streaming (non più E7C8, che è «Registra»), Meet il web.
    /// </summary>
    private static readonly AppNellaRiga[] AppInRiga =
    [
        new("Zoom", Glifo: "\uE8AA"),
        new("Slack", Iniziale: "#"),
        new("OBS", Glifo: "\uE93E"),
        new("Meet", Glifo: "\uE774"),
    ];

    private const string ChiaveConsenso = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam";

    private DispatcherQueueTimer? controlloAppInUso;
    private int richiesteAppInUso;

    private void InizializzaAppInUso()
    {
        CostruisciRigaApp();
        controlloAppInUso = coda.CreateTimer();
        controlloAppInUso.Interval = TimeSpan.FromSeconds(3);
        controlloAppInUso.Tick += (_, _) => _ = AggiornaAppInUsoAsync();
        controlloAppInUso.Start();
        MostraAppInUso([]);
    }

    private void FermaAppInUso() => controlloAppInUso?.Stop();

    private async Task AggiornaAppInUsoAsync()
    {
        var richiesta = ++richiesteAppInUso;
        IReadOnlyList<string> elenco = [];
        if (inOnda)
        {
            try { elenco = await Task.Run(LeggiAppInUso); }
            catch (Exception) { }
        }
        if (richiesta != richiesteAppInUso) return;
        MostraAppInUso(elenco);
    }

    /// <summary>Le app classiche (NonPackaged) e quelle dello Store, per l'utente di adesso.</summary>
    private static IReadOnlyList<string> LeggiAppInUso()
    {
        var voci = new List<(string, long, long)>();
        using var radice = Registry.CurrentUser.OpenSubKey(ChiaveConsenso);
        if (radice is null) return [];
        Leggi(radice, voci, "NonPackaged");
        using (var classiche = radice.OpenSubKey("NonPackaged")) if (classiche is not null) Leggi(classiche, voci, null);
        return AppWebcam.Elenco(voci);

        static void Leggi(RegistryKey chiave, List<(string, long, long)> voci, string? salta)
        {
            foreach (var nome in chiave.GetSubKeyNames().Take(500))
            {
                if (nome == salta) continue;
                using var app = chiave.OpenSubKey(nome);
                if (app is null) continue;
                var inizio = app.GetValue("LastUsedTimeStart") is long i ? i : 0;
                var fine = app.GetValue("LastUsedTimeStop") is long f ? f : 0;
                voci.Add((nome, inizio, fine));
            }
        }
    }

    /// <summary>
    /// «Disponibile per {0} e tanti altri»: il testo tradotto intorno, al posto di {0} le app con il loro segno,
    /// separate da « · ». Un testo solo nel catalogo, così ogni lingua sceglie l'ordine.
    /// </summary>
    private void CostruisciRigaApp()
    {
        RigaAppDisponibili.Children.Clear();
        // Il modello con «{0}» al suo posto, per sapere dove vanno le app.
        var modello = Testi.T("AppWebcam_Disponibile", "{0}");
        var posto = modello.IndexOf("{0}", StringComparison.Ordinal);
        var prima = posto < 0 ? modello : modello[..posto];
        var dopo = posto < 0 ? "" : modello[(posto + 3)..];
        if (prima.Length > 0) RigaAppDisponibili.Children.Add(TestoRiga(prima));
        if (posto >= 0)
        {
            for (var i = 0; i < AppInRiga.Length; i++)
            {
                if (i > 0) RigaAppDisponibili.Children.Add(TestoRiga(" · "));
                RigaAppDisponibili.Children.Add(SegnoApp(AppInRiga[i]));
                RigaAppDisponibili.Children.Add(TestoRiga(" " + AppInRiga[i].Nome));
            }
        }
        if (dopo.Length > 0) RigaAppDisponibili.Children.Add(TestoRiga(dopo));
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(RigaAppDisponibili,
            Testi.T("AppWebcam_Disponibile", string.Join(" · ", AppInRiga.Select(a => a.Nome))));

        static TextBlock TestoRiga(string testo) => new()
        {
            Text = testo,
            FontSize = Token.MisuraTestoPiccolo,
            Foreground = Pennello("TestoSecondario"),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>L'immagine se c'è il permesso, altrimenti il glifo o l'iniziale in salvia chiaro.</summary>
    private static FrameworkElement SegnoApp(AppNellaRiga app)
    {
        if (app.Immagine is { } indirizzo)
        {
            return new Image { Source = new BitmapImage(new Uri(indirizzo)), Width = 14, Height = 14, VerticalAlignment = VerticalAlignment.Center };
        }
        if (app.Glifo is { } glifo)
        {
            return new FontIcon { Glyph = glifo, FontSize = Token.MisuraDettaglio, Foreground = Pennello("SalviaChiara"), VerticalAlignment = VerticalAlignment.Center };
        }
        return new TextBlock
        {
            Text = app.Iniziale ?? "",
            FontFamily = (FontFamily)Application.Current.Resources["Etichette"],
            FontSize = Token.MisuraSezione,
            Foreground = Pennello("SalviaChiara"),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>Le app che usano il video secondo l'ultima lettura (vuoto fuori onda): per l'icona accanto all'orologio.</summary>
    private IReadOnlyList<string> appInUsoAttuali = [];
    /// <summary>«In onda su Zoom» e «Fuori onda» nel registro, una riga per cambio (windows.md N4).</summary>
    private readonly RegistroInOnda registroInOnda = new();

    private void MostraAppInUso(IReadOnlyList<string> elenco)
    {
        // In onda: chi la usa; se Windows non dice quale app (o non si legge), «un'altra app».
        var inUso = inOnda;
        appInUsoAttuali = inUso ? elenco : [];
        // Nel registro e detto dall'Assistente vocale; l'icona accanto all'orologio prende il punto corallo e il nome.
        if (registroInOnda.Cambio(inUso, elenco) is { } riga) Avvisa(riga);
        AggiornaIcona();
        TestoAppInUso.Text = !inUso ? ""
            : elenco.Count == 0 ? Testi.T("AppWebcam_InUsoAltra")
            : Testi.T("AppWebcam_InUsoDa", string.Join(" · ", elenco));
        RigaAppInUso.Visibility = Visibile(inUso);
        RigaAppDisponibili.Visibility = Visibile(!inUso);
        AggiornaAiutoApp();
    }

    /// <summary>Il suggerimento della riga e, nella pagina «Uscite», lo stesso aiuto scritto: cosa serve adesso.</summary>
    private void AggiornaAiutoApp()
    {
        var aiuto = statoWebcam switch
        {
            StatoWebcam.NonInstallata => Testi.T("AppWebcam_AiutoInstalla", Testi.T("Impostazioni_Uscite")),
            StatoWebcam.DaRiparare => Testi.T("AppWebcam_AiutoRipara", Testi.T("Impostazioni_Uscite")),
            _ => Testi.T("AppWebcam_AiutoScegli"),
        };
        ToolTipService.SetToolTip(RigaApp, aiuto);
        AiutoAppWebcam.Text = aiuto;
    }
}
