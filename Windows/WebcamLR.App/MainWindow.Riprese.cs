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
/// «Registra» salva un MP4 in Video › WebcamLR. La registrazione scrive il video così come arriva dal telefono,
/// già compresso (ScrittoreMp4 in WebcamLR.Ricevitore): niente ricompressione, niente processore, qualità piena.
/// Scorciatoie: Ctrl+T, Ctrl+Maiusc+T, Ctrl+R, Ctrl+C.
/// </summary>
public sealed partial class MainWindow
{
    private readonly Istantanee istantanee = new();
    /// <summary>Il formato del video del telefono, dal messaggio «formato»; null finché non arriva video.</summary>
    private FormatoVideo? formatoVideo;
    /// <summary>La registrazione in corso; la legge anche il thread di rete.</summary>
    private Registrazione? registrazione;
    private DateTime inizioRegistrazione;
    private DispatcherQueueTimer? orologioRegistrazione;
    private int secondiRegistrazione;
    private long? spazioScarso;
    /// <summary>Il timer della foto in corso (3, 2, 1); null se non c'è.</summary>
    private CancellationTokenSource? timerFoto;
    private DispatcherQueueTimer? fineAvvisoRiprese;
    private Storyboard? lampo;
    /// <summary>Nella finestra stretta il pulsante «Registra» mostra solo punto e tempo.</summary>
    private bool registraCompatto;
    private Microsoft.UI.Xaml.Media.FontFamily? caratterePulsante;

    private static readonly TimeSpan AttesaFotogramma = TimeSpan.FromSeconds(1.5);

    // MARK: pulsanti

    private void SuFoto(object sender, RoutedEventArgs e) => _ = ScattaFotoAsync();

    private void SuTimerFoto(object sender, RoutedEventArgs e) => AlternaTimerFoto();

    private void SuCopiaFotogramma(object sender, RoutedEventArgs e) => _ = CopiaFotogrammaAsync();

    private void SuRegistra(object sender, RoutedEventArgs e) => _ = AlternaRegistrazioneAsync();

    // MARK: foto

