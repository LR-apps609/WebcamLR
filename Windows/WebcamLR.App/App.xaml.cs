using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using WebcamLR.Ricevitore;

namespace WebcamLR;

public partial class App : Application
{
    private MainWindow? finestra;

    public App()
    {
        InitializeComponent();
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Una sola copia: la porta, l'annuncio in rete e l'icona accanto all'orologio sono di una finestra sola.
        // Riaperta dal menu Start mentre è già nascosta accanto all'orologio, la copia nuova passa l'apertura
        // a quella che c'è (che mostra la finestra) e si chiude.
        var principale = AppInstance.FindOrRegisterForKey("WebcamLR");
        if (!principale.IsCurrent)
        {
            try { await principale.RedirectActivationToAsync(AppInstance.GetCurrent().GetActivatedEventArgs()); }
            catch (Exception) { }
            Exit();
            return;
        }
        finestra = new MainWindow();
        var mostra = finestra;
        // Arriva su un thread di sistema.
        principale.Activated += (_, _) => mostra.DispatcherQueue.TryEnqueue(mostra.MostraFinestra);
        // Lanciata da Windows all'accesso (round 2, funzione 40): resta solo l'icona accanto all'orologio.
        // Gli argomenti si leggono dal processo: in un'app non pacchettizzata args.Arguments può essere vuoto.
        if (AvvioConWindows.AvviatoDaWindows(Environment.GetCommandLineArgs())) return;
        finestra.MostraFinestra();
    }
}
