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
/// Passi 5 e 6 (windows.md 2.10, N3): l'icona ha tre stati (normale; punto corallo in onda o registrando; punto ambra in
/// riconnessione, DescrizioneStato.Icona), il suggerimento dice «In onda su Zoom · Registrazione 12:31» e, mentre si
/// registra, il menu ha «Ferma la registrazione» sotto la riga di stato.
/// </summary>
public sealed class IconaTray : IDisposable
{
    private readonly TaskbarIcon icona;
    private readonly MenuFlyoutItem rigaStato;
    private readonly MenuFlyout menu = new();
    private readonly Action<TelefonoCollegato> scollega;
    /// <summary>«Ferma la registrazione»: nel menu solo mentre si registra (un menu di sistema non conosce Visibility).</summary>
    private readonly MenuFlyoutItem voceFerma;
    /// <summary>Le tre icone, dalle .ico di Assets (Strumenti/genera_icone.py), lette una volta.</summary>
    private readonly Dictionary<IconaNotifica, BitmapImage> immagini = new()
    {
        [IconaNotifica.Normale] = new BitmapImage(new Uri("ms-appx:///Assets/WebcamLR.ico")),
        [IconaNotifica.InOnda] = new BitmapImage(new Uri("ms-appx:///Assets/WebcamLR-InOnda.ico")),
        [IconaNotifica.Riconnessione] = new BitmapImage(new Uri("ms-appx:///Assets/WebcamLR-Riconnessione.ico")),
    };
    /// <summary>La voce «Scollega il telefono» o il sottomenu «Scollega ▸»: si sostituisce quando cambiano i telefoni.</summary>
    private MenuFlyoutItemBase voceScollega;
    private IReadOnlyList<TelefonoCollegato> telefoniMostrati = [];
    private string ultimoSuggerimento = "";
    private IconaNotifica iconaMostrata = IconaNotifica.Normale;

    public IconaTray(Action apri, Action mini, Action<TelefonoCollegato> scollega, Action fermaRegistrazione, Action esci)
    {
        this.scollega = scollega;
        // La riga dello stato non fa nulla: è disattivata, come un'intestazione.
        rigaStato = new MenuFlyoutItem { Text = DescrizioneStato.Riga(FaseCollegamento.NessunTelefono, null), IsEnabled = false };
        voceFerma = new MenuFlyoutItem { Text = Testi.T("Tray_FermaRegistrazione"), Command = new Comando(fermaRegistrazione) };
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
            IconSource = immagini[IconaNotifica.Normale],
            ContextFlyout = menu,
            LeftClickCommand = new Comando(apri),
            NoLeftClickDelay = true,
        };
        icona.ForceCreate(enablesEfficiencyMode: false);
    }

    /// <summary>
    /// Aggiorna l'icona, la riga del menu e il testo al passaggio del mouse, per esempio «WebcamLR · Collegato a iPhone di
    /// Ledion · Ottimo» o «WebcamLR · In onda su Zoom · Registrazione 12:31». Si chiama ogni secondo: tocca l'icona solo
    /// se cambia.
    /// </summary>
    public void Aggiorna(StatoNotifica stato)
    {
        var nuova = DescrizioneStato.Icona(stato);
        if (nuova != iconaMostrata)
        {
            iconaMostrata = nuova;
            icona.IconSource = immagini[nuova];
        }
        MostraFerma(stato.Registrazione is not null);
        var suggerimento = DescrizioneStato.Suggerimento(stato);
        if (suggerimento == ultimoSuggerimento) return;
        ultimoSuggerimento = suggerimento;
        icona.ToolTipText = suggerimento;
        rigaStato.Text = DescrizioneStato.Riga(stato);
    }

    /// <summary>«Ferma la registrazione» subito sotto la riga di stato, solo mentre si registra.</summary>
    private void MostraFerma(bool registrando)
    {
        var presente = menu.Items.Contains(voceFerma);
        if (registrando && !presente) menu.Items.Insert(menu.Items.IndexOf(rigaStato) + 1, voceFerma);
        else if (!registrando && presente) menu.Items.Remove(voceFerma);
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
