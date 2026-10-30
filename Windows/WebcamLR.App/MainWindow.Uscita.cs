using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Uscire e chiudere senza sorprese (1.0 beta 2, passo 2; windows.md 1.1, 1.2, 1.7, 1.10, N1, N2):
/// <list type="bullet">
/// <item>«Esci da WebcamLR» nel menu dell'icona e nel menu Account chiede prima, se un'app usa il video, se si registra
/// o se un telefono è collegato (DomandaUscita, pulsante predefinito «Annulla»); altrimenti esce subito;</item>
/// <item>X e Alt+F4 nascondono la finestra e, la prima volta e sempre registrando o in onda, una notifica lo dice;</item>
/// <item>l'uscita vera (EsciAsync) chiude la registrazione con await, senza bloccare la finestra, con l'avviso
/// «Chiudo la registrazione…»; la usa anche «WebcamLR.exe --esci» dell'installatore, senza domande.</item>
/// </list>
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Vero mentre la domanda «Uscire da WebcamLR?» è aperta: un secondo «Esci» non ne apre un'altra.</summary>
    private bool domandaUscitaAperta;
    /// <summary>Vero solo alla fine di EsciAsync: allora la chiusura della finestra passa (altrimenti si nasconde).</summary>
    private bool chiudiDavvero;
    private readonly AvvisoFinestraNascosta avvisoFinestraNascosta = new();

    private void SuVoceEsci(object sender, RoutedEventArgs e)
    {
        MenuAccount.Hide();
        ChiediEsci();
    }

    /// <summary>«Esci da WebcamLR»: la domanda se serve, poi l'uscita vera.</summary>
    private async void ChiediEsci()
    {
        // async void (comando del menu): un errore qui finisce in Errori.txt, non chiude l'app a metà.
        try
        {
            if (uscita || domandaUscitaAperta) return;
            domandaUscitaAperta = true;
            IReadOnlyList<string> app = [];
            if (inOnda)
            {
                try { app = await Task.Run(LeggiAppInUso); }
                catch (Exception) { }
            }
            var domanda = DomandaUscita.Crea(inOnda, app, registrazione is not null, telefoni.Telefoni.Select(t => t.Nome).ToList());
            if (domanda is not null)
            {
                // Dal menu dell'icona la finestra può essere nascosta: la domanda si fa davanti.
                MostraFinestra();
                await PreparaDialogoAsync();
                if (Content.XamlRoot is not { } radice) return;
                var finestra = new ContentDialog
                {
                    XamlRoot = radice,
                    Title = domanda.Titolo,
                    Content = new TextBlock { Text = domanda.Testo, TextWrapping = TextWrapping.Wrap },
                    PrimaryButtonText = domanda.Esci,
                    CloseButtonText = domanda.Annulla,
                    DefaultButton = ContentDialogButton.Close,
                };
                if (await finestra.ShowAsync() != ContentDialogResult.Primary) return;
            }
            await EsciAsync();
        }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
        }
        finally
        {
            domandaUscitaAperta = false;
        }
    }

    /// <summary>
    /// Dall'installatore («WebcamLR.exe --esci», 1.7): esce come «Esci», senza domande, chiudendo e salvando la
    /// registrazione. Chiamata sul thread dell'interfaccia.
    /// </summary>
    public void EsciSenzaDomande() => _ = EsciAsync();

    /// <summary>
    /// L'uscita vera: salva la posizione, chiude la registrazione (con await e un tetto lungo, N1: la finestra intanto
    /// risponde e dice «Chiudo la registrazione…»), poi chiude la finestra e l'app.
    /// </summary>
    private async Task EsciAsync()
    {
        if (uscita) return;
        uscita = true;
        try
        {
            SalvaPosizione();
            if (registrazione is not null)
            {
                MostraAvvisoRiprese(Testi.T("Uscita_ChiudoRegistrazione"));
                // L'avviso resta finché l'app non esce, invece di sparire dopo 4 secondi.
                fineAvvisoRiprese?.Stop();
            }
            await ChiudiRipreseAsync();
        }
        catch (Exception errore)
        {
            App.ScriviErrore(errore);
        }
        chiudiDavvero = true;
        Close();
        Application.Current.Exit();
    }

    /// <summary>X o Alt+F4 con l'icona accanto all'orologio: la notifica di 1.2, quando serve.</summary>
    private void AvvisaFinestraNascosta()
    {
        var registrando = registrazione is not null;
        if (!avvisoFinestraNascosta.Serve(registrando, inOnda)) return;
        var (titolo, testo) = AvvisoFinestraNascosta.Notifica(registrando);
        // Direttamente, non con Notifica: la finestra è appena stata nascosta, ma può risultare ancora in primo piano.
        notifiche.Mostra(titolo, testo);
    }
}
