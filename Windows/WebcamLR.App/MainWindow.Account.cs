using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il menu Account in alto a destra (disegno finale, Documenti/Interfaccia finale.md): WebcamLR Pro, Preferenze, Telefoni
/// conosciuti, Lingua, Aggiornamenti, Informazioni e privacy. Niente login per ora: in cima il nome dell'utente di Windows.
/// Le voci aprono ciò che c'era già: il riquadro delle preferenze, le schede di «App e assistenza», l'aggiornamento.
/// </summary>
public sealed partial class MainWindow
{
    private void SuAperturaAccount(object? sender, object e) => MostraAccount();

    /// <summary>Nome, piano (gratis o Pro, dal telefono nella webcam), lingua e versione, aggiornati a ogni apertura.</summary>
    private void MostraAccount()
    {
        var nome = string.IsNullOrWhiteSpace(Environment.UserName) ? "WebcamLR" : Environment.UserName;
        var iniziale = char.ToUpper(nome[0], Testi.Cultura).ToString();
        InizialeAccount.Text = iniziale;
        InizialeMenuAccount.Text = iniziale;
        NomeAccount.Text = nome;
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

    /// <summary>«Come sbloccarla» (o «Dettagli»): la pagina «WebcamLR Pro» di «App e assistenza».</summary>
    private void SuProAccount(object sender, RoutedEventArgs e) => _ = ApriAppAsync(PaginaApp.Pro);

    private void SuTelefoniConosciuti(object sender, RoutedEventArgs e) => _ = ApriAppAsync(PaginaApp.Sicurezza);

    private void SuInformazioni(object sender, RoutedEventArgs e) => _ = ApriAppAsync(PaginaApp.Informazioni);

    private async Task ApriAppAsync(PaginaApp pagina)
    {
        try
        {
            MenuAccount.Hide();
            await PreparaDialogoAsync();
            await FinestraApp.MostraAsync(Content.XamlRoot, DatiTecnici(), abbinamento, StatoPro(), pagina: pagina);
        }
        catch (Exception) { }
    }

    /// <summary>«Preferenze»: avvio con Windows, schermata di attesa, «App e assistenza», sotto il pulsante Account.</summary>
    private void SuPreferenze(object sender, RoutedEventArgs e)
    {
        MenuAccount.Hide();
        FlyoutBase.ShowAttachedFlyout(AncoraPreferenze);
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