    /// <summary>Foto dal PC: salva in Immagini › WebcamLR e la mostra in Esplora file, come il Mac nel Finder.</summary>
    private async Task ScattaFotoAsync()
    {
        try
        {
            var immagine = await istantanee.PrendiAsync(AttesaFotogramma);
            if (immagine is null)
            {
                MostraAvvisoRiprese(Riprese.NessunVideo);
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
                MostraAvvisoRiprese(Riprese.FotoNonSalvata);
                return;
            }
            finally
            {
                immagine.Dispose();
            }
            registro.Aggiungi($"Foto salvata: {Path.GetFileName(file)}");
            MostraInEsplora(file);
            MostraAvvisoRiprese(Riprese.FotoSalvata);
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Riprese.FotoNonSalvata);
        }
    }

    /// <summary>Il fotogramma attuale negli appunti (PNG), da incollare in qualsiasi app.</summary>
    private async Task CopiaFotogrammaAsync()
    {
        try
        {
            using var immagine = await istantanee.PrendiAsync(AttesaFotogramma);
            if (immagine is null)
            {
                MostraAvvisoRiprese(Riprese.NessunVideo);
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
            MostraAvvisoRiprese(Riprese.CopiaNonRiuscita);
        }
    }

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
                AutomationPropertiesNome(ContoAllaRovescia, $"Foto tra {secondi} secondi");
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

    private void MostraTimer()
    {
        var partito = timerFoto is not null;
        IconaTimer.Glyph = partito ? "" : "";
        var nome = partito ? "Annulla il timer" : "Foto tra 3 secondi";
        AutomationPropertiesNome(PulsanteTimer, nome);
        Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(PulsanteTimer, partito ? nome : $"{nome} (Ctrl+Maiusc+T)");
    }

    private static void AutomationPropertiesNome(DependencyObject elemento, string nome) =>
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(elemento, nome);

    /// <summary>Lampo bianco sull'anteprima, come sul Mac: 85% per 40 ms, poi sfuma in 350 ms.</summary>
    private void Lampo()
    {
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

    /// <summary>Una frase breve in fondo al video; sparisce da sola dopo 4 secondi.</summary>
    private void MostraAvvisoRiprese(string testo)
    {
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

    /// <summary>Esplora file con il file selezionato. Se non si apre, pazienza: la frase dice dov'è.</summary>
    private static void MostraInEsplora(string file)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{file}\"") { UseShellExecute = true });
        }
        catch (Exception) { }
    }

    // MARK: registrazione

    private Task AlternaRegistrazioneAsync() => registrazione is null ? Task.FromResult(AvviaRegistrazione()) : FermaRegistrazioneAsync();

    private bool AvviaRegistrazione()
    {
        if (registrazione is not null) return true;
        if (Volatile.Read(ref formatoVideo) is not { } formato)
        {
            MostraAvvisoRiprese(Riprese.NessunVideo);
            return false;
        }
        Registrazione nuova;
        try
        {
            var cartella = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyVideos), Riprese.Cartella);
            Directory.CreateDirectory(cartella);
            var file = Riprese.FileLibero(cartella, "mp4", DateTime.Now);
            nuova = Registrazione.Avvia(file, formato.Codec, formato.Larghezza, formato.Altezza, DateTime.Now);
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Riprese.RegistrazioneNonCreata);
            return false;
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
        registro.Aggiungi($"Registrazione iniziata: {Path.GetFileName(nuova.File)}");
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
        return true;
    }

    private async Task FermaRegistrazioneAsync(string? fraseSalvata = null)
    {
        var fermata = registrazione;
        if (fermata is null) return;
        Volatile.Write(ref registrazione, null);
        MostraRegistrazione();
        var fine = await fermata.FermaAsync();
        MostraFineRegistrazione(fine, fraseSalvata);
    }

    private void MostraFineRegistrazione(FineRegistrazione fine, string? fraseSalvata = null)
    {
        registro.Aggiungi($"Registrazione: {Riprese.Testo(fine.Esito)} ({Riprese.Durata(fine.Durata)} · {Riprese.Byte(fine.Byte)})");
        var frase = fine.Esito == EsitoRegistrazione.Salvata && fraseSalvata is not null ? fraseSalvata : Riprese.Testo(fine.Esito);
        MostraAvvisoRiprese(frase);
        if (!fine.FileSalvato) return;
        MostraInEsplora(fine.File);
        Notifica("Registrazione salvata", $"{Path.GetFileName(fine.File)} è in Video › WebcamLR.");
    }

    /// <summary>
    /// Il pulsante «Registra» o, mentre registra, «Ferma · 00:12 · 8,4 MB» con il punto rosso (il rosso è permesso,
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
            TestoRegistra.Text = "Registra";
            if (caratterePulsante is not null) TestoRegistra.FontFamily = caratterePulsante;
            TestoRegistra.Visibility = Visibile(!registraCompatto);
            AutomationPropertiesNome(PulsanteRegistra, "Registra");
            Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(PulsanteRegistra, "Registra il video del telefono in Video › WebcamLR (Ctrl+R)");
        }
        else
        {
            var durata = DateTime.UtcNow - inizioRegistrazione;
            caratterePulsante ??= TestoRegistra.FontFamily;
            IconaRegistra.Visibility = Visibility.Collapsed;
            PuntoRegistra.Visibility = Visibility.Visible;
            TestoRegistra.Text = Riprese.TestoRegistrazione(durata, attiva.Byte, registraCompatto);
            TestoRegistra.FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["Numeri"];
            TestoRegistra.Visibility = Visibility.Visible;
            AutomationPropertiesNome(PulsanteRegistra, $"Ferma la registrazione, {Riprese.Durata(durata)}, {Riprese.Byte(attiva.Byte)}");
            Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(PulsanteRegistra,
                $"Ferma la registrazione e mostra il file (Ctrl+R) · {Riprese.Durata(durata)} · {Riprese.Byte(attiva.Byte)}");
        }
        if (spazioScarso is long liberi)
        {
            TestoAvvisoSpazio.Text = Riprese.AvvisoSpazio(liberi);
            TestoAvvisoSpazio.Visibility = Visibile(!registraCompatto);
            Microsoft.UI.Xaml.Controls.ToolTipService.SetToolTip(AvvisoSpazio, Riprese.SpiegazioneSpazio(liberi));
            AutomationPropertiesNome(AvvisoSpazio, Riprese.SpiegazioneSpazio(liberi));
            AvvisoSpazio.Visibility = Visibility.Visible;
        }
        else
        {
            AvvisoSpazio.Visibility = Visibility.Collapsed;
        }
        AggiornaDisponibilita();
    }

    /// <summary>Lo spazio libero sul disco della registrazione: sotto i 2 GB l'avviso in ambra.</summary>
    private void ControllaSpazio()
    {
        if (registrazione is not { } attiva) return;
        try
        {
            var radice = Path.GetPathRoot(attiva.File);
            spazioScarso = radice is null ? null : Riprese.SpazioScarso(new DriveInfo(radice).AvailableFreeSpace);
        }
        catch (Exception)
        {
            spazioScarso = null;
        }
    }

    // MARK: collegamento con il resto della finestra

    /// <summary>Dal thread di rete, con il messaggio «formato».</summary>
    private void FormatoPerRiprese(FormatoVideo formato)
    {
        Volatile.Write(ref formatoVideo, formato);
        istantanee.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
    }

    /// <summary>Dal thread di rete, per ogni fotogramma: costa nulla se non si registra.</summary>
    private void FotogrammaPerRiprese(FotogrammaVideo fotogramma)
    {
        istantanee.Accoda(fotogramma);
        Volatile.Read(ref registrazione)?.Accoda(fotogramma);
    }

    /// <summary>Il telefono se n'è andato davvero (Scollega, o non è tornato): timer annullato, registrazione salvata.</summary>
    private void FermaRiprese()
    {
        Volatile.Write(ref formatoVideo, null);
        istantanee.Ferma();
        AnnullaTimerFoto();
        if (registrazione is not null) _ = FermaRegistrazioneAsync(Riprese.TelefonoScollegato);
    }

    /// <summary>All'uscita: la registrazione si chiude bene prima che l'app finisca (al massimo 10 secondi).</summary>
    private void ChiudiRiprese()
    {
        var attiva = Interlocked.Exchange(ref registrazione, null);
        try { attiva?.FermaAsync().Wait(TimeSpan.FromSeconds(10)); } catch (Exception) { }
        istantanee.Dispose();
    }

    private bool RipreseDisponibili => telefono is not null;

    /// <summary>Per AggiornaDisponibilita: grigi senza telefono; «Ferma» resta sempre attivo.</summary>
    private void AggiornaDisponibilitaRiprese()
    {
        Abilita(PannelloRiprese, RipreseDisponibili);
        CoperturaRiprese.Visibility = Visibile(!RipreseDisponibili);
        var registra = RipreseDisponibili || registrazione is not null;
        PulsanteRegistra.IsEnabled = registra;
        CoperturaRegistra.Visibility = Visibile(!registra);
    }

    // MARK: tastiera

    private bool FotoDaTastiera()
    {
        if (!RipreseDisponibili) return false;
        _ = ScattaFotoAsync();
        return true;
    }

    private bool TimerDaTastiera()
    {
        if (!RipreseDisponibili && timerFoto is null) return false;
        AlternaTimerFoto();
        return true;
    }

    private bool RegistraDaTastiera()
    {
        if (!RipreseDisponibili && registrazione is null) return false;
        _ = AlternaRegistrazioneAsync();
        return true;
    }

    /// <summary>Ctrl+C copia il fotogramma, ma non quando c'è del testo selezionato (registro, indirizzo).</summary>
    private bool CopiaDaTastiera()
    {
        if (!RipreseDisponibili || TestoRegistro.SelectedText.Length > 0 || IndirizzoScritto.SelectedText.Length > 0) return false;
        _ = CopiaFotogrammaAsync();
        return true;
    }
}
