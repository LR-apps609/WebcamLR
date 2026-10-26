using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Win32;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Sotto la barra delle azioni, come «App che usano WebcamLR» sul Mac: mentre la webcam è in onda, le app che la stanno
/// usando (lette dalle impostazioni della privacy di Windows, fuori dal thread dell'interfaccia, ogni 3 secondi).
/// I nomi in AppWebcam (WebcamLR.Ricevitore), provati con i test.
/// </summary>
public sealed partial class MainWindow
{
    private const string ChiaveConsenso = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam";

    private DispatcherQueueTimer? controlloAppInUso;
    private IReadOnlyList<string> appMostrate = [];
    /// <summary>Lo spazio sotto il video: nascosto nella finestra mini e nella vista pulita.</summary>
    private bool appInUsoVisibile = true;
    private int richiesteAppInUso;

    private void InizializzaAppInUso()
    {
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

    private void MostraAppInUso(IReadOnlyList<string> elenco)
    {
        if (!appMostrate.SequenceEqual(elenco))
        {
            appMostrate = elenco;
            ElencoAppInUso.Children.Clear();
            foreach (var nome in elenco)
            {
                ElencoAppInUso.Children.Add(new Border
                {
                    Background = Pennello("TallyTenue"),
                    CornerRadius = new CornerRadius(12),
                    Padding = new Thickness(10, 3, 10, 4),
                    Child = new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        Spacing = 6,
                        Children =
                        {
                            new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 7, Height = 7, Fill = Pennello("Tally"), VerticalAlignment = VerticalAlignment.Center },
                            new TextBlock { Text = nome, Foreground = Pennello("TallyTesto"), FontSize = 12.5 },
                        },
                    },
                });
            }
        }
        TestoAppInUso.Text = !inOnda
            ? Testi.T("AppInUso_Spiegazione")
            : elenco.Count == 0 ? Testi.T("AppInUso_UnApp")
            : elenco.Count == 1 ? Testi.T("AppInUso_InOndaUna") : Testi.T("AppInUso_InOndaPiu");
        ElencoAppInUso.Visibility = Visibile(elenco.Count > 0);
    }
}
