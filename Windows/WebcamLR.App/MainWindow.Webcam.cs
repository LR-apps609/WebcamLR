using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// «Webcam per le altre app» in «Uscite» (1.24–1.26): stato, installazione con il permesso dell'amministratore,
/// riparazione, rimozione pulita e inquadratura. Lo specchio non è più qui: è uno solo, del telefono, per tutti (1.14).
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
    /// Vero mentre la barra mostra l'avviso della privacy: sparisce da sola quando la privacy si sistema.
    private bool barraPrivacy;

    private void InizializzaWebcam()
    {
        aggiornoWebcam = true;
        SceltaInquadraturaWebcam.SelectedIndex = Preferenze.InquadraturaWebcam == Inquadratura.Riempi ? 1 : 0;
        aggiornoWebcam = false;
        uscitaWebcam.Inquadratura = Preferenze.InquadraturaWebcam;
        // Lo specchio è uno solo (1.14): il video arriva già girato dal telefono, la webcam non lo gira di nuovo.
        uscitaWebcam.Specchia = false;
        uscitaWebcam.Evento += testo => registro.Aggiungi(testo);
        uscitaWebcam.InUsoCambiato += inUso => coda.TryEnqueue(() =>
        {
            ImpostaInOnda(inUso);
            // Fine dell'uso: la prossima app a 60 fps potrà chiedere di nuovo (P12).
            Valuta60Fps();
            _ = AggiornaWebcamAsync();
        });
        // Windows 10 (P23): il filtro DirectShow e l'anello locale, creato dall'app.
        uscitaWebcam.Tipo = InstallazioneWebcam.Tipo;
        MostraWebcam(StatoWebcam.NonInstallata);
        _ = AggiornaWebcamAsync();
    }

    /// <summary>Vero mentre un'app usa la webcam: in alto il rosso «IN ONDA», e lo sa anche il telefono.</summary>
    private bool inOnda;

    private void ImpostaInOnda(bool attivo)
    {
        if (attivo == inOnda) return;
        inOnda = attivo;
        SegnalaATutti();
        Mostra(statoCollegamento);
        _ = AggiornaAppInUsoAsync();
    }

    /// <summary>
    /// Il telefono nella webcam mostra «IN ONDA» come il PC (Documenti/Protocollo.md, «in-onda»); ogni telefono sa se è
    /// quello nella webcam (<c>selezionato</c>), così la CAM 2 mostra «Usa questa prospettiva». Si manda a tutti a ogni
    /// cambio di «in onda» e della scelta. Un errore di rete qui non conta.
    /// </summary>
    private void SegnalaATutti()
    {
        foreach (var collegato in telefoni.Telefoni)
        {
            if (collegato.Sessione is not { } attiva) continue;
            var messaggio = telefoni.InOndaPer(collegato, inOnda);
            _ = Task.Run(async () =>
            {
                try { await attiva.SegnalaAsync(messaggio); }
                catch (Exception) { }
            });
        }
    }

    private async Task AggiornaWebcamAsync()
    {
        var numero = ++richiesteStatoWebcam;
        var stato = await InstallazioneWebcam.StatoAsync(uscitaWebcam.InUso);
        // La privacy della fotocamera vale per le webcam di Windows (Frame Server), non per un filtro DirectShow.
        privacyNegata = InstallazioneWebcam.Tipo == TipoWebcam.MediaFoundation && InstallazioneWebcam.FotocameraNegataDallaPrivacy();
        if (numero != richiesteStatoWebcam) return;
        MostraWebcam(stato);
    }

    private void MostraWebcam(StatoWebcam stato)
    {
        statoWebcam = stato;
        var installata = stato is StatoWebcam.Installata or StatoWebcam.InUso;
        uscitaWebcam.Abilitata = installata;
        DescrizioneWebcam.Text = CodiciInstallazione.Descrivi(stato, InstallazioneWebcam.Tipo, Testi.LinguaWebcam);
        // Verde salvia quando è pronta, corallo solo mentre un'app la usa (in onda), ambra se va riparata.
        var (testo, colore) = stato switch
        {
            StatoWebcam.NonInstallata => (Testi.T("Webcam_NonInstallata"), "TestoSecondario"),
            StatoWebcam.DaRiparare => (Testi.T("Webcam_DaRiparare"), "Ambra"),
            StatoWebcam.InUso => (Testi.T("Webcam_InOnda"), "Tally"),
            _ => (Testi.T("Webcam_InstallataBreve"), "Verde"),
        };
        StatoWebcamTesto.Text = testo;
        StatoWebcamTesto.Foreground = Pennello(colore);
        IconaWebcam.Foreground = Pennello(colore);
        // La riga delle app sotto il video dice nel suggerimento cosa serve (installare, riparare, sceglierla).
        AggiornaAiutoApp();

        PulsanteInstallaWebcam.Visibility = Visibile(stato is StatoWebcam.NonInstallata or StatoWebcam.DaRiparare);
        PulsanteInstallaWebcam.Content = stato == StatoWebcam.DaRiparare ? Testi.T("Webcam_Ripara") : Testi.T("Webcam_Installa");
        PulsanteInstallaWebcam.IsEnabled = !lavoroWebcam;
        SceltaInquadraturaWebcam.Visibility = Visibile(installata);
        PulsanteRimuoviWebcam.Visibility = Visibile(installata || stato == StatoWebcam.DaRiparare);
        PulsanteRimuoviWebcam.IsEnabled = !lavoroWebcam;

        if (!privacyNegata && barraPrivacy)
        {
            barraPrivacy = false;
            BarraWebcam.IsOpen = false;
        }
        if (privacyNegata && !BarraWebcam.IsOpen)
        {
            barraPrivacy = true;
            BarraWebcam.Severity = InfoBarSeverity.Warning;
            BarraWebcam.Title = Testi.T("Webcam_PrivacyTitolo");
            BarraWebcam.Message = Testi.T("Webcam_Privacy");
            AzioneWebcam.Content = Testi.T("Webcam_ApriImpostazioni");
            AzioneWebcam.Visibility = Visibility.Visible;
            BarraWebcam.IsOpen = true;
        }
    }

    private async void SuInstallaWebcam(object sender, RoutedEventArgs e)
    {
        // async void: un errore qui non deve chiudere l'app.
        try { await EseguiInstallatoreAsync(installa: true); }
        catch (Exception errore) { App.ScriviErrore(errore); }
    }

    private async void SuRimuoviWebcam(object sender, RoutedEventArgs e)
    {
        try
        {
            // Se un'app la sta usando lo si dice prima di tutto (passo 4, windows.md 1.8): «Zoom la sta usando adesso…».
            IReadOnlyList<string> app = [];
            if (inOnda)
            {
                try { app = await Task.Run(LeggiAppInUso); }
                catch (Exception) { }
            }
            var inUso = Conferme.WebcamInUso(inOnda, app);
            // Una sola finestra di dialogo alla volta: con un'altra aperta ShowAsync fallirebbe.
            await PreparaDialogoAsync();
            var conferma = new ContentDialog
            {
                XamlRoot = Content.XamlRoot,
                Title = Testi.T("Webcam_RimuovereTitolo"),
                Content = new TextBlock
                {
                    Text = inUso is null ? Testi.T("Webcam_Rimuovere") : inUso + " " + Testi.T("Webcam_Rimuovere"),
                    TextWrapping = TextWrapping.Wrap,
                },
                PrimaryButtonText = Testi.T("Rimuovi"),
                CloseButtonText = Testi.T("Annulla"),
                DefaultButton = ContentDialogButton.Close,
            };
            if (await conferma.ShowAsync() != ContentDialogResult.Primary) return;
            await EseguiInstallatoreAsync(installa: false);
        }
        catch (Exception errore) { App.ScriviErrore(errore); }
    }

    private async Task EseguiInstallatoreAsync(bool installa)
    {
        if (lavoroWebcam) return;
        lavoroWebcam = true;
        barraPrivacy = false;
        BarraWebcam.IsOpen = false;
        MostraWebcam(statoWebcam);
        registro.Aggiungi(installa ? Testi.T("Webcam_Installazione") : Testi.T("Webcam_Rimozione"));
        int codice;
        try { codice = installa ? await InstallazioneWebcam.InstallaAsync() : await InstallazioneWebcam.RimuoviAsync(); }
        catch (Exception errore) { codice = errore.HResult < 0 ? errore.HResult : CodiciInstallazione.InstallatoreMancante; }
        lavoroWebcam = false;
        registro.Aggiungi(Testi.T("Webcam_Riga", CodiciInstallazione.Descrivi(codice, Testi.LinguaWebcam)));

        if (CodiciInstallazione.ÈRiuscita(codice))
        {
            BarraWebcam.Severity = codice == CodiciInstallazione.Riuscita ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
            BarraWebcam.Title = installa ? Testi.T("Webcam_Installata") : Testi.T("Webcam_Rimossa");
            BarraWebcam.Message = !installa
                ? Testi.T("Webcam_RimossaSpiegazione")
                : codice == CodiciInstallazione.RiuscitaSenza32Bit
                    ? CodiciInstallazione.Descrivi(codice, Testi.LinguaWebcam)
                    : InstallazioneWebcam.Tipo == TipoWebcam.DirectShow
                        ? Testi.T("Webcam_InstallataDirectShow")
                        : Testi.T("Webcam_InstallataMediaFoundation");
        }
        else if (codice != CodiciInstallazione.Annullata)
        {
            BarraWebcam.Severity = InfoBarSeverity.Error;
            BarraWebcam.Title = installa ? Testi.T("Webcam_NonInstallataErrore") : Testi.T("Webcam_NonRimossaErrore");
            BarraWebcam.Message = Testi.T("Webcam_Dettagli", CodiciInstallazione.Descrivi(codice, Testi.LinguaWebcam));
        }
        else
        {
            BarraWebcam.Severity = InfoBarSeverity.Informational;
            BarraWebcam.Title = "";
            BarraWebcam.Message = CodiciInstallazione.Descrivi(codice, Testi.LinguaWebcam);
        }
        AzioneWebcam.Visibility = codice == CodiciInstallazione.AccessoNegato ? Visibility.Visible : Visibility.Collapsed;
        AzioneWebcam.Content = Testi.T("Webcam_ApriImpostazioni");
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

}
