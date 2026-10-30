using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Windows.UI.ViewManagement;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Interruzioni dette e stato sempre visibile (1.0 beta 2, passi 5 e 6; windows.md 2.1, 2.10, 2.13, 2.16, N3, N4, N9):
/// <list type="bullet">
/// <item>ogni avviso scrive una riga nel registro e l'Assistente vocale lo dice (<see cref="Avvisa"/>);</item>
/// <item>gli errori restano nella barra sopra il video finché non li chiudi (<see cref="MostraErrore"/>);</item>
/// <item>il telefono che non torna lascia un banner fisso sopra il video, come sul Mac, che si toglie quando torna;</item>
/// <item>l'icona accanto all'orologio segue in onda, registrazione e riconnessione (<see cref="AggiornaIcona"/>);</item>
/// <item>i comandi spenti si raggiungono con Tab e spiegano il perché anche con Invio o Spazio (CoperturaSpenta);</item>
/// <item>con «Effetti di animazione» spenti in Windows niente animazioni di pannello e colonne, niente lampo.</item>
/// </list>
/// </summary>
public sealed partial class MainWindow
{
    // MARK: registro e Assistente vocale

    /// <summary>Un avviso: una riga nel registro e lo stesso testo detto dall'Assistente vocale.</summary>
    private void Avvisa(string testo)
    {
        registro.Aggiungi(testo);
        Annuncia(testo);
    }

    /// <summary>
    /// L'Assistente vocale dice <paramref name="testo"/> senza spostare il fuoco: una notifica UI Automation sulla pillola
    /// dello stato, che c'è sempre. Il più recente prende il posto di quelli non ancora letti.
    /// </summary>
    private void Annuncia(string testo)
    {
        try
        {
            if (TestoStato is null) return;
            var peer = FrameworkElementAutomationPeer.FromElement(TestoStato) ?? FrameworkElementAutomationPeer.CreatePeerForElement(TestoStato);
            peer?.RaiseNotificationEvent(AutomationNotificationKind.Other, AutomationNotificationProcessing.ImportantMostRecent,
                testo, "avviso-webcamlr");
        }
        catch (Exception) { }
    }

    // MARK: errori che restano

    /// <summary>
    /// Un errore nella barra sopra il video (windows.md 2.1): resta finché non lo si chiude con la X; uno nuovo prende il
    /// posto di quello di prima. Nel registro (salvo <paramref name="registra"/> falso) e detto dall'Assistente vocale.
    /// </summary>
    private void MostraErrore(string testo, bool registra = true, InfoBarSeverity severita = InfoBarSeverity.Error)
    {
        if (registra) Avvisa(testo);
        else Annuncia(testo);
        BarraErrore.Severity = severita;
        BarraErrore.Message = testo;
        BarraErrore.IsOpen = true;
    }

    // MARK: telefono perso (passo 5)

    /// <summary>Il nome del telefono nel banner «… non è tornato», se il banner è aperto.</summary>
    private string? telefonoPerso;

    /// <summary>
    /// «iPhone di Ledion non è tornato. Riapri WebcamLR sul telefono.» sopra il video, con «Il telefono non trova il PC?»
    /// e la X; resta finché non lo chiudi o il telefono torna (come il Mac nel passo 2). La riga nel registro c'è già.
    /// </summary>
    private void MostraTelefonoPerso(string nome)
    {
        telefonoPerso = nome;
        var testo = Testi.T("TelefonoPerso_Banner", nome);
        BarraTelefonoPerso.Message = testo;
        BarraTelefonoPerso.IsOpen = true;
        Annuncia(testo);
    }

    /// <summary>Quando un telefono si collega: se è quello perso, il banner si toglie.</summary>
    private void NascondiTelefonoPerso(string nome)
    {
        if (telefonoPerso is null || !string.Equals(telefonoPerso, nome, StringComparison.Ordinal)) return;
        telefonoPerso = null;
        BarraTelefonoPerso.IsOpen = false;
    }

    private void InizializzaAvvisi()
    {
        BarraTelefonoPerso.CloseButtonClick += (_, _) => telefonoPerso = null;
        foreach (var copertura in Coperture) copertura.SpiegazioneChiesta += (origine, _) => MostraNotaSpenta((FrameworkElement)origine!, null);
    }

    // MARK: spazio sul disco

    /// <summary>Vero dopo la riga «Spazio quasi finito» nel registro: la fine si scrive una volta, se si registra ancora.</summary>
    private bool spazioScarsoDetto;

