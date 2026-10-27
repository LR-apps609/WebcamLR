using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>I nomi mostrati per gli effetti del telefono (Documenti/Protocollo.md, «Effetti»): gli identificativi restano quelli del protocollo.</summary>
public static class NomiEffetti
{
    /// <summary>Il nome di un filtro nella lingua attuale; uno sconosciuto (telefono più nuovo) si mostra con il suo identificativo, leggibile.</summary>
    public static string Filtro(string id) => id switch
    {
        Filtri.Naturale => TestiRicevitore.T("Filtro_Naturale"),
        Filtri.Caldo => TestiRicevitore.T("Filtro_Caldo"),
        Filtri.Freddo => TestiRicevitore.T("Filtro_Freddo"),
        Filtri.Luminoso => TestiRicevitore.T("Filtro_Luminoso"),
        Filtri.Cinema => TestiRicevitore.T("Filtro_Cinema"),
        Filtri.Vivido => TestiRicevitore.T("Filtro_Vivido"),
        Filtri.Tenue => TestiRicevitore.T("Filtro_Tenue"),
        Filtri.BiancoNero => TestiRicevitore.T("Filtro_BiancoNero"),
        Filtri.Seppia => TestiRicevitore.T("Filtro_Seppia"),
        Filtri.Notte => TestiRicevitore.T("Filtro_Notte"),
        "" => TestiRicevitore.T("Filtro_Naturale"),
        _ => char.ToUpperInvariant(id[0]) + id[1..].Replace('-', ' '),
    };

    /// <summary>I modi dello sfondo, nell'ordine in cui mostrarli.</summary>
    public static IReadOnlyList<string> ModiSfondo { get; } = [Protocollo.ModiSfondo.Nessuno, Protocollo.ModiSfondo.Sfocato, Protocollo.ModiSfondo.Sostituito];

    public static string Sfondo(string modo) => modo switch
    {
        Protocollo.ModiSfondo.Sfocato => TestiRicevitore.T("Sfondo_Sfocato"),
        Protocollo.ModiSfondo.Sostituito => TestiRicevitore.T("Sfondo_Sostituito"),
        _ => TestiRicevitore.T("Sfondo_Nessuno"),
    };

    /// <summary>Un valore da 0 a 1 come percentuale all'italiana: «40%».</summary>
    public static string Percentuale(double valore) => $"{Math.Round(Math.Clamp(valore, 0, 1) * 100):0}%";

    /// <summary>Un filtro sconosciuto vale «naturale» (Protocollo.md).</summary>
    public static string FiltroValido(string? id, IReadOnlyList<string>? disponibili = null) =>
        id is not null && (Filtri.Tutti.Contains(id) || disponibili?.Contains(id) == true) ? id : Filtri.Naturale;

    /// <summary>Uno sfondo sconosciuto vale «nessuno» (Protocollo.md).</summary>
    public static string SfondoValido(string? modo) =>
        modo is Protocollo.ModiSfondo.Sfocato or Protocollo.ModiSfondo.Sostituito ? modo : Protocollo.ModiSfondo.Nessuno;
}

/// <summary>I tre livelli della sfocatura di «Sfondo» sotto il video: Poco (morbido), Medio, Tanto. Gratis, come la sfocatura.</summary>
public enum LivelloSfocatura
{
    Poco,
    Medio,
    Tanto,
}

/// <summary>
/// Intensità, nomi e preferenza dei livelli della sfocatura. Ognuno è un'intensità dello sfondo sfocato
/// (<c>comando.intensitaSfondo</c>); un clic su «Sfondo», se l'ultima scelta è la sfocatura, usa l'ultimo livello scelto.
/// </summary>
public static class LivelliSfocatura
{
    public static IReadOnlyList<LivelloSfocatura> Tutti { get; } = [LivelloSfocatura.Poco, LivelloSfocatura.Medio, LivelloSfocatura.Tanto];

    public static double Intensita(LivelloSfocatura livello) => livello switch
    {
        LivelloSfocatura.Poco => 0.25,
        LivelloSfocatura.Tanto => 1.0,
        _ => 0.55,
    };

