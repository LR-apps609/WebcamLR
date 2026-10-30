using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il menu «WebcamLR» in alto a destra (prima «Account»: non c'è un account, Glossario): WebcamLR Pro, Impostazioni,
/// Telefoni, Lingua, Aggiornamenti, Informazioni, Esci da WebcamLR. In cima il logo, il nome dell'app e il piano (prima il
/// nome dell'utente di Windows in un cerchio pieno, che sembrava un account).
/// Le voci aprono ciò che c'era già: il pannello Impostazioni (passo 8: il riquadro «Preferenze» non c'è più, le sue voci
/// sono pagine del pannello), la finestra «WebcamLR Pro», «App e assistenza», l'aggiornamento.
/// </summary>
public sealed partial class MainWindow
{
    private void SuAperturaAccount(object? sender, object e) => MostraAccount();

    /// <summary>Piano (gratis o Pro, dal telefono nella webcam), lingua e versione, aggiornati a ogni apertura.</summary>
    private void MostraAccount()
    {
        NomeAccount.Text = "WebcamLR";
        var pro = RegolePro.Attivo(capacitaAttuali);
        PianoAccount.Text = pro ? Testi.T("Account_PianoPro") : Testi.T("Account_PianoGratis");
        // Con Pro attivo la scheda dice su quale telefono; senza, cosa sblocca e come.
        DescrizioneProAccount.Text = pro ? RegolePro.StatoTelefono(telefono?.Nome, capacitaAttuali) : Testi.T("Account_ProDescrizione");
        TestoProAccount.Text = pro ? Testi.T("Account_Dettagli") : Testi.T("Account_ComeSbloccarla");
        ValoreLingua.Text = Testi.T("Account_LinguaAttuale");
        AutomationProperties.SetName(VoceLingua, $"{Testi.T("Account_Lingua")}: {ValoreLingua.Text}");
        ValoreAggiornamenti.Text = versioneNuova is { } nuova
            ? Testi.T("Account_VersioneDisponibile", nuova.Testo) : Testi.T("Account_Aggiornata", VersioneApp);
        AutomationProperties.SetName(VoceAggiornamenti, $"{Testi.T("Account_Aggiornamenti")}: {ValoreAggiornamenti.Text}");
    }

    /// <summary>«Come sbloccarla» (o «Dettagli»): la finestra «WebcamLR Pro».</summary>
    private void SuProAccount(object sender, RoutedEventArgs e) => _ = ApriProAsync();

    /// <summary>Passo 8: «Impostazioni» (Ctrl+,) apre il pannello, l'unico posto per le impostazioni.</summary>
    private void SuVoceImpostazioni(object sender, RoutedEventArgs e)
    {
        MenuAccount.Hide();
        ApriImpostazioni(PaginaImpostazioni.Elenco);
    }

    /// <summary>
    /// «Telefoni»: la pagina del pannello Impostazioni con i telefoni collegati e fidati (un nome solo per la lista, beta 4);
    /// da lì il link «Telefoni fidati» porta al codice di sicurezza e a «Rimuovi».
    /// </summary>
    private void SuTelefoniFidati(object sender, RoutedEventArgs e)
    {
        MenuAccount.Hide();
        ApriImpostazioni(PaginaImpostazioni.Telefoni);
    }

    private void SuInformazioni(object sender, RoutedEventArgs e) => _ = ApriAppAsync(PaginaApp.Informazioni);

    private async Task ApriAppAsync(PaginaApp pagina)
    {
        try
        {
            MenuAccount.Hide();
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), pagina: pagina);
        }
        catch (Exception) { }
    }

    /// <summary>La finestra «WebcamLR Pro»: dalla scheda nel menu «WebcamLR» e dai comandi di WebcamLR Pro bloccati.</summary>
    private async Task ApriProAsync()
    {
        try
        {
            MenuAccount.Hide();
            await PreparaDialogoAsync();
            await FinestraApp.MostraProAsync(Content.XamlRoot, StatoPro());
        }
        catch (Exception) { }
    }

    /// <summary>La lingua segue quella di Windows (italiano, o inglese per tutte le altre): si apre dove si cambia.</summary>
    private async void SuLingua(object sender, RoutedEventArgs e)
    {
        try
        {
            MenuAccount.Hide();
            await Windows.System.Launcher.LaunchUriAsync(new Uri("ms-settings:regionlanguage"));
        }
        catch (Exception) { }
    }

    /// <summary>
    /// «Aggiornamenti»: con una versione nuova il foglio di sempre («Scarica», «Più tardi»); altrimenti si controlla
    /// adesso e si dice com'è andata.
    /// </summary>
    private async void SuVoceAggiornamenti(object sender, RoutedEventArgs e)
    {
        try
        {
            MenuAccount.Hide();
            if (versioneNuova is null)
            {
                var letta = await ControllaAggiornamentiAsync();
                if (versioneNuova is null)
                {
                    await PreparaDialogoAsync();
                    await new ContentDialog
                    {
                        XamlRoot = Content.XamlRoot,
                        Title = Testi.T("Account_Aggiornamenti"),
                        Content = new TextBlock
                        {
                            Text = letta ? Testi.T("Aggiornamento_GiaUltima", VersioneApp) : Testi.T("Aggiornamento_NonRaggiungibile"),
                            TextWrapping = TextWrapping.Wrap,
                        },
                        CloseButtonText = Testi.T("Chiudi"),
                        DefaultButton = ContentDialogButton.Close,
                    }.ShowAsync();
                    return;
                }
            }
            SuAggiornamento(sender, e);
        }
        catch (Exception) { }
    }
}
