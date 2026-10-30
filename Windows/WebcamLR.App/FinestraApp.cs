using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>La scheda su cui aprire «App e assistenza».</summary>
public enum PaginaApp { Guida, Informazioni }

/// <summary>
/// «App e assistenza» (0.12): guida, domande frequenti, «Segnala un bug» e informazioni, in una finestra a schede. I testi
/// stanno in WebcamLR.Ricevitore (SezioneApp.cs, Pro.cs), uguali a quelli di iPhone e Mac. Passo 8 (windows.md §3): le
/// impostazioni non stanno più qui. I telefoni fidati sono in Impostazioni › Telefoni fidati (ContenutoSicurezza, usato dal
/// pannello); WebcamLR Pro ha la sua finestra (MostraProAsync), dal menu «WebcamLR» e dai comandi bloccati.
/// </summary>
public static class FinestraApp
{
    /// <summary>
    /// Il registro del collegamento della finestra principale (passo 9): «Segnala un bug» lo allega se l'interruttore
    /// è acceso. Lo imposta la finestra principale all'avvio.
    /// </summary>
    public static RegistroCollegamento? Registro { get; set; }

    /// <param name="domanda">Se c'è, si apre su «Domande frequenti» con quella risposta aperta (da un errore o dalla diagnosi).</param>
    /// <param name="pagina">Da «Aiuto» e F1 la guida; dal menu «WebcamLR» «Informazioni e privacy».</param>
    public static async Task MostraAsync(XamlRoot radice, IReadOnlyList<(string Nome, string Valore)> datiTecnici,
        string? domanda = null, PaginaApp? pagina = null)
    {
        var schede = new Pivot();
        var guida = Scheda(Testi.T("App_Guida"), ContenutoGuida());
        schede.Items.Add(guida);
        var domande = Scheda(Testi.T("App_DomandeFrequenti"), ContenutoDomande(domanda));
        schede.Items.Add(domande);
        schede.Items.Add(Scheda(Testi.T("App_SegnalaBug"), ContenutoSegnalazione(datiTecnici)));
        var informazioni = Scheda(Testi.T("App_Informazioni"), ContenutoInformazioni());
        schede.Items.Add(informazioni);
        if (domanda is not null) schede.SelectedItem = domande;
        else if (pagina == PaginaApp.Informazioni) schede.SelectedItem = informazioni;
        else schede.SelectedItem = guida;

        await MostraFinestraAsync(radice, "WebcamLR", schede);
    }

    /// <summary>
    /// «WebcamLR Pro» in una finestra sua (passo 8): era la prima scheda di «App e assistenza». Si apre dalla scheda Pro
    /// del menu «WebcamLR» e dai comandi di WebcamLR Pro bloccati.
    /// </summary>
    /// <param name="pro">Il telefono nella webcam e le sue capacità.</param>
    public static Task MostraProAsync(XamlRoot radice, (string? Nome, Capacita? Capacita) pro) =>
        MostraFinestraAsync(radice, "WebcamLR Pro", ContenutoPro(pro.Nome, pro.Capacita));

    private static async Task MostraFinestraAsync(XamlRoot radice, string titolo, UIElement contenuto)
    {
        var finestra = new ContentDialog
        {
            XamlRoot = radice,
            Title = titolo,
            Content = new ScrollViewer { Content = contenuto, MaxHeight = 560, Width = 520 },
            CloseButtonText = Testi.T("Chiudi"),
            DefaultButton = ContentDialogButton.Close,
        };
        await finestra.ShowAsync();
    }

    private static PivotItem Scheda(string titolo, UIElement contenuto) =>
        new() { Header = titolo, Content = new ScrollViewer { Content = contenuto, Padding = Token.PaddingSchedaGuida } };

    private static Brush Colore(string chiave) => (Brush)Application.Current.Resources[chiave];

    // Il grassetto con la famiglia vera (Barlow SemiBold, CorpoForte), non simulato da Windows su Barlow Regular.
    private static TextBlock Testo(string testo, string colore = "Testo", double dimensione = Token.MisuraCorpo, bool grassetto = false) => new()
    {
        Text = testo,
        TextWrapping = TextWrapping.Wrap,
        FontSize = dimensione,
        Foreground = Colore(colore),
        FontFamily = (FontFamily)Application.Current.Resources[grassetto ? "CorpoForte" : "Corpo"],
    };

