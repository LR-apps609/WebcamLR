using Microsoft.UI.Xaml;
using WebcamLR.Ricevitore;

namespace WebcamLR;

public partial class App : Application
{
    private MainWindow? finestra;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        finestra = new MainWindow();
        // Lanciata da Windows all'accesso (round 2, funzione 40): resta solo l'icona accanto all'orologio.
        // Gli argomenti si leggono dal processo: in un'app non pacchettizzata args.Arguments può essere vuoto.
        if (AvvioConWindows.AvviatoDaWindows(Environment.GetCommandLineArgs())) return;
        finestra.MostraFinestra();
    }
}
