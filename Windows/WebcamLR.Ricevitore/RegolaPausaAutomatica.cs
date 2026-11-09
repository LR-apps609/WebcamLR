using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Cosa sa il computer, adesso, del bisogno del video del telefono (Qualità 18, Protocollo.md, «Pausa automatica»).
/// </summary>
/// <param name="Interruttore">«Pausa quando nessuna app usa la webcam» nelle impostazioni, acceso di serie.</param>
/// <param name="SaLeggereUso">
/// Il computer sa dire se un'app usa la webcam virtuale. Windows: webcam installata e memoria condivisa aperta (Windows
/// 11 con la sorgente di Frame Server, Windows 10 con il filtro DirectShow). Mac: la Camera Extension risponde (solo con
/// l'account a pagamento). Senza, la funzione resta spenta: il video non si ferma mai per questo motivo.
/// </param>
/// <param name="WebcamInUso">Un'app usa la webcam virtuale.</param>
/// <param name="Registra">Il computer registra: senza video la registrazione resterebbe ferma.</param>
/// <param name="FinestraGuardata">
/// Qualcuno guarda l'anteprima: la finestra di WebcamLR è quella in primo piano (attiva, non ridotta a icona né
/// nascosta), oppure è aperta la finestra mini, che resta sopra le altre apposta per essere guardata.
/// </param>
public readonly record struct UsoVideo(bool Interruttore, bool SaLeggereUso, bool WebcamInUso, bool Registra, bool FinestraGuardata)
{
    /// <summary>La funzione può lavorare: interruttore acceso e uso della webcam leggibile.</summary>
    public bool Possibile => Interruttore && SaLeggereUso;

    /// <summary>Il video serve adesso: niente pausa, e se c'è finisce subito.</summary>
    public bool Serve => !Possibile || WebcamInUso || Registra || FinestraGuardata;
}

/// <summary>
/// Qualità 18, la pausa automatica: quando il video non serve (<see cref="UsoVideo.Serve"/> falso) da almeno
/// <see cref="Attesa"/>, il computer chiede al telefono di fermare fotocamera e codifica (messaggio «pausa-automatica»);
/// appena serve di nuovo, la toglie subito. Classe pura, con i tempi in millisecondi dall'orologio di chi la usa (nei
/// test un orologio finto). Vale per tutti i telefoni collegati insieme: con la webcam in uso nessuno si ferma, così il
/// passaggio da una prospettiva all'altra resta immediato.
/// </summary>
public sealed class RegolaPausaAutomatica
{
    /// <summary>Quanto il video deve restare inutile prima della pausa (20 s, uguale sul Mac).</summary>
    public static readonly TimeSpan Attesa = TimeSpan.FromSeconds(Servizio.SecondiPausaAutomatica);

    /// <summary>
    /// Ogni quanto controllare se un'app ha aperto la webcam mentre un telefono è in pausa automatica: così il video
    /// riparte in meno di un secondo (al massimo questo, più l'accensione della fotocamera sul telefono).
    /// </summary>
    public static readonly TimeSpan ControlloRapido = TimeSpan.FromMilliseconds(250);

    /// <summary>Il controllo normale, senza pausa automatica in corso.</summary>
    public static readonly TimeSpan ControlloNormale = TimeSpan.FromSeconds(1);

    private long? inutileDalMs;

    /// <summary>Vero se adesso il computer chiede la pausa ai telefoni.</summary>
    public bool Pausa { get; private set; }

    /// <summary>Da quando il video non serve (ms), null se serve.</summary>
    public long? InutileDalMs => inutileDalMs;

    /// <summary>La decisione per adesso: vero = chiedere la pausa automatica.</summary>
    public bool Valuta(UsoVideo uso, long adessoMs)
    {
        if (uso.Serve)
        {
            inutileDalMs = null;
            Pausa = false;
            return false;
        }
        // L'orologio tornato indietro (non dovrebbe): si riparte a contare da qui.
        if (inutileDalMs is not long dal || adessoMs < dal) inutileDalMs = dal = adessoMs;
        Pausa = adessoMs - dal >= (long)Attesa.TotalMilliseconds;
        return Pausa;
    }

    /// <summary>
    /// Qualcosa di nuovo che l'utente vorrà vedere (un telefono appena collegato, l'interruttore appena acceso): la
    /// pausa finisce e i secondi si contano da capo.
    /// </summary>
    public void Riparti(long adessoMs)
    {
        if (inutileDalMs is not null) inutileDalMs = adessoMs;
        Pausa = false;
    }

    /// <summary>Quanto manca alla pausa (null se il video serve o se la pausa c'è già), per il registro e i test.</summary>
    public TimeSpan? MancaAllaPausa(long adessoMs) =>
        inutileDalMs is long dal && !Pausa
            ? TimeSpan.FromMilliseconds(Math.Max(0, dal + (long)Attesa.TotalMilliseconds - adessoMs))
            : null;

    /// <summary>Ogni quanto controllare l'uso della webcam: più spesso mentre c'è la pausa, per riprendere subito.</summary>
    public TimeSpan Controllo => Pausa ? ControlloRapido : ControlloNormale;
}
