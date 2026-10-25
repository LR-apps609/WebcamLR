using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Sezione App (0.12): WebcamLR Pro, guida, domande frequenti, sicurezza, «Segnala un bug» e informazioni, in una
/// finestra a schede. I testi stanno in WebcamLR.Ricevitore (SezioneApp.cs, Pro.cs), uguali a quelli di iPhone e Mac.
/// </summary>
public static class FinestraApp
{
    /// <param name="domanda">Se c'è, si apre su «Domande frequenti» con quella risposta aperta (da un errore o dalla diagnosi).</param>
    /// <param name="apriGuida">Dal pulsante «Aiuto»: si apre sulla guida invece che su Pro.</param>
    /// <param name="pro">Il telefono nella webcam e le sue capacità, per la pagina «WebcamLR Pro».</param>
    public static async Task MostraAsync(XamlRoot radice, IReadOnlyList<(string Nome, string Valore)> datiTecnici,
        Abbinamento abbinamento, (string? Nome, Capacita? Capacita) pro, string? domanda = null, bool apriGuida = false)
    {
        var schede = new Pivot();
        schede.Items.Add(Scheda("WebcamLR Pro", ContenutoPro(pro.Nome, pro.Capacita)));
        var guida = Scheda("Guida", ContenutoGuida());
        schede.Items.Add(guida);
        var domande = Scheda("Domande frequenti", ContenutoDomande(domanda));
        schede.Items.Add(domande);
        schede.Items.Add(Scheda("Sicurezza", ContenutoSicurezza(abbinamento)));
        schede.Items.Add(Scheda("Segnala un bug", ContenutoSegnalazione(datiTecnici)));
        schede.Items.Add(Scheda("Informazioni", ContenutoInformazioni()));
        if (domanda is not null) schede.SelectedItem = domande;
        else if (apriGuida) schede.SelectedItem = guida;

        var finestra = new ContentDialog
        {
            XamlRoot = radice,
            Title = "WebcamLR",
            Content = new ScrollViewer { Content = schede, MaxHeight = 560, Width = 520 },
            CloseButtonText = "Chiudi",
            DefaultButton = ContentDialogButton.Close,
        };
        await finestra.ShowAsync();
    }

    private static PivotItem Scheda(string titolo, UIElement contenuto) =>
        new() { Header = titolo, Content = new ScrollViewer { Content = contenuto, Padding = new Thickness(0, 8, 12, 8) } };

    private static Brush Colore(string chiave) => (Brush)Application.Current.Resources[chiave];

    private static TextBlock Testo(string testo, string colore = "Testo", double dimensione = 14, bool grassetto = false) => new()
    {
        Text = testo,
        TextWrapping = TextWrapping.Wrap,
        FontSize = dimensione,
        Foreground = Colore(colore),
        FontWeight = grassetto ? FontWeights.SemiBold : FontWeights.Normal,
    };

