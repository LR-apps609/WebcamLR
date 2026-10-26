using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using WebcamLR.Ricevitore;
using WebcamLR.Webcam;

namespace WebcamLR;

/// <summary>
/// La schermata di attesa della webcam, come sul Mac (Mac/Sorgenti/AttesaWebcam.swift e Impostazioni «Schermata di
/// attesa»): quando il video del telefono non c'è, Zoom e le altre app vedono «La webcam non è collegata»,
/// «Collegamento interrotto» o «Webcam in pausa». La disegna la webcam (WebcamLR.Webcam.Logica, CompositoreWebcam);
/// l'app scrive nella memoria condivisa perché e con che stile (UscitaWebcam.ImpostaAttesa, ogni secondo anche come
/// battito). Gli stili diversi da «WebcamLR» sono di WebcamLR Pro: senza, vale sempre «WebcamLR». La finestra mostra la
/// stessa schermata sopra il video.
/// </summary>
public sealed partial class MainWindow
{
    private bool aggiornoAttesa;
    private BitmapImage? immagineAttesaFinestra;

    /// <summary>La finestra e la webcam nella stessa lingua dell'app (W2): italiano o inglese.</summary>
    private static LinguaAttesa LinguaFinestra => Testi.LinguaWebcam;

    private void InizializzaAttesa()
    {
        aggiornoAttesa = true;
        SceltaAttesa.SelectedItem = SceltaAttesa.Items.OfType<ComboBoxItem>().FirstOrDefault(v => (string)v.Tag == Preferenze.SchermataAttesa)
            ?? SceltaAttesa.Items[0];
        aggiornoAttesa = false;
        _ = CaricaImmagineAttesaAsync();
        MostraImpostazioniAttesa();
    }

    /// <summary>Lo stile scelto, se il telefono nella webcam ha WebcamLR Pro; altrimenti la schermata di WebcamLR.</summary>
    private StileAttesa StileAttesaAttuale => !ProAttivo ? StileAttesa.WebcamLR : Preferenze.SchermataAttesa switch
    {
        "nero" => StileAttesa.Nero,
        "immagine" when immagineAttesaFinestra is not null => StileAttesa.Immagine,
        "sfocata" => StileAttesa.Sfocata,
        _ => StileAttesa.WebcamLR,
    };

    /// <summary>Perché la webcam non ha video: nessun telefono, collegamento perso, telefono in pausa; Nessuna = video.</summary>
    private StatoAttesa StatoAttesaAttuale =>
        telefono is null ? StatoAttesa.NonCollegata
        : statoCollegamento == FaseCollegamento.Riconnessione ? StatoAttesa.Interrotta
        : InPausa ? StatoAttesa.Pausa
        : StatoAttesa.Nessuna;

    /// <summary>A ogni cambiamento: la webcam lo sa subito (poi UscitaWebcam lo ripete ogni secondo).</summary>
    private void AggiornaAttesa()
    {
        uscitaWebcam.ImpostaAttesa(StatoAttesaAttuale, StileAttesaAttuale);
        MostraImpostazioniAttesa();
    }

    /// <summary>La stessa schermata sopra il video della finestra, con lo stesso stile delle app.</summary>
    private void MostraVeloAttesa(StatoAttesa stato)
    {
        if (stato == StatoAttesa.Nessuna || stato == StatoAttesa.NonCollegata)
        {
            // Senza telefono la finestra mostra il QR e i tre passi, più utili di «non collegata».
            VeloPausa.Visibility = Visibility.Collapsed;
            return;
        }
        var stile = StileAttesaAttuale;
        TitoloVeloAttesa.Text = TestiAttesa.Titolo(stato, LinguaFinestra) ?? "";
        if (stato == StatoAttesa.Interrotta)
        {
            MotivoPausa.Text = TestiAttesa.Sottotitolo(stato, LinguaFinestra) ?? "";
            SuggerimentoPausa.Text = "";
        }
        VeloPausa.Background = stile switch
        {
            StileAttesa.Nero => new SolidColorBrush(Microsoft.UI.Colors.Black),
            // L'ultima immagine resta nel lettore: qui scurita, con il motivo sopra.
            StileAttesa.Sfocata => new SolidColorBrush(Windows.UI.Color.FromArgb(0xC8, 0x0D, 0x1B, 0x18)),
            _ => Pennello("SfumaturaLogo"),
        };
        ImmagineVeloAttesa.Source = stile == StileAttesa.Immagine ? immagineAttesaFinestra : null;
        ImmagineVeloAttesa.Visibility = Visibile(stile == StileAttesa.Immagine && immagineAttesaFinestra is not null);
        // Nero e immagine personale sono senza scritte, come nelle app.
        TestiVeloAttesa.Visibility = Visibile(stile is StileAttesa.WebcamLR or StileAttesa.Sfocata);
        VeloPausa.Visibility = Visibility.Visible;
    }

    // MARK: impostazioni

