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
}

/// <summary>
/// 60 fps per la webcam (Documenti/Protocollo.md, «Video: 60 fps e 4K»): quando un'app usa la webcam a 60 fps e il
/// telefono ne manda meno, il computer chiede una volta, per ogni periodo d'uso, lo stesso video a 60 fps. Con
/// <c>capacita.formati</c> non chiede ciò che il telefono non sa fare: sceglie la risoluzione più grande a 60 fps che non
/// supera quella attuale. Senza <c>formati</c> chiede e guarda la risposta, come dice il protocollo.
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
    public FormatoVideo? Valuta(bool webcamInUso, int fpsWebcam, FormatoVideo? attuale, IReadOnlyList<FormatoSupportato>? formati)
    {
        if (!webcamInUso)
        {
            chiesta = false;
            return null;
        }
        if (chiesta || fpsWebcam < Fps || attuale is null || attuale.Fps >= Fps) return null;
        if (Scegli(attuale, formati) is not { } scelto) return null;
        chiesta = true;
        return scelto;
    }

    /// <summary>Un telefono nuovo parte da capo.</summary>
    public void Azzera() => chiesta = false;

    /// <summary>Lo stesso orientamento del video attuale (un telefono in verticale manda l'altezza più grande).</summary>
    public static FormatoVideo? Scegli(FormatoVideo attuale, IReadOnlyList<FormatoSupportato>? formati)
    {
        if (formati is null) return attuale with { Fps = Fps };
        var pixel = (long)attuale.Larghezza * attuale.Altezza;
        var adatto = formati
            .Where(f => f.FpsMassimo >= Fps && f.Larghezza > 0 && f.Altezza > 0 && (long)f.Larghezza * f.Altezza <= pixel)
            .MaxBy(f => (long)f.Larghezza * f.Altezza);
        if (adatto is null) return null;
        var lungo = Math.Max(adatto.Larghezza, adatto.Altezza);
        var corto = Math.Min(adatto.Larghezza, adatto.Altezza);
        var verticale = attuale.Altezza > attuale.Larghezza;
        return new FormatoVideo(attuale.Codec, verticale ? corto : lungo, verticale ? lungo : corto, Fps);
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
