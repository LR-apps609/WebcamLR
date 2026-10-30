using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WebcamLR;

/// <summary>Il quadro dietro i nove quadratini del logo.</summary>
public enum FondoLogo
{
    /// <summary>La sfumatura verde scuro del logo (intestazione).</summary>
    Sfumatura,
    /// <summary>Nessun quadro: il logo sta già sulla sfumatura (segnaposto e schermata di attesa sul video, come la webcam).</summary>
    Nessuno,
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
        }
    }
}
