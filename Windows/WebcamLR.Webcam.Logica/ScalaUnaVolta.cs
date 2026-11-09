namespace WebcamLR.Webcam;

/// <summary>
/// Qualità 16: il video del telefono arriva alla webcam scalato una volta sola, qualunque sia il formato che l'app di
/// chiamata ha scelto (da 640×360 al 4K, a 30 o 60 fps).
/// <list type="bullet">
/// <item>Senza gli effetti sul computer la webcam ha il suo decodificatore (UscitaWebcam): la scheda video porta il
/// fotogramma a <see cref="Inquadrature.DimensioneIntermedia"/> e il processore converte soltanto in NV12.</item>
/// <item>Con gli effetti sul computer i fotogrammi passano dal motore (MotoreVideo), che prima lavorava sempre al massimo
/// a 1080p: un 4K del telefono diventava 1080p e poi la webcam in 4K lo ingrandiva di nuovo. Adesso, con un'app che usa
/// la webcam, il motore lavora alla misura che serve alla webcam (<see cref="MisuraLavoro"/>): se il telefono manda di più,
/// riduce la scheda video nella copia; se manda di meno, il motore lavora alla misura del telefono e ingrandisce soltanto la
/// conversione in NV12, alla fine.</item>
/// </list>
/// </summary>
public static class ScalaUnaVolta
{
    /// <summary>Il lato corto più grande del motore quando nessuna app usa la webcam (anteprima, foto, registrazione).</summary>
    public const int LatoCortoSenzaWebcam = 1080;

    /// <summary>
    /// La misura a cui il motore effetti lavora un video di <paramref name="larghezzaVideo"/>×<paramref name="altezzaVideo"/>.
    /// <list type="number">
    /// <item>Durante una registrazione (<paramref name="registrazione"/>, la sua misura) resta quella della registrazione,
    /// finché il video del telefono non cambia: una misura diversa chiuderebbe il file. La webcam la scala poi una volta.</item>
    /// <item>Senza un'app sulla webcam (<paramref name="webcam"/> null): il video com'è fino al 1080p, ridotto oltre
    /// (come prima della Qualità 16: un 4K sul processore costa quattro volte un 1080p).</item>
    /// <item>Con un'app sulla webcam: la parte del video che entra nel formato, alla misura che avrà nella webcam
    /// (<see cref="Inquadrature.DimensioneIntermedia"/>), ma mai più grande del video: non si ingrandisce prima degli
    /// effetti, solo alla fine. Così un 4K del telefono arriva intero a un'app in 4K, e a un'app a 720p arriva ridotto una
    /// volta, dalla scheda video.</item>
    /// </list>
    /// Misure sempre pari, almeno 2.
    /// </summary>
    public static (int Larghezza, int Altezza) MisuraLavoro(int larghezzaVideo, int altezzaVideo, FormatoWebcam? webcam,
        Inquadratura modo, (int Larghezza, int Altezza)? registrazione = null)
    {
        if (larghezzaVideo <= 0 || altezzaVideo <= 0) return (larghezzaVideo, altezzaVideo);
        var senzaWebcam = SenzaWebcam(larghezzaVideo, altezzaVideo);
        if (registrazione is { } fissa && fissa == senzaWebcam) return fissa;
        if (webcam is not { } formato) return senzaWebcam;
        var (larghezza, altezza) = Inquadrature.DimensioneIntermedia(larghezzaVideo, altezzaVideo, formato.Larghezza, formato.Altezza, modo);
        // Il telefono manda meno di quanto serve: si lavora alla sua misura e si ingrandisce una volta, nella conversione.
        if (larghezza >= larghezzaVideo || altezza >= altezzaVideo) return (Pari(larghezzaVideo), Pari(altezzaVideo));
        return (larghezza, altezza);
    }

    /// <summary>La misura senza webcam: la stessa fino al 1080p, ridotta (pari) oltre.</summary>
    public static (int Larghezza, int Altezza) SenzaWebcam(int larghezza, int altezza)
    {
        var corto = Math.Min(larghezza, altezza);
        if (larghezza <= 0 || altezza <= 0 || corto <= LatoCortoSenzaWebcam) return (larghezza, altezza);
        var scala = (double)LatoCortoSenzaWebcam / corto;
        return ((int)Math.Round(larghezza * scala) & ~1, (int)Math.Round(altezza * scala) & ~1);
    }

    /// <summary>
    /// Quante volte il video si ridimensiona dal telefono alla webcam, con il motore effetti (copia dalla scheda video alla
    /// misura di lavoro, poi conversione nel formato): 0, 1 o 2. Serve ai test e al registro.
    /// </summary>
    public static int Scalature(int larghezzaVideo, int altezzaVideo, (int Larghezza, int Altezza) lavoro, FormatoWebcam webcam,
        Inquadratura modo)
    {
        var volte = lavoro == (larghezzaVideo, altezzaVideo) || lavoro == (Pari(larghezzaVideo), Pari(altezzaVideo)) ? 0 : 1;
        var (sorgente, destinazione) = Inquadrature.Calcola(lavoro.Larghezza, lavoro.Altezza, webcam.Larghezza, webcam.Altezza, modo);
        if (sorgente.Larghezza != destinazione.Larghezza || sorgente.Altezza != destinazione.Altezza) volte++;
        return volte;
    }

    /// <summary>
    /// I byte che la memoria condivisa sposta ogni secondo per un formato (NV12, un fotogramma nuovo a ogni intervallo):
    /// 93 MB/s a 1080p 30, 187 a 1080p 60, 373 al 4K 30. Per il registro e per i test sui posti dell'anello.
    /// </summary>
    public static long ByteAlSecondo(FormatoWebcam formato) => (long)formato.Byte * formato.Fps;

    private static int Pari(int valore) => Math.Max(2, valore & ~1);
}
