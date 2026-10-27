using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Il ritardo «da vetro a uscita» (Protocollo.md, «Latenza»): conto, mediana, fotogramma mostrato, recupero.</summary>
public class RitardoUscitaTest
{
    [Fact]
    public void IlRitardoSiContaDallaCatturaConLoScartoDegliOrologi()
    {
        // Il telefono è 5 secondi avanti: la cattura a 5_100_000 sul telefono è 100_000 sul computer.
        const long scarto = 5_000_000;
        Assert.Equal(72, RitardoVetro.Ms(5_100_000, scarto, 172_400));
        // Uscita prima della cattura (orologi appena cambiati): non credibile.
        Assert.Null(RitardoVetro.Ms(5_100_000, scarto, 99_000));
        // Oltre 10 secondi: non credibile.
        Assert.Null(RitardoVetro.Ms(5_100_000, scarto, 100_000 + 10_000_000));
        // Valori assurdi dalla rete non fanno traboccare nulla.
        Assert.Null(RitardoVetro.Ms(ulong.MaxValue, long.MinValue, 0));
    }

    [Fact]
    public void LaLatenzaMostrataPreferisceLaWebcamPoiLAnteprimaPoiLArrivo()
    {
        Assert.Equal(80, RitardoVetro.Latenza(80, 60, 40));
        Assert.Equal(60, RitardoVetro.Latenza(null, 60, 40));
        Assert.Equal(40, RitardoVetro.Latenza(null, null, 40));
        Assert.Null(RitardoVetro.Latenza(null, null, null));
    }

    [Fact]
    public void LaMisuraEUnaMedianaDiUnSecondoCheScade()
    {
        var misura = new MisuraRitardo();
        Assert.Null(misura.Valore(0));
        ulong t = 1_000_000;
        foreach (var ms in new[] { 70, 300, 65, 72, 68 })
        {
            misura.Aggiungi(ms, t);
            t += 100_000;
        }
        // Il secondo non è ancora finito.
        Assert.Null(misura.Valore(t));
        // Finito: la mediana, non il picco da 300 ms.
        Assert.Equal(70, misura.Valore(2_000_000));
        // Chiunque la legga, il valore resta (anteprima, webcam e sessione leggono la stessa misura).
        Assert.Equal(70, misura.Valore(2_500_000));
        // Nessun fotogramma da più di 2 secondi: non vale più.
        Assert.Null(misura.Valore(4_100_000));
    }

    [Fact]
    public void IlFotogrammaMostratoEQuelloConIlTempoPiuGrandeNonOltreLaPosizione()
    {
        var traccia = new TracciaFotogrammi();
        Assert.Null(traccia.Mostrato(0));
        // Tre fotogrammi a 30 fps, con il timestamp del telefono.
        traccia.Aggiungi(0, 1_000);
        traccia.Aggiungi(33_333, 34_333);
        traccia.Aggiungi(66_666, 67_666);
        Assert.Equal(1_000UL, traccia.Mostrato(10_000));
        Assert.Equal(34_333UL, traccia.Mostrato(50_000));
        // Un pelo prima del tempo del fotogramma: è già quello (tolleranza di 2 ms).
        Assert.Equal(67_666UL, traccia.Mostrato(65_000));
        // Molto dopo: l'ultimo dato al decodificatore.
        Assert.Equal(67_666UL, traccia.Mostrato(1_000_000));
        // Prima del primo: nessuno.
        Assert.Null(traccia.Mostrato(-10_000));
    }

    [Fact]
    public void LaTracciaTieneSoloGliUltimiFotogrammi()
    {
        var traccia = new TracciaFotogrammi();
        for (var i = 0; i < TracciaFotogrammi.Capacita + 10; i++) traccia.Aggiungi(i * 33_333L, (ulong)i);
        // I primi 10 sono usciti: per una posizione così vecchia non c'è più niente.
        Assert.Null(traccia.Mostrato(5 * 33_333L));
        Assert.Equal((ulong)(TracciaFotogrammi.Capacita + 9), traccia.Mostrato(long.MaxValue - TracciaFotogrammi.Tolleranza));
        traccia.Azzera();
        Assert.Null(traccia.Mostrato(long.MaxValue - TracciaFotogrammi.Tolleranza));
    }

    [Fact]
    public void IlRecuperoTogliLAttesaCostanteAPiccoliPassi()
    {
        var recupero = new RecuperoRitardo();
        // Il lettore tiene ogni fotogramma 80 ms prima di mostrarlo (il primo era arrivato tardi).
        var anticipo = 80_000L;
        var passi = new List<long>();
        for (var i = 0; i < 200; i++)
        {
            var passo = recupero.Aggiungi(anticipo);
            Assert.InRange(passo, 0, RecuperoRitardo.PassoMassimo);
            passi.Add(passo);
            anticipo -= passo;
        }
        // Per i primi 29 non si fa nulla: serve una finestra intera.
        Assert.All(passi.Take(RecuperoRitardo.Finestra - 1), p => Assert.Equal(0, p));
        // Alla fine resta solo la soglia: 60 ms recuperati, 2 ms alla volta.
        Assert.Equal(RecuperoRitardo.Soglia, anticipo);
        Assert.Equal(60_000, recupero.Spostamento);
    }

    [Fact]
    public void IlRecuperoNonToccaUnLettoreGiaPuntuale()
    {
        var recupero = new RecuperoRitardo();
        var casuale = new Random(7);
        for (var i = 0; i < 300; i++)
        {
            // Anticipo tra -10 e +40 ms: ogni tanto sotto la soglia, quindi l'attesa non è costante.
            var anticipo = i % 10 == 0 ? 5_000 : casuale.Next(-10_000, 40_000);
            Assert.Equal(0, recupero.Aggiungi(anticipo));
        }
        Assert.Equal(0, recupero.Spostamento);
    }

    [Fact]
    public void UnaPosizioneNonCredibileFermaIlRecupero()
    {
        var recupero = new RecuperoRitardo();
        for (var i = 0; i < 40; i++)
        {
            // Una posizione ferma a zero (il lettore non la aggiorna): l'anticipo cresce senza fine.
            Assert.Equal(0, recupero.Aggiungi(3_000_000 + i * 33_333L));
        }
        Assert.Equal(0, recupero.Spostamento);
    }

    [Fact]
    public void IlRecuperoHaUnLimite()
    {
        var recupero = new RecuperoRitardo();
        for (var i = 0; i < 1_000; i++) recupero.Aggiungi(1_500_000);
        Assert.Equal(RecuperoRitardo.LimiteTotale, recupero.Spostamento);
        recupero.Azzera();
        Assert.Equal(0, recupero.Spostamento);
    }

    [Fact]
    public void LoStabilizzatoreTieneIlMassimoDiCinqueSecondi()
    {
        var stabile = new StabilizzatoreRitardo();
        Assert.Null(stabile.Voluto);
        stabile.Aggiungi(80, 0);
        stabile.Aggiungi(120, 500_000);
        stabile.Aggiungi(90, 1_000_000);
        Assert.Equal(120, stabile.Voluto);
        stabile.Aggiungi(90, 4_900_000);
        Assert.Equal(120, stabile.Voluto);
        // Cinque secondi dopo il secondo dei 120 ms.
        stabile.Aggiungi(90, 5_000_000);
        Assert.Equal(90, stabile.Voluto);
    }
}
