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

    /// <returns>Vero se versione.json è stato letto (per «Aggiornamenti» nel menu Account, che lo dice).</returns>
    private async Task<bool> ControllaAggiornamentiAsync()
    {
        if (controlloInCorso || uscita) return false;
        controlloInCorso = true;
        try
        {
            var letta = await Task.Run(() => Aggiornamenti.ScaricaAsync(ClientAggiornamenti));
            if (letta is null) return false;
            var build = typeof(MainWindow).Assembly.GetName().Version?.Revision ?? 0;
            // Il file dice che questa è l'ultima: niente pillola (anche dopo un aggiornamento).
            versioneNuova = Aggiornamenti.DaAggiornare(letta, VersioneApp, Math.Max(0, build)) ? letta : null;
            MostraAggiornamento();
            return true;
        }
        catch (Exception) { return false; }
        finally { controlloInCorso = false; }
    }

    private void MostraAggiornamento()
    {
        var mostra = versioneNuova is { } nuova && nuova.Testo != Preferenze.AggiornamentoRimandato;
        PulsanteAggiornamento.Visibility = Visibile(mostra);
        if (mostra) ToolTipService.SetToolTip(PulsanteAggiornamento, Testi.T("Aggiornamento_Disponibile", versioneNuova!.Testo));
    }

    /// <summary>Il foglio di «Aggiornamento disponibile»: versione, data, novità, «Scarica» e «Più tardi».</summary>
    private async void SuAggiornamento(object sender, RoutedEventArgs e)
    {
        if (versioneNuova is not { } versione) return;
        try
        {
            await PreparaDialogoAsync();
            var contenuto = new StackPanel { Spacing = Token.SpazioMezzo, MaxWidth = 420 };
            contenuto.Children.Add(new TextBlock
            {
                Text = Testi.T("Aggiornamento_OraHai", versione.Testo, VersioneApp),
                FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
                FontSize = Token.MisuraNumeri,
                Foreground = Pennello("TestoSecondario"),
            });
            if (versione.DataLeggibile is { } data)
                contenuto.Children.Add(new TextBlock { Text = Testi.T("Aggiornamento_Pubblicata", data), FontSize = Token.MisuraTestoPiccolo, Foreground = Pennello("TestoSecondario") });
            if (!string.IsNullOrWhiteSpace(versione.Novita))
            {
                contenuto.Children.Add(new ScrollViewer
                {
                    MaxHeight = 180,
                    Background = Pennello("Pannello"),
                    CornerRadius = new CornerRadius(Token.RaggioStretto),
                    Padding = new Thickness(Token.SpazioMezzo),
                    // Le novità arrivano dal sito, in italiano come il resto del sito.
                    Content = new TextBlock { Text = versione.Novita, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, Foreground = Pennello("TestoChiaro") },
                });
            }
            contenuto.Children.Add(new TextBlock
            {
                Text = Testi.T("Aggiornamento_ComeSiScarica"),
                TextWrapping = TextWrapping.Wrap,
                FontSize = Token.MisuraNota,
                Foreground = Pennello("TestoSecondario"),
            });
            var foglio = new ContentDialog
            {
                XamlRoot = Content.XamlRoot,
                Title = Testi.T("Aggiornamento_Titolo"),
                Content = contenuto,
                PrimaryButtonText = Testi.T("Aggiornamento_Scarica"),
                CloseButtonText = Testi.T("Aggiornamento_PiuTardi"),
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
