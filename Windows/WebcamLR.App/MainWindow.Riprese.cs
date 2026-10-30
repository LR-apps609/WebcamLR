using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Foto e registrazioni su Windows (P18), come sul Mac (Riprese.swift): «Foto» salva l'immagine attuale in PNG in
/// Immagini › WebcamLR con il lampo bianco, «Foto tra 3 secondi» con il 3-2-1, «Copia il fotogramma» negli appunti,
/// «Registra» salva un MP4 in Video › WebcamLR. Con gli effetti sul computer foto e registrazione sono l'immagine elaborata
/// dal motore (MotoreVideo, RegistrazioneElaborata: ricompressa con il codificatore hardware); altrimenti la registrazione
/// scrive il video così come arriva dal telefono, già compresso (ScrittoreMp4 in WebcamLR.Ricevitore).
/// Scorciatoie: Ctrl+T, Ctrl+Maiusc+T, Ctrl+R, Ctrl+C. Foto e registrazione sono di WebcamLR Pro, come sul Mac:
/// con un telefono gratis i pulsanti restano con il segno «PRO» e i tasti mostrano la strada per sbloccarle.
/// 1.0 beta 2, passo 3 (windows.md 1.3–1.6, 2.7): registrazione frammentata che non si perde, disco pieno che tiene il
/// file e lo dice, «Spazio quasi finito» in minuti, domanda prima dei comandi che chiudono la registrazione
/// (<see cref="PrimaDiFermareLaRegistrazione"/>), file salvati annunciati con «Mostra nella cartella» invece di Esplora file.
/// </summary>
public sealed partial class MainWindow
{
    private readonly Istantanee istantanee = new();
    /// <summary>Il formato del video del telefono nella webcam, dal messaggio «formato»; null finché non arriva video.</summary>
    private FormatoVideo? formatoVideo => Scelto?.Formato;
    /// <summary>La registrazione in corso; la legge anche il thread di rete.</summary>
    private IRegistrazione? registrazione;
    /// <summary>Una registrazione sta partendo (con gli effetti sul computer si apre il codificatore): niente doppi avvii.</summary>
    private bool registrazioneInAvvio;
    private DateTime inizioRegistrazione;
    private DispatcherQueueTimer? orologioRegistrazione;
    private int secondiRegistrazione;
    /// <summary>Minuti di registrazione che restano sul disco (sotto i 10) e byte liberi; null se lo spazio basta.</summary>
    private (int Minuti, long Liberi)? spazioScarso;
    /// <summary>Il file della barra «salvato»: «Mostra nella cartella» apre Esplora file su di lui.</summary>
    private string? fileBarraRiprese;
    private DispatcherQueueTimer? fineBarraRiprese;
    /// <summary>Vero mentre la domanda «Stai registrando…» è aperta: un secondo comando non ne apre un'altra.</summary>
    private bool domandaRegistrazioneAperta;
    /// <summary>Il timer della foto in corso (3, 2, 1); null se non c'è.</summary>
    private CancellationTokenSource? timerFoto;
    private DispatcherQueueTimer? fineAvvisoRiprese;
    private Storyboard? lampo;
    /// <summary>Nella finestra stretta il pulsante «Registra» mostra solo punto e tempo.</summary>
    private bool registraCompatto;
    private Microsoft.UI.Xaml.Media.FontFamily? caratterePulsante;

    private static readonly TimeSpan AttesaFotogramma = TimeSpan.FromSeconds(1.5);

    // MARK: pulsanti

    /// <summary>«Foto»; con il timer partito il pulsante è «Annulla il timer», come sul Mac.</summary>
    private void SuFoto(object sender, RoutedEventArgs e)
    {
        if (timerFoto is not null) AnnullaTimerFoto();
        else if (RipreseConsentite) _ = ScattaFotoAsync();
    }

    private void SuTimerFoto(object sender, RoutedEventArgs e)
    {
        if (RipreseConsentite || timerFoto is not null) AlternaTimerFoto();
    }

