using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// La strada scelta per un telefono (interfaccia finale, Documenti/Interfaccia finale.md): «Automatico», «Wi-Fi» o
/// «Cavo USB», come <c>comando.collegamento</c> del protocollo. Valori sconosciuti valgono «automatico».
/// </summary>
public static class PreferenzaCollegamento
{
    public const string Automatico = PreferenzeCollegamento.Automatico;
    public const string WiFi = PreferenzeCollegamento.Wifi;
    public const string Cavo = PreferenzeCollegamento.Cavo;

    /// <summary>Una delle tre; tutto il resto (assente, sconosciuto) è «automatico».</summary>
    public static string Normalizza(string? valore) => valore is WiFi or Cavo ? valore : Automatico;

    /// <summary>«Automatico», «Wi-Fi», «Cavo USB».</summary>
    public static string Testo(string preferenza) => Normalizza(preferenza) switch
    {
        WiFi => TestiRicevitore.T("Collegamento_WiFi"),
        Cavo => TestiRicevitore.T("Collegamento_CavoUsb"),
        _ => TestiRicevitore.T("Strada_Automatico"),
    };
}

/// <summary>Una strada che il telefono conosce (<c>stato.collegamento.strade</c>): tipo e ultima latenza misurata, se c'è.</summary>
/// <param name="Tipo">"wifi", "cavo", "hotspot", "wifiDiretto", "rete"; altri valori si tollerano e non si mostrano.</param>
public sealed record StradaNota(string Tipo, int? Ms);

/// <summary>
/// Le strade del telefono come le racconta lui (<c>stato.collegamento</c>), copiate nei tipi del ricevitore: così la
/// logica e la finestra non dipendono da come il protocollo le chiama (vedi <see cref="ContrattoCollegamento"/>).
/// </summary>
public sealed record StradeTelefono(string Attivo, string Preferenza, IReadOnlyList<StradaNota> Strade)
{
    public bool Equals(StradeTelefono? altre) =>
        altre is not null && Attivo == altre.Attivo && Preferenza == altre.Preferenza && Strade.SequenceEqual(altre.Strade);

    public override int GetHashCode() => HashCode.Combine(Attivo, Preferenza, Strade.Count);
}

/// <summary>Cosa fare quando lo stesso telefono arriva da un'altra strada mentre quella in uso funziona ancora.</summary>
public enum DecisioneStrada
{
    /// <summary>La sessione nuova prende il posto di quella in uso.</summary>
    PassaAllaNuova,
    /// <summary>Resta la sessione in uso; quella nuova si chiude.</summary>
    TieniQuellaInUso,
}

/// <summary>
/// La regola «Automatico» decisa da Ledion (Documenti/Interfaccia finale.md, «niente sbalzi»), per un telefono:
/// la strada si sceglie all'inizio e poi resta. Si cambia solo se quella in uso si stacca, o se arriva il cavo mentre
/// si è in Wi-Fi (un passaggio, il gesto voluto); mai per la latenza. Dopo un cambio, per 30 secondi niente cambi
/// automatici (anche se il cavo va e viene). Con «Wi-Fi» o «Cavo USB» scelti a mano resta quella strada: l'altra si
/// usa solo se quella scelta si stacca, e si torna appena la scelta arriva di nuovo.
/// Il PC decide solo tra le sessioni che arrivano (il cavo dell'iPhone lo apre lui; il Wi-Fi e il tethering di Android
/// li apre il telefono, che segue la stessa regola). Thread-safe: decide sul thread di rete (<see cref="ElencoTelefoni.Accogli"/>),
/// la finestra imposta la scelta e legge la preferenza del telefono sul suo.
/// </summary>
public sealed class RegolaCollegamento
{
    /// <summary>Dopo un cambio di strada, niente cambi automatici per questo tempo.</summary>
    public static readonly TimeSpan PausaDopoCambio = TimeSpan.FromSeconds(30);

    /// <summary>Dopo una scelta fatta qui, lo stato del telefono che dice ancora quella vecchia non la rimette.</summary>
    public static readonly TimeSpan AttesaConferma = TimeSpan.FromSeconds(3);

    private readonly object blocco = new();
    private string preferenza = PreferenzaCollegamento.Automatico;
    private long? ultimoCambioMs;
    private long? sceltaQuiMs;

    /// <summary>«automatico», «wifi» o «cavo».</summary>
    public string Preferenza
    {
        get { lock (blocco) return preferenza; }
    }

    /// <summary>Vero nei 30 secondi dopo un cambio di strada.</summary>
    public bool InPausa(long adessoMs)
    {
        lock (blocco) return InPausaSenzaBlocco(adessoMs);
    }

    private bool InPausaSenzaBlocco(long adessoMs) =>
        ultimoCambioMs is long cambio && adessoMs - cambio < (long)PausaDopoCambio.TotalMilliseconds;

    /// <summary>
    /// Lo stesso telefono arriva da una strada (cavo o no) mentre ne aveva un'altra. <paramref name="inUsoAttiva"/> falso:
    /// la sessione in uso si è staccata (o non c'è più), e la nuova passa sempre, contando come cambio se la strada è diversa.
    /// <paramref name="telefonoSceglie"/>: il telefono segue la stessa regola (<c>capacita.sceltaCollegamento</c>), quindi
    /// apre il Wi-Fi mentre è sul cavo solo per cambiare davvero (preferenza sua, come sul Mac): il Wi-Fi prende il posto
    /// del cavo e il cavo resta fermo per lui. Un telefono di prima riaprirebbe il Wi-Fi da solo: per lui resta il cavo.
    /// </summary>
    public DecisioneStrada Decidi(bool nuovaViaCavo, bool inUsoViaCavo, bool inUsoAttiva, long adessoMs, bool telefonoSceglie = false)
    {
        lock (blocco) return DecidiSenzaBlocco(nuovaViaCavo, inUsoViaCavo, inUsoAttiva, adessoMs, telefonoSceglie);
    }

