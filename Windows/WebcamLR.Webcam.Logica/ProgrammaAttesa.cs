namespace WebcamLR.Webcam;

/// <summary>
/// Decide istante per istante se la webcam mostra il video o la schermata di attesa, e quale. Come ProgrammaAttesa del
/// Mac (Mac/Sorgenti/AttesaWebcam.swift), più il caso «WebcamLR chiusa» che sul Mac gestisce l'estensione.
/// Un valore per chi consegna i fotogrammi, usato solo dal suo thread. Tempi in millisecondi (Environment.TickCount64).
/// </summary>
public sealed class ProgrammaAttesa
{
    /// <summary>Dopo una caduta (o con WebcamLR chiusa) l'ultima immagine resta ferma per 2 secondi, poi l'attesa.</summary>
    public const long TenutaMs = 2000;

    /// <summary>Quello che vale adesso, dall'app; <see cref="StatoAttesa.Nessuna"/>: il video dovrebbe arrivare.</summary>
    public StatoAttesa Stato { get; private set; } = StatoAttesa.NonCollegata;

    /// <summary>WebcamLR non scrive più il suo stato (chiusa, o una versione che non lo scrive).</summary>
    public bool AppChiusa { get; private set; } = true;

    private long statoDa;
    private long ultimoVivo;
    private StatoAttesa ultimaAttesa = StatoAttesa.NonCollegata;

    /// <summary>
    /// Lo stato scritto dall'app. Con l'app chiusa conta «non collegata», ma solo dopo la tenuta: chi chiude WebcamLR
    /// durante una chiamata vede l'ultima immagine per 2 secondi e poi «La webcam non è collegata», come sul Mac.
    /// </summary>
    public void Imposta(StatoAttesa stato, bool appChiusa, long adesso)
    {
        var effettivo = appChiusa ? StatoAttesa.NonCollegata : stato;
        if (effettivo == Stato && appChiusa == AppChiusa) return;
        Stato = effettivo;
        AppChiusa = appChiusa;
        statoDa = adesso;
    }

    /// <summary>È arrivato un fotogramma nuovo dall'app.</summary>
    public void Vivo(long adesso) => ultimoVivo = adesso;

    /// <summary>
    /// null: si mostra il video (anche l'ultimo fotogramma ripetuto, durante la tenuta). Altrimenti l'attesa da mostrare.
    /// <list type="bullet">
    /// <item>I fotogrammi arrivati dopo l'ultimo cambio di stato vincono: lo stato può arrivare un po' dopo il video.</item>
    /// <item>Collegamento interrotto e WebcamLR chiusa: l'ultima immagine resta per <see cref="TenutaMs"/>, poi l'attesa.</item>
    /// <item>Senza attesa (il telefono dovrebbe mandare): se il video si ferma per <see cref="TenutaMs"/> è un'interruzione;
    /// se non è ancora arrivato resta l'attesa di prima (per esempio la pausa, finché il video riparte).</item>
    /// </list>
    /// </summary>
    public StatoAttesa? Decidi(long adesso)
    {
        var recente = ultimoVivo != 0 && adesso - ultimoVivo < TenutaMs;
        StatoAttesa? deciso;
        if (Stato != StatoAttesa.Nessuna)
        {
            var tieni = Stato == StatoAttesa.Interrotta || AppChiusa;
            deciso = recente && (ultimoVivo > statoDa || tieni) ? null : Stato;
        }
        else if (recente)
        {
            deciso = null;
        }
        else if (ultimoVivo != 0 && ultimoVivo > statoDa)
        {
            deciso = StatoAttesa.Interrotta;
        }
        else
        {
            deciso = ultimaAttesa;
        }
        if (deciso is { } attesa) ultimaAttesa = attesa;
        return deciso;
    }
}
