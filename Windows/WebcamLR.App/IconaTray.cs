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
/// </summary>
public sealed class IconaTray : IDisposable
{
    private readonly TaskbarIcon icona;
    private readonly MenuFlyoutItem rigaStato;
    private readonly MenuFlyoutItem voceScollega;
    private string ultimoSuggerimento = "";

    public IconaTray(Action apri, Action mini, Action scollega, Action esci)
    {
        // La riga dello stato non fa nulla: è disattivata, come un'intestazione.
        rigaStato = new MenuFlyoutItem { Text = DescrizioneStato.Riga(StatoCollegamento.NessunTelefono, null), IsEnabled = false };
        voceScollega = new MenuFlyoutItem { Text = "Scollega il telefono", Command = new Comando(scollega), IsEnabled = false };

        var menu = new MenuFlyout();
        menu.Items.Add(rigaStato);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(new MenuFlyoutItem { Text = "Finestra mini", Command = new Comando(mini) });
        menu.Items.Add(voceScollega);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(new MenuFlyoutItem { Text = "Apri WebcamLR", Command = new Comando(apri) });
        menu.Items.Add(new MenuFlyoutItem { Text = "Esci", Command = new Comando(esci) });

        icona = new TaskbarIcon
        {
            ToolTipText = DescrizioneStato.Suggerimento(StatoCollegamento.NessunTelefono, null),
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
    public void Aggiorna(StatoCollegamento stato, string? nomeTelefono, int? latenzaMs)
    {
        var suggerimento = DescrizioneStato.Suggerimento(stato, nomeTelefono, latenzaMs);
        if (suggerimento == ultimoSuggerimento) return;
        ultimoSuggerimento = suggerimento;
        icona.ToolTipText = suggerimento;
        rigaStato.Text = DescrizioneStato.Riga(stato, nomeTelefono, latenzaMs);
        voceScollega.IsEnabled = stato != StatoCollegamento.NessunTelefono;
    }

    public void Dispose() => icona.Dispose();

    private sealed class Comando(Action azione) : ICommand
    {
        public event EventHandler? CanExecuteChanged { add { } remove { } }
        public bool CanExecute(object? parametro) => true;
        public void Execute(object? parametro) => azione();
    }
}