    /// <summary>
    /// La pagina «WebcamLR Pro», come sul Mac (PaginaProMac): lo stato del telefono collegato, la strada per sbloccarlo
    /// dal telefono e il confronto Gratis/Pro. Sul PC non si compra nulla: il Pro si compra sul telefono (iPhone o
    /// Android) e sblocca anche il PC tramite il telefono collegato.
    /// </summary>
    private static UIElement ContenutoPro(string? nomeTelefono, Capacita? capacita)
    {
        var attivo = RegolePro.Attivo(capacita);
        var pannello = new StackPanel { Spacing = 14 };
        var titolo = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        titolo.Children.Add(new SegnoPro { Grande = true });
        titolo.Children.Add(new TextBlock
        {
            Text = "WebcamLR Pro",
            FontFamily = (FontFamily)Application.Current.Resources["Titoli"],
            FontSize = 28,
            VerticalAlignment = VerticalAlignment.Center,
        });
        pannello.Children.Add(titolo);
        if (attivo)
        {
            pannello.Children.Add(new Border
            {
                Background = Colore("AccentoTenue"),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(14),
                Child = new StackPanel
                {
                    Spacing = 4,
                    Children =
                    {
                        new TextBlock { Text = "Pro attivo", FontFamily = (FontFamily)Application.Current.Resources["Titoli"], FontSize = 20, Foreground = Colore("AccentoChiaro") },
                        Testo("Grazie per aver scelto WebcamLR Pro: è tutto sbloccato.", "TestoChiaro"),
                    },
                },
            });
        }
        else
        {
            pannello.Children.Add(Testo("Qualità piena, effetti da studio e tutti i comandi del PC. Si paga una volta sola, senza abbonamento. Il resto di WebcamLR resta gratis.", "TestoChiaro"));
        }
        // Lo stato del telefono e la strada per sbloccarlo: sul PC non si compra nulla.
        var stato = new StackPanel { Spacing = 8 };
        stato.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            Children =
            {
                new FontIcon { Glyph = "\uE8EA", FontSize = 14, Foreground = Colore("TestoSecondario") },
                new TextBlock { Text = RegolePro.StatoTelefono(nomeTelefono, capacita), TextWrapping = TextWrapping.Wrap, MaxWidth = 420, FontFamily = (FontFamily)Application.Current.Resources["CorpoEvidente"] },
            },
        });
        if (!attivo) stato.Children.Add(Testo(RegolePro.Strada, "TestoChiaro"));
        if (!attivo) stato.Children.Add(Testo("Con un telefono Android: apri WebcamLR › App › WebcamLR Pro, come sull'iPhone.", "TestoSecondario", 12));
        pannello.Children.Add(new Border
        {
            Background = Colore("Pannello"),
            BorderBrush = Colore("LineaTenue"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(14),
            Child = stato,
        });
        pannello.Children.Add(Confronto("Gratis", "per sempre", RegolePro.Gratis, pro: false));
        pannello.Children.Add(Confronto("Pro", "tutto il gratis, più:", RegolePro.VociPro, pro: true));
        return pannello;
    }

    private static Border Confronto(string titolo, string nota, IReadOnlyList<string> voci, bool pro)
    {
        var colonna = new StackPanel { Spacing = 8 };
        var intestazione = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (pro) intestazione.Children.Add(new SegnoPro());
        else intestazione.Children.Add(new TextBlock { Text = titolo, FontFamily = (FontFamily)Application.Current.Resources["Titoli"], FontSize = 20 });
        intestazione.Children.Add(new TextBlock { Text = nota, FontSize = 12, Foreground = Colore("TestoSecondario"), VerticalAlignment = VerticalAlignment.Center });
        colonna.Children.Add(intestazione);
        foreach (var voce in voci)
        {
            colonna.Children.Add(new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                Children =
                {
                    new FontIcon { Glyph = pro ? "\uE710" : "\uE73E", FontSize = 11, Foreground = Colore(pro ? "Accento" : "TestoSecondario"), Width = 14 },
                    new TextBlock { Text = voce, TextWrapping = TextWrapping.Wrap, MaxWidth = 400, Foreground = Colore("TestoChiaro") },
                },
            });
        }
        return new Border
        {
            Background = Colore(pro ? "PannelloChiaro" : "Pannello"),
            BorderBrush = pro ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x8C, 0x9F, 0xD0, 0xB6)) : Colore("LineaTenue"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(16),
            Child = colonna,
        };
    }

    private static UIElement ContenutoGuida()
    {
        var pannello = new StackPanel { Spacing = 14 };
        foreach (var sezione in Guida.Sezioni)
        {
            pannello.Children.Add(Testo(sezione.Titolo, dimensione: 18, grassetto: true));
            for (var indice = 0; indice < sezione.Passi.Count; indice++)
            {
                pannello.Children.Add(Testo($"{indice + 1}.  {sezione.Passi[indice]}", "TestoSecondario"));
            }
        }
        pannello.Children.Add(new HyperlinkButton { Content = "Altre risposte sul sito", NavigateUri = new Uri(InfoApp.Aiuto) });
        return pannello;
    }

    /// <summary>
    /// Domande frequenti (1.4), senza Internet: la ricerca filtra mentre si scrive, senza badare a maiuscole e accenti
    /// (DomandeFrequenti.Cerca). Ogni risposta si apre con un clic.
    /// </summary>
    private static UIElement ContenutoDomande(string? aperta)
    {
        var pannello = new StackPanel { Spacing = 10 };
        var ricerca = new TextBox { PlaceholderText = "Cerca, per esempio «cavo», «firewall», «ritardo»" };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(ricerca, "Cerca nelle domande frequenti");
        var nessuna = Testo("Nessuna risposta con queste parole. Prova con un'altra parola, oppure scrivici da «Segnala un bug».", "TestoSecondario");
        nessuna.Visibility = Visibility.Collapsed;
        var elenco = new StackPanel { Spacing = 6 };
        var voci = new List<(DomandaFrequente Domanda, Expander Voce)>();
        foreach (var domanda in DomandeFrequenti.Tutte)
        {
            var voce = new Expander
            {
                Header = new TextBlock { Text = domanda.Domanda, TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.SemiBold },
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
        pannello.Children.Add(new HyperlinkButton { Content = "Altre risposte sul sito", NavigateUri = new Uri(InfoApp.Aiuto) });
        return pannello;
    }

    private static UIElement ContenutoSegnalazione(IReadOnlyList<(string Nome, string Valore)> datiTecnici)
    {
        var pannello = new StackPanel { Spacing = 10 };
        var descrizione = new TextBox
        {
            Header = "Cosa è successo? Cosa stavi facendo?",
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 120,
        };
        var includi = new CheckBox { Content = "Includi i dati tecnici", IsChecked = true };
        var dati = Testo(string.Join("\n", datiTecnici.Select(d => $"{d.Nome}: {d.Valore}")), "TestoSecondario", 12);
        includi.Checked += (_, _) => dati.Visibility = Visibility.Visible;
        includi.Unchecked += (_, _) => dati.Visibility = Visibility.Collapsed;
        var esito = Testo("", "TestoSecondario", 12);
        var invia = new Button
        {
            Content = string.IsNullOrEmpty(InfoApp.EmailAssistenza) ? "Copia la segnalazione" : "Invia per email",
            IsEnabled = false,
            Style = (Style)Application.Current.Resources["AccentButtonStyle"],
        };
        descrizione.TextChanged += (_, _) => invia.IsEnabled = descrizione.Text.Trim().Length > 0;
        invia.Click += async (_, _) =>
        {
            var testo = SegnalazioneBug.Testo(descrizione.Text, includi.IsChecked == true ? datiTecnici : null);
            // async void: gli appunti occupati da un'altra app o la mail che non si apre non chiudono WebcamLR.
            try
            {
                if (SegnalazioneBug.Mail(InfoApp.EmailAssistenza, testo) is { } mail
                    && await Windows.System.Launcher.LaunchUriAsync(mail))
                {
                    return;
                }
                var contenuto = new DataPackage();
                contenuto.SetText(testo);
                Clipboard.SetContent(contenuto);
                esito.Text = "Copiata: incollala in una mail all'assistenza.";
            }
            catch (Exception)
            {
                esito.Text = "Non riesco a copiarla adesso: riprova tra un attimo.";
            }
        };

        pannello.Children.Add(descrizione);
        pannello.Children.Add(includi);
        pannello.Children.Add(dati);
        pannello.Children.Add(invia);
        pannello.Children.Add(esito);
        pannello.Children.Add(Testo("Nessun video e nessuna immagine vengono inviati: solo il testo qui sopra.", "TestoSecondario", 12));
        return pannello;
    }

    /// <summary>Collegamento sicuro (0.10): l'impronta del PC e i telefoni fidati, da togliere se serve.</summary>
    private static UIElement ContenutoSicurezza(Abbinamento abbinamento)
    {
        var pannello = new StackPanel { Spacing = 10 };
        pannello.Children.Add(Testo("Il video e i comandi viaggiano cifrati. I telefoni nuovi si collegano solo " +
                                    "con il QR code di questa finestra o dopo la tua conferma con il codice.", "TestoSecondario"));
        pannello.Children.Add(Testo("Codice di sicurezza di questo PC", grassetto: true));
        pannello.Children.Add(new TextBlock
        {
            Text = abbinamento.Identita.Impronta,
            FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
            IsTextSelectionEnabled = true,
            Foreground = Colore("TestoSecondario"),
        });
        pannello.Children.Add(Testo("Telefoni fidati", grassetto: true));
        var elenco = new StackPanel { Spacing = 6 };
        void Aggiorna()
        {
            elenco.Children.Clear();
            var fidati = abbinamento.Fidati;
            if (fidati.Count == 0) elenco.Children.Add(Testo("Nessuno, per ora.", "TestoSecondario"));
            foreach (var (impronta, nome) in fidati)
            {
                var riga = new Grid { ColumnSpacing = 8 };
                riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                riga.Children.Add(Testo(nome));
                var rimuovi = new Button { Content = "Rimuovi" };
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(rimuovi, $"Rimuovi {nome}");
                rimuovi.Click += (_, _) =>
                {
                    abbinamento.Rimuovi(impronta);
                    Aggiorna();
                };
                Grid.SetColumn(rimuovi, 1);
                riga.Children.Add(rimuovi);
                elenco.Children.Add(riga);
            }
        }
        Aggiorna();
        pannello.Children.Add(elenco);
        pannello.Children.Add(Testo("Un telefono rimosso dovrà essere confermato di nuovo.", "TestoSecondario", 12));
        return pannello;
    }

    private static UIElement ContenutoInformazioni()
    {
        var pannello = new StackPanel { Spacing = 10 };
        var versione = typeof(FinestraApp).Assembly.GetName().Version?.ToString(3) ?? "—";
        pannello.Children.Add(Testo($"WebcamLR per Windows · versione {versione}", grassetto: true));
        pannello.Children.Add(Testo("Il video va dal telefono al PC solo sulla tua rete: niente passa da Internet.", "TestoSecondario"));
        pannello.Children.Add(new HyperlinkButton { Content = "Privacy", NavigateUri = new Uri(InfoApp.Privacy) });
        pannello.Children.Add(new HyperlinkButton { Content = "Sito di WebcamLR", NavigateUri = new Uri(InfoApp.Sito) });
        pannello.Children.Add(Testo("Una app di LR Apps, come " + string.Join(" e ", InfoApp.AltreAppLR) + ".", "TestoSecondario", 12));
        return pannello;
    }
}
