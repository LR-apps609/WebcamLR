using Microsoft.UI.Xaml.Controls;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Clic destro (1.0 beta 2, passo 8; windows.md 2.9 e §5): menu contestuali con comandi che esistono già, come in ogni app
/// di Windows. Si rifanno a ogni apertura, così dicono lo stato di adesso (registrazione, vista pulita, riempi):
/// <list type="bullet">
/// <item>sul video: Foto, Copia il fotogramma, Registra (o «Ferma la registrazione»), Vista pulita, Riempi l'inquadratura,
/// con il tasto scritto a destra (KeyboardAcceleratorTextOverride: i tasti veri stanno sulla radice, AggiungiScorciatoie);</item>
/// <item>sulla finestra mini (lo stesso video): Apri WebcamLR, Chiudi;</item>
/// <item>sulla CAM 2: Usa prospettiva, Chiudi;</item>
/// <item>sulle schede dei telefoni: «Nella webcam», «Scollega…» (con la domanda del passo 4, ChiediScollega);</item>
/// <item>sui profili salvati (SuAperturaProfili): Applica, Elimina… (con la domanda del passo 4).</item>
/// </list>
/// Il tasto «Sfondo» e l'icona accanto all'orologio avevano già il loro menu.
/// </summary>
public sealed partial class MainWindow
{
    private readonly MenuFlyout menuVideo = new();
    private readonly MenuFlyout menuRiquadro = new();

    private void InizializzaMenu()
    {
        menuVideo.Opening += (_, _) => RiempiMenuVideo();
        RiquadroVideo.ContextFlyout = menuVideo;
        menuRiquadro.Opening += (_, _) => RiempiMenuRiquadro();
        RiquadroPiccolo.ContextFlyout = menuRiquadro;
        // Con un telefono solo la scheda è sempre la stessa: vale per quello nella webcam.
        SchedaTelefono.ContextFlyout = MenuTelefono(() => Scelto);
    }

    /// <summary>Il video; nella finestra mini solo «Apri WebcamLR» e «Chiudi».</summary>
    private void RiempiMenuVideo()
    {
        menuVideo.Items.Clear();
        if (InMini)
        {
            Voce(menuVideo, Testi.T("Tray_Apri"), () => ImpostaMini(false));
            // Chiudere la finestrella la nasconde accanto all'orologio, come la X; riaprendola torna la finestra intera.
            Voce(menuVideo, Testi.T("Chiudi"), () =>
            {
                ImpostaMini(false);
                NascondiFinestra();
            });
            return;
        }
        // Foto e Registra spiegano da sole se serve WebcamLR Pro (FotoDaTastiera, RegistraDaTastiera); senza telefono spente.
        Voce(menuVideo, Testi.T("Menu_Foto"), () => FotoDaTastiera(), "Ctrl+T", attiva: RipreseDisponibili);
        Voce(menuVideo, Testi.T("Menu_CopiaFotogramma"), () => _ = CopiaFotogrammaAsync(), "Ctrl+C", attiva: RipreseConsentite);
        Voce(menuVideo, registrazione is null ? Testi.T("Menu_Registra") : Testi.T("Tray_FermaRegistrazione"), () => RegistraDaTastiera(),
            "Ctrl+R", attiva: RipreseDisponibili || registrazione is not null);
        menuVideo.Items.Add(new MenuFlyoutSeparator());
        Interruttore(menuVideo, Testi.T("Menu_VistaPulita"), vistaPulita, () => ImpostaVistaPulita(!vistaPulita), Testi.T("Tasto_CtrlMaiuscP"));
        // «Riempi l'inquadratura» passa dall'interruttore della pagina «Schermo», che salva la scelta (SuRiempi).
        Interruttore(menuVideo, Testi.T("Menu_Riempi"), InterruttoreRiempi.IsOn, () => InterruttoreRiempi.IsOn = !InterruttoreRiempi.IsOn);
    }

    /// <summary>La CAM 2: «Usa prospettiva» solo quando l'altro telefono c'è davvero (non mentre si ricollega), «Chiudi».</summary>
    private void RiempiMenuRiquadro()
    {
        menuRiquadro.Items.Clear();
        var altro = telefoni.Altro;
        Voce(menuRiquadro, Testi.T("Menu_UsaProspettiva"), () => ScegliTelefono(telefoni.Altro), attiva: altro is { InRiconnessione: false });
        Voce(menuRiquadro, Testi.T("Chiudi"), () => ImpostaRiquadro(false));
    }

    /// <summary>La scheda di un telefono: «Nella webcam» (spunta su quello scelto) e «Scollega…», con la domanda se serve.</summary>
    private MenuFlyout MenuTelefono(Func<TelefonoCollegato?> quale)
    {
        var menu = new MenuFlyout();
        menu.Opening += (_, _) =>
        {
            menu.Items.Clear();
            var collegato = quale();
            var presente = collegato is not null && telefoni.Contiene(collegato);
            var scelto = presente && telefoni.ESelezionato(collegato!);
            Interruttore(menu, Testi.T("Telefoni_NellaWebcam"), scelto, () => { if (collegato is not null) ScegliTelefono(collegato); },
                attiva: presente && !scelto);
            Voce(menu, Testi.T("Menu_Scollega"), () => { if (collegato is not null) ChiediScollega(collegato); }, attiva: presente);
        };
        return menu;
    }

    /// <summary>Clic destro su un profilo salvato: Applica, Elimina… (la stessa domanda del sottomenu «Elimina»).</summary>
    private MenuFlyout MenuProfiloSalvato(string nome, Action applica)
    {
        var menu = new MenuFlyout();
        Voce(menu, Testi.T("Menu_Applica"), () =>
        {
            MenuProfili.Hide();
            applica();
        });
        Voce(menu, Testi.T("Menu_Elimina"), () =>
        {
            MenuProfili.Hide();
            ChiediEliminaProfilo(nome);
        });
        return menu;
    }

    private static void Voce(MenuFlyout menu, string testo, Action azione, string? tasto = null, bool attiva = true)
    {
        var voce = new MenuFlyoutItem { Text = testo, IsEnabled = attiva };
        if (tasto is not null) voce.KeyboardAcceleratorTextOverride = tasto;
        voce.Click += (_, _) => azione();
        menu.Items.Add(voce);
    }

    private static void Interruttore(MenuFlyout menu, string testo, bool acceso, Action azione, string? tasto = null, bool attiva = true)
    {
        var voce = new ToggleMenuFlyoutItem { Text = testo, IsChecked = acceso, IsEnabled = attiva };
        if (tasto is not null) voce.KeyboardAcceleratorTextOverride = tasto;
        voce.Click += (_, _) => azione();
        menu.Items.Add(voce);
    }
}
