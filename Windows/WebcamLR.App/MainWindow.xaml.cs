using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace WebcamLR;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        AppWindow.Resize(new SizeInt32(1280, 800));
    }
}
