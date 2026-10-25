namespace WebcamLR.Webcam;

/// <summary>
/// Il fotogramma che la webcam consegna alle app, uguale per la sorgente di Windows 11 (FlussoWebcam) e per il filtro
/// DirectShow di Windows 10 (FonteFotogrammi): il video scritto da WebcamLR nella memoria condivisa, oppure la schermata
/// di attesa (<see cref="DisegnoAttesa"/>) con le dissolvenze del Mac:
/// <list type="bullet">
/// <item>verso l'attesa: dall'ultima immagine (tenuta ferma 2 secondi dopo una caduta) in mezzo secondo, a 16 passi
/// già mescolati (ogni passo si calcola una volta, poi si ripete);</item>
/// <item>da un'attesa all'altra: mezzo secondo;</item>
/// <item>ritorno al video: l'attesa svanisce sopra le prime immagini in 0,3 secondi.</item>
/// </list>
/// Stato, stile e lingua li scrive l'app (<see cref="AnelloFotogrammi.ImpostaAttesa"/>); senza l'app (chiusa, o la
/// memoria condivisa non c'è) vale «La webcam non è collegata» nello stile di WebcamLR. Ogni schermata si disegna una
/// volta per stato, stile, lingua e misura. Un'istanza per thread di consegna; nessun'altra la tocca.
/// </summary>
public sealed class CompositoreWebcam
{
    public const long EntrataMs = 500;
    public const long UscitaMs = 300;
    private const int Passi = 16;
    private const int MassimoSchermate = 6;

    private readonly LinguaAttesa linguaDiSistema;
    private readonly Action<string>? registro;
    private readonly ProgrammaAttesa programma = new();

    // Il video: l'ultima lettura riuscita dall'anello (letto) e quella in corso (lettura), scambiate a ogni successo.
    private byte[] letto = [];
    private byte[] lettura = [];
    private InfoFotogramma infoLetto;
    private long ultimoNumero;
    private long ultimoFresco;
    private bool conMemoria;
    /// <summary>L'ultimo fotogramma alla misura del formato chiesto: <see cref="letto"/> stesso o la sua copia scalata.</summary>
    private byte[]? vivo;
    private (long Numero, int Larghezza, int Altezza) vivoPer;
    private byte[] scalato = [];

    // La schermata di attesa.
    private readonly Dictionary<(StatoAttesa, StileAttesa, LinguaAttesa, int, int, long), byte[]> schermate = [];
    private ImmagineNv12? personale;
    private long versionePersonale;
    private ImmagineNv12? sfocato;
    private long versioneSfocato;
    /// <summary>L'attesa che le app stanno vedendo; null quando vedono il video.</summary>
    private StatoAttesa? mostrata;
    private byte[]? attesaMostrata;
    private (StatoAttesa, StileAttesa, LinguaAttesa)? descrizioneMostrata;

    // Le dissolvenze.
    private byte[]? da;
    private long dissolvenzaInizio;
    private long dissolvenzaDurata;
    private bool versoIlVideo;
    private int passoMescolato = -1;
    private byte[] misto = [];

    /// <param name="linguaDiSistema">La lingua di Windows per chi consegna (dentro Frame Server: quella del sistema),
    /// usata quando l'app non ha scritto la sua.</param>
    public CompositoreWebcam(LinguaAttesa linguaDiSistema, Action<string>? registro = null)
    {
        this.linguaDiSistema = linguaDiSistema;
        this.registro = registro;
    }

    /// <summary>Vero se l'app ha mandato un fotogramma da poco: allora si aspetta il suo segnale invece del ritmo fisso.</summary>
    public bool AppAttiva(long adessoMs) => conMemoria && adessoMs - ultimoFresco < 200;

    /// <summary>L'attesa che le app vedono adesso (null: il video), per il registro e per i test.</summary>
    public StatoAttesa? Mostrata => mostrata;

