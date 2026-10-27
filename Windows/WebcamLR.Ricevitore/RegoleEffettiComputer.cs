using System.Text.Json;
using System.Text.Json.Serialization;
using WebcamLR.Effetti;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Gli effetti sul computer (27 ottobre, «come iVCam»; Documenti/Effetti su Windows.md): con <see cref="EffettiSulComputer"/>
/// gli effetti di immagine li fa il motore del PC (WebcamLR.Effetti) dopo la decodifica, il telefono fa solo fotocamera e
/// codifica. Le stesse regole del Mac (Mac/Sorgenti/Ricevitore.swift, «Effetti sul computer»):
/// - il PC non manda più al telefono i comandi degli effetti di immagine (<see cref="PerIlTelefono"/>);
/// - all'arrivo del telefono gli chiede di spegnere i suoi (<see cref="SpegniEffettiDelTelefono"/>);
/// - le immagini caricate (sfondo personale, logo) restano sul PC;
/// - la finestra legge e scrive le scelte del motore (salvate nelle preferenze, <see cref="InTesto"/>);
/// - WebcamLR Pro: le regole le applica il PC in base a <c>capacita.pro</c> (<see cref="RegoleMotore"/>).
/// Doppia vista, postura e gobbo restano del telefono.
/// </summary>
public static class RegoleEffettiComputer
{
    /// <summary>L'interruttore: vero = gli effetti di immagine li fa il PC. Falso = come prima (comandi al telefono).</summary>
    public const bool EffettiSulComputer = true;

    /// <summary>
    /// Il comando che spegne gli effetti di immagine del telefono, in uno solo: sfondo nessuno, filtro naturale,
    /// regolazioni a 0, pelle 0, calore 0, scritta vuota, specchio e inquadratura spenti, luce sul volto spenta (la fa il
    /// PC). Doppia vista e postura restano come sono. Il logo salvato sul telefono non si cancella: senza scritta non si vede.
    /// </summary>
    public static Comando SpegniEffettiDelTelefono { get; } = new(
        Filtro: Filtri.Naturale, Regolazioni: new Regolazioni(0, 0, 0, 0), Sfondo: ModiSfondo.Nessuno, Pelle: 0,
        Inquadratura: false, LuceVolto: false, Scritta: Scritta.Nessuna, Specchia: false, Calore: 0);

    /// <summary>
    /// Il comando senza gli effetti di immagine (li applica il motore del PC): restano la fotocamera, l'audio, il
    /// collegamento, la doppia vista e la postura. Null se non resta niente da mandare.
    /// </summary>
    public static Comando? PerIlTelefono(Comando comando)
    {
        var restante = comando with
        {
            Filtro = null, Regolazioni = null, Sfondo = null, IntensitaSfondo = null, Pelle = null, Inquadratura = null,
            LuceVolto = null, Scritta = null, Specchia = null, ImmagineSfondo = null, TogliLogo = null, Calore = null,
        };
        return restante == new Comando() ? null : restante;
    }

    /// <summary>
    /// Cosa si può comandare, per le sezioni degli effetti (come <c>capacitaEffetti</c> del Mac): gli effetti di immagine li
    /// sa fare il PC con qualsiasi telefono (tutti i filtri, sfondo con gli sfondi pronti e le immagini, pelle, luce,
    /// inquadratura, scritta e logo, calore, specchio); il resto (doppia vista, postura, gobbo, fotocamera, Pro) è del
    /// telefono. Null senza capacità del telefono (non è ancora pronto).
    /// </summary>
    public static Capacita? CapacitaEffetti(Capacita? delTelefono, bool sulComputer = EffettiSulComputer)
    {
        if (delTelefono is null || !sulComputer) return delTelefono;
        return delTelefono with
        {
            Filtri = Filtri.Tutti, Sfondo = true, Pelle = true, Inquadratura = true, LuceVolto = true, Scritta = true,
            Calore = true, Specchia = true, Immagini = true, SfondiPronti = SfondiPronti.Tutti,
        };
    }

    // MARK: preferenze

    private static readonly JsonSerializerOptions Opzioni = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>Le scelte salvate nelle preferenze (JSON). Doppia vista e postura no: sono del telefono.</summary>
    private sealed record Salvati(string? Filtro, double Luminosita, double Contrasto, double Saturazione, double Nitidezza,
        string? Sfondo, double IntensitaSfondo, string? ImmagineSfondo, double Pelle, bool Inquadratura, bool LuceVolto,
        string? Nome, string? Ruolo, bool Specchia, double Calore);

    /// <summary>La prima volta: tutto spento e il calore a 0,3, come lo propone il telefono.</summary>
    public static ValoriEffetti Iniziali { get; } = ValoriEffetti.Iniziali with { Calore = 0.3 };

