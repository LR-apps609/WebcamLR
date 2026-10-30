using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il gobbo (P06), in una finestra a parte che non blocca quella principale: si incolla il testo, si sceglie velocità e
/// dimensione, «Avvia» e «Pausa», «Dall'inizio». Il testo scorre sul telefono, vicino all'obiettivo; qui si vede a che
/// punto è arrivato (stato.gobbo.posizione). Cosa ricordare e come rimandarlo è in MemoriaGobbo.
/// </summary>
public sealed class FinestraGobbo
{
    private MemoriaGobbo memoria;
    private readonly Action<Gobbo> invia;
    private readonly Action chiusa;
    private Window? finestra;
    private DispatcherQueueTimer? ritardoVelocita;
    /// <summary>Il testo si salva un attimo dopo l'ultima lettera (passo 9): resta anche se l'app si chiude male.</summary>
    private DispatcherQueueTimer? ritardoSalvataggio;
    private bool disponibile;
    private bool aggiorno;

    private TextBox casella = null!;
    private TextBlock caratteri = null!;
    private TextBlock nota = null!;
    private HyperlinkButton aggiornaTesto = null!;
    private Slider velocita = null!;
    private ComboBox dimensione = null!;
    private Button avvia = null!;
    private TextBlock testoAvvia = null!;
    private FontIcon iconaAvvia = null!;
    private Button dallInizio = null!;
    private ProgressBar avanzamento = null!;
    private TextBlock posizione = null!;

    /// <param name="invia">Manda un messaggio «gobbo» al telefono (la finestra principale lo passa alla sessione).</param>
    /// <param name="chiusa">La finestra si è chiusa: la prossima volta se ne crea una nuova.</param>
    public FinestraGobbo(MemoriaGobbo memoria, Action<Gobbo> invia, Action chiusa)
    {
        this.memoria = memoria;
        this.invia = invia;
        this.chiusa = chiusa;
        RiprendiScelte();
    }

    /// <summary>
    /// Velocità e dimensione scelte l'ultima volta (passo 9): valgono finché a questo telefono non è arrivato un gobbo,
    /// poi conta la sua memoria.
    /// </summary>
    private void RiprendiScelte()
    {
        if (memoria.Inviato) return;
        memoria.Imposta(Preferenze.VelocitaGobbo, Preferenze.DimensioneGobbo);
    }

    private static Brush Pennello(string nome) => (Brush)Application.Current.Resources[nome];

    public void Mostra(bool disponibile)
    {
        if (finestra is null) Crea();
        Aggiorna(disponibile);
        finestra!.Activate();
    }

    public void Chiudi() => finestra?.Close();

    /// <summary>
    /// P21: un altro telefono va nella webcam e il gobbo passa a lui, con la sua memoria (velocità, dimensione, a che
    /// punto è). Il testo scritto nella finestra resta: per mandarlo al telefono nuovo basta «Avvia».
    /// </summary>
    public void UsaMemoria(MemoriaGobbo nuova, bool disponibile)
    {
        memoria = nuova;
        RiprendiScelte();
        Aggiorna(disponibile);
    }

    private void Crea()
    {
        var testoIniziale = memoria.Inviato ? memoria.Testo : Preferenze.TestoGobbo;
        casella = new TextBox
        {
            Text = testoIniziale,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MaxLength = Gobbo.LunghezzaMassima,
            PlaceholderText = Testi.T("Gobbo_Segnaposto"),
            FontSize = Token.MisuraCorpoGrande,
            VerticalAlignment = VerticalAlignment.Stretch,
        };
        ScrollViewer.SetVerticalScrollBarVisibility(casella, ScrollBarVisibility.Auto);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(casella, Testi.T("Gobbo_TestoNome"));
        casella.TextChanged += (_, _) =>
        {
            MostraTesto();
            ritardoSalvataggio?.Stop();
            ritardoSalvataggio?.Start();
        };

        caratteri = new TextBlock { FontFamily = (FontFamily)Application.Current.Resources["Numeri"], FontSize = Token.MisuraNumeri, Foreground = Pennello("TestoSecondario") };
        nota = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = Token.MisuraNota, Foreground = Pennello("TestoSecondario") };
        // Come sul Mac: il testo cambiato parte solo con un clic, perché il gobbo riparte dall'inizio.
        aggiornaTesto = new HyperlinkButton { Content = Testi.T("Gobbo_Aggiorna"), Style = (Style)Application.Current.Resources["PulsanteLink"], Visibility = Visibility.Collapsed };
        ToolTipService.SetToolTip(aggiornaTesto, Testi.T("Gobbo_AggiornaSpiegazione"));
        aggiornaTesto.Click += (_, _) => SuAggiornaTesto();