    /// <summary>
    /// La pagina «WebcamLR Pro», come sul Mac (PaginaProMac): lo stato del telefono collegato, la strada per sbloccarlo
    /// dal telefono e il confronto Gratis/Pro. Sul PC non si compra nulla: il Pro si compra sul telefono (iPhone o
    /// Android) e sblocca anche il PC tramite il telefono collegato.
    /// </summary>
    private static UIElement ContenutoPro(string? nomeTelefono, Capacita? capacita)
    {
        var attivo = RegolePro.Attivo(capacita);
        var pannello = new StackPanel { Spacing = Token.SpazioComodo };
        var titolo = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Token.SpazioMezzo };
        titolo.Children.Add(new SegnoPro { Grande = true });
        titolo.Children.Add(new TextBlock
        {
            Text = "WebcamLR Pro",
            FontFamily = (FontFamily)Application.Current.Resources["Titoli"],
            FontSize = Token.MisuraTitoloGrande,
            VerticalAlignment = VerticalAlignment.Center,
        });
        pannello.Children.Add(titolo);
        if (attivo)
        {
            pannello.Children.Add(new Border
            {
                Background = Colore("AccentoTenue"),
                CornerRadius = new CornerRadius(Token.RaggioRiquadro),
                Padding = new Thickness(Token.SpazioComodo),
                Child = new StackPanel
                {
                    Spacing = Token.SpazioMinimo,
                    Children =
                    {
                        new TextBlock { Text = Testi.T("App_ProAttivo"), FontFamily = (FontFamily)Application.Current.Resources["Titoli"], FontSize = Token.MisuraTitolo, Foreground = Colore("AccentoChiaro") },
                        Testo(Testi.T("App_GraziePro"), "TestoChiaro"),
                    },
                },
            });
        }
        else
        {
            pannello.Children.Add(Testo(Testi.T("App_DescrizionePro"), "TestoChiaro"));
        }
        // Lo stato del telefono e la strada per sbloccarlo: sul PC non si compra nulla.
        var stato = new StackPanel { Spacing = Token.SpazioStretto };
        stato.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = Token.SpazioStretto,
            Children =
            {
                new FontIcon { Glyph = "\uE8EA", FontSize = Token.MisuraIcona, Foreground = Colore("TestoSecondario") },
                new TextBlock { Text = RegolePro.StatoTelefono(nomeTelefono, capacita), TextWrapping = TextWrapping.Wrap, MaxWidth = 420, FontFamily = (FontFamily)Application.Current.Resources["CorpoEvidente"] },
            },
        });
        if (!attivo) stato.Children.Add(Testo(RegolePro.Strada, "TestoChiaro"));
        if (!attivo) stato.Children.Add(Testo(Testi.T("App_ProAndroid"), "TestoSecondario", Token.MisuraNota));
        pannello.Children.Add(new Border
        {
            Background = Colore("Pannello"),
            BorderBrush = Colore("LineaTenue"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(Token.RaggioScheda),
            Padding = new Thickness(Token.SpazioComodo),
            Child = stato,
        });
        pannello.Children.Add(Confronto(Testi.T("App_Gratis"), Testi.T("App_PerSempre"), RegolePro.Gratis, pro: false));
        pannello.Children.Add(Confronto("Pro", Testi.T("App_TuttoIlGratisPiu"), RegolePro.VociPro, pro: true));
        return pannello;
    }

    private static Border Confronto(string titolo, string nota, IReadOnlyList<string> voci, bool pro)
    {
        var colonna = new StackPanel { Spacing = Token.SpazioStretto };
        var intestazione = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Token.SpazioStretto };
        if (pro) intestazione.Children.Add(new SegnoPro());
        else intestazione.Children.Add(new TextBlock { Text = titolo, FontFamily = (FontFamily)Application.Current.Resources["Titoli"], FontSize = Token.MisuraTitolo });
        intestazione.Children.Add(new TextBlock { Text = nota, FontSize = Token.MisuraNota, Foreground = Colore("TestoSecondario"), VerticalAlignment = VerticalAlignment.Center });
        colonna.Children.Add(intestazione);
        foreach (var voce in voci)
        {
            colonna.Children.Add(new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = Token.SpazioStretto,
                Children =
                {
                    new FontIcon { Glyph = pro ? "\uE710" : "\uE73E", FontSize = Token.MisuraDettaglio, Foreground = Colore(pro ? "Accento" : "TestoSecondario"), Width = 14 },
                    new TextBlock { Text = voce, TextWrapping = TextWrapping.Wrap, MaxWidth = 400, Foreground = Colore("TestoChiaro") },
                },
            });
        }
        return new Border
        {
            Background = Colore(pro ? "PannelloChiaro" : "Pannello"),
            BorderBrush = Colore(pro ? "BordoPro" : "LineaTenue"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(Token.RaggioRiquadro),
            Padding = new Thickness(Token.SpazioMedio),
            Child = colonna,
        };
    }

    private static UIElement ContenutoGuida()
    {
        var pannello = new StackPanel { Spacing = Token.SpazioComodo };
        foreach (var sezione in Guida.Sezioni)
        {
            pannello.Children.Add(Testo(sezione.Titolo, dimensione: Token.MisuraTitoloSezione, grassetto: true));
            for (var indice = 0; indice < sezione.Passi.Count; indice++)
            {
                pannello.Children.Add(Testo($"{indice + 1}.  {sezione.Passi[indice]}", "TestoSecondario"));
            }
        }
        pannello.Children.Add(new HyperlinkButton { Content = Testi.T("App_AltreRisposte"), NavigateUri = new Uri(InfoApp.Aiuto), Style = (Style)Application.Current.Resources["PulsanteLink"] });
        return pannello;
    }

    /// <summary>
    /// Domande frequenti (1.4), senza Internet: la ricerca filtra mentre si scrive, senza badare a maiuscole e accenti
    /// (DomandeFrequenti.Cerca). Ogni risposta si apre con un clic.
    /// </summary>
    private static UIElement ContenutoDomande(string? aperta)
    {
        var pannello = new StackPanel { Spacing = Token.SpazioMezzo };
        var ricerca = new TextBox { PlaceholderText = Testi.T("App_CercaEsempio") };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(ricerca, Testi.T("App_CercaDomande"));
        var nessuna = Testo(Testi.T("App_NessunaRisposta"), "TestoSecondario");
        nessuna.Visibility = Visibility.Collapsed;
        var elenco = new StackPanel { Spacing = Token.SpazioFine };
        var voci = new List<(DomandaFrequente Domanda, Expander Voce)>();
        foreach (var domanda in DomandeFrequenti.Tutte)
        {
            var voce = new Expander
            {
                Header = new TextBlock { Text = domanda.Domanda, TextWrapping = TextWrapping.Wrap, FontFamily = (FontFamily)Application.Current.Resources["CorpoForte"] },
                Content = Testo(domanda.Risposta, "TestoSecondario"),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Left,
                IsExpanded = domanda.Id == aperta,
            };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(voce, domanda.Domanda);
            voci.Add((domanda, voce));
            elenco.Children.Add(voce);
        }
        ricerca.TextChanged += (_, _) =>
        {
            var trovate = DomandeFrequenti.Cerca(ricerca.Text).Select(d => d.Id).ToHashSet();
            foreach (var (domanda, voce) in voci) voce.Visibility = trovate.Contains(domanda.Id) ? Visibility.Visible : Visibility.Collapsed;
            nessuna.Visibility = trovate.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        };
        // Aperta da un errore: la risposta giusta si porta in vista appena la finestra è pronta.
        if (voci.FirstOrDefault(v => v.Domanda.Id == aperta).Voce is { } daMostrare)
        {
            daMostrare.Loaded += (_, _) => daMostrare.StartBringIntoView();
        }

        pannello.Children.Add(ricerca);
        pannello.Children.Add(nessuna);
        pannello.Children.Add(elenco);
        pannello.Children.Add(new HyperlinkButton { Content = Testi.T("App_AltreRisposte"), NavigateUri = new Uri(InfoApp.Aiuto), Style = (Style)Application.Current.Resources["PulsanteLink"] });
        return pannello;
    }

    private static UIElement ContenutoSegnalazione(IReadOnlyList<(string Nome, string Valore)> datiTecnici)
    {
        var pannello = new StackPanel { Spacing = Token.SpazioMezzo };
        // La bozza (passo 9): il testo resta se la finestra si chiude o se arriva la domanda di un telefono.
        var descrizione = new TextBox
        {
            Header = Testi.T("Bug_CosaESuccesso"),
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 120,
            Text = Preferenze.BozzaSegnalazione,
        };
        var includi = new CheckBox { Content = Testi.T("Bug_IncludiDati"), IsChecked = true };
        var dati = Testo(string.Join("\n", datiTecnici.Select(d => $"{d.Nome}: {d.Valore}")), "TestoSecondario", Token.MisuraNota);
        var includiRegistro = new CheckBox { Content = Testi.T("Bug_IncludiRegistro"), IsChecked = Preferenze.SegnalazioneConRegistro };
        includiRegistro.Checked += (_, _) => Preferenze.SegnalazioneConRegistro = true;
        includiRegistro.Unchecked += (_, _) => Preferenze.SegnalazioneConRegistro = false;
        includi.Checked += (_, _) =>
        {
            dati.Visibility = Visibility.Visible;
            includiRegistro.IsEnabled = true;
        };
        includi.Unchecked += (_, _) =>
        {
            dati.Visibility = Visibility.Collapsed;
            includiRegistro.IsEnabled = false;
        };
        var esito = Testo("", "TestoSecondario", Token.MisuraNota);
        var invia = new Button
        {
            Content = string.IsNullOrEmpty(InfoApp.EmailAssistenza) ? Testi.T("Bug_Copia") : Testi.T("Bug_InviaEmail"),
            IsEnabled = descrizione.Text.Trim().Length > 0,
            Style = (Style)Application.Current.Resources["PulsantePrimario"],
        };
        descrizione.TextChanged += (_, _) =>
        {
            invia.IsEnabled = descrizione.Text.Trim().Length > 0;
            Preferenze.BozzaSegnalazione = descrizione.Text;
        };
        invia.Click += async (_, _) =>
        {
            var conDati = includi.IsChecked == true;
            var registro = conDati && includiRegistro.IsChecked == true ? Registro?.Testo() : null;
            var testo = SegnalazioneBug.Testo(descrizione.Text, conDati ? datiTecnici : null, registro);
            // async void: gli appunti occupati da un'altra app o la mail che non si apre non chiudono WebcamLR.
            try
            {
                if (SegnalazioneBug.Mail(InfoApp.EmailAssistenza, testo) is { } mail
                    && await Windows.System.Launcher.LaunchUriAsync(mail))
                {
                    // Partita: la bozza non serve più (il testo resta nella casella finché la finestra è aperta).
                    Preferenze.BozzaSegnalazione = "";
                    return;
                }
                var contenuto = new DataPackage();
                contenuto.SetText(testo);
                Clipboard.SetContent(contenuto);
                Preferenze.BozzaSegnalazione = "";
                esito.Text = Testi.T("Bug_Copiata");
            }
            catch (Exception)
            {
                esito.Text = Testi.T("Bug_CopiaNonRiuscita");
            }
        };

        pannello.Children.Add(descrizione);
        pannello.Children.Add(includi);
        pannello.Children.Add(dati);
        pannello.Children.Add(includiRegistro);
        pannello.Children.Add(invia);
        pannello.Children.Add(esito);
        pannello.Children.Add(Testo(Testi.T("Bug_NienteVideo"), "TestoSecondario", Token.MisuraNota));
        return pannello;
    }

    /// <summary>
    /// Collegamento sicuro (0.10): l'impronta del PC e i telefoni fidati, da togliere se serve. Passo 8: è la pagina
    /// «Telefoni fidati» del pannello Impostazioni (MainWindow.Viste.cs); <paramref name="cambiati"/> avvisa la finestra
    /// quando se ne toglie uno.
    /// </summary>
    public static UIElement ContenutoSicurezza(Abbinamento abbinamento, Action? cambiati = null)
    {
        var pannello = new StackPanel { Spacing = Token.SpazioMezzo };
        pannello.Children.Add(Testo(Testi.T("Sicurezza_Spiegazione"), "TestoSecondario"));
        pannello.Children.Add(Testo(Testi.T("Sicurezza_CodicePC"), grassetto: true));
        pannello.Children.Add(new TextBlock
        {
            Text = abbinamento.Identita.Impronta,
            FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
            IsTextSelectionEnabled = true,
            // Nel pannello Impostazioni (largo 360) il codice va a capo.
            TextWrapping = TextWrapping.Wrap,
            Foreground = Colore("TestoSecondario"),
        });
        pannello.Children.Add(Testo(Testi.T("Sicurezza_TelefoniFidati"), grassetto: true));
        var elenco = new StackPanel { Spacing = Token.SpazioFine };
        void Aggiorna()
        {
            elenco.Children.Clear();
            var fidati = abbinamento.Fidati;
            if (fidati.Count == 0) elenco.Children.Add(Testo(Testi.T("Sicurezza_Nessuno"), "TestoSecondario"));
            foreach (var (impronta, nome) in fidati)
            {
                var riga = new Grid { ColumnSpacing = Token.SpazioStretto };
                riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                riga.Children.Add(Testo(nome));
                var rimuovi = new Button { Content = Testi.T("Rimuovi"), Style = (Style)Application.Current.Resources["PulsanteDistruttivo"] };
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(rimuovi, Testi.T("Sicurezza_RimuoviNome", nome));
                rimuovi.Click += (_, _) => ChiediRimuoviFidato(rimuovi, nome, () =>
                {
                    abbinamento.Rimuovi(impronta);
                    Aggiorna();
                    cambiati?.Invoke();
                });
                Grid.SetColumn(rimuovi, 1);
                riga.Children.Add(rimuovi);
                elenco.Children.Add(riga);
            }
        }
        Aggiorna();
        pannello.Children.Add(elenco);
        pannello.Children.Add(Testo(Testi.T("Sicurezza_Rimosso"), "TestoSecondario", Token.MisuraNota));
        return pannello;
    }

    /// <summary>
    /// Passo 4 (windows.md 1.8): prima di togliere un telefono fidato, «Rimuovere «Pixel 8» dai telefoni fidati? La
    /// prossima volta dovrai confermarlo con il codice.» La domanda è un riquadro sotto il pulsante (era nata dentro una
    /// ContentDialog, che ne tiene aperta una sola), con lo stato attivo su «Annulla»: Invio ed Esc non tolgono nulla.
    /// </summary>
    private static void ChiediRimuoviFidato(Button dove, string nome, Action rimuovi)
    {
        var domanda = Conferme.RimuoviFidato(nome);
        var conferma = new Button { Content = domanda.Conferma, Style = (Style)Application.Current.Resources["PulsanteDistruttivo"] };
        var annulla = new Button { Content = domanda.Annulla, Style = (Style)Application.Current.Resources["PulsanteSecondario"] };
        var pulsanti = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Token.SpazioStretto, HorizontalAlignment = HorizontalAlignment.Right };
        pulsanti.Children.Add(conferma);
        pulsanti.Children.Add(annulla);
        var pannello = new StackPanel { Spacing = Token.SpazioMezzo, MaxWidth = 300 };
        pannello.Children.Add(Testo(domanda.Titolo, grassetto: true));
        pannello.Children.Add(Testo(domanda.Testo, "TestoSecondario", Token.MisuraCorpoPiccolo));
        pannello.Children.Add(pulsanti);
        var riquadro = new Flyout { Content = pannello, Placement = Microsoft.UI.Xaml.Controls.Primitives.FlyoutPlacementMode.Bottom };
        conferma.Click += (_, _) =>
        {
            riquadro.Hide();
            rimuovi();
        };
        annulla.Click += (_, _) => riquadro.Hide();
        // Esc chiude solo il riquadro: gestito già in PreviewKeyDown, non arriva alla ContentDialog sotto (che si
        // chiuderebbe tutta) né alle scorciatoie della finestra.
        pannello.PreviewKeyDown += (_, evento) =>
        {
            if (evento.Key != Windows.System.VirtualKey.Escape) return;
            evento.Handled = true;
            riquadro.Hide();
        };
        riquadro.Opened += (_, _) => annulla.Focus(FocusState.Programmatic);
        riquadro.ShowAt(dove);
    }

    private static UIElement ContenutoInformazioni()
    {
        var pannello = new StackPanel { Spacing = Token.SpazioMezzo };
        var versione = typeof(FinestraApp).Assembly.GetName().Version?.ToString(3) ?? "—";
        pannello.Children.Add(Testo(Testi.T("Info_Versione", versione), grassetto: true));
        pannello.Children.Add(Testo(Testi.T("Info_Privacy"), "TestoSecondario"));
        pannello.Children.Add(new HyperlinkButton { Content = "Privacy", NavigateUri = new Uri(InfoApp.Privacy), Style = (Style)Application.Current.Resources["PulsanteLink"] });
        pannello.Children.Add(new HyperlinkButton { Content = Testi.T("Info_Sito"), NavigateUri = new Uri(InfoApp.Sito), Style = (Style)Application.Current.Resources["PulsanteLink"] });
        pannello.Children.Add(Testo(Testi.T("Info_AltreApp", string.Join(Testi.T("Congiunzione"), InfoApp.AltreAppLR)), "TestoSecondario", Token.MisuraNota));
        return pannello;
    }
}