    public static string Nome(LivelloSfocatura livello) => livello switch
    {
        LivelloSfocatura.Poco => TestiRicevitore.T("Sfocatura_Poco"),
        LivelloSfocatura.Tanto => TestiRicevitore.T("Sfocatura_Tanto"),
        _ => TestiRicevitore.T("Sfocatura_Medio"),
    };

    /// <summary>Il livello più vicino a un'intensità (quella che il telefono conferma in <c>stato.intensitaSfondo</c>).</summary>
    public static LivelloSfocatura Vicino(double intensita) =>
        Tutti.MinBy(livello => Math.Abs(Intensita(livello) - intensita));

    /// <summary>Come si salva nelle preferenze: «poco», «medio», «tanto».</summary>
    public static string Id(LivelloSfocatura livello) => livello switch
    {
        LivelloSfocatura.Poco => "poco",
        LivelloSfocatura.Tanto => "tanto",
        _ => "medio",
    };

    /// <summary>Dalle preferenze; un valore mancante o sconosciuto vale «Medio».</summary>
    public static LivelloSfocatura Da(string? id) => id switch
    {
        "poco" => LivelloSfocatura.Poco,
        "tanto" => LivelloSfocatura.Tanto,
        _ => LivelloSfocatura.Medio,
    };
}

/// <summary>Cosa il telefono sa fare tra gli effetti, da <see cref="Capacita"/>: solo questo si mostra nella colonna «Effetti».</summary>
public sealed record DisponibilitaEffetti(IReadOnlyList<string> Filtri, bool Sfondo, bool Pelle, bool Inquadratura,
    bool LuceVolto, bool Scritta, bool DoppiaVista, bool Postura, bool Gobbo)
{
    /// <summary>Le regolazioni ci sono sempre quando ci sono i filtri.</summary>
    public bool Regolazioni => Filtri.Count > 0;

    /// <summary>Falso per un telefono che non conosce gli effetti (versione vecchia).</summary>
    public bool Qualcuno => Filtri.Count > 0 || Sfondo || Pelle || Inquadratura || LuceVolto || Scritta || DoppiaVista || Postura || Gobbo;

    public static DisponibilitaEffetti Nessuno { get; } = new([], false, false, false, false, false, false, false, false);

    /// <summary>Senza telefono si vede come sarà: tutto, tranne la doppia vista che dipende dal telefono.</summary>
    public static DisponibilitaEffetti Esempio { get; } = new(Protocollo.Filtri.Tutti, true, true, true, true, true, false, true, true);

    public static DisponibilitaEffetti Da(Capacita capacita)
    {
        var filtri = (capacita.Filtri ?? []).Where(f => !string.IsNullOrWhiteSpace(f)).Distinct().ToList();
        // «naturale» è il ritorno a nessun filtro: c'è sempre, in testa se il telefono l'ha dimenticato.
        if (filtri.Count > 0 && !filtri.Contains(Protocollo.Filtri.Naturale)) filtri.Insert(0, Protocollo.Filtri.Naturale);
        return new(filtri, capacita.Sfondo == true, capacita.Pelle == true, capacita.Inquadratura == true,
            capacita.LuceVolto == true, capacita.Scritta == true, capacita.DoppiaVista == true, capacita.Postura == true,
            capacita.Gobbo == true);
    }

    public bool Equals(DisponibilitaEffetti? altra) =>
        altra is not null && Filtri.SequenceEqual(altra.Filtri) && Sfondo == altra.Sfondo && Pelle == altra.Pelle
        && Inquadratura == altra.Inquadratura && LuceVolto == altra.LuceVolto && Scritta == altra.Scritta
        && DoppiaVista == altra.DoppiaVista && Postura == altra.Postura && Gobbo == altra.Gobbo;

    public override int GetHashCode() => HashCode.Combine(Filtri.Count, Sfondo, Pelle, Inquadratura, Scritta, Gobbo);
}

