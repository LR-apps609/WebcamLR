using System.Windows.Input;
using H.NotifyIcon;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Icona accanto all'orologio (bozza grafica, Windows 2): WebcamLR resta attiva anche a finestra chiusa,
/// come sul Mac con il menu nella barra in alto. Il menu usa i comandi, non i Click: H.NotifyIcon
/// mostra un menu di sistema che non conosce gli eventi XAML.
/// Round 2 (funzioni 44 e 45): in cima la riga dello stato, poi finestra mini e scollega;
/// lo stesso stato compare passando sopra l'icona.
/// 1.0 beta 2, passo 4 (windows.md 2.10): con un telefono «Scollega il telefono» scollega quello; con due «Scollega ▸»
/// apre un sottomenu con un telefono per riga, invece di scollegarli tutti. La domanda, se serve, la fa la finestra.
/// </summary>
public sealed class IconaTray : IDisposable
{
    private readonly TaskbarIcon icona;
    private readonly MenuFlyoutItem rigaStato;
    private readonly MenuFlyout menu = new();
    private readonly Action<TelefonoCollegato> scollega;
    /// <summary>La voce «Scollega il telefono» o il sottomenu «Scollega ▸»: si sostituisce quando cambiano i telefoni.</summary>
    private MenuFlyoutItemBase voceScollega;
    private IReadOnlyList<TelefonoCollegato> telefoniMostrati = [];
    private string ultimoSuggerimento = "";

    public IconaTray(Action apri, Action mini, Action<TelefonoCollegato> scollega, Action esci)
    {
        this.scollega = scollega;
        // La riga dello stato non fa nulla: è disattivata, come un'intestazione.
        rigaStato = new MenuFlyoutItem { Text = DescrizioneStato.Riga(FaseCollegamento.NessunTelefono, null), IsEnabled = false };
        voceScollega = VoceScollega([]);

        menu.Items.Add(rigaStato);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(new MenuFlyoutItem { Text = Testi.T("FinestraMini"), Command = new Comando(mini) });
        menu.Items.Add(voceScollega);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(new MenuFlyoutItem { Text = Testi.T("Tray_Apri"), Command = new Comando(apri) });
        menu.Items.Add(new MenuFlyoutItem { Text = Testi.T("EsciDaWebcamLR"), Command = new Comando(esci) });

        icona = new TaskbarIcon
        {
            ToolTipText = DescrizioneStato.Suggerimento(FaseCollegamento.NessunTelefono, null),
            IconSource = new BitmapImage(new Uri("ms-appx:///Assets/WebcamLR.ico")),
            ContextFlyout = menu,
            LeftClickCommand = new Comando(apri),
            NoLeftClickDelay = true,
        };
        icona.ForceCreate(enablesEfficiencyMode: false);
    }

    /// <summary>
    /// Aggiorna la riga del menu e il testo al passaggio del mouse, per esempio
    /// «WebcamLR · Collegato a iPhone di Ledion · Ottimo». Si chiama ogni secondo: tocca l'icona solo se cambia.
    /// </summary>
    public void Aggiorna(FaseCollegamento stato, string? nomeTelefono, int? latenzaMs)
    {
        var suggerimento = DescrizioneStato.Suggerimento(stato, nomeTelefono, latenzaMs);
        if (suggerimento == ultimoSuggerimento) return;
        ultimoSuggerimento = suggerimento;
        icona.ToolTipText = suggerimento;
        rigaStato.Text = DescrizioneStato.Riga(stato, nomeTelefono, latenzaMs);
    }

    /// <summary>I telefoni collegati, per la voce «Scollega»: si rifà solo se l'elenco è cambiato.</summary>
    public void MostraTelefoni(IReadOnlyList<TelefonoCollegato> elenco)
    {
        if (elenco.SequenceEqual(telefoniMostrati)) return;
        telefoniMostrati = elenco.ToList();
        var nuova = VoceScollega(telefoniMostrati);
        var posto = menu.Items.IndexOf(voceScollega);
        if (posto >= 0) menu.Items[posto] = nuova;
        voceScollega = nuova;
    }

    /// <summary>Nessun telefono: la voce grigia. Uno: la voce diretta. Due o più: «Scollega ▸» con un telefono per riga.</summary>
    private MenuFlyoutItemBase VoceScollega(IReadOnlyList<TelefonoCollegato> elenco)
    {
        if (elenco.Count < 2)
        {
            var unico = elenco.FirstOrDefault();
            return new MenuFlyoutItem
            {
                Text = Testi.T("Tray_Scollega"),
                Command = new Comando(() => { if (unico is not null) scollega(unico); }),
                IsEnabled = unico is not null,
            };
        }
        var sottomenu = new MenuFlyoutSubItem { Text = Testi.T("Scollega") };
        foreach (var collegato in elenco)
        {
            sottomenu.Items.Add(new MenuFlyoutItem { Text = collegato.Nome, Command = new Comando(() => scollega(collegato)) });
        }
        return sottomenu;
    }

    public void Dispose() => icona.Dispose();

    private sealed class Comando(Action azione) : ICommand
    {
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parametro) => true;
        public void Execute(object? parametro) => azione();
    }
}
