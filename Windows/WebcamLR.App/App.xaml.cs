using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using WebcamLR.Ricevitore;

namespace WebcamLR;

public partial class App : Application
{
    private MainWindow? finestra;

    /// <summary>Gli errori che arrivano fino in cima finiscono qui, per «Segnala un bug».</summary>
    private static readonly string FileErrori =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WebcamLR", "Errori.txt");

    public App()
    {
        // La lingua prima di qualsiasi XAML (W2): gli x:Uid si risolvono quando le pagine si caricano.
        Testi.Imposta();
        InitializeComponent();
        // Un errore non previsto in un gestore (async void, un evento di WinUI) non chiude l'app senza dire nulla:
        // si scrive in Errori.txt e l'app continua.
        UnhandledException += (_, evento) =>
        {
            ScriviErrore(evento.Exception);
            evento.Handled = true;
        };
        TaskScheduler.UnobservedTaskException += (_, evento) =>
        {
            ScriviErrore(evento.Exception);
            evento.SetObserved();
        };
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            // Una sola copia: la porta, l'annuncio in rete e l'icona accanto all'orologio sono di una finestra sola.
            // Riaperta dal menu Start mentre è già nascosta accanto all'orologio, la copia nuova passa l'apertura
            // a quella che c'è (che mostra la finestra) e si chiude.
            // «--esci» (1.7): l'installatore chiede alla copia aperta di uscire bene. Passa con lo stesso canale.
            var esci = UscitaRichiesta.Chiesta(Environment.GetCommandLineArgs());
            var principale = AppInstance.FindOrRegisterForKey("WebcamLR");
            if (!principale.IsCurrent)
            {
                try { await principale.RedirectActivationToAsync(AppInstance.GetCurrent().GetActivatedEventArgs()); }
                catch (Exception) { }
                Exit();
                return;
            }
            // Nessuna copia aperta da chiudere: non si apre niente.
            if (esci)
            {
                Exit();
                return;
            }
            finestra = new MainWindow();
            var mostra = finestra;
            // Arriva su un thread di sistema. Con «--esci» la copia aperta esce come con «Esci», senza domande
            // (chiude e salva la registrazione); altrimenti mostra la finestra.
            principale.Activated += (_, attivazione) =>
            {
                var chiedeUscita = ChiedeUscita(attivazione);
                mostra.DispatcherQueue.TryEnqueue(() =>
                {
                    if (chiedeUscita) mostra.EsciSenzaDomande();
                    else mostra.MostraFinestra();
                });
            };
            // Lanciata da Windows all'accesso (round 2, funzione 40): resta solo l'icona accanto all'orologio.
            // Gli argomenti si leggono dal processo: in un'app non pacchettizzata args.Arguments può essere vuoto.
            // Senza icona (non si è potuta creare) la finestra si mostra comunque: altrimenti l'app sarebbe invisibile.
            if (AvvioConWindows.AvviatoDaWindows(Environment.GetCommandLineArgs()) && finestra.HaIconaTray) return;
            finestra.MostraFinestra();
        }
        catch (Exception errore)
        {
            // La finestra non si è creata: un messaggio, invece di un'app che sparisce senza dire nulla.
            ScriviErrore(errore);
            _ = MessageBoxW(IntPtr.Zero, Testi.T("AvvioNonRiuscito", errore.Message, FileErrori), "WebcamLR", 0x10);
            Exit();
        }
    }

    /// <summary>
    /// Vero se l'attivazione girata da un'altra copia porta «--esci». In un'app non pacchettizzata gli argomenti
    /// arrivano come riga di comando intera (con il percorso dell'exe) in ILaunchActivatedEventArgs.Arguments.
    /// </summary>
    private static bool ChiedeUscita(AppActivationArguments attivazione)
    {
        try
        {
            return attivazione.Kind == ExtendedActivationKind.Launch
                   && attivazione.Data is global::Windows.ApplicationModel.Activation.ILaunchActivatedEventArgs avvio
                   && UscitaRichiesta.Chiesta(avvio.Arguments);
        }
        catch (Exception) { return false; }
    }

    public static void ScriviErrore(Exception errore)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FileErrori)!);
            // Un errore che si ripete non riempie il disco: oltre 1 MB si ricomincia.
            if (File.Exists(FileErrori) && new FileInfo(FileErrori).Length > 1_000_000) File.Delete(FileErrori);
            File.AppendAllText(FileErrori, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} · {errore}\n\n");
        }
        catch (Exception) { }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr finestra, string testo, string titolo, uint tipo);
}