/// <summary>Gli effetti come li mostra la finestra: quelli del telefono, più i cambi fatti qui e non ancora confermati.</summary>
/// <param name="Scritta">Nome vuoto = nessuna scritta.</param>
public sealed record ValoriEffetti(string Filtro, double Luminosita, double Contrasto, double Saturazione, double Nitidezza,
    string Sfondo, double IntensitaSfondo, double Pelle, bool Inquadratura, bool LuceVolto, Scritta Scritta,
    bool DoppiaVista, bool Postura, bool Specchia = false, string? ImmagineSfondo = null, string? ImmaginePersonale = null,
    string? Logo = null)
{
    public static ValoriEffetti Iniziali { get; } = new(Filtri.Naturale, 0, 0, 0, 0, ModiSfondo.Nessuno, 0.5, 0,
        false, false, Scritta.Nessuna, false, false);

    public bool RegolazioniNeutre => Luminosita == 0 && Contrasto == 0 && Saturazione == 0 && Nitidezza == 0;

    public bool ScrittaMostrata => (Scritta.Nome ?? "").Trim().Length > 0;

    /// <summary>Lo sfondo è sfocato (non «sostituito»).</summary>
    public bool SfondoSfocato => Sfondo == ModiSfondo.Sfocato;

    /// <summary>Sfocato o sostituito: il pulsante «Sfondo» sotto il video è acceso.</summary>
    public bool SfondoAcceso => Sfondo != ModiSfondo.Nessuno;

    /// <summary>I campi presenti nel comando, con i valori portati nei limiti.</summary>
    public ValoriEffetti Applica(Comando comando) => Applica(new CampiEffetti(comando.Filtro, comando.Regolazioni,
        comando.Sfondo, comando.IntensitaSfondo, comando.Pelle, comando.Inquadratura, comando.LuceVolto, comando.Scritta,
        comando.DoppiaVista, comando.Postura, comando.Specchia, comando.ImmagineSfondo), _ => false);

    /// <summary>
    /// I campi presenti nello stato del telefono. <paramref name="salta"/> dice quali tenere come sono:
    /// quelli appena cambiati qui, che lo stato (partito prima) riporterebbe indietro mentre si trascina un cursore.
    /// Le impronte dell'immagine personale e del logo seguono sempre lo stato: assenti = il telefono non ne ha.
    /// </summary>
    public ValoriEffetti Applica(StatoTelefono stato, Func<string, bool> salta) => Applica(new CampiEffetti(stato.Filtro,
        stato.Regolazioni, stato.Sfondo, stato.IntensitaSfondo, stato.Pelle, stato.Inquadratura, stato.LuceVolto,
        stato.Scritta, stato.DoppiaVista, stato.Postura, stato.Specchia, stato.ImmagineSfondo), salta)
        with { ImmaginePersonale = stato.ImmaginePersonale, Logo = stato.Logo };

    private ValoriEffetti Applica(CampiEffetti c, Func<string, bool> salta)
    {
        var nuovi = this;
        if (c.Filtro is { } filtro && !salta(CampoEffetto.Filtro)) nuovi = nuovi with { Filtro = filtro.Length == 0 ? Filtri.Naturale : filtro };
        if (c.Regolazioni is { } r)
        {
            if (r.Luminosita is double l && !salta(CampoEffetto.Luminosita)) nuovi = nuovi with { Luminosita = Regolazione(l) };
            if (r.Contrasto is double co && !salta(CampoEffetto.Contrasto)) nuovi = nuovi with { Contrasto = Regolazione(co) };
            if (r.Saturazione is double s && !salta(CampoEffetto.Saturazione)) nuovi = nuovi with { Saturazione = Regolazione(s) };
            if (r.Nitidezza is double n && !salta(CampoEffetto.Nitidezza)) nuovi = nuovi with { Nitidezza = Regolazione(n) };
        }
        if (c.Sfondo is { } sfondo && !salta(CampoEffetto.Sfondo)) nuovi = nuovi with { Sfondo = NomiEffetti.SfondoValido(sfondo) };
        if (c.IntensitaSfondo is double i && !salta(CampoEffetto.IntensitaSfondo)) nuovi = nuovi with { IntensitaSfondo = Unitario(i) };
        if (c.Pelle is double p && !salta(CampoEffetto.Pelle)) nuovi = nuovi with { Pelle = Unitario(p) };
        if (c.Inquadratura is bool q && !salta(CampoEffetto.Inquadratura)) nuovi = nuovi with { Inquadratura = q };
        if (c.LuceVolto is bool v && !salta(CampoEffetto.LuceVolto)) nuovi = nuovi with { LuceVolto = v };
        if (c.Scritta is { } scritta && !salta(CampoEffetto.Scritta)) nuovi = nuovi with { Scritta = scritta with { Nome = scritta.Nome ?? "" } };
        if (c.DoppiaVista is bool d && !salta(CampoEffetto.DoppiaVista)) nuovi = nuovi with { DoppiaVista = d };
        if (c.Postura is bool po && !salta(CampoEffetto.Postura)) nuovi = nuovi with { Postura = po };
        // Lo specchio è uno solo, del telefono (1.14): il PC mostra quello che il telefono dice di mandare.
        if (c.Specchia is bool sp && !salta(CampoEffetto.Specchia)) nuovi = nuovi with { Specchia = sp };
        // Quale immagine dello sfondo sostituito: ha la precedenza di «sfondo», con cui parte sempre.
        if (c.ImmagineSfondo is { } immagine && !salta(CampoEffetto.Sfondo)) nuovi = nuovi with { ImmagineSfondo = immagine };
        return nuovi;
    }

    private static double Regolazione(double valore) => double.IsFinite(valore) ? Math.Clamp(valore, -1, 1) : 0;

    private static double Unitario(double valore) => double.IsFinite(valore) ? Math.Clamp(valore, 0, 1) : 0;

    private sealed record CampiEffetti(string? Filtro, Regolazioni? Regolazioni, string? Sfondo, double? IntensitaSfondo,
        double? Pelle, bool? Inquadratura, bool? LuceVolto, Scritta? Scritta, bool? DoppiaVista, bool? Postura, bool? Specchia,
        string? ImmagineSfondo);
}

