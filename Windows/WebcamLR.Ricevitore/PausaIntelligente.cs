using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Pausa intelligente (Documenti/Protocollo.md): cosa mostrare quando il telefono è in pausa, e quando dire al telefono
/// che la finestra del computer sta mostrando il video (messaggio «anteprima»).
/// </summary>
public static class PausaIntelligente
{
    public const string Titolo = "In pausa";

    /// <summary>Vero se lo stato dice che il telefono non manda video.</summary>
    public static bool InPausa(StatoTelefono? stato) => !string.IsNullOrEmpty(stato?.Pausa);

    /// <summary>Il motivo, in una frase; un motivo sconosciuto si mostra come una pausa qualsiasi.</summary>
    public static string Motivo(string? motivo) => motivo switch
    {
        MotiviPausa.FacciaInGiu => "Il telefono è a faccia in giù",
        MotiviPausa.NessunaApp => "Nessuna app usa la webcam",
        MotiviPausa.Utente => "In pausa dal telefono",
        _ => "Il telefono ha messo in pausa il video",
    };

    /// <summary>Cosa fare per riprendere.</summary>
    public static string Suggerimento(string? motivo) => motivo switch
    {
        MotiviPausa.FacciaInGiu => "Giralo per riprendere.",
        MotiviPausa.NessunaApp => "Riprende da solo appena un'app usa la webcam o guardi questa finestra.",
        MotiviPausa.Utente => "Riprendi dal telefono.",
        _ => "Controlla il telefono per riprendere.",
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
