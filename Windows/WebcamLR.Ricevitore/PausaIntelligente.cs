using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Pausa intelligente (Documenti/Protocollo.md): cosa mostrare quando il telefono è in pausa, e quando dire al telefono
/// che la finestra del computer sta mostrando il video (messaggio «anteprima»).
/// </summary>
public static class PausaIntelligente
{
    public static string Titolo => TestiRicevitore.T("Pausa_Titolo");

    /// <summary>Vero se lo stato dice che il telefono non manda video.</summary>
    public static bool InPausa(StatoTelefono? stato) => !string.IsNullOrEmpty(stato?.Pausa);

    /// <summary>Il motivo, in una frase; un motivo sconosciuto si mostra come una pausa qualsiasi.</summary>
    public static string Motivo(string? motivo) => motivo switch
    {
        MotiviPausa.FacciaInGiu => TestiRicevitore.T("Pausa_FacciaInGiu"),
        MotiviPausa.NessunaApp => TestiRicevitore.T("Pausa_NessunaApp"),
        MotiviPausa.Utente => TestiRicevitore.T("Pausa_Utente"),
        MotiviPausa.Sottofondo => TestiRicevitore.T("Pausa_Sottofondo"),
        MotiviPausa.FotocameraInterrotta => TestiRicevitore.T("Pausa_FotocameraInterrotta"),
        _ => TestiRicevitore.T("Pausa_Altro"),
    };

    /// <summary>
    /// Il motivo dentro una frase («In pausa: il telefono è a faccia in giù»): l'iniziale minuscola, tranne quando la
    /// prima parola è un nome come «WebcamLR» (con un'altra maiuscola dentro).
    /// </summary>
    public static string MotivoInFrase(string? motivo)
    {
        var testo = Motivo(motivo);
        if (testo.Length == 0) return testo;
        var primaParola = testo.Split(' ', 2)[0];
        if (primaParola.Skip(1).Any(char.IsUpper)) return testo;
        return char.ToLower(testo[0], Lingua.Attuale) + testo[1..];
    }

    /// <summary>Cosa fare per riprendere; vuoto quando il motivo lo dice già (sottofondo).</summary>
    public static string Suggerimento(string? motivo) => motivo switch
    {
        MotiviPausa.Sottofondo => "",
        MotiviPausa.FacciaInGiu => TestiRicevitore.T("Pausa_GiraloPerRiprendere"),
        MotiviPausa.NessunaApp => TestiRicevitore.T("Pausa_RiprendeDaSolo"),
        MotiviPausa.Utente => TestiRicevitore.T("Pausa_RiprendiDalTelefono"),
        _ => TestiRicevitore.T("Pausa_ControllaIlTelefono"),
    };

    /// <summary>
    /// Il video serve al computer: la finestra è aperta (non ridotta a icona né nascosta accanto all'orologio), oppure
    /// è la finestra mini, oppure si sta registrando (senza video la registrazione resterebbe ferma).
    /// Le app che usano la webcam le dice già «in-onda».
    /// </summary>
    public static bool AnteprimaVisibile(bool finestraMostrata, bool ridottaAIcona, bool mini, bool registra) =>
        registra || (finestraMostrata && (mini || !ridottaAIcona));

    /// <summary>
    /// P21: il telefono che non è nella webcam si vede solo nel riquadro piccolo, quindi solo nella finestra intera
    /// (non mini, non ridotta a icona né nascosta) e con il riquadro aperto. La registrazione non conta: registra
    /// solo il telefono nella webcam.
    /// </summary>
    public static bool AnteprimaAltroTelefono(bool finestraMostrata, bool ridottaAIcona, bool mini, bool riquadroAperto) =>
        finestraMostrata && !ridottaAIcona && !mini && riquadroAperto;
}