    public static string InTesto(ValoriEffetti v) => JsonSerializer.Serialize(new Salvati(v.Filtro, v.Luminosita, v.Contrasto,
        v.Saturazione, v.Nitidezza, v.Sfondo, v.IntensitaSfondo, v.ImmagineSfondo, v.Pelle, v.Inquadratura, v.LuceVolto,
        v.Scritta.Nome, v.Scritta.Ruolo, v.Specchia, v.Calore), Opzioni);

    /// <summary>Dalle preferenze; un testo mancante o rovinato vale <see cref="Iniziali"/>. I valori si portano nei limiti.</summary>
    public static ValoriEffetti DaTesto(string? testo)
    {
        if (string.IsNullOrWhiteSpace(testo)) return Iniziali;
        try
        {
            var s = JsonSerializer.Deserialize<Salvati>(testo, Opzioni);
            if (s is null) return Iniziali;
            // Passano dalle stesse regole di un comando: un valore fuori dai limiti o sconosciuto torna valido.
            return ValoriEffetti.Iniziali.Applica(new Comando(Filtro: s.Filtro ?? Filtri.Naturale,
                Regolazioni: new Regolazioni(s.Luminosita, s.Contrasto, s.Saturazione, s.Nitidezza), Sfondo: s.Sfondo ?? ModiSfondo.Nessuno,
                IntensitaSfondo: s.IntensitaSfondo, Pelle: s.Pelle, Inquadratura: s.Inquadratura, LuceVolto: s.LuceVolto,
                Scritta: new Scritta(s.Nome ?? "", string.IsNullOrWhiteSpace(s.Ruolo) ? null : s.Ruolo), Specchia: s.Specchia,
                ImmagineSfondo: s.ImmagineSfondo, Calore: s.Calore)) with
            {
                Filtro = NomiEffetti.FiltroValido(s.Filtro),
            };
        }
        catch (JsonException)
        {
            return Iniziali;
        }
    }
}

/// <summary>
/// Dalle scelte della finestra a ciò che il motore applica (come <c>aggiornaMotore</c> del Mac), con le regole di WebcamLR
/// Pro del telefono nella webcam (<c>capacita.pro</c>): gratis la sfocatura, il calore, la luce sul volto e lo specchio;
/// il resto (sfondo sostituito, filtri, regolazioni, pelle, inquadratura, scritta e logo) solo con Pro. Specchio e sfondo
/// solo con la fotocamera frontale (<c>stato.obiettivo</c>), come oggi: con la posteriore niente specchio e niente sfondo.
/// Con la sfocatura o la luce del sistema del telefono accese (Ritratto, Luce da studio) le nostre restano spente: mai due.
/// </summary>
public static class RegoleMotore
{
    /// <param name="immagineSfondo">Con lo sfondo sostituito: l'immagine da mostrare (<see cref="RegoleSfondo.ImmagineAttuale"/>).</param>
    /// <param name="logo">Il PC ha un logo caricato.</param>
    public static ImpostazioniMotore Da(ValoriEffetti scelti, bool pro, StatoTelefono? stato, string? immagineSfondo, bool logo)
    {
        var frontale = !SoloFrontale.Posteriore(stato);
        var sfocaturaSistema = EffettiDelSistema.Sfocatura(stato);
        var luceSistema = EffettiDelSistema.Luce(stato);
        var motore = new ImpostazioniMotore
        {
            Calore = scelti.Calore,
            Specchia = scelti.Specchia && frontale,
            LuceVolto = scelti.LuceVolto && !luceSistema,
        };
        var sfocato = scelti.Sfondo == ModiSfondo.Sfocato && !sfocaturaSistema;
        var sostituito = scelti.Sfondo == ModiSfondo.Sostituito && pro && immagineSfondo is not null;
        if (frontale && (sfocato || sostituito))
        {
            motore = motore with
            {
                Sfondo = scelti.Sfondo,
                IntensitaSfondo = scelti.IntensitaSfondo,
                ImmagineSfondo = sostituito ? immagineSfondo : null,
            };
        }
        if (!pro) return motore;
        var scritta = scelti.ScrittaMostrata ? scelti.Scritta : Scritta.Nessuna;
        return motore with
        {
            Filtro = NomiEffetti.FiltroValido(scelti.Filtro),
            Luminosita = scelti.Luminosita,
            Contrasto = scelti.Contrasto,
            Saturazione = scelti.Saturazione,
            Nitidezza = scelti.Nitidezza,
            Pelle = scelti.Pelle,
            Inquadratura = scelti.Inquadratura,
            Nome = (scritta.Nome ?? "").Trim(),
            Ruolo = (scritta.Ruolo ?? "").Trim(),
            // Il logo in alto a destra, come il motore del Mac: c'è finché il PC ne ha uno («Togli logo» lo cancella).
            Logo = logo,
        };
    }
}