    /// <summary>Lo spazio quasi finito resta in ambra finché c'è (MostraRegistrazione); qui inizio e fine nel registro.</summary>
    private void RegistraSpazio(bool scarso)
    {
        if (scarso == spazioScarsoDetto) return;
        spazioScarsoDetto = scarso;
        if (scarso && spazioScarso is (int minuti, _)) Avvisa(Riprese.AvvisoSpazio(minuti));
        else if (!scarso && registrazione is not null) Avvisa(Testi.T("Riprese_SpazioDiNuovo"));
    }

    // MARK: icona accanto all'orologio (passo 6)

    /// <summary>
    /// Icona, riga del menu e suggerimento dell'icona accanto all'orologio, da tutto quello che si sa adesso: collegamento,
    /// in onda (con le app), registrazione. Si chiama a ogni cambio e ogni secondo mentre si registra.
    /// </summary>
    private void AggiornaIcona()
    {
        iconaTray?.Aggiorna(new StatoNotifica(statoCollegamento, telefono?.Nome, statistiche?.LatenzaMs, inOnda, appInUsoAttuali,
            registrazione is null ? null : DateTime.UtcNow - inizioRegistrazione, InPausa));
    }

    // MARK: comandi spenti (windows.md 2.13)

    private IEnumerable<CoperturaSpenta> Coperture =>
    [
        CoperturaSpecchia, CoperturaSfondoVideo, CoperturaRiprese, CoperturaRegistra,
        CoperturaProfilo, CoperturaComandi, CoperturaEffetti, CoperturaRegoleFini,
    ];

    /// <summary>Il nome che l'Assistente vocale legge prima di «non disponibile»: il tasto o la sezione coperta.</summary>
    private string? NomeCoperto(CoperturaSpenta copertura) =>
        ReferenceEquals(copertura, CoperturaSpecchia) ? TestoSpecchia.Text
        : ReferenceEquals(copertura, CoperturaSfondoVideo) ? TestoSfondoVideo.Text
        : ReferenceEquals(copertura, CoperturaRiprese) ? TestoPulsanteFoto.Text
        : ReferenceEquals(copertura, CoperturaRegistra) ? TestoRegistra.Text
        : ReferenceEquals(copertura, CoperturaProfilo) ? NomeSezioneProfilo.Text
        : ReferenceEquals(copertura, CoperturaComandi) ? TitoloFotocamera.Text
        : ReferenceEquals(copertura, CoperturaEffetti) ? NomeSezioneEffetti.Text
        : ReferenceEquals(copertura, CoperturaRegoleFini) ? NomeSezioneRegoleFini.Text
        : null;

    /// <summary>Perché il comando sotto la copertura è spento: la stessa frase della nota che si apre.</summary>
    private string MotivoSpento(FrameworkElement copertura)
    {
        // «Specchia» e «Sfondo» con la fotocamera posteriore: la stessa copertura dice perché sono grigi.
        var soloFrontale = SoloFrontaleBloccati
            && (ReferenceEquals(copertura, CoperturaSpecchia) || ReferenceEquals(copertura, CoperturaSfondoVideo));
        return soloFrontale ? Testi.T("Comandi_SoloFrontale")
            : telefono is not null && statoCollegamento == FaseCollegamento.Riconnessione
            ? Testi.T("Comandi_MiRicollegoBreve")
            : telefono is not null ? Testi.T("Comandi_TraUnAttimo")
            : Testi.T("Comandi_CollegaUnTelefono");
    }

    /// <summary>
    /// Il motivo in <c>AutomationProperties.HelpText</c> delle coperture a vista e dei tasti spenti sotto, e il nome
    /// «Specchia, non disponibile: solo con la fotocamera frontale» sulla copertura, che è quella che prende il fuoco.
    /// </summary>
    private void AggiornaCoperture()
    {
        if (CoperturaSpecchia is null) return;
        foreach (var copertura in Coperture)
        {
            if (copertura.Visibility != Visibility.Visible) continue;
            copertura.Descrivi(NomeCoperto(copertura), MotivoSpento(copertura));
        }
        foreach (var (copertura, tasto) in new (CoperturaSpenta, Control)[]
                 {
                     (CoperturaSpecchia, PulsanteSpecchia), (CoperturaSfondoVideo, PulsanteSfondoVideo),
                     (CoperturaRiprese, PulsanteFoto), (CoperturaRegistra, PulsanteRegistra),
                 })
        {
            AutomationProperties.SetHelpText(tasto, copertura.Visibility == Visibility.Visible ? MotivoSpento(copertura) : "");
        }
    }

    // MARK: «Effetti di animazione» (windows.md N9)

    private static readonly UISettings impostazioniSistema = new();

    /// <summary>Falso se in Windows «Effetti di animazione» è spento (Accessibilità › Effetti visivi): niente animazioni.</summary>
    private static bool AnimazioniAttive
    {
        get
        {
            try { return impostazioniSistema.AnimationsEnabled; }
            catch (Exception) { return true; }
        }
    }
}
