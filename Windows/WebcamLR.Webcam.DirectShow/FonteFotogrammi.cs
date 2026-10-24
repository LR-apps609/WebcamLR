namespace WebcamLR.Webcam.DirectShow;

/// <summary>
/// Da dove il filtro prende i fotogrammi NV12: l'anello scritto da WebcamLR, oppure l'immagine di attesa. Prima prova
/// l'anello globale (c'è solo su Windows 11, se anche la sorgente Media Foundation è installata e attiva), poi crea o
/// apre quello locale della sessione, che su Windows 10 scrive l'app. Solo il thread di consegna la usa.
/// </summary>
internal sealed class FonteFotogrammi : IDisposable
{
    private MemoriaCondivisa? memoria;
    private long prossimoTentativo;
    private readonly byte[] letto = new byte[FormatiWebcam.Massimo.Byte];
    private byte[] scalato = [];
    private readonly Dictionary<(int, int), byte[]> immaginiAttesa = [];
    private long ultimoFresco;
    private bool mostravaAttesa = true;

    /// <summary>Vero se l'app ha mandato un fotogramma da poco: allora si aspetta il suo segnale invece del ritmo fisso.</summary>
    public bool AppAttiva => memoria is not null && Environment.TickCount64 - ultimoFresco < 200;

    /// <summary>Aspetta il segnale «fotogramma nuovo» dell'app, al massimo per il tempo dato.</summary>
    public void Aspetta(int millisecondi)
    {
        if (memoria is { } m && millisecondi > 0) m.Aspetta(millisecondi);
    }

    /// <summary>L'ultimo fotogramma dell'app alla misura chiesta (NV12), oppure l'immagine di attesa.</summary>
    public byte[] Fotogramma(FormatoWebcam f)
    {
        var adesso = Environment.TickCount64;
        if (memoria is null && adesso >= prossimoTentativo) Apri(adesso);
        if (memoria is not null)
        {
            var anello = memoria.Anello;
            anello.SegnalaRichiesta(f.Larghezza, f.Altezza, adesso, f.Fps);
            if (anello.Leggi(letto, out var info) && AnelloFotogrammi.Fresco(info, adesso))
            {
                ultimoFresco = adesso;
                if (mostravaAttesa)
                {
                    mostravaAttesa = false;
                    RegistroDirectShow.Scrivi($"Video dall'app: {info.Larghezza}×{info.Altezza} → {f}");
                }
                if (info.Larghezza == f.Larghezza && info.Altezza == f.Altezza) return letto;
                // Un'altra app usa la webcam a un'altra misura e WebcamLR scrive quella: si scala qui.
                if (scalato.Length < f.Byte) scalato = new byte[f.Byte];
                ConversioneVideo.ScalaNv12(letto, info.Larghezza, info.Altezza, scalato, f.Larghezza, f.Altezza);
                return scalato;
            }
        }
        if (!mostravaAttesa)
        {
            mostravaAttesa = true;
            RegistroDirectShow.Scrivi("Nessun fotogramma fresco: immagine di attesa");
        }
        if (!immaginiAttesa.TryGetValue((f.Larghezza, f.Altezza), out var attesa))
        {
            attesa = ImmagineAttesa.CreaNv12(f.Larghezza, f.Altezza);
            immaginiAttesa[(f.Larghezza, f.Altezza)] = attesa;
        }
        return attesa;
    }

    private void Apri(long adesso)
    {
        try
        {
            memoria = MemoriaCondivisa.Apri(NomiAnello.Globale);
            if (memoria is not null)
            {
                RegistroDirectShow.Scrivi("Memoria condivisa globale (sorgente di Windows 11) aperta");
                return;
            }
            memoria = MemoriaCondivisa.Crea(NomiAnello.Locale);
            RegistroDirectShow.Scrivi("Memoria condivisa locale pronta");
        }
        catch (Exception errore)
        {
            memoria = null;
            prossimoTentativo = adesso + 5000;
            RegistroDirectShow.Scrivi($"Memoria condivisa non disponibile: {errore.Message}");
        }
    }

    public void Dispose()
    {
        memoria?.Dispose();
        memoria = null;
    }
}