/// <summary>I nomi dei singoli campi degli effetti, per sapere quali sono stati appena cambiati dalla finestra.</summary>
public static class CampoEffetto
{
    public const string Filtro = "filtro";
    public const string Luminosita = "regolazioni.luminosita";
    public const string Contrasto = "regolazioni.contrasto";
    public const string Saturazione = "regolazioni.saturazione";
    public const string Nitidezza = "regolazioni.nitidezza";
    public const string Sfondo = "sfondo";
    public const string IntensitaSfondo = "intensitaSfondo";
    public const string Pelle = "pelle";
    public const string Inquadratura = "inquadratura";
    public const string LuceVolto = "luceVolto";
    public const string Scritta = "scritta";
    public const string DoppiaVista = "doppiaVista";
    public const string Postura = "postura";
    public const string Specchia = "specchia";
    public const string ImmagineSfondo = "immagineSfondo";

    /// <summary>I campi degli effetti presenti in un comando.</summary>
    public static IEnumerable<string> Di(Comando comando)
    {
        if (comando.Filtro is not null) yield return Filtro;
        if (comando.Regolazioni?.Luminosita is not null) yield return Luminosita;
        if (comando.Regolazioni?.Contrasto is not null) yield return Contrasto;
        if (comando.Regolazioni?.Saturazione is not null) yield return Saturazione;
        if (comando.Regolazioni?.Nitidezza is not null) yield return Nitidezza;
        if (comando.Sfondo is not null) yield return Sfondo;
        if (comando.IntensitaSfondo is not null) yield return IntensitaSfondo;
        if (comando.Pelle is not null) yield return Pelle;
        if (comando.Inquadratura is not null) yield return Inquadratura;
        if (comando.LuceVolto is not null) yield return LuceVolto;
        if (comando.Scritta is not null) yield return Scritta;
        if (comando.DoppiaVista is not null) yield return DoppiaVista;
        if (comando.Postura is not null) yield return Postura;
        if (comando.Specchia is not null) yield return Specchia;
        if (comando.ImmagineSfondo is not null) yield return ImmagineSfondo;
    }
}

