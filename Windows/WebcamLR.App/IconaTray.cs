using System.Windows.Input;
using H.NotifyIcon;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace WebcamLR;

/// <summary>
/// Icona accanto all'orologio (bozza grafica, Windows 2): WebcamLR resta attiva anche a finestra chiusa,
/// come sul Mac con il menu nella barra in alto. Il menu usa i comandi, non i Click: H.NotifyIcon
/// mostra un menu di sistema che non conosce gli eventi XAML.
/// </summary>
public sealed class IconaTray : IDisposable
{
    private readonly TaskbarIcon icona;

    public IconaTray(Action apri, Action esci)
    {
        var menu = new MenuFlyout();
        menu.Items.Add(new MenuFlyoutItem { Text = "Apri WebcamLR", Command = new Comando(apri) });
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(new MenuFlyoutItem { Text = "Esci", Command = new Comando(esci) });

        icona = new TaskbarIcon
        {
            ToolTipText = "WebcamLR",
            IconSource = new BitmapImage(new Uri("ms-appx:///Assets/WebcamLR.ico")),
            ContextFlyout = menu,
            LeftClickCommand = new Comando(apri),
            NoLeftClickDelay = true,
        };
        icona.ForceCreate(enablesEfficiencyMode: false);
    }

    /// <summary>Il testo che compare passando sopra l'icona, per esempio lo stato del telefono.</summary>
    public void Descrivi(string testo) => icona.ToolTipText = $"WebcamLR · {testo}";

    public void Dispose() => icona.Dispose();

    private sealed class Comando(Action azione) : ICommand
    {
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parametro) => true;
        public void Execute(object? parametro) => azione();
    }
}
