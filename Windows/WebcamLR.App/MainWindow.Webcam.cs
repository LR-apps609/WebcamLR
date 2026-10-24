using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// La scheda «Webcam per le altre app» (1.24–1.26): stato, installazione con il permesso dell'amministratore,
/// riparazione, rimozione pulita, inquadratura e specchio per chi guarda.
/// </summary>
public sealed partial class MainWindow
{
    private readonly UscitaWebcam uscitaWebcam = new();
    private StatoWebcam statoWebcam = StatoWebcam.NonInstallata;
    /// <summary>Vero mentre l'installatore lavora: i pulsanti restano spenti.</summary>
    private bool lavoroWebcam;
    private bool aggiornoWebcam;
    /// Cresce a ogni controllo: uno vecchio che finisce dopo non rimette lo stato di prima.
    private int richiesteStatoWebcam;
    private bool privacyNegata;

    private void InizializzaWebcam()
    {
        aggiornoWebcam = true;
        SceltaInquadraturaWebcam.SelectedIndex = Preferenze.InquadraturaWebcam == Inquadratura.Riempi ? 1 : 0;
        InterruttoreSpecchiaWebcam.IsOn = Preferenze.SpecchiaWebcam;
        aggiornoWebcam = false;
        uscitaWebcam.Inquadratura = Preferenze.InquadraturaWebcam;
        uscitaWebcam.Specchia = Preferenze.SpecchiaWebcam;
        uscitaWebcam.Evento += testo => registro.Aggiungi(testo);
        uscitaWebcam.InUsoCambiato += inUso => coda.TryEnqueue(() => _ = AggiornaWebcamAsync());
        MostraWebcam(InstallazioneWebcam.WindowsSupportato ? StatoWebcam.NonInstallata : StatoWebcam.NonSupportata);
        _ = AggiornaWebcamAsync();
    }

    private async Task AggiornaWebcamAsync()
    {
        var numero = ++richiesteStatoWebcam;
        var stato = await InstallazioneWebcam.StatoAsync(uscitaWebcam.InUso);
        privacyNegata = InstallazioneWebcam.WindowsSupportato && InstallazioneWebcam.FotocameraNegataDallaPrivacy();
        if (numero != richiesteStatoWebcam) return;
        MostraWebcam(stato);
    }

    private void MostraWebcam(StatoWebcam stato)
    {
        statoWebcam = stato;
        var installata = stato is StatoWebcam.Installata or StatoWebcam.InUso;
        uscitaWebcam.Abilitata = installata;
        DescrizioneWebcam.Text = CodiciInstallazione.Descrivi(stato);
        var (testo, colore) = stato switch
        {
            StatoWebcam.NonSupportata => ("WINDOWS 10", "TestoSecondario"),
            StatoWebcam.NonInstallata => ("NON INSTALLATA", "TestoSecondario"),
            StatoWebcam.DaRiparare => ("DA RIPARARE", "Ambra"),
            StatoWebcam.InUso => ("IN ONDA", "Tally"),
            _ => ("INSTALLATA", "Verde"),
        };
        StatoWebcamTesto.Text = testo;
        StatoWebcamTesto.Foreground = Pennello(colore == "Verde" || colore == "Tally" ? "Testo" : colore);
        PuntoWebcam.Fill = Pennello(colore);

        PulsanteInstallaWebcam.Visibility = Visibile(stato is StatoWebcam.NonInstallata or StatoWebcam.DaRiparare);
        PulsanteInstallaWebcam.Content = stato == StatoWebcam.DaRiparare ? "Ripara la webcam" : "Installa la webcam WebcamLR";
        PulsanteInstallaWebcam.IsEnabled = !lavoroWebcam;
        PannelloOpzioniWebcam.Visibility = Visibile(installata);
        PulsanteRimuoviWebcam.Visibility = Visibile(installata || stato == StatoWebcam.DaRiparare);
        PulsanteRimuoviWebcam.IsEnabled = !lavoroWebcam;

        if (privacyNegata && !BarraWebcam.IsOpen)
        {
            BarraWebcam.Severity = InfoBarSeverity.Warning;
            BarraWebcam.Title = "Windows nega la fotocamera alle app.";
            BarraWebcam.Message = "Zoom, Teams e i browser non vedono nessuna webcam finché in Impostazioni → Privacy e sicurezza → Fotocamera "
                + "non accendi «Consenti alle app desktop di accedere alla fotocamera».";
            AzioneWebcam.Content = "Apri le impostazioni";
            AzioneWebcam.Visibility = Visibility.Visible;
            BarraWebcam.IsOpen = true;
        }
    }