public static class Comandi
{
    /// <summary>Un comando solo con i campi di tutti e due; per un campo presente in entrambi vale <paramref name="dopo"/>.</summary>
    public static Comando Unisci(Comando prima, Comando dopo) => new(
        dopo.Obiettivo ?? prima.Obiettivo, dopo.Zoom ?? prima.Zoom, dopo.Torcia ?? prima.Torcia,
        dopo.Esposizione ?? prima.Esposizione, dopo.Bianco ?? prima.Bianco, dopo.Fuoco ?? prima.Fuoco,
        dopo.Iso ?? prima.Iso, dopo.Tempo ?? prima.Tempo,
        dopo.Filtro ?? prima.Filtro, Unisci(prima.Regolazioni, dopo.Regolazioni), dopo.Sfondo ?? prima.Sfondo,
        dopo.IntensitaSfondo ?? prima.IntensitaSfondo, dopo.Pelle ?? prima.Pelle, dopo.Inquadratura ?? prima.Inquadratura,
        dopo.LuceVolto ?? prima.LuceVolto, dopo.Scritta ?? prima.Scritta, dopo.DoppiaVista ?? prima.DoppiaVista,
        dopo.Postura ?? prima.Postura, dopo.Audio ?? prima.Audio, dopo.Specchia ?? prima.Specchia,
        dopo.Collegamento ?? prima.Collegamento, dopo.ImmagineSfondo ?? prima.ImmagineSfondo, dopo.TogliLogo ?? prima.TogliLogo);

    private static Regolazioni? Unisci(Regolazioni? prima, Regolazioni? dopo) =>
        prima is null ? dopo
        : dopo is null ? prima
        : new(dopo.Luminosita ?? prima.Luminosita, dopo.Contrasto ?? prima.Contrasto,
            dopo.Saturazione ?? prima.Saturazione, dopo.Nitidezza ?? prima.Nitidezza);

    /// <summary>
    /// La scritta da mandare: con «Mostra» acceso e un nome, nome e ruolo (il ruolo vuoto non si scrive);
    /// altrimenti la scritta vuota, che la toglie (Protocollo.md: nome vuoto = nessuna scritta).
    /// </summary>
    public static Scritta Scritta(string? nome, string? ruolo, bool mostra)
    {
        var n = (nome ?? "").Trim();
        if (!mostra || n.Length == 0) return Protocollo.Scritta.Nessuna;
        var r = (ruolo ?? "").Trim();
        return new(n, r.Length == 0 ? null : r);
    }
}

/// <summary>
/// La colonna «Effetti» del computer, senza interfaccia: cosa il telefono sa fare, i valori da mostrare e i comandi da mandare.
/// I cursori si raccolgono: il primo cambio fa partire un'attesa di <see cref="Ritardo"/>, i cambi che arrivano nel
/// frattempo si uniscono e allo scadere parte un solo comando con i valori più recenti (al massimo dieci al secondo
/// mentre si trascina). Interruttori ed elenchi partono subito, con dentro anche i cursori in attesa.
/// Lo stato del telefono aggiorna i valori, tranne i campi cambiati qui da meno di <see cref="Protezione"/>.
/// Non è thread-safe: la usa solo il thread dell'interfaccia.
/// </summary>
public sealed class ControlloEffetti
{
    public static readonly TimeSpan RitardoPredefinito = TimeSpan.FromMilliseconds(100);
    public static readonly TimeSpan ProtezionePredefinita = TimeSpan.FromMilliseconds(1500);

    private readonly Dictionary<string, long> toccati = [];
    private Comando? inAttesa;

    public ControlloEffetti(TimeSpan? ritardo = null, TimeSpan? protezione = null)
    {
        Ritardo = ritardo ?? RitardoPredefinito;
        Protezione = protezione ?? ProtezionePredefinita;
    }

    public TimeSpan Ritardo { get; }
    public TimeSpan Protezione { get; }
    public ValoriEffetti Valori { get; private set; } = ValoriEffetti.Iniziali;
    public DisponibilitaEffetti Disponibili { get; private set; } = DisponibilitaEffetti.Nessuno;

    /// <summary>Vero se c'è un comando dei cursori in attesa di partire.</summary>
    public bool InAttesa => inAttesa is not null;

    /// <summary>Vero se le capacità sono cambiate (allora la colonna si ridisegna).</summary>
    public bool Capacita(Capacita capacita)
    {
        var nuove = DisponibilitaEffetti.Da(capacita);
        if (nuove.Equals(Disponibili)) return false;
        Disponibili = nuove;
        return true;
    }

    /// <summary>Lo stato del telefono; vero se i valori mostrati cambiano.</summary>
    public bool Stato(StatoTelefono stato, long adessoMs)
    {
        var protezione = (long)Protezione.TotalMilliseconds;
        var nuovi = Valori.Applica(stato, campo =>
            (inAttesa is not null && CampoEffetto.Di(inAttesa).Contains(campo))
            || (toccati.TryGetValue(campo, out var quando) && adessoMs - quando < protezione));
        if (nuovi == Valori) return false;
        Valori = nuovi;
        return true;
    }

