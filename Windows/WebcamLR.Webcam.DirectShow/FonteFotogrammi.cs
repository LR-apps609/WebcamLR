namespace WebcamLR.Webcam.DirectShow;

/// <summary>
/// Da dove il filtro prende i fotogrammi NV12: l'anello scritto da WebcamLR, oppure la schermata di attesa. Prima prova
/// l'anello globale (c'è solo su Windows 11, se anche la sorgente Media Foundation è installata e attiva), poi crea o
/// apre quello locale della sessione, che su Windows 10 scrive l'app. Solo il thread di consegna la usa.
/// </summary>
internal sealed class FonteFotogrammi : IDisposable
{
    private MemoriaCondivisa? memoria;
    private long prossimoTentativo;
    /// <summary>Video o schermata di attesa, come nella sorgente di Windows 11. Nella lingua dell'utente: qui si gira dentro la sua app.</summary>
    private readonly CompositoreWebcam compositore = new(LinguaDiSistema.Leggi(), RegistroDirectShow.Scrivi);

    /// <summary>Vero se l'app ha mandato un fotogramma da poco: allora si aspetta il suo segnale invece del ritmo fisso.</summary>
    public bool AppAttiva => memoria is not null && compositore.AppAttiva(Environment.TickCount64);

    /// <summary>Aspetta il segnale «fotogramma nuovo» dell'app, al massimo per il tempo dato.</summary>
    public void Aspetta(int millisecondi)
    {
        if (memoria is { } m && millisecondi > 0) m.Aspetta(millisecondi);
    }

    /// <summary>L'ultimo fotogramma dell'app alla misura chiesta (NV12), oppure la schermata di attesa.</summary>
    public byte[] Fotogramma(FormatoWebcam f)
    {
        var adesso = Environment.TickCount64;
        if (memoria is null && adesso >= prossimoTentativo) Apri(adesso);
        return compositore.Fotogramma(memoria?.Anello, f, adesso);
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