    private async void SuInstallaWebcam(object sender, RoutedEventArgs e)
    {
        await EseguiInstallatoreAsync(installa: true);
    }

    private async void SuRimuoviWebcam(object sender, RoutedEventArgs e)
    {
        var conferma = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Rimuovere la webcam WebcamLR?",
            Content = "Sparisce dall'elenco delle fotocamere di tutte le app, senza riavviare il PC. "
                + "Il video in questa finestra continua a funzionare, e la puoi reinstallare quando vuoi.",
            PrimaryButtonText = "Rimuovi",
            CloseButtonText = "Annulla",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await conferma.ShowAsync() != ContentDialogResult.Primary) return;
        await EseguiInstallatoreAsync(installa: false);
    }

    private async Task EseguiInstallatoreAsync(bool installa)
    {
        if (lavoroWebcam) return;
        lavoroWebcam = true;
        BarraWebcam.IsOpen = false;
        MostraWebcam(statoWebcam);
        registro.Aggiungi(installa ? "Webcam: installazione…" : "Webcam: rimozione…");
        int codice;
        try { codice = installa ? await InstallazioneWebcam.InstallaAsync() : await InstallazioneWebcam.RimuoviAsync(); }
        catch (Exception errore) { codice = errore.HResult < 0 ? errore.HResult : CodiciInstallazione.InstallatoreMancante; }
        lavoroWebcam = false;
        registro.Aggiungi($"Webcam: {CodiciInstallazione.Descrivi(codice)}");

        if (codice == CodiciInstallazione.Riuscita)
        {
            BarraWebcam.Severity = InfoBarSeverity.Success;
            BarraWebcam.Title = installa ? "Webcam installata." : "Webcam rimossa.";
            BarraWebcam.Message = installa
                ? "Scegli «WebcamLR» come fotocamera in Zoom, Teams, Meet o OBS. Un'app già aperta va chiusa del tutto e riaperta per vederla."
                : "Non compare più nelle app. Qualche file ancora aperto si cancella al prossimo riavvio, da solo.";
        }
        else if (codice != CodiciInstallazione.Annullata)
        {
            BarraWebcam.Severity = InfoBarSeverity.Error;
            BarraWebcam.Title = installa ? "La webcam non si è installata." : "La webcam non si è rimossa del tutto.";
            BarraWebcam.Message = CodiciInstallazione.Descrivi(codice) + " Dettagli in C:\\ProgramData\\WebcamLR\\Installazione webcam.txt.";
        }
        else
        {
            BarraWebcam.Severity = InfoBarSeverity.Informational;
            BarraWebcam.Title = "";
            BarraWebcam.Message = CodiciInstallazione.Descrivi(codice);
        }
        AzioneWebcam.Visibility = codice == CodiciInstallazione.AccessoNegato ? Visibility.Visible : Visibility.Collapsed;
        AzioneWebcam.Content = "Apri le impostazioni";
        BarraWebcam.IsOpen = true;
        await AggiornaWebcamAsync();
    }

    private void SuAzioneWebcam(object sender, RoutedEventArgs e) => InstallazioneWebcam.ApriPrivacy();

    private void SuInquadraturaWebcam(object sender, SelectionChangedEventArgs e)
    {
        if (aggiornoWebcam || SceltaInquadraturaWebcam is null) return;
        var modo = SceltaInquadraturaWebcam.SelectedIndex == 1 ? Inquadratura.Riempi : Inquadratura.Adatta;
        Preferenze.InquadraturaWebcam = modo;
        uscitaWebcam.Inquadratura = modo;
    }

    private void SuSpecchiaWebcam(object sender, RoutedEventArgs e)
    {
        if (aggiornoWebcam || InterruttoreSpecchiaWebcam is null) return;
        Preferenze.SpecchiaWebcam = InterruttoreSpecchiaWebcam.IsOn;
        uscitaWebcam.Specchia = InterruttoreSpecchiaWebcam.IsOn;
    }
}