    /// <summary>
    /// Il fotogramma da consegnare adesso, nel formato <paramref name="f"/> (i primi f.Byte byte). Il buffer resta
    /// valido fino alla chiamata dopo. <paramref name="anello"/>: null se la memoria condivisa non c'è.
    /// </summary>
    public byte[] Fotogramma(AnelloFotogrammi? anello, FormatoWebcam f, long adessoMs)
    {
        var stato = StatoAttesa.NonCollegata;
        var stile = StileAttesa.WebcamLR;
        var lingua = LinguaAttesa.Automatica;
        var chiusa = true;
        conMemoria = anello is not null && anello.Valido;
        if (conMemoria)
        {
            anello!.SegnalaRichiesta(f.Larghezza, f.Altezza, adessoMs, f.Fps);
            var scritto = anello.LeggiAttesa();
            chiusa = !AnelloFotogrammi.AppViva(scritto.BattitoMs, adessoMs);
            (stato, stile, lingua) = (scritto.Stato, scritto.Stile, scritto.Lingua);
            LeggiVideo(anello, adessoMs);
            if (stile == StileAttesa.Immagine) LeggiPersonale(anello);
        }
        lingua = Lingue.Risolvi(lingua, linguaDiSistema);

        programma.Imposta(stato, chiusa, adessoMs);
        var voluta = programma.Decidi(adessoMs);
        var video = VideoPer(f);
        if (voluta is null && video is not null) return Video(video, f, adessoMs);
        return Attesa(voluta ?? mostrata ?? StatoAttesa.NonCollegata, stile, lingua, video, f, adessoMs);
    }

    private void LeggiVideo(AnelloFotogrammi anello, long adessoMs)
    {
        if (anello.UltimoNumero == ultimoNumero) return;
        if (lettura.Length < FormatiWebcam.Massimo.Byte) lettura = new byte[FormatiWebcam.Massimo.Byte];
        if (!anello.Leggi(lettura, out var info) || info.Numero == ultimoNumero) return;
        ultimoNumero = info.Numero;
        // Un fotogramma vecchio (rimasto nella memoria da prima) non è video: la webcam resta in attesa.
        if (!AnelloFotogrammi.Fresco(info, adessoMs)) return;
        (letto, lettura) = (lettura, letto);
        infoLetto = info;
        ultimoFresco = adessoMs;
        programma.Vivo(adessoMs);
    }

    private void LeggiPersonale(AnelloFotogrammi anello)
    {
        var versione = anello.VersioneImmagine;
        if (versione == versionePersonale) return;
        if (versione <= 0)
        {
            personale = null;
            versionePersonale = versione;
            return;
        }
        // Se l'app la sta riscrivendo proprio adesso, si riprova al fotogramma dopo.
        if (anello.LeggiImmaginePersonale() is { } letta)
        {
            personale = letta.Immagine;
            versionePersonale = letta.Versione;
        }
    }

    /// <summary>L'ultimo fotogramma arrivato, alla misura chiesta (scalato una volta per fotogramma e misura); null se non ce n'è.</summary>
    private byte[]? VideoPer(FormatoWebcam f)
    {
        if (infoLetto.Numero == 0) return null;
        if (infoLetto.Larghezza == f.Larghezza && infoLetto.Altezza == f.Altezza) return letto;
        if (vivo is not null && vivoPer == (infoLetto.Numero, f.Larghezza, f.Altezza)) return vivo;
        // Un'altra app usa la webcam a un'altra misura, o il formato è appena cambiato: si scala qui, con le bande.
        if (scalato.Length < f.Byte) scalato = new byte[f.Byte];
        ConversioneVideo.ScalaNv12(letto, infoLetto.Larghezza, infoLetto.Altezza, scalato, f.Larghezza, f.Altezza);
        vivo = scalato;
        vivoPer = (infoLetto.Numero, f.Larghezza, f.Altezza);
        return vivo;
    }

    private byte[] Video(byte[] video, FormatoWebcam f, long adessoMs)
    {
        if (mostrata is not null)
        {
            registro?.Invoke($"Video dall'app: {infoLetto.Larghezza}×{infoLetto.Altezza} → {f}");
            // Il video torna: l'attesa svanisce sopra le prime immagini.
            IniziaDissolvenza(attesaMostrata, f, adessoMs, UscitaMs, versoIlVideo: true);
            mostrata = null;
            attesaMostrata = null;
            descrizioneMostrata = null;
        }
        if (da is not null && versoIlVideo)
        {
            var trascorso = adessoMs - dissolvenzaInizio;
            if (trascorso < dissolvenzaDurata && da.Length >= f.Byte)
            {
                // Ogni fotogramma del video è nuovo: qui si mescola sempre (al massimo 0,3 secondi).
                if (misto.Length < f.Byte) misto = new byte[f.Byte];
                var opacita = (int)(256 - trascorso * 256 / dissolvenzaDurata);
                ImmaginiNv12.Mescola(video.AsSpan(0, f.Byte), da.AsSpan(0, f.Byte), misto, opacita);
                return misto;
            }
            da = null;
        }
        return video;
    }

