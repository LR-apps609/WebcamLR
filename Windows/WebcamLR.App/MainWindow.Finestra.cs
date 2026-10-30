using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;

namespace WebcamLR;

/// <summary>
/// I bordi nativi di Windows 11 (1.0 beta 4, dalla direzione C): la Mica sotto la finestra, come nel gobbo, e una barra
/// del titolo sola. Prima c'erano due fasce (la barra di sistema ricolorata, 32, e sotto l'intestazione, 52) e il nome
/// «WebcamLR» due volte. Ora l'intestazione è la barra del titolo: ExtendsContentIntoTitleBar e SetTitleBar, i pulsanti
/// di sistema (riduci, ingrandisci, chiudi) dentro l'intestazione, alta come loro (Tall, 48). Si trascina dove non ci sono
/// pulsanti; i pulsanti dell'intestazione restano cliccabili perché le loro zone sono «Passthrough»
/// (InputNonClientPointerSource, Windows App SDK 1.4 o più). Con il Contrasto elevato i pulsanti di sistema tornano ai
/// colori di sistema.
/// Nella finestra mini e nella vista pulita l'intestazione non c'è: torna la barra di sistema (con i colori della
/// finestra), così la finestra si trascina e si chiude come prima. Nello schermo intero la barra non c'è comunque.
/// </summary>
public sealed partial class MainWindow
{
    /// Vero se Windows sa mettere il contenuto nella barra del titolo (Windows 10 1809 o più con il Windows App SDK).
    private bool barraPersonalizzabile;
    /// Le zone cliccabili dell'intestazione mandate a Windows l'ultima volta (in pixel), per non rimandarle uguali.
    private RectInt32[] zoneCliccabili = [];
    private readonly Windows.UI.ViewManagement.AccessibilitySettings accessibilita = new();

    private void PreparaFinestra()
    {
        // La Mica, come nel gobbo (FinestraGobbo). La radice è trasparente: si vede solo nell'intestazione, sotto la sua
        // tinta verde (TintaIntestazione); il resto della finestra ha i suoi fondi. Senza Mica (Windows 10) il fondo pieno.
        var mica = false;
        try
        {
            if (Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported())
            {
                SystemBackdrop = new MicaBackdrop();
                mica = true;
            }
        }
        catch (Exception) { }
        if (!mica) Radice.Background = Pennello("Fondo");

        try { barraPersonalizzabile = AppWindowTitleBar.IsCustomizationSupported(); }
        catch (Exception) { barraPersonalizzabile = false; }
        ColoraBarraDelTitolo();
        AggiornaBarraDelTitolo();
        // Le zone cliccabili cambiano con la misura della finestra, dei pulsanti (nomi nascosti nella finestra stretta,
        // «Aggiornamento disponibile») e con la scala dello schermo.
        Intestazione.SizeChanged += (_, _) => AggiornaZoneTitolo();
        ComandiIntestazione.SizeChanged += (_, _) => AggiornaZoneTitolo();
        Intestazione.Loaded += (_, _) =>
        {
            if (Intestazione.XamlRoot is { } radice) radice.Changed += (_, _) => AggiornaZoneTitolo();
            AggiornaZoneTitolo();
        };
        AppWindow.Changed += (_, cambio) =>
        {
            if (cambio.DidSizeChange || cambio.DidPresenterChange) AggiornaZoneTitolo();
        };
        // Contrasto elevato acceso o spento con la finestra aperta: i pulsanti di sistema seguono.
        accessibilita.HighContrastChanged += (_, _) => DispatcherQueue.TryEnqueue(ColoraBarraDelTitolo);
    }

    /// <summary>
    /// Una barra sola quando c'è l'intestazione; nella finestra mini, nella vista pulita e nello schermo intero la barra di
    /// sistema (AggiornaModalita la richiama a ogni cambio).
    /// </summary>
    private void AggiornaBarraDelTitolo()
    {
        if (!barraPersonalizzabile) return;
        try
        {
            var unica = !SoloVideo;
            if (ExtendsContentIntoTitleBar != unica) ExtendsContentIntoTitleBar = unica;
            if (unica)
            {
                SetTitleBar(Intestazione);
                // Alta come l'intestazione (48): i pulsanti di sistema sono della stessa altezza.
                AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
            }
            else
            {
                SetTitleBar(null);
            }
            zoneCliccabili = [];
            AggiornaZoneTitolo();
        }
        catch (Exception) { }
    }

