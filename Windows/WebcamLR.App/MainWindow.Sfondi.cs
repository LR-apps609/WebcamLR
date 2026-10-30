using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il pulsante «Sfondo» sotto il video, come sul Mac (Mac/Sorgenti/Sfondi.swift): un clic riaccende l'ultima scelta (la
/// sfocatura con l'ultimo livello, o l'ultimo sfondo) o spegne; il menu verso l'alto ha Nessuno · Sfocatura (Poco, Medio,
/// Tanto) · Sfondi ▸, che apre di lato le miniature degli sfondi pronti, «La tua immagine» e «Carica un'immagine…».
/// Poi «Carica logo…» e «Togli logo» accanto alla scritta. Il telefono fa il lavoro: il PC riduce l'immagine, ne tiene una
/// copia (MemoriaImmagini) e la manda con il pacchetto tipo 4, solo a un telefono con <c>capacita.immagini</c>.
/// Sfondi, immagine e logo sono di WebcamLR Pro; la sfocatura resta gratis. La logica è in Ricevitore/Sfondi.cs.
/// </summary>
public sealed partial class MainWindow
{
    private readonly MemoriaImmagini memoriaImmagini = new(Preferenze.CartellaImmagini);
    /// <summary>La miniatura di «La tua immagine», dalla copia salvata; null se non ce n'è una.</summary>
    private BitmapImage? miniaturaPersonale;
    /// <summary>«Sfondi ▸»: le miniature, a destra del pulsante come un sottomenu.</summary>
    private Flyout? flyoutSfondi;

    /// <summary>Gli sfondi pronti del telefono nella webcam che il PC sa mostrare.</summary>
    /// <remarks>Con gli effetti sul computer: tutti, dalle immagini grandi del PC (Assets\Sfondi\grandi).</remarks>
    private IReadOnlyList<string> ProntiDelTelefono => RegoleSfondo.Pronti(capacitaEffetti);

    private bool SfondoDisponibile => sessione is not null && capacitaEffetti?.Sfondo == true;

    /// <summary>
    /// Il telefono nella webcam accetta le immagini dal PC: mai mandarle a un telefono che non lo dice. Con gli effetti sul
    /// computer le immagini restano sul PC: si caricano sempre.
    /// </summary>
    private bool ImmaginiDisponibili => sessione is not null && RegoleSfondo.Immagini(capacitaEffetti);

    private bool PersonaleDisponibile => RegoleSfondo.PersonaleDisponibile(memoriaImmagini.Impronta(UsoImmagine.Sfondo),
        RegoleSfondo.Immagini(capacitaEffetti), effetti.Valori.ImmaginePersonale);

    private void InizializzaSfondi()
    {
        // Dalla freccina e con il clic destro: due menu uguali, uno per chi lo apre.
        PulsanteMenuSfondo.Flyout = MenuSfondo();
        PulsanteSfondoVideo.ContextFlyout = MenuSfondo();
        flyoutSfondi = new Flyout { Placement = FlyoutPlacementMode.RightEdgeAlignedBottom };
        flyoutSfondi.Opening += (_, _) =>
        {
            if (flyoutSfondi is not null) flyoutSfondi.Content = ContenutoSfondi();
        };
        _ = CaricaMiniaturaPersonaleAsync();
    }