    private byte[] Attesa(StatoAttesa voluta, StileAttesa stile, LinguaAttesa lingua, byte[]? video, FormatoWebcam f, long adessoMs)
    {
        if (voluta != mostrata)
        {
            if (mostrata is null)
            {
                // Dal video: lo sfondo sfocato si rifà dall'ultima immagine, e da lì parte la dissolvenza.
                sfocato = null;
                IniziaDissolvenza(video, f, adessoMs, EntrataMs, versoIlVideo: false);
            }
            else
            {
                IniziaDissolvenza(attesaMostrata, f, adessoMs, EntrataMs, versoIlVideo: false);
            }
            mostrata = voluta;
        }
        var immagine = Schermata(voluta, stile, lingua, video, f);
        if (descrizioneMostrata != (voluta, stile, lingua))
        {
            descrizioneMostrata = (voluta, stile, lingua);
            registro?.Invoke($"Schermata di attesa: {voluta} (stile {stile}, {lingua}, {f.Larghezza}×{f.Altezza})");
        }
        attesaMostrata = immagine;

        if (da is not null && !versoIlVideo)
        {
            var trascorso = adessoMs - dissolvenzaInizio;
            var passo = (int)(trascorso * Passi / dissolvenzaDurata);
            if (passo < Passi && da.Length >= f.Byte)
            {
                if (passo != passoMescolato || misto.Length < f.Byte)
                {
                    if (misto.Length < f.Byte) misto = new byte[f.Byte];
                    // Opacità dell'attesa da 1/17 a 16/17: dopo l'ultimo passo, l'attesa stessa.
                    ImmaginiNv12.Mescola(da.AsSpan(0, f.Byte), immagine, misto, (passo + 1) * 256 / (Passi + 1));
                    passoMescolato = passo;
                }
                return misto;
            }
            da = null;
        }
        return immagine;
    }

    /// <summary>Fissa da dove parte una dissolvenza: una copia, perché l'originale può cambiare (un fotogramma nuovo).</summary>
    private void IniziaDissolvenza(byte[]? partenza, FormatoWebcam f, long adessoMs, long durata, bool versoIlVideo)
    {
        passoMescolato = -1;
        if (partenza is null || partenza.Length < f.Byte)
        {
            da = null;
            return;
        }
        if (da is null || da.Length < f.Byte || ReferenceEquals(da, partenza)) da = new byte[f.Byte];
        partenza.AsSpan(0, f.Byte).CopyTo(da);
        dissolvenzaInizio = adessoMs;
        dissolvenzaDurata = durata;
        this.versoIlVideo = versoIlVideo;
    }

    /// <summary>La schermata di attesa, disegnata una volta per stato, stile, lingua, misura e sfondo.</summary>
    private byte[] Schermata(StatoAttesa stato, StileAttesa stile, LinguaAttesa lingua, byte[]? video, FormatoWebcam f)
    {
        ImmagineNv12? sfondo = null;
        long versione = 0;
        if (stile == StileAttesa.Immagine && personale is not null)
        {
            sfondo = personale;
            versione = versionePersonale;
        }
        else if (stile == StileAttesa.Sfocata)
        {
            if (sfocato is null && video is not null)
            {
                var (dati, l, a) = ImmaginiNv12.Sfoca(video.AsSpan(0, f.Byte), f.Larghezza, f.Altezza);
                sfocato = new ImmagineNv12(l, a, dati);
                versioneSfocato++;
            }
            sfondo = sfocato;
            versione = versioneSfocato;
        }
        // Senza immagine (personale o ultima del telefono) vale il disegno di WebcamLR, come sul Mac.
        var effettivo = stile is StileAttesa.Immagine or StileAttesa.Sfocata && sfondo is null ? StileAttesa.WebcamLR : stile;
        if (effettivo is StileAttesa.WebcamLR or StileAttesa.Nero) versione = 0;
        var chiave = (stato, effettivo, effettivo == StileAttesa.Nero || effettivo == StileAttesa.Immagine ? LinguaAttesa.Automatica : lingua,
            f.Larghezza, f.Altezza, versione);
        if (schermate.TryGetValue(chiave, out var pronta)) return pronta;
        if (schermate.Count >= MassimoSchermate) schermate.Clear();
        var nuova = DisegnoAttesa.CreaNv12(stato, effettivo, lingua, f.Larghezza, f.Altezza, sfondo);
        schermate[chiave] = nuova;
        return nuova;
    }
}