    private void SuCopiaFotogramma(object sender, RoutedEventArgs e)
    {
        if (RipreseConsentite) _ = CopiaFotogrammaAsync();
    }

    private void SuRegistra(object sender, RoutedEventArgs e)
    {
        if (registrazione is not null || RipreseConsentite) _ = AlternaRegistrazioneAsync();
    }

    // MARK: foto

    /// <summary>Foto dal PC: salva in Immagini › WebcamLR e lo dice con «Mostra nella cartella» (windows.md 2.7).</summary>
    private async Task ScattaFotoAsync()
    {
        try
        {
            var immagine = await PrendiImmagineAsync();
            if (immagine is null)
            {
                MostraAvvisoRiprese(Riprese.NessunVideo, errore: true);
                return;
            }
            // Lampo subito; il PNG si prepara e si scrive fuori dal thread dell'interfaccia.
            Lampo();
            string file;
            try
            {
                var png = await PngAsync(immagine);
                file = await Task.Run(() =>
                {
                    var cartella = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), Riprese.Cartella);
                    Directory.CreateDirectory(cartella);
                    var nuovo = Riprese.FileLibero(cartella, "png", DateTime.Now);
                    using var flusso = new FileStream(nuovo, FileMode.CreateNew, FileAccess.Write);
                    flusso.Write(png);
                    return nuovo;
                });
            }
            catch (Exception)
            {
                MostraAvvisoRiprese(Riprese.FotoNonSalvata, errore: true);
                return;
            }
            finally
            {
                immagine.Dispose();
            }
            registro.Aggiungi(Testi.T("Riprese_FotoSalvataFile", Path.GetFileName(file)));
            MostraFileSalvato(Riprese.FotoSalvata, file);
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Riprese.FotoNonSalvata, errore: true);
        }
    }

    /// <summary>Il fotogramma attuale negli appunti (PNG), da incollare in qualsiasi app.</summary>
    private async Task CopiaFotogrammaAsync()
    {
        try
        {
            using var immagine = await PrendiImmagineAsync();
            if (immagine is null)
            {
                MostraAvvisoRiprese(Riprese.NessunVideo, errore: true);
                return;
            }
            var png = await PngAsync(immagine);
            var flusso = new InMemoryRandomAccessStream();
            using (var scrittore = new DataWriter(flusso))
            {
                scrittore.WriteBytes(png);
                await scrittore.StoreAsync();
                scrittore.DetachStream();
            }
            flusso.Seek(0);
            var contenuto = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
            contenuto.SetBitmap(RandomAccessStreamReference.CreateFromStream(flusso));
            Clipboard.SetContent(contenuto);
            // Resta negli appunti anche dopo la chiusura dell'app.
            try { Clipboard.Flush(); } catch (Exception) { }
            Lampo();
            MostraAvvisoRiprese(Riprese.FotogrammaCopiato);
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Riprese.CopiaNonRiuscita, errore: true);
        }
    }

    /// <summary>
    /// L'immagine attuale: con gli effetti sul computer dal motore (la stessa dell'anteprima e della webcam, elaborata),
    /// altrimenti dal decodificatore delle istantanee.
    /// </summary>
    private Task<SoftwareBitmap?> PrendiImmagineAsync() =>
        SulComputer ? motoreVideo.PrendiAsync(AttesaFotogramma) : istantanee.PrendiAsync(AttesaFotogramma);

    private static async Task<byte[]> PngAsync(SoftwareBitmap immagine)
    {
        using var flusso = new InMemoryRandomAccessStream();
        var codificatore = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, flusso);
        codificatore.SetSoftwareBitmap(immagine);
        await codificatore.FlushAsync();
        var dati = new byte[flusso.Size];
        using var lettore = new DataReader(flusso.GetInputStreamAt(0));
        await lettore.LoadAsync((uint)flusso.Size);
        lettore.ReadBytes(dati);
        return dati;
    }

    /// <summary>Foto con il timer di 3 secondi; se il timer è già partito, lo annulla.</summary>
    private void AlternaTimerFoto()
    {
        if (timerFoto is not null)
        {
            AnnullaTimerFoto();
            return;
        }
        var annulla = new CancellationTokenSource();
        timerFoto = annulla;
        MostraTimer();
        _ = ContoAllaRovesciaAsync(annulla);
    }

    private async Task ContoAllaRovesciaAsync(CancellationTokenSource annulla)
    {
        try
        {
            for (var secondi = Riprese.SecondiTimer; secondi >= 1; secondi--)
            {
                TestoContoAllaRovescia.Text = secondi.ToString();
                AutomationPropertiesNome(ContoAllaRovescia, Testi.T("Riprese_FotoTra", secondi));
                ContoAllaRovescia.Visibility = Visibility.Visible;
                await Task.Delay(1000, annulla.Token);
            }
        }
        catch (TaskCanceledException)
        {
            return;
        }
        if (timerFoto != annulla) return;
        timerFoto = null;
        ContoAllaRovescia.Visibility = Visibility.Collapsed;
        MostraTimer();
        await ScattaFotoAsync();
    }

    private void AnnullaTimerFoto()
    {
        timerFoto?.Cancel();
        timerFoto = null;
        ContoAllaRovescia.Visibility = Visibility.Collapsed;
        MostraTimer();
    }

    /// <summary>Con il timer partito «Foto» diventa «Annulla il timer», anche se intanto il telefono se n'è andato.</summary>
    private void MostraTimer()
    {
        var partito = timerFoto is not null;
        IconaFoto.Glyph = partito ? "" : "";
        TestoPulsanteFoto.Text = partito ? Testi.T("Riprese_AnnullaTimer") : Testi.T("Riprese_Foto");
        VoceTimer.Text = partito ? Testi.T("Riprese_AnnullaTimerTasti") : Testi.T("Riprese_FotoTra3Tasti");
        AutomationPropertiesNome(PulsanteFoto, partito ? Testi.T("Riprese_AnnullaTimer") : Testi.T("Riprese_Foto"));
        Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(PulsanteFoto, partito
            ? Testi.T("Riprese_AnnullaTimerTasti") : Testi.T("Riprese_FotoSpiegazione"));
        AggiornaDisponibilitaRiprese();
    }

    private static void AutomationPropertiesNome(DependencyObject elemento, string nome) =>
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(elemento, nome);

    /// <summary>Lampo bianco sull'anteprima, come sul Mac: 85% per 40 ms, poi sfuma in 350 ms.</summary>
    private void Lampo()
    {
        // «Effetti di animazione» spenti in Windows: niente lampo (windows.md N9).
        if (!AnimazioniAttive) return;
        if (lampo is null)
        {
            var animazione = new DoubleAnimationUsingKeyFrames();
            animazione.KeyFrames.Add(new DiscreteDoubleKeyFrame { KeyTime = TimeSpan.Zero, Value = 0.85 });
            animazione.KeyFrames.Add(new DiscreteDoubleKeyFrame { KeyTime = TimeSpan.FromMilliseconds(40), Value = 0.85 });
            animazione.KeyFrames.Add(new EasingDoubleKeyFrame
            {
                KeyTime = TimeSpan.FromMilliseconds(390),
                Value = 0,
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut },
            });
            Storyboard.SetTarget(animazione, LampoFoto);
            Storyboard.SetTargetProperty(animazione, "Opacity");
            lampo = new Storyboard();
            lampo.Children.Add(animazione);
        }
        lampo.Stop();
        lampo.Begin();
    }

    /// <summary>
    /// Una frase breve in fondo al video; sparisce da sola dopo 4 secondi. Un errore (<paramref name="errore"/>) va invece
    /// nella barra sopra il video, che resta finché non la si chiude (windows.md 2.1). Tutte e due finiscono nel registro
    /// (salvo <paramref name="registra"/> falso, quando la riga c'è già) e le dice l'Assistente vocale.
    /// </summary>
    private void MostraAvvisoRiprese(string testo, bool errore = false, bool registra = true)
    {
        if (errore)
        {
            MostraErrore(testo, registra);
            return;
        }
        if (registra) Avvisa(testo);
        else Annuncia(testo);
        TestoAvvisoRiprese.Text = testo;
        AvvisoRiprese.Visibility = Visibility.Visible;
        if (fineAvvisoRiprese is null)
        {
            fineAvvisoRiprese = coda.CreateTimer();
            fineAvvisoRiprese.Interval = TimeSpan.FromSeconds(4);
            fineAvvisoRiprese.IsRepeating = false;
            fineAvvisoRiprese.Tick += (_, _) => AvvisoRiprese.Visibility = Visibility.Collapsed;
        }
        fineAvvisoRiprese.Stop();
        fineAvvisoRiprese.Start();
    }

    /// <summary>
    /// Foto o registrazione salvata (windows.md 2.7): la barra sopra il video dice dove, con «Mostra nella cartella»,
    /// invece di portare Esplora file davanti alla chiamata. Si chiude da sola dopo 8 secondi; un avviso (registrazione
    /// salvata in parte) resta finché non lo si chiude.
    /// </summary>
    private void MostraFileSalvato(string frase, string file, bool avviso = false)
    {
        fileBarraRiprese = file;
        AvvisoRiprese.Visibility = Visibility.Collapsed;
        BarraRiprese.Severity = avviso ? Microsoft.UI.Xaml.Controls.InfoBarSeverity.Warning : Microsoft.UI.Xaml.Controls.InfoBarSeverity.Informational;
        BarraRiprese.Message = frase;
        AzioneRiprese.Content = Testi.T("Riprese_MostraNellaCartella");
        BarraRiprese.IsOpen = true;
        Annuncia(frase);
        if (fineBarraRiprese is null)
        {
            fineBarraRiprese = coda.CreateTimer();
            fineBarraRiprese.Interval = TimeSpan.FromSeconds(8);
            fineBarraRiprese.IsRepeating = false;
            fineBarraRiprese.Tick += (_, _) => BarraRiprese.IsOpen = false;
        }
        fineBarraRiprese.Stop();
        if (!avviso) fineBarraRiprese.Start();
    }

    /// <summary>«Mostra nella cartella» nella barra: Esplora file con il file selezionato, solo perché lo si è chiesto.</summary>
    private void SuMostraNellaCartella(object sender, RoutedEventArgs e)
    {
        fineBarraRiprese?.Stop();
        BarraRiprese.IsOpen = false;
        if (fileBarraRiprese is { } file) MostraInEsplora(file);
    }

    /// <summary>
    /// Esplora file con il file selezionato. Se non si apre, pazienza: la frase dice dov'è. Mai mentre l'app esce (N1).
    /// </summary>
    private void MostraInEsplora(string file)
    {
        if (uscita) return;
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{file}\"") { UseShellExecute = true });
        }
        catch (Exception) { }
    }

    /// <summary>
    /// L'unico punto di passaggio dei comandi che chiudono la registrazione (windows.md 1.6: obiettivo, qualità, profilo,
    /// «Nella webcam», «Usa prospettiva», clic sulla CAM 2). Se si registra e il comando cambia il video
    /// (<paramref name="cambiaIlVideo"/>), prima la domanda «Stai registrando: la registrazione si chiude e si salva.
    /// Continuare?», con «Annulla» predefinito: Invio ed Esc non chiudono la registrazione per sbaglio. Altrimenti il
    /// comando parte subito. <paramref name="annullato"/> rimette il controllo com'era.
    /// </summary>
    private async void PrimaDiFermareLaRegistrazione(Action comando, Action? annullato = null, bool cambiaIlVideo = true)
    {
        // async void (comandi della finestra): un errore finisce in Errori.txt, non chiude l'app.
        try
        {
            if (!cambiaIlVideo || registrazione is null)
            {
                comando();
                return;
            }
            if (domandaRegistrazioneAperta || uscita)
            {
                annullato?.Invoke();
                return;
            }
            domandaRegistrazioneAperta = true;
            var continua = false;
            try
            {
                await PreparaDialogoAsync();
                if (Content.XamlRoot is { } radice)
                {
                    var finestra = new Microsoft.UI.Xaml.Controls.ContentDialog
                    {
                        XamlRoot = radice,
                        Content = new Microsoft.UI.Xaml.Controls.TextBlock { Text = Riprese.DomandaRegistrando, TextWrapping = TextWrapping.Wrap },
                        PrimaryButtonText = Riprese.Continua,
                        CloseButtonText = Riprese.Annulla,
                        DefaultButton = Microsoft.UI.Xaml.Controls.ContentDialogButton.Close,
                    };
                    continua = await finestra.ShowAsync() == Microsoft.UI.Xaml.Controls.ContentDialogResult.Primary;
                }
            }
            finally
            {
                domandaRegistrazioneAperta = false;
            }
            if (continua && !uscita) comando();
            else annullato?.Invoke();
        }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
        }
    }

    // MARK: registrazione

    private Task AlternaRegistrazioneAsync() => registrazione is null ? AvviaRegistrazioneAsync() : FermaRegistrazioneAsync();

    /// <summary>
    /// Con gli effetti sul computer la registrazione è l'immagine elaborata, ricompressa (RegistrazioneElaborata): la
    /// stessa dell'anteprima e della webcam. Altrimenti il video del telefono copiato com'è.
    /// </summary>
    private async Task AvviaRegistrazioneAsync()
    {
        if (registrazione is not null || registrazioneInAvvio || uscita) return;
        if (formatoVideo is not { } formato)
        {
            MostraAvvisoRiprese(Riprese.NessunVideo, errore: true);
            return;
        }
        IRegistrazione nuova;
        registrazioneInAvvio = true;
        try
        {
            var cartella = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), Riprese.Cartella);
            Directory.CreateDirectory(cartella);
            var file = Riprese.FileLibero(cartella, "mp4", DateTime.Now);
            nuova = SulComputer
                ? await RegistrazioneElaborata.AvviaAsync(file, MotoreVideo.MisuraLavoro(formato.Larghezza, formato.Altezza).Larghezza,
                    MotoreVideo.MisuraLavoro(formato.Larghezza, formato.Altezza).Altezza, formato.Fps)
                : Registrazione.Avvia(file, formato.Codec, formato.Larghezza, formato.Altezza, DateTime.Now);
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Riprese.RegistrazioneNonCreata, errore: true);
            return;
        }
        finally
        {
            registrazioneInAvvio = false;
        }
        // Il telefono può essere andato via mentre il file si apriva, o l'app sta uscendo: si chiude subito.
        if (formatoVideo is null || uscita)
        {
            _ = nuova.FermaAsync();
            return;
        }
        nuova.FinitaDaSola += fine => coda.TryEnqueue(() =>
        {
            if (registrazione != nuova) return;
            Volatile.Write(ref registrazione, null);
            MostraRegistrazione();
            MostraFineRegistrazione(fine);
        });
        Volatile.Write(ref registrazione, nuova);
        inizioRegistrazione = DateTime.UtcNow;
        secondiRegistrazione = 0;
        spazioScarso = null;
        registro.Aggiungi(Testi.T("Riprese_Iniziata", Path.GetFileName(nuova.File)));
        if (nuova is RegistrazioneElaborata elaborata) _ = RegistraContenitoreAsync(elaborata);
        if (orologioRegistrazione is null)
        {
            orologioRegistrazione = coda.CreateTimer();
            orologioRegistrazione.Interval = TimeSpan.FromSeconds(1);
            orologioRegistrazione.Tick += (_, _) =>
            {
                // Lo spazio libero cambia piano: basta guardarlo ogni 5 secondi.
                if (++secondiRegistrazione % 5 == 0) ControllaSpazio();
                MostraRegistrazione();
            };
        }
        orologioRegistrazione.Start();
        ControllaSpazio();
        MostraRegistrazione();
    }

    /// <summary>
    /// Con gli effetti sul computer: nel registro se Windows ha accettato l'MP4 frammentato o se si è tornati a quello
    /// normale (da controllare nelle prove, windows.md 1.3).
    /// </summary>
    private async Task RegistraContenitoreAsync(RegistrazioneElaborata elaborata)
    {
        for (var i = 0; i < 50 && elaborata.Frammentata is null; i++) await Task.Delay(100);
        if (elaborata.Frammentata is bool frammentata)
            registro.Aggiungi(frammentata ? Testi.T("Riprese_ContenitoreFrammentato") : Testi.T("Riprese_ContenitoreNormale"));
    }

    private async Task FermaRegistrazioneAsync(string? fraseSalvata = null)
    {
        var fermata = registrazione;
        if (fermata is null) return;
        Volatile.Write(ref registrazione, null);
        MostraRegistrazione();
        var chiusura = fermata.FermaAsync();
        // Se intanto si esce, ChiudiRipreseAsync aspetta anche questo file.
        chiusuraInCorso = chiusura;
        var fine = await chiusura;
        MostraFineRegistrazione(fine, fraseSalvata);
    }

    /// <summary>
    /// La chiusura dell'ultima registrazione fermata con il pulsante o dall'app (telefono in sottofondo o cambiato):
    /// «Esci» subito dopo «Ferma» non deve uscire con il file MP4 ancora senza indice.
    /// </summary>
    private Task chiusuraInCorso = Task.CompletedTask;

    private void MostraFineRegistrazione(FineRegistrazione fine, string? fraseSalvata = null)
    {
        registro.Aggiungi(Testi.T("Riprese_Fine", Riprese.Testo(fine), Riprese.Durata(fine.Durata), Riprese.Byte(fine.Byte)));
        var frase = fine.Esito == EsitoRegistrazione.Salvata && fraseSalvata is not null ? fraseSalvata : Riprese.Testo(fine);
        // I 60 fps automatici aspettavano la fine della registrazione (windows.md 1.6).
        Valuta60Fps();
        if (!fine.FileSalvato)
        {
            // Registrazione persa o non partita: un errore, che resta finché non lo si chiude (windows.md 2.1). La riga
            // nel registro c'è già, qui sopra.
            MostraAvvisoRiprese(frase, errore: true, registra: false);
            return;
        }
        MostraFileSalvato(frase, fine.File, avviso: fine.SalvataInParte);
        Notifica(Testi.T("Riprese_SalvataTitolo"), fine.SalvataInParte ? frase : Testi.T("Riprese_SalvataIn", Path.GetFileName(fine.File)));
    }

    /// <summary>
    /// Il pulsante «Registra» o, mentre registra, «00:12» con il punto rosso (il rosso è permesso,
    /// come per «in onda»); l'avviso in ambra se lo spazio sul disco sta finendo.
    /// </summary>
    private void MostraRegistrazione()
    {
        var attiva = registrazione;
        if (attiva is null)
        {
            orologioRegistrazione?.Stop();
            spazioScarso = null;
            IconaRegistra.Visibility = Visibility.Visible;
            PuntoRegistra.Visibility = Visibility.Collapsed;
            TestoRegistra.Text = Testi.T("Riprese_Registra");
            if (caratterePulsante is not null) TestoRegistra.FontFamily = caratterePulsante;
            TestoRegistra.Visibility = Visibility.Visible;
            AutomationPropertiesNome(PulsanteRegistra, Testi.T("Riprese_Registra"));
            Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(PulsanteRegistra, Testi.T("Riprese_RegistraSpiegazione"));
        }
        else
        {
            var durata = DateTime.UtcNow - inizioRegistrazione;
            caratterePulsante ??= TestoRegistra.FontFamily;
            IconaRegistra.Visibility = Visibility.Collapsed;
            PuntoRegistra.Visibility = Visibility.Visible;
            // Nel tasto sotto il video c'è posto solo per la durata; i megabyte sono nel suggerimento e per l'Assistente vocale.
            TestoRegistra.Text = Riprese.TestoRegistrazione(durata, attiva.Byte, compatto: true);
            TestoRegistra.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["Numeri"];
            TestoRegistra.Visibility = Visibility.Visible;
            AutomationPropertiesNome(PulsanteRegistra, Testi.T("Riprese_FermaNome", Riprese.Durata(durata), Riprese.Byte(attiva.Byte)));
            Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(PulsanteRegistra,
                Testi.T("Riprese_FermaSpiegazione", Riprese.Durata(durata), Riprese.Byte(attiva.Byte)));
        }
        if (spazioScarso is (int minuti, long liberi))
        {
            TestoAvvisoSpazio.Text = Riprese.AvvisoSpazio(minuti);
            TestoAvvisoSpazio.Visibility = Visibile(!registraCompatto);
            Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(AvvisoSpazio, Riprese.SpiegazioneSpazio(liberi));
            AutomationPropertiesNome(AvvisoSpazio, Riprese.SpiegazioneSpazio(liberi));
            AvvisoSpazio.Visibility = Visibility.Visible;
        }
        else
        {
            AvvisoSpazio.Visibility = Visibility.Collapsed;
        }
        RegistraSpazio(spazioScarso is not null);
        AggiornaDisponibilita();
        AggiornaIcona();
    }

    /// <summary>
    /// Lo spazio libero sul disco della registrazione, in minuti al ritmo attuale (windows.md 1.4): sotto i 10 l'avviso
    /// in ambra «Spazio quasi finito: restano circa N minuti».
    /// </summary>
    private void ControllaSpazio()
    {
        if (registrazione is not { } attiva) return;
        try
        {
            var radice = Path.GetPathRoot(attiva.File);
            var liberi = radice is null ? (long?)null : new DriveInfo(radice).AvailableFreeSpace;
            spazioScarso = liberi is long l && Riprese.SpazioScarso(l, attiva.Byte, DateTime.UtcNow - inizioRegistrazione) is int minuti
                ? (minuti, l) : null;
        }
        catch (Exception)
        {
            spazioScarso = null;
        }
    }

    // MARK: collegamento con il resto della finestra

    /// <summary>Dal thread di rete, con il messaggio «formato» del telefono nella webcam, o quando si passa all'altro (P21).</summary>
    private void FormatoPerRiprese(FormatoVideo formato)
    {
        // Con gli effetti sul computer foto e registrazione prendono l'immagine dal motore (MotoreVideo).
        if (!SulComputer) istantanee.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
    }

    /// <summary>Dal thread di rete, per ogni fotogramma: costa nulla se non si registra.</summary>
    private void FotogrammaPerRiprese(FotogrammaVideo fotogramma)
    {
        if (!SulComputer) istantanee.Accoda(fotogramma);
        (Volatile.Read(ref registrazione) as Registrazione)?.Accoda(fotogramma);
    }

    /// <summary>
    /// Il telefono nella webcam se n'è andato davvero (Scollega, o non è tornato) o l'utente sceglie l'altro (P21):
    /// timer annullato, registrazione salvata (è di un solo video).
    /// </summary>
    private void FermaRiprese(string frase)
    {
        AnnullaTimerFoto();
        if (registrazione is not null) _ = FermaRegistrazioneAsync(frase);
    }

    /// <summary>
    /// All'uscita: la registrazione si chiude bene prima che l'app finisca (N1). Si aspetta con await, senza bloccare
    /// il thread dell'interfaccia, fino a <see cref="TettoChiusuraRegistrazione"/>: con un file lungo l'indice MP4
    /// richiede qualche secondo, e la finestra intanto risponde.
    /// </summary>
    private async Task ChiudiRipreseAsync()
    {
        AnnullaTimerFoto();
        var attiva = Interlocked.Exchange(ref registrazione, null);
        if (attiva is not null)
        {
            MostraRegistrazione();
            try
            {
                var fermata = attiva.FermaAsync();
                if (await Task.WhenAny(fermata, Task.Delay(TettoChiusuraRegistrazione)) == fermata)
                {
                    var fine = await fermata;
                    registro.Aggiungi(Testi.T("Riprese_Fine", Riprese.Testo(fine), Riprese.Durata(fine.Durata), Riprese.Byte(fine.Byte)));
                }
            }
            catch (Exception) { }
        }
        // Una registrazione fermata un attimo prima e non ancora chiusa: si aspetta con lo stesso tetto.
        if (!chiusuraInCorso.IsCompleted)
        {
            try { await Task.WhenAny(chiusuraInCorso, Task.Delay(TettoChiusuraRegistrazione)); }
            catch (Exception) { }
        }
        if (Interlocked.Exchange(ref istantaneeChiuse, 1) == 0) istantanee.Dispose();
    }

    /// <summary>Quanto si aspetta al massimo la chiusura della registrazione all'uscita: un tetto lungo, solo contro un blocco.</summary>
    private static readonly TimeSpan TettoChiusuraRegistrazione = TimeSpan.FromSeconds(60);

    /// <summary>ChiudiRipreseAsync può arrivare due volte (uscita e poi la chiusura della finestra): le istantanee si chiudono una volta.</summary>
    private int istantaneeChiuse;

    private bool RipreseDisponibili => telefono is not null;

    /// <summary>WebcamLR Pro: foto e registrazione solo se il telefono nella webcam l'ha sbloccato, come sul Mac.</summary>
    private bool RipreseConsentite => RipreseDisponibili && ProAttivo;

    /// <summary>
    /// Per AggiornaDisponibilita: grigi senza telefono; «Ferma» e «Annulla il timer» restano sempre attivi. Con un telefono
    /// gratis il segno «PRO» lo mette AggiornaPro, dopo.
    /// </summary>
    private void AggiornaDisponibilitaRiprese()
    {
        if (PannelloRiprese is null) return;
        var foto = RipreseDisponibili || timerFoto is not null;
        Abilita(PannelloRiprese, RipreseDisponibili);
        PulsanteFoto.IsEnabled = foto;
        CoperturaRiprese.Visibility = Visibile(!foto);
        var registra = RipreseDisponibili || registrazione is not null;
        PulsanteRegistra.IsEnabled = registra;
        CoperturaRegistra.Visibility = Visibile(!registra);
        AggiornaCoperture();
    }

    /// <summary>Un tasto di foto o registrazione con un telefono gratis: la nota con la strada per sbloccarle.</summary>
    private bool AvvisaRipresePro()
    {
        NotaPro.Mostra(PulsanteFoto);
        return true;
    }

    // MARK: tastiera

    private bool FotoDaTastiera()
    {
        if (!RipreseDisponibili) return false;
        if (!RipreseConsentite) return AvvisaRipresePro();
        _ = ScattaFotoAsync();
        return true;
    }

    private bool TimerDaTastiera()
    {
        if (!RipreseDisponibili && timerFoto is null) return false;
        if (!RipreseConsentite && timerFoto is null) return AvvisaRipresePro();
        AlternaTimerFoto();
        return true;
    }

    private bool RegistraDaTastiera()
    {
        if (!RipreseDisponibili && registrazione is null) return false;
        if (!RipreseConsentite && registrazione is null) return AvvisaRipresePro();
        _ = AlternaRegistrazioneAsync();
        return true;
    }

    /// <summary>Ctrl+C copia il fotogramma, ma non quando c'è del testo selezionato (registro, indirizzo).</summary>
    private bool CopiaDaTastiera()
    {
        if (!RipreseConsentite || TestoRegistro.SelectedText.Length > 0 || IndirizzoScritto.SelectedText.Length > 0) return false;
        _ = CopiaFotogrammaAsync();
        return true;
    }
}
