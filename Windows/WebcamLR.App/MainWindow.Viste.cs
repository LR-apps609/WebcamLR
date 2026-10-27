using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Le tre viste della finestra (27 ottobre), come sul Mac:
/// <list type="bullet">
/// <item>«Completo»: com'era, con le colonne a sinistra e a destra;</item>
/// <item>«Essenziale» (la vista di partenza di chi installa l'app): il video grande, la barra e «Impostazioni», un pannello
/// che scorre da destra sopra il video con le voci a livelli; in alto a sinistra sul video la pillola del telefono, che apre
/// il QR;</item>
/// <item>«Schermo intero»: solo il video; muovendo il mouse o premendo un tasto compare per qualche secondo «Esci».</item>
/// </list>
/// Le pagine delle impostazioni non rifanno i comandi: prendono in prestito le sezioni delle colonne (gli stessi controlli,
/// con la stessa logica) e le rimettono al loro posto quando si torna indietro o si chiude il pannello. La scelta della
/// vista resta (Preferenze); chi aveva già usato l'app parte da Completo.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Le voci delle impostazioni, nell'ordine del Mac. «Elenco» è la prima pagina, con le voci.</summary>
    private enum PaginaImpostazioni { Elenco, Fotocamera, Effetti, Sfondo, Profili, Qualita, Schermo, Microfono, Telefoni, Uscite, Gobbo, Registro }

    /// <summary>Le voci con il nome nella lingua dell'app e l'icona (si leggono dopo Testi.Imposta).</summary>
    private static (PaginaImpostazioni Pagina, string Nome, string Icona)[] VociImpostazioni() =>
    [
        (PaginaImpostazioni.Fotocamera, Testi.T("Impostazioni_Fotocamera"), ""),
        (PaginaImpostazioni.Effetti, Testi.T("Impostazioni_Effetti"), ""),
        (PaginaImpostazioni.Sfondo, Testi.T("Impostazioni_Sfondo"), ""),
        (PaginaImpostazioni.Profili, Testi.T("Impostazioni_Profili"), ""),
        (PaginaImpostazioni.Qualita, Testi.T("Impostazioni_Qualita"), ""),
        (PaginaImpostazioni.Schermo, Testi.T("Impostazioni_Schermo"), ""),
        (PaginaImpostazioni.Microfono, Testi.T("Impostazioni_Microfono"), ""),
        (PaginaImpostazioni.Telefoni, Testi.T("Impostazioni_Telefoni"), ""),
        (PaginaImpostazioni.Uscite, Testi.T("Impostazioni_Uscite"), ""),
        (PaginaImpostazioni.Gobbo, Testi.T("Impostazioni_Gobbo"), ""),
        (PaginaImpostazioni.Registro, Testi.T("Impostazioni_Registro"), ""),
    ];

    /// <summary>Vero nella vista «Essenziale». Letta prima di tutto il resto: la prima volta decide guardando le preferenze.</summary>
    private bool vistaEssenziale = Preferenze.VistaEssenziale();
    /// <summary>Quanto sono aperte le colonne laterali: 0 in «Essenziale», 1 in «Completo», in mezzo durante il passaggio.</summary>
    private double aperturaColonne;
    private DispatcherQueueTimer? passoColonne;
    private readonly System.Diagnostics.Stopwatch orologioColonne = new();
    private double aperturaDa;
    private double aperturaA;

    /// <summary>Le pagine aperte sopra l'elenco: per ora una sola alla volta, ma «Indietro» toglie sempre l'ultima.</summary>
    private readonly Stack<PaginaImpostazioni> pilaImpostazioni = new();
    private bool impostazioniAperte;
    /// <summary>Cresce a ogni apertura: una chiusura animata vecchia non nasconde il pannello riaperto nel frattempo.</summary>
    private int giroImpostazioni;
    private readonly TranslateTransform spostamentoPagine = new();
    private StackPanel? paginaSfondo;
    private string statoPaginaSfondo = "";

    /// <summary>Un controllo spostato dalla sua colonna: come rimetterlo dov'era.</summary>
    private sealed record Prestito(UIElement Elemento, Action Rimetti);

    /// <summary>Ciò che la pagina aperta ha preso dalle colonne (si rimette in ordine inverso).</summary>
    private readonly List<Prestito> prestitiPagina = [];
    /// <summary>Il QR preso dalla colonna di sinistra per il menu della pillola del telefono.</summary>
    private readonly List<Prestito> prestitiPillola = [];

    /// <summary>«Esci» nello schermo intero e nella vista pulita: compare per qualche secondo al movimento o a un tasto.</summary>
    private DispatcherQueueTimer? tempoEsci;
    private bool esciVisibile;

    private PaginaImpostazioni PaginaAttuale =>
        impostazioniAperte && pilaImpostazioni.Count > 0 ? pilaImpostazioni.Peek() : PaginaImpostazioni.Elenco;

    private bool InSchermoIntero => AppWindow.Presenter.Kind == Microsoft.UI.Windowing.AppWindowPresenterKind.FullScreen;

    /// <summary>Solo il video, senza intestazione, colonne e barra: finestra mini, vista pulita e schermo intero.</summary>
    private bool SoloVideo => InMini || vistaPulita || InSchermoIntero;

    private void InizializzaViste()
    {
        aperturaColonne = vistaEssenziale ? 0 : 1;
        ContenitorePagine.RenderTransform = spostamentoPagine;
        AutomationProperties.SetHeadingLevel(TitoloPaginaImpostazioni, AutomationHeadingLevel.Level1);
        foreach (var (pagina, nome, icona) in VociImpostazioni()) ElencoImpostazioni.Children.Add(VoceElenco(pagina, nome, icona));

        passoColonne = coda.CreateTimer();
        passoColonne.Interval = TimeSpan.FromMilliseconds(15);
        passoColonne.Tick += (_, _) => PassoColonne();

        tempoEsci = coda.CreateTimer();
        tempoEsci.Interval = TimeSpan.FromSeconds(3);
        tempoEsci.IsRepeating = false;
        tempoEsci.Tick += (_, _) =>
        {
            // Con il puntatore sopra o il fuoco sul pulsante resta.
            if (PulsanteTornaFinestra.IsPointerOver || PulsanteTornaFinestra.FocusState != FocusState.Unfocused)
            {
                tempoEsci.Start();
                return;
            }
            esciVisibile = false;
            MostraPulsanteTorna();
        };
        RiquadroVideo.PointerMoved += (_, _) => MostraEsciPerUnPo();
        Radice.AddHandler(UIElement.KeyDownEvent, new KeyEventHandler((_, _) => MostraEsciPerUnPo()), true);
        MostraVista();
    }

    // MARK: viste

    /// <summary>Essenziale o Completo (dal menu «Schermo», Ctrl+1, Ctrl+2). Dallo schermo intero si torna prima alla finestra.</summary>
    private void ImpostaVista(bool essenziale)
    {
        if (InSchermoIntero) AppWindow.SetPresenter(Microsoft.UI.Windowing.AppWindowPresenterKind.Overlapped);
        if (vistaPulita) ImpostaVistaPulita(false);
        if (InMini) ImpostaMini(false);
        if (vistaEssenziale != essenziale)
        {
            vistaEssenziale = essenziale;
            Preferenze.ScriviVista(essenziale);
            ChiudiImpostazioni(subito: true);
            AnimaColonne(essenziale ? 0 : 1);
        }
        MostraVista();
    }

    /// <summary>Ciò che cambia con la vista, a parte le colonne (AdattaLayout).</summary>
    private void MostraVista()
    {
        // La riga delle app in fondo resta in tutte e due le viste: è una riga sola.
        RigaSotto.Visibility = Visibile(!SoloVideo);
        PillolaTelefono.Visibility = Visibile(!SoloVideo && vistaEssenziale);
        if (PillolaTelefono.Visibility == Visibility.Collapsed) FinestraPillolaTelefono.Hide();
        AggiornaPillolaTelefono();
        AggiornaPulsantiVista();
        AdattaLayout();
    }

    /// <summary>Nel menu «Schermo» la vista di adesso è accesa.</summary>
    private void AggiornaPulsantiVista()
    {
        PulsanteSchermoIntero.IsChecked = InSchermoIntero;
        PulsanteVistaEssenziale.IsChecked = !InSchermoIntero && vistaEssenziale;
        PulsanteVistaCompleto.IsChecked = !InSchermoIntero && !vistaEssenziale;
    }

    private void SuAperturaMenuSchermo(object? sender, object e) => AggiornaPulsantiVista();

    private void SuVistaEssenziale(object sender, RoutedEventArgs e)
    {
        MenuSchermo.Hide();
        ImpostaVista(true);
    }

    private void SuVistaCompleto(object sender, RoutedEventArgs e)
    {
        MenuSchermo.Hide();
        ImpostaVista(false);
    }

    /// <summary>Le colonne si aprono e si chiudono in un quarto di secondo: il video si allarga o si stringe senza fermarsi.</summary>
    private void AnimaColonne(double verso)
    {
        aperturaDa = aperturaColonne;
        aperturaA = verso;
        orologioColonne.Restart();
        passoColonne?.Start();
    }

    private void PassoColonne()
    {
        var t = Math.Min(1, orologioColonne.Elapsed.TotalMilliseconds / 260);
        var curva = 1 - Math.Pow(1 - t, 3);
        aperturaColonne = aperturaDa + (aperturaA - aperturaDa) * curva;
        if (t >= 1)
        {
            aperturaColonne = aperturaA;
            passoColonne?.Stop();
        }
        AdattaLayout();
    }

    // MARK: pillola del telefono (vista «Essenziale»)

    /// <summary>Il nome del telefono nella webcam, o «Collega il tuo smartphone»; il punto verde, ambra mentre si ricollega.</summary>
    private void AggiornaPillolaTelefono()
    {
        if (PillolaTelefono is null) return;
        var scelto = telefono is null ? null : Scelto;
        TestoPillolaTelefono.Text = scelto?.Nome ?? Testi.T("QR_CollegaIlTuo");
        PuntoPillolaTelefono.Visibility = Visibile(scelto is not null);
        PuntoPillolaTelefono.Fill = Pennello(scelto?.InRiconnessione == true ? "Ambra" : "Verde");
        var nome = scelto is null ? Testi.T("Pillola_Collega") : Testi.T("Pillola_Collegato", scelto.Nome);
        AutomationProperties.SetName(PillolaTelefono, nome);
        ToolTipService.SetToolTip(PillolaTelefono, nome);
    }

    /// <summary>Il menu della pillola mostra il QR di sempre, preso in prestito dalla colonna di sinistra.</summary>
    private void SuAperturaPillolaTelefono(object? sender, object e)
    {
        RestituisciPillola();
        if (BloccoQR.Parent != PannelloSinistro) return;
        var prestito = Togli(BloccoQR);
        PostoQR.Children.Add(BloccoQR);
        prestitiPillola.Add(new Prestito(BloccoQR, () =>
        {
            PostoQR.Children.Remove(BloccoQR);
            prestito.Rimetti();
        }));
    }

    private void SuChiusuraPillolaTelefono(object? sender, object e) => RestituisciPillola();

    private void RestituisciPillola()
    {
        for (var i = prestitiPillola.Count - 1; i >= 0; i--) prestitiPillola[i].Rimetti();
        prestitiPillola.Clear();
    }

    private void SuGestisciTelefoni(object sender, RoutedEventArgs e)
    {
        // Il QR torna subito al suo posto: la pagina «Telefoni» lo vuole.
        RestituisciPillola();
        FinestraPillolaTelefono.Hide();
        ApriImpostazioni(PaginaImpostazioni.Telefoni);
    }

    // MARK: pannello «Impostazioni»

    private void SuImpostazioni(object sender, RoutedEventArgs e)
    {
        if (impostazioniAperte) ChiudiImpostazioni();
        else ApriImpostazioni();
    }

    private void SuChiudiImpostazioni(object sender, RoutedEventArgs e) => ChiudiImpostazioni();

    /// <summary>Come sul Mac: in salvia (accento tenue, bordo e testo nell'accento) mentre il pannello è aperto.</summary>
    private void MostraPulsanteImpostazioni()
    {
        PulsanteImpostazioni.Background = impostazioniAperte ? Pennello("AccentoTenue") : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        PulsanteImpostazioni.BorderBrush = Pennello(impostazioniAperte ? "Accento" : "Linea");
        PulsanteImpostazioni.Foreground = Pennello(impostazioniAperte ? "AccentoChiaro" : "TestoChiaro");
        AutomationProperties.SetItemStatus(PulsanteImpostazioni, impostazioniAperte ? Testi.T("Impostazioni_Aperte") : "");
    }

    private void SuVeloImpostazioni(object sender, TappedRoutedEventArgs e)
    {
        ChiudiImpostazioni();
        e.Handled = true;
    }

    private void SuIndietroImpostazioni(object sender, RoutedEventArgs e) => Indietro();

    /// <summary>Il pannello scorre da destra; con <paramref name="pagina"/> si apre già su quella voce.</summary>
    private void ApriImpostazioni(PaginaImpostazioni? pagina = null)
    {
        if (SoloVideo) return;
        giroImpostazioni++;
        var eraAperto = impostazioniAperte;
        impostazioniAperte = true;
        MostraPulsanteImpostazioni();
        StratoImpostazioni.Visibility = Visibility.Visible;
        if (!eraAperto)
        {
            pilaImpostazioni.Clear();
            Anima(SpostamentoImpostazioni, "X", PannelloImpostazioni.Width, 0, 240);
            Anima(VeloImpostazioni, "Opacity", 0, 1, 240);
        }
        if (pagina is { } p && p != PaginaImpostazioni.Elenco)
        {
            pilaImpostazioni.Clear();
            pilaImpostazioni.Push(p);
        }
        MostraPagina(avanti: true);
        AnnunciaPagina();
    }

    /// <summary>Con la X, con Esc, con un clic sul video; <paramref name="subito"/> senza animazione (cambio di vista).</summary>
    private void ChiudiImpostazioni(bool subito = false)
    {
        if (!impostazioniAperte) return;
        impostazioniAperte = false;
        MostraPulsanteImpostazioni();
        var giro = ++giroImpostazioni;
        void Fine()
        {
            if (giro != giroImpostazioni) return;
            StratoImpostazioni.Visibility = Visibility.Collapsed;
            // Le sezioni tornano nelle colonne quando il pannello non si vede più.
            pilaImpostazioni.Clear();
            RestituisciPagina();
        }
        if (subito)
        {
            Fine();
        }
        else
        {
            Anima(SpostamentoImpostazioni, "X", 0, PannelloImpostazioni.Width, 200, Fine);
            Anima(VeloImpostazioni, "Opacity", 1, 0, 200);
        }
        if (PulsanteImpostazioni.IsLoaded) PulsanteImpostazioni.Focus(FocusState.Programmatic);
    }

    private void Vai(PaginaImpostazioni pagina)
    {
        pilaImpostazioni.Push(pagina);
        MostraPagina(avanti: true);
        AnnunciaPagina();
    }

    private void Indietro()
    {
        if (pilaImpostazioni.Count == 0) return;
        var lasciata = pilaImpostazioni.Pop();
        MostraPagina(avanti: false);
        AnnunciaPagina();
        // Tornando all'elenco il fuoco va sulla voce da cui si era entrati.
        if (PaginaAttuale == PaginaImpostazioni.Elenco
            && ElencoImpostazioni.Children.OfType<Button>().FirstOrDefault(v => Equals(v.Tag, lasciata)) is { } voce)
        {
            voce.Focus(FocusState.Programmatic);
        }
    }

    /// <summary>Dal menu della qualità, della strada o del registro mentre una pagina li tiene: la pagina li ridà.</summary>
    private void RidaiAlMenu()
    {
        if (prestitiPagina.Count == 0) return;
        pilaImpostazioni.Clear();
        MostraPagina(avanti: false);
    }

    private void MostraPagina(bool avanti)
    {
        RestituisciPagina();
        ContenutoPagina.Children.Clear();
        paginaSfondo = null;
        var pagina = PaginaAttuale;
        var elenco = pagina == PaginaImpostazioni.Elenco;
        ElencoImpostazioni.Visibility = Visibile(elenco);
        ContenutoPagina.Visibility = Visibile(!elenco);
        PulsanteIndietroImpostazioni.Visibility = Visibile(!elenco);
        TitoloPaginaImpostazioni.Text = elenco ? Testi.T("Impostazioni_Titolo")
            : VociImpostazioni().First(v => v.Pagina == pagina).Nome;
        if (!elenco) RiempiPagina(pagina);
        ScorrimentoImpostazioni.ChangeView(null, 0, null, true);
        if (impostazioniAperte)
        {
            Anima(spostamentoPagine, "X", avanti ? 40 : -40, 0, 200);
            Anima(ContenitorePagine, "Opacity", 0, 1, 200);
        }
    }

    /// <summary>L'Assistente vocale dice dove si è arrivati; il fuoco va su «Indietro» o sulla prima voce.</summary>
    private void AnnunciaPagina()
    {
        coda.TryEnqueue(() =>
        {
            if (!impostazioniAperte) return;
            Control? primo = PaginaAttuale == PaginaImpostazioni.Elenco
                ? ElencoImpostazioni.Children.OfType<Button>().FirstOrDefault()
                : PulsanteIndietroImpostazioni;
            primo?.Focus(FocusState.Programmatic);
            if (FrameworkElementAutomationPeer.FromElement(PannelloImpostazioni) is { } peer)
            {
                peer.RaiseNotificationEvent(AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent,
                    TitoloPaginaImpostazioni.Text, "pagina-impostazioni");
            }
        });
    }

    /// <summary>Una voce dell'elenco: icona, nome e la freccia verso destra.</summary>
    private Button VoceElenco(PaginaImpostazioni pagina, string nome, string icona)
    {
        var riga = new Grid { ColumnSpacing = 12 };
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(20) });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        riga.Children.Add(new FontIcon { Glyph = icona, FontSize = 16, Foreground = Pennello("Accento") });
        var testo = new TextBlock { Text = nome, FontSize = 15, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        Grid.SetColumn(testo, 1);
        riga.Children.Add(testo);
        var freccia = new FontIcon { Glyph = "", FontSize = 11, Foreground = Pennello("TestoSecondario") };
        Grid.SetColumn(freccia, 2);
        riga.Children.Add(freccia);
        var voce = new Button
        {
            Style = (Style)Application.Current.Resources["VoceMenu"],
            Content = riga,
            Tag = pagina,
            Padding = new Thickness(12, 11, 12, 11),
        };
        AutomationProperties.SetName(voce, nome);
        voce.Click += (_, _) => Vai(pagina);
        return voce;
    }

    /// <summary>
    /// Ogni pagina con le sezioni che oggi stanno nelle colonne, nello stesso ordine delle voci del Mac. I titoli che il
    /// pannello già dice e ciò che ha una pagina sua aspettano nel deposito.
    /// </summary>
    private void RiempiPagina(PaginaImpostazioni pagina)
    {
        switch (pagina)
        {
            case PaginaImpostazioni.Fotocamera:
                // Obiettivo, zoom, esposizione, messa a fuoco, torcia; poi «Regole fini» (ISO, tempo, bianco, regolazioni).
                Nascondi(TitoloFotocamera);
                Prendi(SezioneFotocamera);
                Sottotitolo(Testi.T("Sezione_RegoleFini"));
                Prendi(ContenutoRegoleFini);
                ContenutoRegoleFini.Visibility = Visibility.Visible;
                break;
            case PaginaImpostazioni.Effetti:
                // Lo sfondo e il gobbo hanno la loro voce.
                Nascondi(PannelloSfondo);
                Nascondi(ZonaGobbo);
                Prendi(ContenutoEffetti);
                ContenutoEffetti.Visibility = Visibility.Visible;
                break;
            case PaginaImpostazioni.Sfondo:
                paginaSfondo = new StackPanel { Spacing = 6 };
                ContenutoPagina.Children.Add(paginaSfondo);
                statoPaginaSfondo = "";
                AggiornaPaginaSfondo();
                break;
            case PaginaImpostazioni.Profili:
                Prendi(ContenitoreProfilo);
                break;
            case PaginaImpostazioni.Qualita:
                // Senza telefono le strade possibili; con un telefono la qualità, la strada (se si può scegliere) e i numeri.
                Prendi(SezioneConnessione);
                Prendi(FinestraNumeri, ContenutoQualita);
                Prendi(FinestraCollegamento, ContenutoCollegamento);
                SuAperturaQualitaInPagina();
                break;
            case PaginaImpostazioni.Microfono:
                Prendi(RigaMicrofono);
                break;
            case PaginaImpostazioni.Telefoni:
                // Collegati e conosciuti, diagnosi, «Scollega», e il QR per collegarne un altro.
                Nascondi(EtichettaTelefoni);
                Nascondi(PulsanteRegistro);
                Prendi(SezioneTelefoni);
                Prendi(BarraDiagnosi);
                Prendi(BarraCavo);
                var conosciuti = new HyperlinkButton { Content = Testi.T("Impostazioni_TelefoniConosciuti"), Padding = new Thickness(0) };
                conosciuti.Click += (_, _) => _ = ApriAppAsync(PaginaApp.Sicurezza);
                ContenutoPagina.Children.Add(conosciuti);
                Prendi(PulsanteScollega);
                Prendi(BloccoQR);
                break;
            case PaginaImpostazioni.Uscite:
                // La webcam per le altre app, il microfono del telefono, NDI (in arrivo); sotto, la riga delle app con l'aiuto scritto.
                Nascondi(EtichettaUscite);
                Prendi(SezioneUscite);
                Prendi(PannelloAppInUso);
                PannelloAppInUso.HorizontalAlignment = HorizontalAlignment.Left;
                AiutoAppWebcam.Visibility = Visibility.Visible;
                break;
            case PaginaImpostazioni.Schermo:
                Prendi(SezioneSchermo);
                break;
            case PaginaImpostazioni.Gobbo:
                Prendi(ZonaGobbo);
                if (ZonaGobbo.Visibility == Visibility.Collapsed)
                {
                    Nota(DettagliEffetti.Text.Length > 0 ? DettagliEffetti.Text : Testi.T("Comandi_SiAttivano"));
                }
                break;
            case PaginaImpostazioni.Registro:
                Prendi(FinestraRegistro, ContenutoRegistro);
                ContenutoRegistro.Width = double.NaN;
                SuAperturaRegistro(null, EventArgs.Empty);
                break;
        }
    }

    /// <summary>Qualità, strada e numeri nella pagina: come all'apertura dei loro menu sul video.</summary>
    private void SuAperturaQualitaInPagina()
    {
        MostraNumeri();
        qualitaMostrate = [];
        MostraQualita();
        vociStradaMostrate = [];
        MostraMenuCollegamento();
        ContenutoCollegamento.Visibility = Visibile(StradaSceglibile);
    }

    private void Sottotitolo(string testo) => ContenutoPagina.Children.Add(new TextBlock
    {
        Text = testo.ToUpper(Testi.Cultura),
        FontFamily = (FontFamily)Application.Current.Resources["Etichette"],
        FontSize = 14,
        CharacterSpacing = 110,
        Foreground = Pennello("TestoSecondario"),
        Margin = new Thickness(0, 8, 0, -6),
    });

    private void Nota(string testo) => ContenutoPagina.Children.Add(new TextBlock
    {
        Text = testo,
        FontSize = 12.5,
        TextWrapping = TextWrapping.Wrap,
        Foreground = Pennello("TestoSecondario"),
    });

    /// <summary>Sposta una sezione dalla sua colonna alla pagina.</summary>
    private void Prendi(FrameworkElement elemento) => Presta(Togli(elemento), ContenutoPagina);

    /// <summary>Sposta il contenuto di un menu (qualità, strada, registro) alla pagina.</summary>
    private void Prendi(Flyout menu, FrameworkElement contenuto)
    {
        if (!ReferenceEquals(menu.Content, contenuto)) return;
        if (menu.IsOpen) menu.Hide();
        menu.Content = null;
        Presta(new Prestito(contenuto, () => menu.Content = contenuto), ContenutoPagina);
    }

    /// <summary>Toglie per un po' ciò che la pagina non deve mostrare: aspetta nel deposito, invisibile.</summary>
    private void Nascondi(FrameworkElement elemento) => Presta(Togli(elemento), Deposito);

    private void Presta(Prestito prestito, Panel dove)
    {
        dove.Children.Add(prestito.Elemento);
        prestitiPagina.Add(new Prestito(prestito.Elemento, () =>
        {
            dove.Children.Remove(prestito.Elemento);
            prestito.Rimetti();
        }));
    }

    /// <summary>Stacca un controllo dal suo genitore e ricorda dove rimetterlo (stesso posto nell'elenco dei figli).</summary>
    private static Prestito Togli(FrameworkElement elemento)
    {
        switch (elemento.Parent)
        {
            case Panel pannello:
                var indice = pannello.Children.IndexOf(elemento);
                pannello.Children.RemoveAt(indice);
                return new Prestito(elemento, () => pannello.Children.Insert(Math.Min(indice, pannello.Children.Count), elemento));
            case Border bordo:
                bordo.Child = null;
                return new Prestito(elemento, () => bordo.Child = elemento);
            default:
                return new Prestito(elemento, () => { });
        }
    }

    /// <summary>Tutto torna nelle colonne, in ordine inverso; poi ciò che la pagina aveva cambiato torna com'era.</summary>
    private void RestituisciPagina()
    {
        if (prestitiPagina.Count == 0) return;
        for (var i = prestitiPagina.Count - 1; i >= 0; i--) prestitiPagina[i].Rimetti();
        prestitiPagina.Clear();
        ContenutoRegistro.Width = 380;
        ContenutoCollegamento.Visibility = Visibility.Visible;
        PannelloAppInUso.HorizontalAlignment = HorizontalAlignment.Center;
        AiutoAppWebcam.Visibility = Visibility.Collapsed;
        // «Effetti» e «Regole fini» tornano aperte o chiuse come le aveva lasciate l'utente.
        MostraSezioni();
    }

    // MARK: pagina «Sfondo»: lo stesso contenuto del menu del pulsante «Sfondo»

    /// <summary>
    /// Nessuno · Sfocatura (Poco, Medio, Tanto) · Sfondi, con le scelte del menu (ScegliNessunSfondo, ScegliLivelloSfocatura,
    /// le miniature di ContenutoSfondi). Si rifà quando cambia lo stato che il telefono conferma.
    /// </summary>
    private void AggiornaPaginaSfondo()
    {
        if (paginaSfondo is null) return;
        var stato = StatoSfondo();
        var valori = effetti.Valori;
        var disponibile = SfondoDisponibile && !SoloFrontaleBloccati;
        var firma = string.Join("|", stato, disponibile, valori.SfondoSfocato, RegoleSfondo.ImmagineAttuale(valori, ProntiDelTelefono),
            BloccoPro, PersonaleDisponibile, ImmaginiDisponibili, ProntiDelTelefono.Count, miniaturaPersonale?.GetHashCode());
        if (firma == statoPaginaSfondo) return;
        statoPaginaSfondo = firma;
        paginaSfondo.Children.Clear();
        if (!disponibile)
        {
            paginaSfondo.Children.Add(new TextBlock
            {
                Text = telefono is null ? Testi.T("Comandi_SiAttivano") : SoloFrontaleBloccati ? Testi.T("Comandi_SoloFrontale") : "",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12.5,
                Foreground = Pennello("TestoSecondario"),
                Margin = new Thickness(0, 0, 0, 6),
            });
        }
        var scelte = new StackPanel { Spacing = 2, IsHitTestVisible = disponibile, Opacity = disponibile ? 1 : 0.5 };
        var nessuno = Scelta(Testi.T("Sfondo_Nessuno"), stato.Nessuno, disponibile);
        nessuno.Click += (_, _) => ScegliNessunSfondo();
        scelte.Children.Add(nessuno);
        scelte.Children.Add(new TextBlock
        {
            Text = Testi.T("Sfondo_Sfocatura"),
            FontFamily = (FontFamily)Application.Current.Resources["CorpoForte"],
            Margin = new Thickness(0, 10, 0, 2),
        });
        if (stato.Sistema)
        {
            // La sfocatura del telefono (Effetti video di Apple): accesa e spiegata, i nostri livelli grigi.
            scelte.Children.Add(Scelta(Testi.T("Sfondo_SfocaturaTelefono"), stato.SistemaAccesa, false));
            scelte.Children.Add(new TextBlock { Text = Testi.T("Effetti_SiRegolaSulTelefono"), FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = Pennello("TestoSecondario") });
        }
        foreach (var livello in LivelliSfocatura.Tutti)
        {
            var voce = Scelta(LivelliSfocatura.Nome(livello), valori.SfondoSfocato && livello == stato.Attuale, disponibile && !stato.Sistema);
            voce.Click += (_, _) => ScegliLivelloSfocatura(livello);
            scelte.Children.Add(voce);
        }
        scelte.Children.Add(new TextBlock
        {
            Text = BloccoPro ? Testi.T("Sfondo_SfondiPro") : Testi.T("Sfondo_Sfondi"),
            FontFamily = (FontFamily)Application.Current.Resources["CorpoForte"],
            Margin = new Thickness(0, 10, 0, 6),
        });
        scelte.Children.Add(ContenutoSfondi());
        paginaSfondo.Children.Add(scelte);

        static RadioButton Scelta(string testo, bool scelta, bool attiva) => new()
        {
            Content = testo,
            GroupName = "sfondo-impostazioni",
            IsChecked = scelta,
            IsEnabled = attiva,
        };
    }

    // MARK: schermo intero e «Esci»

    /// <summary>«Esci» compare al movimento del mouse o a un tasto, nello schermo intero e nella vista pulita.</summary>
    private void MostraEsciPerUnPo()
    {
        if (!(vistaPulita || InSchermoIntero) || InMini || tempoEsci is null) return;
        esciVisibile = true;
        MostraPulsanteTorna();
        tempoEsci.Stop();
        tempoEsci.Start();
    }

    // MARK: animazioni

    private static void Anima(DependencyObject bersaglio, string proprieta, double da, double a, int millisecondi, Action? fine = null)
    {
        var animazione = new DoubleAnimation
        {
            From = da,
            To = a,
            Duration = new Duration(TimeSpan.FromMilliseconds(millisecondi)),
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        };
        Storyboard.SetTarget(animazione, bersaglio);
        Storyboard.SetTargetProperty(animazione, proprieta);
        var storia = new Storyboard();
        storia.Children.Add(animazione);
        if (fine is not null) storia.Completed += (_, _) => fine();
        storia.Begin();
    }
}