    /// <summary>
    /// Un cursore cambiato: il comando aspetta. Restituisce vero se è il primo dell'attesa, cioè se bisogna far partire
    /// il timer di <see cref="Ritardo"/>, allo scadere del quale si chiama <see cref="Scaduto"/>.
    /// </summary>
    public bool Cambia(Comando comando, long adessoMs)
    {
        Segna(comando, adessoMs);
        var primo = inAttesa is null;
        inAttesa = primo ? comando : Comandi.Unisci(inAttesa!, comando);
        return primo;
    }

    /// <summary>Il comando raccolto dai cursori, da mandare adesso; null se non c'è niente.</summary>
    public Comando? Scaduto()
    {
        var pronto = inAttesa;
        inAttesa = null;
        return pronto;
    }

    /// <summary>Un interruttore o un elenco: parte subito, insieme ai cursori in attesa.</summary>
    public Comando Subito(Comando comando, long adessoMs)
    {
        Segna(comando, adessoMs);
        var tutto = inAttesa is null ? comando : Comandi.Unisci(inAttesa, comando);
        inAttesa = null;
        return tutto;
    }

    /// <summary>
    /// «Specchia» (1.14): il comando che gira lo specchio di adesso. Il pulsante segue lo <c>stato</c> del telefono
    /// (l'unica fonte di verità); per un attimo mostra la scelta appena fatta, finché lo stato non la conferma.
    /// </summary>
    public Comando AlternaSpecchio(long adessoMs) => Subito(new Comando(Specchia: !Valori.Specchia), adessoMs);

    /// <summary>Sfondo tolto («Nessuno» nel menu di «Sfondo»).</summary>
    public Comando TogliSfondo(long adessoMs) => Subito(new Comando(Sfondo: ModiSfondo.Nessuno), adessoMs);

    /// <summary>
    /// Uno sfondo pronto o <see cref="SfondiPronti.Personale"/> (sfondo «sostituito», WebcamLR Pro), in un solo comando.
    /// </summary>
    public Comando SostituisciSfondo(string immagine, long adessoMs) =>
        Subito(new Comando(Sfondo: ModiSfondo.Sostituito, ImmagineSfondo: immagine), adessoMs);

    /// <summary>
    /// «Sfoca sfondo» a un clic: sfocato ↔ nessuno. Accendendo usa <paramref name="intensita"/> (l'ultimo livello scelto,
    /// <see cref="LivelliSfocatura"/>); senza, l'intensità attuale.
    /// </summary>
    public Comando AlternaSfocatura(long adessoMs, double? intensita = null) => Valori.SfondoSfocato
        ? Subito(new Comando(Sfondo: ModiSfondo.Nessuno), adessoMs)
        : Sfoca(intensita ?? Valori.IntensitaSfondo, adessoMs);

    /// <summary>Sfondo sfocato con questa intensità, in un solo comando (Poco, Medio o Tanto dal menu di «Sfondo»).</summary>
    public Comando Sfoca(double intensita, long adessoMs) =>
        Subito(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: Math.Clamp(intensita, 0, 1)), adessoMs);

    /// <summary>
    /// Il livello con la spunta nel menu di «Sfondo»: con lo sfondo sfocato quello più vicino all'intensità che il telefono
    /// conferma, altrimenti <paramref name="ultimo"/> (l'ultimo scelto).
    /// </summary>
    public LivelloSfocatura LivelloAttuale(LivelloSfocatura ultimo) =>
        Valori.SfondoSfocato ? LivelliSfocatura.Vicino(Valori.IntensitaSfondo) : ultimo;

    /// <summary>Un altro telefono, o nessuno: tutto come all'apertura.</summary>
    public void Azzera()
    {
        Valori = ValoriEffetti.Iniziali;
        Disponibili = DisponibilitaEffetti.Nessuno;
        inAttesa = null;
        toccati.Clear();
    }

    private void Segna(Comando comando, long adessoMs)
    {
        Valori = Valori.Applica(comando);
        foreach (var campo in CampoEffetto.Di(comando)) toccati[campo] = adessoMs;
    }
}