    private void MostraImpostazioniAttesa()
    {
        if (SceltaAttesa is null) return;
        var bloccato = !ProAttivo;
        SceltaAttesa.IsEnabled = !bloccato;
        // Con un telefono collegato senza Pro il segno «PRO»; senza telefono si vede spento con la stessa nota.
        ZonaAttesa.Bloccata = bloccato;
        PulsanteImmagineAttesa.Visibility = Visibile(!bloccato && Preferenze.SchermataAttesa == "immagine");
        NotaAttesa.Text = bloccato
            ? Testi.T("Attesa_SoloPro", RegolePro.Sblocca)
            : Testi.T("Attesa_Nota");
    }

    private void SuSchermataAttesa(object sender, SelectionChangedEventArgs e)
    {
        if (aggiornoAttesa || SceltaAttesa.SelectedItem is not ComboBoxItem { Tag: string scelta }) return;
        Preferenze.SchermataAttesa = scelta;
        ErroreImmagineAttesa.Visibility = Visibility.Collapsed;
        if (scelta == "immagine" && immagineAttesaFinestra is null) _ = ScegliImmagineAttesaAsync();
        AggiornaAttesa();
        MostraPausa();
    }

    private void SuScegliImmagineAttesa(object sender, RoutedEventArgs e) => _ = ScegliImmagineAttesaAsync();

    /// <summary>«Immagine personale…»: un'immagine dal disco, copiata nelle preferenze e mandata alla webcam (al massimo 1920×1080).</summary>
    private async Task ScegliImmagineAttesaAsync()
    {
        try
        {
            var scelta = new FileOpenPicker { ViewMode = PickerViewMode.Thumbnail, SuggestedStartLocation = PickerLocationId.PicturesLibrary };
            foreach (var tipo in new[] { ".png", ".jpg", ".jpeg", ".bmp", ".heic", ".webp" }) scelta.FileTypeFilter.Add(tipo);
            // App non pacchettizzata: il selettore va legato alla finestra.
            WinRT.Interop.InitializeWithWindow.Initialize(scelta, WinRT.Interop.WindowNative.GetWindowHandle(this));
            if (await scelta.PickSingleFileAsync() is not { } file) return;
            var dati = await Task.Run(() => File.ReadAllBytes(file.Path));
            if (dati.Length > 40_000_000) throw new InvalidDataException(Testi.T("Attesa_ImmagineGrande"));
            await Task.Run(() =>
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Preferenze.FileImmagineAttesa)!);
                File.WriteAllBytes(Preferenze.FileImmagineAttesa, dati);
            });
            await CaricaImmagineAttesaAsync();
            if (immagineAttesaFinestra is null) throw new InvalidDataException(Testi.T("Attesa_ImmagineIlleggibile"));
            ErroreImmagineAttesa.Visibility = Visibility.Collapsed;
            registro.Aggiungi(Testi.T("Attesa_ImmagineScelta"));
        }
        catch (Exception)
        {
            ErroreImmagineAttesa.Text = Testi.T("Attesa_ImmagineNonUsabile");
            ErroreImmagineAttesa.Visibility = Visibility.Visible;
        }
        AggiornaAttesa();
        MostraPausa();
    }

    /// <summary>
    /// L'immagine salvata: decodificata fuori dal thread dell'interfaccia, in BGRA, rimpicciolita a 1920×1080 al massimo, e
    /// passata alla webcam; la finestra la mostra con un BitmapImage.
    /// </summary>
    private async Task CaricaImmagineAttesaAsync()
    {
        try
        {
            if (!File.Exists(Preferenze.FileImmagineAttesa))
            {
                immagineAttesaFinestra = null;
                uscitaWebcam.ImpostaImmaginePersonale(null, 0, 0, 0);
                return;
            }
            var file = await StorageFile.GetFileFromPathAsync(Preferenze.FileImmagineAttesa);
            using var flusso = await file.OpenReadAsync();
            var decodificatore = await BitmapDecoder.CreateAsync(flusso);
            var scala = Math.Min(1.0, Math.Min((double)AnelloFotogrammi.LarghezzaMassimaImmagine / decodificatore.OrientedPixelWidth,
                (double)AnelloFotogrammi.AltezzaMassimaImmagine / decodificatore.OrientedPixelHeight));
            var larghezza = Math.Max(1, (uint)Math.Round(decodificatore.OrientedPixelWidth * scala));
            var altezza = Math.Max(1, (uint)Math.Round(decodificatore.OrientedPixelHeight * scala));
            var trasformazione = new BitmapTransform { ScaledWidth = larghezza, ScaledHeight = altezza, InterpolationMode = BitmapInterpolationMode.Fant };
            var pixel = await decodificatore.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, trasformazione,
                ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
            var bgra = pixel.DetachPixelData();
            // La conversione in NV12 per la webcam fuori dal thread dell'interfaccia.
            await Task.Run(() => uscitaWebcam.ImpostaImmaginePersonale(bgra, (int)larghezza, (int)altezza, (int)larghezza * 4));
            flusso.Seek(0);
            var immagine = new BitmapImage();
            await immagine.SetSourceAsync(flusso);
            immagineAttesaFinestra = immagine;
        }
        catch (Exception)
        {
            immagineAttesaFinestra = null;
            uscitaWebcam.ImpostaImmaginePersonale(null, 0, 0, 0);
        }
    }
}
