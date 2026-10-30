using WebcamLR.Webcam;
using Xunit;

namespace WebcamLR.Webcam.Test;

/// <summary>Quando la webcam passa dal video all'attesa e ritorno: le regole del Mac più «WebcamLR chiusa».</summary>
public class ProgrammaAttesaTest
{
    private readonly ProgrammaAttesa programma = new();

    /// <summary>Fotogrammi ogni 33 ms da <paramref name="da"/> a <paramref name="a"/> (escluso).</summary>
    private void Video(long da, long a)
    {
        for (var t = da; t < a; t += 33) programma.Vivo(t);
    }

    [Fact]
    public void AllInizioNonCollegata()
    {
        Assert.Equal(StatoAttesa.NonCollegata, programma.Decidi(1000));
        programma.Imposta(StatoAttesa.Nessuna, appChiusa: false, 1000);
        // Il telefono dovrebbe mandare, ma il video non c'è ancora: resta l'attesa di prima.
        Assert.Equal(StatoAttesa.NonCollegata, programma.Decidi(1500));
        programma.Vivo(1600);
        Assert.Null(programma.Decidi(1600));
    }

    [Fact]
    public void InterruzioneTieneLUltimaImmagineDueSecondi()
    {
        programma.Imposta(StatoAttesa.Nessuna, false, 1000);
        Video(1000, 5000);
        Assert.Null(programma.Decidi(5000));
        // Il telefono si perde: l'app lo dice subito, ma l'ultima immagine resta per 2 secondi dall'ultimo fotogramma.
        programma.Imposta(StatoAttesa.Interrotta, false, 5100);
        Assert.Null(programma.Decidi(5100));
        Assert.Null(programma.Decidi(6900));
        Assert.Equal(StatoAttesa.Interrotta, programma.Decidi(7000));
    }

    [Fact]
    public void VideoFermoSenzaStatoDiventaInterruzione()
    {
        programma.Imposta(StatoAttesa.Nessuna, false, 1000);
        Video(1000, 3000);
        Assert.Null(programma.Decidi(4900));
        Assert.Equal(StatoAttesa.Interrotta, programma.Decidi(4999));
        // Il video riparte: vince subito.
        programma.Vivo(5200);
        Assert.Null(programma.Decidi(5200));
    }

    [Fact]
    public void PausaSubito()
    {
        programma.Imposta(StatoAttesa.Nessuna, false, 1000);
        Video(1000, 3000);
        programma.Imposta(StatoAttesa.Pausa, false, 3000);
        Assert.Equal(StatoAttesa.Pausa, programma.Decidi(3000));
        // Un fotogramma arrivato dopo il cambio vince (lo stato può arrivare prima delle ultime immagini).
        programma.Vivo(3010);
        Assert.Null(programma.Decidi(3010));
        // Si esce dalla pausa: finché il video non riparte resta la pausa, non «interrotto».
        programma.Imposta(StatoAttesa.Nessuna, false, 8000);
        Assert.Equal(StatoAttesa.Pausa, programma.Decidi(8500));
        programma.Vivo(9000);
        Assert.Null(programma.Decidi(9000));
    }

    [Fact]
    public void TelefonoScollegatoDallUtenteSubito()
    {
        programma.Imposta(StatoAttesa.Nessuna, false, 1000);
        Video(1000, 3000);
        programma.Imposta(StatoAttesa.NonCollegata, false, 3000);
        Assert.Equal(StatoAttesa.NonCollegata, programma.Decidi(3000));
    }

    [Fact]
    public void AppChiusaTieneLUltimaImmagineEPoiLoDice()
    {
        programma.Imposta(StatoAttesa.Nessuna, false, 1000);
        Video(1000, 3000);
        // WebcamLR si chiude (SegnalaChiusura) mentre un'app usa la webcam: «WebcamLR è chiusa», non «non collegata».
        programma.Imposta(StatoAttesa.Nessuna, appChiusa: true, 3000);
        Assert.Equal(StatoAttesa.AppChiusa, programma.Stato);
        Assert.Null(programma.Decidi(4000));
        Assert.Null(programma.Decidi(4960));
        Assert.Equal(StatoAttesa.AppChiusa, programma.Decidi(5000));
    }

    [Fact]
    public void UnaAppCheNonScriveLoStatoFunzionaLoStesso()
    {
        // Un'app che manda solo i fotogrammi (o una versione vecchia): vale «chiusa», ma il video passa.
        programma.Imposta(StatoAttesa.Nessuna, appChiusa: true, 0);
        Assert.Equal(StatoAttesa.AppChiusa, programma.Decidi(500));
        Video(1000, 3000);
        Assert.Null(programma.Decidi(3000));
        Assert.Null(programma.Decidi(4900));
        Assert.Equal(StatoAttesa.AppChiusa, programma.Decidi(5000));
    }

    [Fact]
    public void LUltimaAttesaRestaFinchéNonArrivaIlVideo()
    {
        programma.Imposta(StatoAttesa.Interrotta, false, 1000);
        Assert.Equal(StatoAttesa.Interrotta, programma.Decidi(1000));
        // Riconnesso: il telefono dovrebbe mandare, ma il decodificatore aspetta un fotogramma chiave.
        programma.Imposta(StatoAttesa.Nessuna, false, 2000);
        Assert.Equal(StatoAttesa.Interrotta, programma.Decidi(3500));
        programma.Vivo(3600);
        Assert.Null(programma.Decidi(3600));
    }
}
