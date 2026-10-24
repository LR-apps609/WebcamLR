using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Sezione App (0.12): WebcamLR Pro, accesso, guida, informazioni e «Segnala un bug», in una finestra a schede.
/// I testi stanno in WebcamLR.Ricevitore/SezioneApp.cs, uguali a quelli di iPhone e Mac.
/// </summary>
public static class FinestraApp
{
    public static async Task MostraAsync(XamlRoot radice, IReadOnlyList<(string Nome, string Valore)> datiTecnici)
    {
        var schede = new Pivot();
        schede.Items.Add(Scheda("Pro", ContenutoPro()));
        schede.Items.Add(Scheda("Guida", ContenutoGuida()));
        schede.Items.Add(Scheda("Segnala un bug", ContenutoSegnalazione(datiTecnici)));
        schede.Items.Add(Scheda("Informazioni", ContenutoInformazioni()));

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

    private static UIElement ContenutoPro()
    {
        var pannello = new StackPanel { Spacing = 10 };
        pannello.Children.Add(Testo("WebcamLR Pro", dimensione: 22, grassetto: true));
        foreach (var vantaggio in InfoApp.VantaggiPro) pannello.Children.Add(Testo("✓  " + vantaggio, "TestoSecondario"));
        // Non ancora acquistabile: il pulsante c'è, spento, così si vede dove sarà.
        pannello.Children.Add(new Button { Content = "Presto disponibile", IsEnabled = false, Margin = new Thickness(0, 6, 0, 0) });
        pannello.Children.Add(Testo("Tutto il resto di WebcamLR è gratis, senza limiti di tempo.", "TestoSecondario", 12));

        pannello.Children.Add(Testo("Accesso", dimensione: 18, grassetto: true));
        pannello.Children.Add(Testo("Modalità senza account: WebcamLR funziona completamente senza registrarti. " +
                                    "L'accesso con l'account LR Apps arriverà per usare Pro su più dispositivi.", "TestoSecondario"));
        pannello.Children.Add(new Button { Content = "Accedi", IsEnabled = false });
        return pannello;
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
            if (SegnalazioneBug.Mail(InfoApp.EmailAssistenza, testo) is { } mail)
            {
                await Windows.System.Launcher.LaunchUriAsync(mail);
                return;
            }
            var contenuto = new DataPackage();
            contenuto.SetText(testo);
            Clipboard.SetContent(contenuto);
            esito.Text = "Copiata: incollala in una mail all'assistenza.";
        };

        pannello.Children.Add(descrizione);
        pannello.Children.Add(includi);
        pannello.Children.Add(dati);
        pannello.Children.Add(invia);
        pannello.Children.Add(esito);
        pannello.Children.Add(Testo("Nessun video e nessuna immagine vengono inviati: solo il testo qui sopra.", "TestoSecondario", 12));
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
