using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// «Aggiornamento disponibile», come sul Mac (Mac/Sorgenti/ControlloAggiornamenti.swift): all'avvio e ogni 6 ore si legge
/// versione.json dal sito, fuori dal thread dell'interfaccia; con una versione più nuova compare la pillola in alto
/// (nell'accento, mai in corallo). Niente rete o file sbagliato: non dice niente. Non scarica e non installa nulla:
/// «Scarica» apre la pagina nel browser, «Più tardi» la nasconde fino alla versione dopo. La logica è in Aggiornamenti.
/// </summary>
public sealed partial class MainWindow
{
    private static readonly HttpClient ClientAggiornamenti = new();
    private DispatcherQueueTimer? controlloAggiornamenti;
    private VersionePubblicata? versioneNuova;
    private bool controlloInCorso;

    private void InizializzaAggiornamenti()
    {
        controlloAggiornamenti = coda.CreateTimer();
        controlloAggiornamenti.Interval = Aggiornamenti.Intervallo;
        controlloAggiornamenti.Tick += (_, _) => _ = ControllaAggiornamentiAsync();
        controlloAggiornamenti.Start();
        // Il primo controllo poco dopo l'avvio: la finestra e il collegamento vengono prima.
        var primo = coda.CreateTimer();
        primo.Interval = TimeSpan.FromSeconds(5);
        primo.IsRepeating = false;
        primo.Tick += (_, _) => _ = ControllaAggiornamentiAsync();
        primo.Start();
    }

    private void FermaAggiornamenti() => controlloAggiornamenti?.Stop();

    private async Task ControllaAggiornamentiAsync()
    {
        if (controlloInCorso || uscita) return;
        controlloInCorso = true;
        try
        {
            var letta = await Task.Run(() => Aggiornamenti.ScaricaAsync(ClientAggiornamenti));
            if (letta is null) return;
            var build = typeof(MainWindow).Assembly.GetName().Version?.Revision ?? 0;
            // Il file dice che questa è l'ultima: niente pillola (anche dopo un aggiornamento).
            versioneNuova = Aggiornamenti.DaAggiornare(letta, VersioneApp, Math.Max(0, build)) ? letta : null;
            MostraAggiornamento();
        }
        catch (Exception) { }
        finally { controlloInCorso = false; }
    }

    private void MostraAggiornamento()
    {
        var mostra = versioneNuova is { } nuova && nuova.Testo != Preferenze.AggiornamentoRimandato;
        PulsanteAggiornamento.Visibility = Visibile(mostra);
        if (mostra) ToolTipService.SetToolTip(PulsanteAggiornamento, $"WebcamLR {versioneNuova!.Testo} è disponibile sul sito");
    }

    /// <summary>Il foglio di «Aggiornamento disponibile»: versione, data, novità, «Scarica» e «Più tardi».</summary>
    private async void SuAggiornamento(object sender, RoutedEventArgs e)
    {
        if (versioneNuova is not { } versione) return;
        try
        {
            await PreparaDialogoAsync();
            var contenuto = new StackPanel { Spacing = 10, MaxWidth = 420 };
            contenuto.Children.Add(new TextBlock
            {
                Text = $"WebcamLR {versione.Testo} · ora hai {VersioneApp}",
                FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
                FontSize = 12,
                Foreground = Pennello("TestoSecondario"),
            });
            if (versione.DataLeggibile is { } data)
                contenuto.Children.Add(new TextBlock { Text = $"Pubblicata il {data}", FontSize = 12.5, Foreground = Pennello("TestoSecondario") });
            if (!string.IsNullOrWhiteSpace(versione.Novita))
            {
                contenuto.Children.Add(new ScrollViewer
                {
                    MaxHeight = 180,
                    Background = Pennello("Pannello"),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(10),
                    // Le novità arrivano dal sito, in italiano come il resto del sito.
                    Content = new TextBlock { Text = versione.Novita, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, Foreground = Pennello("TestoChiaro") },
                });
            }
            contenuto.Children.Add(new TextBlock
            {
                Text = "Si scarica dal sito: chiudi WebcamLR, apri il file scaricato e segui l'installazione.",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12,
                Foreground = Pennello("TestoSecondario"),
            });
            var foglio = new ContentDialog
            {
                XamlRoot = Content.XamlRoot,
                Title = "Aggiornamento disponibile",
                Content = contenuto,
                PrimaryButtonText = "Scarica",
                CloseButtonText = "Più tardi",
                DefaultButton = ContentDialogButton.Primary,
            };
            var esito = await foglio.ShowAsync();
            if (esito == ContentDialogResult.Primary)
            {
                await Windows.System.Launcher.LaunchUriAsync(versione.Indirizzo);
            }
            else
            {
                // «Più tardi»: il pulsante torna solo con una versione ancora più nuova.
                Preferenze.AggiornamentoRimandato = versione.Testo;
                MostraAggiornamento();
            }
        }
        catch (Exception) { }
    }
}