        velocita = new Slider
        {
            Header = Testi.T("Gobbo_Velocita"),
            Minimum = Gobbo.VelocitaMinima,
            Maximum = Gobbo.VelocitaMassima,
            StepFrequency = 0.1,
            Value = memoria.Velocita,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        velocita.ThumbToolTipValueConverter = new ConvertitoreVelocita();
        velocita.ValueChanged += (_, _) => SuVelocita();

        dimensione = new ComboBox { Header = Testi.T("Gobbo_Dimensione"), HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (valore, nome) in new[] { (DimensioniGobbo.Piccola, Testi.T("Gobbo_Piccola")), (DimensioniGobbo.Media, Testi.T("Gobbo_Media")), (DimensioniGobbo.Grande, Testi.T("Gobbo_Grande")) })
            dimensione.Items.Add(new ComboBoxItem { Content = nome, Tag = valore });
        dimensione.SelectedItem = dimensione.Items.OfType<ComboBoxItem>().First(voce => (string)voce.Tag == memoria.Dimensione);
        dimensione.SelectionChanged += (_, _) => SuDimensione();

        iconaAvvia = new FontIcon { Glyph = "", FontSize = Token.MisuraIcona };
        testoAvvia = new TextBlock { Text = Testi.T("Gobbo_Avvia") };
        avvia = new Button
        {
            Content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Token.SpazioStretto, Children = { iconaAvvia, testoAvvia } },
            Style = (Style)Application.Current.Resources["PulsantePrimario"],
        };
        avvia.Click += (_, _) => SuAvvia();
        dallInizio = new Button
        {
            Style = (Style)Application.Current.Resources["PulsanteSecondario"],
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = Token.SpazioStretto,
                Children = { new FontIcon { Glyph = "", FontSize = Token.MisuraIcona }, new TextBlock { Text = Testi.T("Gobbo_DallInizio") } },
            },
        };
        ToolTipService.SetToolTip(dallInizio, Testi.T("Gobbo_DallInizioSpiegazione"));
        dallInizio.Click += (_, _) => invia(new Gobbo(Posizione: 0));

        avanzamento = new ProgressBar { Minimum = 0, Maximum = 1, Height = 4, VerticalAlignment = VerticalAlignment.Center };
        posizione = new TextBlock
        {
            FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
            FontSize = Token.MisuraNumeri,
            Foreground = Pennello("TestoSecondario"),
            VerticalAlignment = VerticalAlignment.Center,
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetLiveSetting(posizione, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Off);

        var comandi = new Grid { ColumnSpacing = Token.SpazioPiccolo, RowSpacing = Token.SpazioStretto };
        comandi.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        comandi.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(dimensione, 1);
        comandi.Children.Add(velocita);
        comandi.Children.Add(dimensione);

        var pulsanti = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Token.SpazioStretto, Children = { avvia, dallInizio } };

        var riga = new Grid { ColumnSpacing = Token.SpazioMezzo };
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(posizione, 1);
        riga.Children.Add(avanzamento);
        riga.Children.Add(posizione);

        var radice = new Grid { Padding = new Thickness(Token.SpazioMedio), RowSpacing = Token.SpazioMezzo, Background = Pennello("Pannello") };
        foreach (var altezza in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto, GridLength.Auto, GridLength.Auto })
            radice.RowDefinitions.Add(new RowDefinition { Height = altezza });
        var titolo = new TextBlock { Text = Testi.T("Gobbo_Titolo"), FontFamily = (FontFamily)Application.Current.Resources["Titoli"], FontSize = Token.MisuraTitoloGrande };
        var spiegazione = new TextBlock
        {
            Text = Testi.T("Gobbo_Spiegazione"),
            TextWrapping = TextWrapping.Wrap,
            Foreground = Pennello("TestoSecondario"),
        };
        var sottoCasella = new Grid { ColumnSpacing = Token.SpazioStretto };
        sottoCasella.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        sottoCasella.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(caratteri, 1);
        sottoCasella.Children.Add(new StackPanel { Spacing = Token.SpazioMinuscolo, Children = { nota, aggiornaTesto } });
        sottoCasella.Children.Add(caratteri);
        UIElement[] righe = [titolo, spiegazione, casella, sottoCasella, comandi, pulsanti, riga];
        for (var i = 0; i < righe.Length; i++)
        {
            Grid.SetRow((FrameworkElement)righe[i], i);
            radice.Children.Add(righe[i]);
        }

        finestra = new Window { Title = Testi.T("Gobbo_TitoloFinestra"), Content = radice };
        if (Microsoft.UI.Composition.SystemBackdrops.MicaController.IsSupported()) finestra.SystemBackdrop = new MicaBackdrop();
        try { finestra.AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "WebcamLR.ico")); }
        catch (Exception) { }
        // 560×680 DIP, con la scala dello schermo (passo 7): a 150 % non si rimpicciolisce.
        var scala = ScalaFinestra.Di(WinRT.Interop.WindowNative.GetWindowHandle(finestra));
        finestra.AppWindow.Resize(new SizeInt32(PosizioneFinestra.InPixel(560, scala), PosizioneFinestra.InPixel(680, scala)));
        ritardoVelocita = finestra.DispatcherQueue.CreateTimer();
        ritardoVelocita.Interval = TimeSpan.FromMilliseconds(150);
        ritardoVelocita.IsRepeating = false;
        ritardoVelocita.Tick += (_, _) => { if (memoria.Inviato) invia(new Gobbo(Velocita: memoria.Velocita)); };
        ritardoSalvataggio = finestra.DispatcherQueue.CreateTimer();
        ritardoSalvataggio.Interval = TimeSpan.FromSeconds(1);
        ritardoSalvataggio.IsRepeating = false;
        ritardoSalvataggio.Tick += (_, _) => SalvaTesto();
        finestra.Closed += (_, _) =>
        {
            ritardoVelocita?.Stop();
            ritardoSalvataggio?.Stop();
            SalvaTesto();
            finestra = null;
            chiusa();
        };
        MostraTesto();
    }

    /// <summary>Lo stato del telefono o il collegamento sono cambiati: pulsanti, posizione e testo del pulsante principale.</summary>
    public void Aggiorna(bool disponibile)
    {
        this.disponibile = disponibile;
        if (finestra is null) return;
        aggiorno = true;
        velocita.Value = memoria.Velocita;
        dimensione.SelectedItem = dimensione.Items.OfType<ComboBoxItem>().First(voce => (string)voce.Tag == memoria.Dimensione);
        aggiorno = false;
        var scorre = memoria.Inviato && memoria.Attivo;
        iconaAvvia.Glyph = scorre ? "" : "";
        testoAvvia.Text = scorre ? Testi.T("Gobbo_Pausa") : Testi.T("Gobbo_Avvia");
        avvia.IsEnabled = disponibile;
        dallInizio.IsEnabled = disponibile && memoria.Inviato;
        avanzamento.Value = memoria.Inviato ? memoria.Posizione : 0;
        posizione.Text = memoria.Inviato ? Testi.T("Gobbo_APuntoDi", MemoriaGobbo.TestoPosizione(memoria.Posizione)) : "";
        MostraTesto();
    }

    private void MostraTesto()
    {
        if (finestra is null) return;
        var testo = MemoriaGobbo.Taglia(casella.Text);
        caratteri.Text = MemoriaGobbo.TestoCaratteri(testo.Length);
        var cambiato = disponibile && memoria.Inviato && testo != memoria.Testo;
        nota.Text = !disponibile ? Testi.T("Gobbo_SenzaTelefono")
            : cambiato ? Testi.T("Gobbo_TestoCambiato")
            : "";
        aggiornaTesto.Visibility = cambiato ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SuAvvia()
    {
        var testo = MemoriaGobbo.Taglia(casella.Text);
        if (memoria.Inviato && memoria.Attivo)
        {
            invia(new Gobbo(Attivo: false));
            return;
        }
        if (memoria.Inviato)
        {
            // Riprende da dove era; un testo cambiato parte con «Aggiorna il testo».
            invia(new Gobbo(Attivo: true));
            return;
        }
        if (testo.Trim().Length == 0)
        {
            nota.Text = Testi.T("Gobbo_TestoVuoto");
            casella.Focus(FocusState.Programmatic);
            return;
        }
        SalvaTesto();
        // Il primo testo parte intero, con velocità e dimensione.
        invia(new Gobbo(testo, memoria.Velocita, true, memoria.Dimensione));
    }

    /// <summary>Il testo nuovo al telefono, che lo fa ripartire dall'inizio; se scorreva, continua a scorrere.</summary>
    private void SuAggiornaTesto()
    {
        var testo = MemoriaGobbo.Taglia(casella.Text);
        if (testo.Trim().Length == 0) return;
        SalvaTesto();
        invia(new Gobbo(testo, memoria.Velocita, memoria.Attivo, memoria.Dimensione));
    }

    private void SuVelocita()
    {
        if (aggiorno) return;
        memoria.Imposta(velocita: velocita.Value);
        Preferenze.VelocitaGobbo = memoria.Velocita;
        if (!memoria.Inviato) return;
        ritardoVelocita?.Stop();
        ritardoVelocita?.Start();
    }

    private void SuDimensione()
    {
        if (aggiorno || dimensione.SelectedItem is not ComboBoxItem { Tag: string valore }) return;
        Preferenze.DimensioneGobbo = valore;
        if (memoria.Inviato) invia(new Gobbo(Dimensione: valore));
        else memoria.Imposta(dimensione: valore);
    }

    private void SalvaTesto() => Preferenze.TestoGobbo = casella.Text;

    /// <summary>Il valore del cursore come «1,5 righe al secondo».</summary>
    private sealed class ConvertitoreVelocita : Microsoft.UI.Xaml.Data.IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, string language) =>
            value is double v ? MemoriaGobbo.TestoVelocita(v) : "";

        public object ConvertBack(object value, Type targetType, object parameter, string language) => throw new NotSupportedException();
    }
}