/// <summary>
/// La pausa «sottofondo» (Documenti/Protocollo.md, «Pausa intelligente»): l'app del telefono non è più in primo piano e
/// dopo poco il telefono può smettere anche i <c>ping</c>. Con l'ultimo motivo <c>sottofondo</c> il computer non passa a
/// «Riconnessione» e non dimentica il telefono per <see cref="Durata"/>, e tiene il motivo a schermo.
/// </summary>
public static class TolleranzaSottofondo
{
    public static readonly TimeSpan Durata = TimeSpan.FromMinutes(10);

    public static bool InSottofondo(StatoTelefono? stato) => stato?.Pausa == MotiviPausa.Sottofondo;

    /// <summary>Vero se la pausa «sottofondo» è iniziata (ms) da meno di <see cref="Durata"/>.</summary>
    public static bool Tollera(long? sottofondoDalMs, long adessoMs) =>
        sottofondoDalMs is long dal && adessoMs - dal < (long)Durata.TotalMilliseconds;

    /// <summary>Quanto resta della tolleranza (ms), zero se non c'è.</summary>
    public static long RestoMs(long? sottofondoDalMs, long adessoMs) =>
        sottofondoDalMs is long dal ? Math.Max(0, dal + (long)Durata.TotalMilliseconds - adessoMs) : 0;
}

/// <summary>Cosa è cambiato nella pausa con l'ultimo «stato»: è iniziata (o ha cambiato motivo) oppure è finita.</summary>
/// <param name="Iniziata">Il motivo della pausa appena iniziata o cambiata; null se non è iniziata.</param>
/// <param name="FinitaDopo">Quanto è durata la pausa appena finita; null se non è finita.</param>
public readonly record struct CambioPausa(string? Iniziata, TimeSpan? FinitaDopo)
{
    public bool Nessuno => Iniziata is null && FinitaDopo is null;
}

/// <summary>
/// La pausa di un telefono nel tempo, dai suoi «stato»: da quando è in pausa, da quando è in sottofondo (per la
/// tolleranza) e cosa cambia a ogni stato. Tempi in millisecondi, dall'orologio di chi la usa.
/// </summary>
public sealed class StoriaPausa
{
    /// <summary>Il motivo della pausa in corso; null se il telefono manda video.</summary>
    public string? Motivo { get; private set; }

    /// <summary>Da quando il telefono è in pausa (anche se il motivo è cambiato nel frattempo).</summary>
    public long? DalMs { get; private set; }

    /// <summary>Da quando il motivo è «sottofondo»; null con un altro motivo o senza pausa.</summary>
    public long? SottofondoDalMs { get; private set; }

    public CambioPausa Aggiorna(StatoTelefono? stato, long adessoMs)
    {
        var nuovo = string.IsNullOrEmpty(stato?.Pausa) ? null : stato!.Pausa;
        var prima = Motivo;
        Motivo = nuovo;
        if (nuovo == MotiviPausa.Sottofondo) SottofondoDalMs ??= adessoMs;
        else SottofondoDalMs = null;
        if (nuovo is null)
        {
            var dal = DalMs;
            DalMs = null;
            return prima is not null && dal is long inizio
                ? new CambioPausa(null, TimeSpan.FromMilliseconds(Math.Max(0, adessoMs - inizio)))
                : default;
        }
        DalMs ??= adessoMs;
        return nuovo != prima ? new CambioPausa(nuovo, null) : default;
    }

    /// <summary>Vero se il telefono è in sottofondo da meno di <see cref="TolleranzaSottofondo.Durata"/>.</summary>
    public bool Tollerato(long adessoMs) => TolleranzaSottofondo.Tollera(SottofondoDalMs, adessoMs);
}

/// <summary>
/// 60 fps per la webcam (Documenti/Protocollo.md, «Video: 60 fps e 4K»): quando un'app usa la webcam a 60 fps e il
/// telefono ne manda meno, il computer chiede una volta, per ogni periodo d'uso, lo stesso video (risoluzione e codec)
/// a 60 fps, come il Mac. Con <c>capacita.formati</c> non chiede ciò che il telefono non sa fare: al massimo gli fps che
/// dichiara per quella risoluzione (una risoluzione non elencata non ci arriva). Senza <c>formati</c> chiede e guarda la
/// risposta, come dice il protocollo.
/// </summary>
public sealed class Richiesta60Fps
{
    public const int Fps = 60;

