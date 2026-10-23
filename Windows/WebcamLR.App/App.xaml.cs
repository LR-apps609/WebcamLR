using Microsoft.UI.Xaml;

namespace WebcamLR;

public partial class App : Application
{
    private Window? finestra;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        finestra = new MainWindow();
        finestra.Activate();
    }
}
