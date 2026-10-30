using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace WebcamLR;

/// <summary>Il quadro dietro i nove quadratini del logo.</summary>
public enum FondoLogo
{
    /// <summary>La sfumatura verde scuro del logo (intestazione).</summary>
    Sfumatura,
    /// <summary>Nessun quadro: il logo sta già sulla sfumatura (segnaposto sul video).</summary>
    Nessuno,
    /// <summary>Un quadro chiaro e trasparente, sopra la schermata di attesa.</summary>
    Velo,
}

/// <summary>Il logo di WebcamLR, uno solo per tutta la finestra (LogoWebcamLR.xaml).</summary>
public sealed partial class LogoWebcamLR : UserControl
{
    private FondoLogo fondo = FondoLogo.Sfumatura;

    public LogoWebcamLR()
    {
        InitializeComponent();
    }

    public FondoLogo Fondo
    {
        get => fondo;
        set
        {
            fondo = value;
            Quadro.Visibility = value == FondoLogo.Nessuno ? Visibility.Collapsed : Visibility.Visible;
            Quadro.Fill = value == FondoLogo.Velo
                ? (Brush)Resources["LogoFondoVelo"]
                : (Brush)Application.Current.Resources["SfumaturaLogo"];
        }
    }
}