    /// <summary>Nessuno · Sfocatura (Poco, Medio, Tanto) · Sfondi ▸, con la spunta su quello che il telefono conferma.</summary>
    private MenuFlyout MenuSfondo()
    {
        var menu = new MenuFlyout { Placement = FlyoutPlacementMode.Top };
        var nessuno = new ToggleMenuFlyoutItem { Text = Testi.T("Sfondo_Nessuno") };
        nessuno.Click += (_, _) => ScegliNessunSfondo();
        menu.Items.Add(nessuno);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(new MenuFlyoutItem { Text = Testi.T("Sfondo_Sfocatura"), IsEnabled = false });
        // La sfocatura del telefono (Effetti video di Apple): accesa e spiegata, i nostri livelli grigi.
        var delTelefono = new ToggleMenuFlyoutItem { Text = Testi.T("Sfondo_SfocaturaTelefono"), IsEnabled = false };
        var nota = new MenuFlyoutItem { Text = Testi.T("Effetti_SiRegolaSulTelefono"), IsEnabled = false };
        menu.Items.Add(delTelefono);
        menu.Items.Add(nota);
        var livelli = new List<(ToggleMenuFlyoutItem Voce, LivelloSfocatura Livello)>();
        foreach (var livello in LivelliSfocatura.Tutti)
        {
            var voce = new ToggleMenuFlyoutItem { Text = LivelliSfocatura.Nome(livello) };
            voce.Click += (_, _) => ScegliLivelloSfocatura(livello);
            menu.Items.Add(voce);
            livelli.Add((voce, livello));
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        var sfondi = new MenuFlyoutItem { Icon = new FontIcon { Glyph = "" }, KeyboardAcceleratorTextOverride = "›" };
        // Il menu si chiude con il clic: le miniature si aprono subito dopo, accanto al pulsante.
        sfondi.Click += (_, _) => coda.TryEnqueue(() => flyoutSfondi?.ShowAt(PulsanteSfondoVideo));
        menu.Items.Add(sfondi);
        menu.Opening += (_, _) =>
        {
            var valori = effetti.Valori;
            var (nessunoAcceso, sistema, sistemaAccesa, attuale) = StatoSfondo();
            nessuno.IsChecked = nessunoAcceso;
            delTelefono.Visibility = Visibile(sistema);
            delTelefono.IsChecked = sistemaAccesa;
            nota.Visibility = Visibile(sistema);
            foreach (var (voce, livello) in livelli)
            {
                voce.IsChecked = valori.SfondoSfocato && livello == attuale;
                voce.IsEnabled = !sistema;
                ToolTipService.SetToolTip(voce, sistema ? Testi.T("Effetti_SiRegolaSulTelefono") : null);
            }
            sfondi.Text = BloccoPro ? Testi.T("Sfondo_SfondiPro") : Testi.T("Sfondo_Sfondi");
        };
        return menu;
    }

    /// <summary>
    /// Ciò che il menu e la pagina «Sfondo» delle impostazioni segnano: nessuno sfondo, la sfocatura del telefono (Effetti
    /// video di Apple) c'è ed è accesa, il livello della nostra sfocatura.
    /// </summary>
    private (bool Nessuno, bool Sistema, bool SistemaAccesa, LivelloSfocatura Attuale) StatoSfondo()
    {
        var valori = effetti.Valori;
        var sistemaAccesa = EffettiDelSistema.SfocaturaDelTelefono(valori, statoTelefono);
        return (!valori.SfondoAcceso && !sistemaAccesa, EffettiDelSistema.Sfocatura(statoTelefono), sistemaAccesa,
            effetti.LivelloAttuale(Preferenze.LivelloSfocatura));
    }

    /// <summary>Le miniature (due colonne), «La tua immagine» e «Carica un'immagine…»; con un telefono gratis il segno «PRO».</summary>
    private UIElement ContenutoSfondi()
    {
        var bloccato = BloccoPro;
        var pila = new StackPanel { Spacing = 10, Width = 280 };
        if (bloccato) pila.Children.Add(new RigaPro());

        var pronti = ProntiDelTelefono;
        var voci = pronti.Select(id => (Id: id, Immagine: (ImageSource?)new BitmapImage(new Uri($"ms-appx:///Assets/Sfondi/{id}.jpg"))))
            .ToList();
        if (PersonaleDisponibile) voci.Add((SfondiPronti.Personale, miniaturaPersonale));
        var attuale = RegoleSfondo.ImmagineAttuale(effetti.Valori, pronti);
        var griglia = new Grid { ColumnSpacing = 8, RowSpacing = 10 };
        griglia.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(132) });
        griglia.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(132) });
        for (var i = 0; i < voci.Count; i++)
        {
            if (i % 2 == 0) griglia.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var miniatura = Miniatura(voci[i].Id, voci[i].Immagine, voci[i].Id == attuale, bloccato);
            Grid.SetRow(miniatura, i / 2);
            Grid.SetColumn(miniatura, i % 2);
            griglia.Children.Add(miniatura);
        }
        if (voci.Count > 0) pila.Children.Add(griglia);
        pila.Children.Add(new Rectangle { Height = 1, Fill = Pennello("LineaTenue") });

        if (ImmaginiDisponibili)
        {
            var riga = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            riga.Children.Add(new FontIcon { Glyph = "", FontSize = 14 });
            riga.Children.Add(new TextBlock { Text = Testi.T("Sfondo_CaricaImmagine"), VerticalAlignment = VerticalAlignment.Center });
            if (bloccato) riga.Children.Add(new SegnoPro());
            var carica = new Button { Content = riga, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left };
            ToolTipService.SetToolTip(carica, SulComputer ? Testi.T("Sfondo_CaricaImmagineAiutoComputer") : Testi.T("Sfondo_CaricaImmagineAiuto"));
            AutomationProperties.SetName(carica, Testi.T("Sfondo_CaricaImmagine"));
            carica.Click += (_, _) =>
            {
                flyoutSfondi?.Hide();
                if (BloccoPro) _ = ApriAppAsync(PaginaApp.Pro);
                else _ = CaricaSfondoAsync();
            };
            pila.Children.Add(carica);
        }
        else
        {
            // Un telefono di prima del 27 ottobre: l'immagine dal PC non la può ricevere.
            pila.Children.Add(new TextBlock { Text = Testi.T("Sfondo_CaricaImmagine"), Opacity = 0.5, Foreground = Pennello("TestoSecondario") });
            pila.Children.Add(new TextBlock
            {
                Text = Testi.T("Sfondo_AggiornaTelefono"),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
                Foreground = Pennello("TestoSecondario"),
            });
        }
        return pila;
    }

    /// <summary>Una miniatura 16:9 con il nome sotto: la scelta attuale ha il bordo e la spunta nell'accento.</summary>
    private Button Miniatura(string id, ImageSource? immagine, bool scelta, bool bloccato)
    {
        var nome = RegoleSfondo.Nome(id);
        var quadro = new Grid { Width = 132, Height = 74 };
        quadro.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(scelta ? 2 : 1),
            BorderBrush = Pennello(scelta ? "Accento" : "LineaTenue"),
            Background = immagine is null ? Pennello("PannelloChiaro") : new ImageBrush { ImageSource = immagine, Stretch = Stretch.UniformToFill },
        });
        if (bloccato)
        {
            quadro.Children.Add(new SegnoPro { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(5) });
        }
        else if (scelta)
        {
            quadro.Children.Add(new FontIcon
            {
                Glyph = "",
                FontSize = 14,
                Foreground = Pennello("Accento"),
                HorizontalAlignment = HorizontalAlignment.Right,
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(6),
            });
        }
        var pila = new StackPanel { Spacing = 4 };
        pila.Children.Add(quadro);
        pila.Children.Add(new TextBlock
        {
            Text = nome,
            FontSize = 12,
            MaxWidth = 132,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = Pennello(scelta ? "AccentoChiaro" : "TestoTenue"),
        });
        var pulsante = new Button { Content = pila, Padding = new Thickness(0), BorderThickness = new Thickness(0) };
        pulsante.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        AutomationProperties.SetName(pulsante, nome);
        if (scelta) AutomationProperties.SetItemStatus(pulsante, Testi.T("Sfondo_Scelto"));
        ToolTipService.SetToolTip(pulsante, bloccato ? RegolePro.Sblocca : nome);
        pulsante.Click += (_, _) =>
        {
            flyoutSfondi?.Hide();
            // Senza Pro: la spiegazione di WebcamLR Pro, come le altre funzioni Pro.
            if (BloccoPro) _ = ApriAppAsync(PaginaApp.Pro);
            else ScegliImmagineSfondo(id);
        };
        return pulsante;
    }

    // MARK: scelte

    /// <summary>Il clic su «Sfondo»: spegne lo sfondo acceso, o riaccende l'ultima scelta.</summary>
    private void SuSfondoVideo(object sender, RoutedEventArgs e)
    {
        if (!SfondoDisponibile || SoloFrontaleBloccati)
        {
            MostraPulsantiVideo();
            return;
        }
        if (EffettiDelSistema.Sfocatura(statoTelefono) && !effetti.Valori.SfondoAcceso)
        {
            // La sfocatura del telefono si spegne solo sul telefono, e la nostra non si accende sopra (mai due sfocature):
            // il clic apre il menu, con la nota e gli sfondi.
            MostraPulsantiVideo();
            PulsanteMenuSfondo.Flyout?.ShowAt(PulsanteSfondoVideo);
            return;
        }
        var scelta = RegoleSfondo.Clic(effetti.Valori, Preferenze.UltimoSfondo, !BloccoPro, ProntiDelTelefono, PersonaleDisponibile);
        if (scelta == ModiSfondo.Nessuno) ScegliNessunSfondo();
        else if (scelta == RegoleSfondo.Sfocatura) ScegliLivelloSfocatura(Preferenze.LivelloSfocatura);
        else ScegliImmagineSfondo(scelta);
        // Il pulsante segue lo sfondo, non il clic (anche quando non parte nulla).
        MostraPulsantiVideo();
    }

    private void ScegliNessunSfondo()
    {
        if (!SfondoDisponibile)
        {
            MostraPulsantiVideo();
            return;
        }
        ritardoEffetti?.Stop();
        Comanda(effetti.TogliSfondo(AdessoMs));
        MostraValoriEffetti();
    }

    /// <summary>
    /// Uno sfondo pronto o «La tua immagine» (sfondo «sostituito», WebcamLR Pro). La tua immagine si rimanda prima del
    /// comando se il telefono ne ha un'altra (impronta diversa in <c>stato.immaginePersonale</c>).
    /// </summary>
    private void ScegliImmagineSfondo(string id)
    {
        if (!SfondoDisponibile || BloccoPro || Scelto is not { Sessione: { } attiva }) return;
        if (SulComputer)
        {
            // Lo sfondo lo mette il motore del PC: niente da mandare al telefono; la tua immagine è la copia del PC.
            if (id == SfondiPronti.Personale && memoriaImmagini.Impronta(UsoImmagine.Sfondo) is null) return;
        }
        else if (id == SfondiPronti.Personale)
        {
            var sulTelefono = effetti.Valori.ImmaginePersonale;
            if (RegoleSfondo.DaRimandare(memoriaImmagini.Impronta(UsoImmagine.Sfondo), RegoleSfondo.Immagini(capacitaAttuali), sulTelefono)
                && memoriaImmagini.Leggi(UsoImmagine.Sfondo) is { } dati)
            {
                // Prima il pacchetto, poi il comando: sulla stessa connessione arrivano in quest'ordine.
                MandaImmagine(attiva, new PacchettoImmagine(UsoImmagine.Sfondo, dati));
                registro.Aggiungi(Testi.T("Sfondo_ImmagineMandata"));
            }
            else if (sulTelefono is null)
            {
                // Né una copia da mandare né un'immagine sul telefono: non c'è niente da mostrare.
                return;
            }
        }
        Preferenze.UltimoSfondo = id;
        ritardoEffetti?.Stop();
        Comanda(effetti.SostituisciSfondo(id, AdessoMs));
        MostraValoriEffetti();
    }

    /// <summary>Dal thread dell'interfaccia, nell'ordine dei clic. Un errore di rete qui non conta.</summary>
    private static async void MandaImmagine(SessioneComputer attiva, PacchettoImmagine immagine)
    {
        try { await attiva.MandaImmagineAsync(immagine); }
        catch (Exception) { }
    }

    // MARK: immagini dal PC

    /// <summary>
    /// «Carica un'immagine…»: ridotta (lato lungo 1920, JPEG), salvata nella cartella dell'app (resta tra i riavvii) e
    /// mandata al telefono nella webcam, che la mette subito come sfondo. Senza <c>capacita.immagini</c> o senza Pro resta
    /// solo salvata.
    /// </summary>
    private async Task CaricaSfondoAsync()
    {
        try
        {
            if (await ScegliImmagineAsync(".jpg", ".jpeg", ".png", ".heic") is not { } file) return;
            var dati = await RiduciAsync(file, RiduzioneImmagine.LatoSfondo, png: false);
            memoriaImmagini.Salva(UsoImmagine.Sfondo, dati);
            if (SulComputer) effettiComputer.ImpostaImmagini(memoriaImmagini.Impronta(UsoImmagine.Sfondo), memoriaImmagini.Impronta(UsoImmagine.Logo));
            await CaricaMiniaturaPersonaleAsync();
            registro.Aggiungi(Testi.T("Sfondo_ImmagineCaricata"));
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Testi.T("Sfondo_ImmagineIlleggibile"), errore: true);
            return;
        }
        if (ImmaginiDisponibili && !BloccoPro) ScegliImmagineSfondo(SfondiPronti.Personale);
    }

    private void SuCaricaLogo(object sender, RoutedEventArgs e) => _ = CaricaLogoAsync();

    /// <summary>«Carica logo…»: PNG con la trasparenza, lato lungo 512; salvato anche sul PC e mandato al telefono.</summary>
    private async Task CaricaLogoAsync()
    {
        byte[] dati;
        try
        {
            if (await ScegliImmagineAsync(".png") is not { } file) return;
            dati = await RiduciAsync(file, RiduzioneImmagine.LatoLogo, png: true);
            memoriaImmagini.Salva(UsoImmagine.Logo, dati);
        }
        catch (Exception)
        {
            MostraAvvisoRiprese(Testi.T("Sfondo_LogoIlleggibile"), errore: true);
            return;
        }
        if (SulComputer)
        {
            // Il logo lo mette il motore del PC.
            effettiComputer.ImpostaImmagini(memoriaImmagini.Impronta(UsoImmagine.Sfondo), memoriaImmagini.Impronta(UsoImmagine.Logo));
            registro.Aggiungi(Testi.T("Sfondo_LogoCaricato"));
            MostraLogo();
            return;
        }
        if (!ImmaginiDisponibili || BloccoPro || Scelto is not { Sessione: { } attiva }) return;
        MandaImmagine(attiva, new PacchettoImmagine(UsoImmagine.Logo, dati));
        registro.Aggiungi(Testi.T("Sfondo_LogoMandato"));
    }

    /// <summary>«Togli logo»: il telefono lo cancella (<c>comando.togliLogo</c>). La copia sul PC resta.</summary>
    private void SuTogliLogo(object sender, RoutedEventArgs e)
    {
        if (!ImmaginiDisponibili) return;
        if (SulComputer)
        {
            // Il logo è del PC: si cancella la sua copia.
            memoriaImmagini.Togli(UsoImmagine.Logo);
            effettiComputer.ImpostaImmagini(memoriaImmagini.Impronta(UsoImmagine.Sfondo), null);
            registro.Aggiungi(Testi.T("Sfondo_LogoToltoComputer"));
            MostraLogo();
            return;
        }
        Comanda(new Comando(TogliLogo: true));
        registro.Aggiungi(Testi.T("Sfondo_LogoTolto"));
    }

    /// <summary>«Carica logo…» e «Togli logo» accanto alla scritta: solo con un telefono che accetta le immagini.</summary>
    private void MostraLogo()
    {
        if (ZonaLogo is null) return;
        ZonaLogo.Visibility = Visibile(!EffettiAttivi || RegoleSfondo.Immagini(capacitaEffetti));
        PulsanteTogliLogo.Visibility = Visibile(EffettiAttivi && effetti.Valori.Logo is not null);
    }

    /// <summary>Il selettore dei file di Windows, legato alla finestra (l'app non è pacchettizzata).</summary>
    private async Task<StorageFile?> ScegliImmagineAsync(params string[] tipi)
    {
        var scelta = new FileOpenPicker { ViewMode = PickerViewMode.Thumbnail, SuggestedStartLocation = PickerLocationId.PicturesLibrary };
        foreach (var tipo in tipi) scelta.FileTypeFilter.Add(tipo);
        WinRT.Interop.InitializeWithWindow.Initialize(scelta, WinRT.Interop.WindowNative.GetWindowHandle(this));
        return await scelta.PickSingleFileAsync();
    }

    /// <summary>
    /// Decodifica (girata secondo l'EXIF), riduce a <paramref name="latoMassimo"/> sul lato lungo e codifica: JPEG di qualità
    /// 0,85 per lo sfondo, PNG con la trasparenza per il logo. Solo i codec di Windows (HEIC se c'è l'estensione HEIF).
    /// </summary>
    private static async Task<byte[]> RiduciAsync(StorageFile file, uint latoMassimo, bool png)
    {
        using var flusso = await file.OpenReadAsync();
        var decodificatore = await BitmapDecoder.CreateAsync(flusso);
        // Prima l'immagine intera già girata, poi la riduzione nel codificatore: le misure sono quelle vere.
        using var bitmap = await decodificatore.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8,
            png ? BitmapAlphaMode.Straight : BitmapAlphaMode.Ignore, new BitmapTransform(),
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
        var (larghezza, altezza) = RiduzioneImmagine.Misure((uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, latoMassimo);
        using var uscita = new InMemoryRandomAccessStream();
        var codificatore = png
            ? await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, uscita)
            : await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, uscita, new[]
            {
                new KeyValuePair<string, BitmapTypedValue>("ImageQuality",
                    new BitmapTypedValue(RiduzioneImmagine.QualitaJpeg, Windows.Foundation.PropertyType.Single)),
            });
        codificatore.SetSoftwareBitmap(bitmap);
        codificatore.BitmapTransform.ScaledWidth = larghezza;
        codificatore.BitmapTransform.ScaledHeight = altezza;
        codificatore.BitmapTransform.InterpolationMode = BitmapInterpolationMode.Fant;
        await codificatore.FlushAsync();
        var dati = new byte[uscita.Size];
        using var lettore = new DataReader(uscita.GetInputStreamAt(0));
        await lettore.LoadAsync((uint)uscita.Size);
        lettore.ReadBytes(dati);
        if (dati.Length == 0 || dati.Length > PacchettoImmagine.DimensioneMassima) throw new InvalidDataException();
        return dati;
    }

    /// <summary>La miniatura di «La tua immagine», dalla copia salvata.</summary>
    private async Task CaricaMiniaturaPersonaleAsync()
    {
        try
        {
            if (memoriaImmagini.Leggi(UsoImmagine.Sfondo) is not { } dati)
            {
                miniaturaPersonale = null;
                return;
            }
            using var flusso = new InMemoryRandomAccessStream();
            using (var scrittore = new DataWriter(flusso))
            {
                scrittore.WriteBytes(dati);
                await scrittore.StoreAsync();
                scrittore.DetachStream();
            }
            flusso.Seek(0);
            var immagine = new BitmapImage { DecodePixelWidth = 264 };
            await immagine.SetSourceAsync(flusso);
            miniaturaPersonale = immagine;
        }
        catch (Exception)
        {
            miniaturaPersonale = null;
        }
    }
}