    /// <summary>
    /// I colori dei pulsanti di sistema: trasparenti sopra l'intestazione, testo quasi bianco, al passaggio un gradino più
    /// chiaro (come i nostri pulsanti). Il fondo vale per la barra di sistema della finestra mini. Con il Contrasto elevato
    /// nessun colore nostro: quelli del tema di Windows.
    /// </summary>
    private void ColoraBarraDelTitolo()
    {
        if (!barraPersonalizzabile) return;
        try
        {
            var barra = AppWindow.TitleBar;
            if (accessibilita.HighContrast)
            {
                barra.BackgroundColor = barra.InactiveBackgroundColor = barra.ForegroundColor = barra.InactiveForegroundColor = null;
                barra.ButtonBackgroundColor = barra.ButtonInactiveBackgroundColor = null;
                barra.ButtonForegroundColor = barra.ButtonInactiveForegroundColor = null;
                barra.ButtonHoverBackgroundColor = barra.ButtonHoverForegroundColor = null;
                barra.ButtonPressedBackgroundColor = barra.ButtonPressedForegroundColor = null;
                return;
            }
            var fondo = Token.Colore(Token.ColorePannelloScuro);
            var testo = Token.Colore(Token.ColoreTesto);
            var tenue = Token.Colore(Token.ColoreTestoSecondario);
            var trasparente = Microsoft.UI.Colors.Transparent;
            barra.BackgroundColor = fondo;
            barra.InactiveBackgroundColor = fondo;
            barra.ForegroundColor = testo;
            barra.InactiveForegroundColor = tenue;
            barra.ButtonBackgroundColor = trasparente;
            barra.ButtonInactiveBackgroundColor = trasparente;
            barra.ButtonForegroundColor = testo;
            barra.ButtonInactiveForegroundColor = tenue;
            barra.ButtonHoverBackgroundColor = Token.Colore(Token.ColoreSfondoSopra);
            barra.ButtonHoverForegroundColor = testo;
            barra.ButtonPressedBackgroundColor = Token.Colore(Token.ColoreSfondoPremuto);
            barra.ButtonPressedForegroundColor = Token.Colore(Token.ColoreTestoTenue);
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Il posto per i pulsanti di sistema a destra (e a sinistra, con le lingue da destra a sinistra) e le zone cliccabili
    /// dell'intestazione: Impostazioni, Aiuto, il menu «WebcamLR» e «Aggiornamento disponibile». Tutto il resto
    /// dell'intestazione (logo, nome, pillola di stato, spazio vuoto) trascina la finestra; doppio clic la ingrandisce.
    /// </summary>
    private void AggiornaZoneTitolo()
    {
        if (!barraPersonalizzabile || !ExtendsContentIntoTitleBar || Intestazione.XamlRoot is not { } radice) return;
        try
        {
            var scala = radice.RasterizationScale;
            if (scala <= 0) return;
            var barra = AppWindow.TitleBar;
            var base_ = Token.PaddingIntestazione;
            var padding = new Thickness(base_.Left + barra.LeftInset / scala, base_.Top,
                base_.Right + barra.RightInset / scala, base_.Bottom);
            if (!Intestazione.Padding.Equals(padding))
            {
                // Il nuovo margine sposta i pulsanti, ma né l'intestazione né ComandiIntestazione cambiano misura (nessun
                // SizeChanged): le zone si misurano dopo il prossimo passaggio di layout, non con le posizioni di prima
                // (sarebbero sotto i pulsanti di sistema e Impostazioni, Aiuto e «WebcamLR» non si potrebbero cliccare).
                Intestazione.Padding = padding;
                void DopoIlLayout(object? mittente, object e)
                {
                    Intestazione.LayoutUpdated -= DopoIlLayout;
                    AggiornaZoneTitolo();
                }
                Intestazione.LayoutUpdated += DopoIlLayout;
                return;
            }
            var zone = new List<RectInt32>();
            foreach (var elemento in new FrameworkElement[] { PulsanteAggiornamento, PulsanteImpostazioni, PulsanteAiuto, PulsanteAccount })
            {
                if (elemento.Visibility != Visibility.Visible || elemento.ActualWidth <= 0) continue;
                var r = elemento.TransformToVisual(null).TransformBounds(
                    new Windows.Foundation.Rect(0, 0, elemento.ActualWidth, elemento.ActualHeight));
                zone.Add(new RectInt32((int)Math.Round(r.X * scala), (int)Math.Round(r.Y * scala),
                    (int)Math.Round(r.Width * scala), (int)Math.Round(r.Height * scala)));
            }
            var nuove = zone.ToArray();
            if (nuove.SequenceEqual(zoneCliccabili)) return;
            zoneCliccabili = nuove;
            InputNonClientPointerSource.GetForWindowId(AppWindow.Id).SetRegionRects(NonClientRegionKind.Passthrough, nuove);
        }
        catch (Exception) { }
    }
}
