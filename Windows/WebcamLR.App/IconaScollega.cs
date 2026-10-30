using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace WebcamLR;

/// <summary>
/// L'icona di «Scollega», uguale su tutte le piattaforme: il «link spezzato» (Material <c>link_off</c>, SF
/// <c>link.badge.minus</c>). Segoe Fluent Icons non ha un link spezzato: dei 1574 glifi (elenco della WinUI Gallery,
/// Samples/Iconography/IconsData.json) ci sono Link (E71B), DisconnectDrive (E8CD: un disco di rete, usato fino alla
/// beta 3), DisconnectDisplay (EA14: un monitor), Unpin, SignOut; RemoveLink (ED90) è solo in Fabric MDL2, non in
/// Segoe. Si disegna allora come <c>link_off</c>: il glifo Link di Segoe con una barra in diagonale sopra, nel colore
/// del testo (segue Foreground, anche con il Contrasto elevato). Mai la X: la X è solo per chiudere.
/// </summary>
public sealed partial class IconaScollega : UserControl
{
    public IconaScollega()
    {
        IsTabStop = false;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAccessibilityView(this, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        var lato = Token.MisuraIcona + Token.SpazioMinuscolo;
        var link = new FontIcon { Glyph = "", FontSize = Token.MisuraIcona, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        // La barra dall'angolo in alto a sinistra a quello in basso a destra: taglia il link, che va dal basso a sinistra
        // all'alto a destra.
        var barra = new Line { X1 = 2, Y1 = 2, X2 = lato - 2, Y2 = lato - 2, StrokeThickness = 1.5, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
        barra.SetBinding(Shape.StrokeProperty, new Binding { Source = this, Path = new PropertyPath(nameof(Foreground)) });
        Content = new Grid { Width = lato, Height = lato, Children = { link, barra } };
    }
}