    private DecisioneStrada DecidiSenzaBlocco(bool nuovaViaCavo, bool inUsoViaCavo, bool inUsoAttiva, long adessoMs, bool telefonoSceglie)
    {
        if (nuovaViaCavo == inUsoViaCavo) return DecisioneStrada.PassaAllaNuova;
        if (!inUsoAttiva)
        {
            ultimoCambioMs = adessoMs;
            return DecisioneStrada.PassaAllaNuova;
        }
        var passa = preferenza switch
        {
            // Scelta a mano: si torna sempre alla strada scelta, e non si lascia mai per l'altra.
            PreferenzaCollegamento.Cavo => nuovaViaCavo,
            PreferenzaCollegamento.WiFi => !nuovaViaCavo,
            // Automatico: il cavo che arriva durante il Wi-Fi è un passaggio voluto, ma non subito dopo un altro cambio;
            // il Wi-Fi scavalca il cavo che funziona solo se lo apre un telefono che sceglie da sé.
            _ => nuovaViaCavo ? !InPausaSenzaBlocco(adessoMs) : telefonoSceglie,
        };
        if (!passa) return DecisioneStrada.TieniQuellaInUso;
        ultimoCambioMs = adessoMs;
        return DecisioneStrada.PassaAllaNuova;
    }

    /// <summary>La scelta fatta qui (menu del collegamento). Vero se è cambiata.</summary>
    public bool Imposta(string? nuova, long adessoMs)
    {
        var normalizzata = PreferenzaCollegamento.Normalizza(nuova);
        lock (blocco)
        {
            sceltaQuiMs = adessoMs;
            if (normalizzata == preferenza) return false;
            preferenza = normalizzata;
            return true;
        }
    }

    /// <summary>
    /// La preferenza che il telefono dice di avere (<c>stato.collegamento.preferenza</c>): il telefono può cambiarla da sé.
    /// Subito dopo una scelta fatta qui, uno stato che dice ancora quella vecchia non la rimette. Vero se è cambiata.
    /// </summary>
    public bool DalTelefono(string? delTelefono, long adessoMs)
    {
        if (delTelefono is null) return false;
        var normalizzata = PreferenzaCollegamento.Normalizza(delTelefono);
        lock (blocco)
        {
            if (normalizzata == preferenza) return false;
            if (sceltaQuiMs is long scelta && adessoMs - scelta < (long)AttesaConferma.TotalMilliseconds) return false;
            preferenza = normalizzata;
            return true;
        }
    }
}

/// <summary>Una riga del menu del collegamento: «Automatico», «Wi-Fi · 38 ms», «Cavo USB · 9 ms».</summary>
/// <param name="Preferenza">Quella che la riga sceglie.</param>
/// <param name="Ms">L'ultima latenza su quella strada; null se mai misurata (o per «Automatico»).</param>
/// <param name="Scelta">La preferenza attuale (con la spunta).</param>
/// <param name="PiuVeloce">La strada più veloce adesso: solo un'informazione, «Automatico» non la segue.</param>
public sealed record VoceCollegamento(string Preferenza, int? Ms, bool Scelta, bool PiuVeloce)
{
    /// <summary>«Wi-Fi · 38 ms», «Cavo USB», «Automatico».</summary>
    public string Testo => Ms is int ms ? $"{PreferenzaCollegamento.Testo(Preferenza)} · {ms} ms" : PreferenzaCollegamento.Testo(Preferenza);
}

/// <summary>Il menu dell'etichetta del collegamento sul video: quando si apre e cosa contiene.</summary>
public static class MenuCollegamento
{
    /// <summary>Le strade che si possono scegliere, nell'ordine del menu.</summary>
    private static readonly string[] Selezionabili = [PreferenzaCollegamento.WiFi, PreferenzaCollegamento.Cavo];

    /// <summary>Cliccabile solo se il telefono sa cambiare strada e ne conosce più di una (Wi-Fi e cavo).</summary>
    public static bool Cliccabile(bool saScegliere, StradeTelefono? strade) =>
        saScegliere && strade is not null && Selezionabili.Count(t => strade.Strade.Any(s => s.Tipo == t)) >= 2;

    /// <summary>
    /// «Automatico», poi Wi-Fi e cavo se il telefono li conosce, con la latenza. «Più veloce ora» va alla strada con
    /// la latenza più bassa, solo se se ne conoscono almeno due (con una sola non dice niente).
    /// </summary>
    public static IReadOnlyList<VoceCollegamento> Voci(StradeTelefono strade, string preferenza)
    {
        var scelta = PreferenzaCollegamento.Normalizza(preferenza);
        var note = Selezionabili
            .Select(tipo => strade.Strade.FirstOrDefault(s => s.Tipo == tipo))
            .Where(s => s is not null)
            .Select(s => s!)
            .ToList();
        var misurate = note.Where(s => s.Ms is not null).ToList();
        var veloce = misurate.Count >= 2 ? misurate.MinBy(s => s.Ms)!.Tipo : null;
        var voci = new List<VoceCollegamento> { new(PreferenzaCollegamento.Automatico, null, scelta == PreferenzaCollegamento.Automatico, false) };
        voci.AddRange(note.Select(s => new VoceCollegamento(s.Tipo, s.Ms, scelta == s.Tipo, s.Tipo == veloce)));
        return voci;
    }
}
