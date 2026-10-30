using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Niente gesti distruttivi a sorpresa (1.0 beta 2, passo 4; windows.md 1.8, 2.10, 2.11):
/// <list type="bullet">
/// <item>«Scollega» (pulsante in fondo a destra, link nella scheda del telefono, menu dell'icona) chiede prima se un'app
/// usa il video o se registri, con «Annulla» predefinito; altrimenti scollega subito;</item>
/// <item>«Personalizzato» si clicca: «Torna a «Riunione»»;</item>
/// <item>«Azzera» delle regolazioni mostra «Regolazioni azzerate · Annulla» per 8 secondi; Ctrl+Z fa lo stesso.</item>
/// </list>
/// Le parole e le regole sono in Conferme (WebcamLR.Ricevitore), con i test. Eliminare e sostituire un profilo sono in
/// MainWindow.Fotocamera.cs, la webcam in uso in MainWindow.Webcam.cs, i telefoni fidati in FinestraApp.cs.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Vero mentre la domanda «Scollegare…?» è aperta: un secondo clic non ne apre un'altra.</summary>
    private bool domandaScollegaAperta;

    /// <summary>I valori delle regolazioni prima di «Azzera», da rimettere con «Annulla» o Ctrl+Z.</summary>
    private readonly AnnullaPerPoco<Regolazioni> annullaAzzera = new();
    /// <summary>Gli effetti azzerati (di quel telefono o del computer): «Annulla» vale solo per loro.</summary>
    private ControlloEffetti? effettiAzzerati;
    private DispatcherQueueTimer? fineBarraAzzerate;

    /// <summary>
    /// Una domanda prima di un gesto distruttivo: titolo, testo (con <paramref name="fraseInPiu"/> davanti, se c'è) e
    /// «Annulla» predefinito, così Invio ed Esc non distruggono nulla. Vero solo con il pulsante di conferma.
    /// </summary>
    private async Task<bool> ChiediAsync(Domanda domanda, string? fraseInPiu = null)
    {
        await PreparaDialogoAsync();
        if (Content.XamlRoot is not { } radice) return false;
        var testo = string.Join(" ", new[] { fraseInPiu, domanda.Testo }.Where(f => !string.IsNullOrWhiteSpace(f)));
        var finestra = new ContentDialog
        {
            XamlRoot = radice,
            Title = new TextBlock { Text = domanda.Titolo, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = domanda.Conferma,
            CloseButtonText = domanda.Annulla,
            DefaultButton = ContentDialogButton.Close,
        };
        if (testo.Length > 0) finestra.Content = new TextBlock { Text = testo, TextWrapping = TextWrapping.Wrap };
        return await finestra.ShowAsync() == ContentDialogResult.Primary;
    }

    // MARK: Scollega

    /// <summary>
    /// «Scollega» da ogni posto: se il telefono è quello nella webcam e un'app usa il video, o registri, prima la domanda
    /// «Scollegare «iPhone di Ledion»? Zoom sta usando il video: si fermerà.»; altrimenti scollega subito. Dal menu
    /// dell'icona (<paramref name="dallIcona"/>) la finestra può essere nascosta: la domanda si fa davanti.
    /// </summary>
    private async void ChiediScollega(TelefonoCollegato collegato, bool dallIcona = false)
    {
        // Fuori dal try: il finally rimette a falso la bandierina solo se l'ha alzata questa chiamata.
        if (uscita || domandaScollegaAperta) return;
        domandaScollegaAperta = true;
        // async void (comando della finestra o del menu): un errore finisce in Errori.txt, non chiude l'app.
        try
        {
            if (!telefoni.Contiene(collegato)) return;
            var nellaWebcam = telefoni.ESelezionato(collegato);
            IReadOnlyList<string> app = [];
            if (nellaWebcam && inOnda)
            {
                try { app = await Task.Run(LeggiAppInUso); }
                catch (Exception) { }
            }
            // Con due telefoni, togliendo quello nella webcam il video passa all'altro invece di fermarsi.
            var altro = nellaWebcam ? telefoni.Telefoni.FirstOrDefault(t => !ReferenceEquals(t, collegato))?.Nome : null;
            var domanda = Conferme.Scollega(collegato.Nome, nellaWebcam, inOnda, app, registrazione is not null, altro);
            if (domanda is not null)
            {
                if (dallIcona) MostraFinestra();
                if (!await ChiediAsync(domanda) || uscita) return;
            }
            // Mentre si rispondeva il telefono può essere già andato via: ScollegaAsync lo controlla.
            await ScollegaAsync(collegato);
        }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
        }
        finally
        {
            domandaScollegaAperta = false;
        }
    }

    // MARK: «Personalizzato»

    /// <summary>
    /// Il menu di «Personalizzato»: solo «Torna a «Riunione»». Niente «Salva come profilo…»: i profili salvati di oggi
    /// tengono i comandi della fotocamera, non gli effetti che rendono il profilo «Personalizzato» (idea per dopo).
    /// </summary>
    private void SuAperturaPersonalizzato(object? sender, object e)
    {
        MenuPersonalizzato.Items.Clear();
        // «Personalizzato» si vede solo se c'era un profilo scelto (ProfiloPronto.Stato): la voce c'è sempre.
        if (ProfiloPronto.Cerca(Scelto?.ProfiloPronto) is not { } profilo) return;
        var torna = new MenuFlyoutItem { Text = Testi.T("Personalizzato_TornaA", profilo.Nome) };
        torna.Click += (_, _) => ApplicaProfiloPronto(profilo);
        MenuPersonalizzato.Items.Add(torna);
    }

    // MARK: «Azzera» con «Annulla»

    /// <summary>«Azzera»: le quattro regolazioni a 0, e per 8 secondi «Regolazioni azzerate · Annulla» (anche Ctrl+Z).</summary>
    private void SuAzzeraRegolazioni(object sender, RoutedEventArgs e)
    {
        if (sessione is null) return;
        var v = effetti.Valori;
        var prima = new Regolazioni(v.Luminosita, v.Contrasto, v.Saturazione, v.Nitidezza);
        ComandaEffetto(new Comando(Regolazioni: new Regolazioni(0, 0, 0, 0)));
        MostraValoriEffetti();
        annullaAzzera.Ricorda(prima, AdessoMs);
        effettiAzzerati = effetti;
        if (fineBarraAzzerate is null)
        {
            fineBarraAzzerate = coda.CreateTimer();
            fineBarraAzzerate.Interval = AnnullaPerPoco<Regolazioni>.Durata;
            fineBarraAzzerate.IsRepeating = false;
            fineBarraAzzerate.Tick += (_, _) => BarraAzzerate.IsOpen = false;
        }
        fineBarraAzzerate.Stop();
        BarraAzzerate.IsOpen = true;
        fineBarraAzzerate.Start();
    }

    private void SuAnnullaAzzera(object sender, RoutedEventArgs e) => AnnullaAzzera();

    /// <summary>Chiusa dal tempo, dalla X o da «Annulla»: non si annulla più.</summary>
    private void SuChiusaBarraAzzerate(InfoBar sender, InfoBarClosedEventArgs args)
    {
        fineBarraAzzerate?.Stop();
        annullaAzzera.Dimentica();
        effettiAzzerati = null;
    }

    /// <summary>Ctrl+Z: annulla «Azzera» finché l'InfoBar è visibile; altrimenti il tasto passa oltre.</summary>
    private bool AnnullaDaTastiera() => BarraAzzerate.IsOpen && AnnullaAzzera();

    /// <summary>Rimette le regolazioni di prima, se si è in tempo e sono ancora gli stessi effetti (stesso telefono).</summary>
    private bool AnnullaAzzera()
    {
        var stessi = sessione is not null && ReferenceEquals(effetti, effettiAzzerati);
        var prima = annullaAzzera.Annulla(AdessoMs);
        BarraAzzerate.IsOpen = false;
        if (!stessi || prima is null) return false;
        ComandaEffetto(new Comando(Regolazioni: prima));
        MostraValoriEffetti();
        return true;
    }
}