    private bool chiesta;

    /// <summary>Vero dopo la richiesta, fino alla fine del periodo d'uso della webcam.</summary>
    public bool Chiesta => chiesta;

    /// <summary>Il formato da chiedere adesso, oppure null.</summary>
    /// <param name="fpsWebcam">I fotogrammi al secondo del formato che l'app ha scelto (0 se non si sa).</param>
    /// <param name="attuale">Il formato che il telefono sta mandando.</param>
    /// <param name="pro">Il telefono ha WebcamLR Pro: gratis resta a 30 fps (il telefono non manderebbe di più).</param>
    public FormatoVideo? Valuta(bool webcamInUso, int fpsWebcam, FormatoVideo? attuale, IReadOnlyList<FormatoSupportato>? formati,
        bool pro = true)
    {
        if (!webcamInUso)
        {
            chiesta = false;
            return null;
        }
        if (chiesta || !pro || fpsWebcam < Fps || attuale is null || attuale.Fps >= Fps) return null;
        if (Scegli(attuale, formati) is not { } scelto) return null;
        chiesta = true;
        return scelto;
    }

    /// <summary>Un telefono nuovo parte da capo.</summary>
    public void Azzera() => chiesta = false;

    /// <summary>
    /// Lo stesso formato con più fps: 60, ma non oltre il massimo che il telefono dichiara per questa risoluzione
    /// (in orizzontale o in verticale). Null se così non si guadagna nulla.
    /// </summary>
    public static FormatoVideo? Scegli(FormatoVideo attuale, IReadOnlyList<FormatoSupportato>? formati)
    {
        // Il 4K resta a 30 fps (1.14): da solo il PC chiede i 60 fps solo fino al 1080p, come il Mac.
        if (Math.Min(attuale.Larghezza, attuale.Altezza) >= 2160) return null;
        var fps = formati is null
            ? Fps
            : Math.Min(Fps, formati
                .Where(f => (f.Larghezza == attuale.Larghezza && f.Altezza == attuale.Altezza)
                    || (f.Larghezza == attuale.Altezza && f.Altezza == attuale.Larghezza))
                .Select(f => f.FpsMassimo)
                .DefaultIfEmpty(0)
                .Max());
        return fps > attuale.Fps ? attuale with { Fps = fps } : null;
    }
}

/// <summary>
/// I tempi dei campioni per il decodificatore: dal primo fotogramma, con i timestamp del telefono. Un salto (la pausa
/// intelligente, o l'orologio del telefono ripartito) non diventa un buco: il lettore aspetterebbe tutto quel tempo
/// prima di mostrare il fotogramma dopo. Si va avanti di un fotogramma e la linea del tempo continua.
/// </summary>
public sealed class TempiVideo
{
    /// <summary>Oltre questo salto (in µs) tra due fotogrammi la linea del tempo si ricuce.</summary>
    public const long SaltoMassimo = 1_000_000;
    /// <summary>Il passo usato al posto del salto: un fotogramma a 30 fps.</summary>
    public const long Passo = 33_333;

    private long? ultimo;
    private long tempo;

    /// <summary>Il tempo del campione, in microsecondi dal primo (mai negativo).</summary>
    public long Microsecondi(ulong timestamp)
    {
        var t = (long)Math.Min(timestamp, long.MaxValue);
        if (ultimo is not long precedente)
        {
            ultimo = t;
            tempo = 0;
            return 0;
        }
        var differenza = t - precedente;
        // Piccoli passi indietro (fotogrammi B) restano com'erano: la somma delle differenze torna al timestamp vero.
        if (differenza > SaltoMassimo || differenza < -SaltoMassimo) differenza = Passo;
        ultimo = t;
        tempo += differenza;
        return Math.Max(0, tempo);
    }

    public void Azzera()
    {
        ultimo = null;
        tempo = 0;
    }
}
