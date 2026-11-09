using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>
/// Qualità 14: la coda di ricezione che si adatta (CodaAdattiva.cs), con tempi finti. La stessa logica gira sul Mac
/// (Mac/Sorgenti/CodaAdattiva.swift), che qui non si può provare: questi test valgono anche per lei.
/// </summary>
public class CodaAdattivaTest
{
    private const long Fotogramma = 33_333;

    /// <summary>Mac: i fotogrammi catturati ogni 33 ms, pronti dopo <paramref name="transiti"/>; quanti escono tardi.</summary>
    private static int Simula(CodaAdattiva coda, IEnumerable<long> transiti, ref long cattura)
    {
        var tardi = 0;
        foreach (var transito in transiti)
        {
            var pronto = (ulong)(cattura + transito);
            var uscita = coda.Uscita(cattura, pronto);
            Assert.NotNull(uscita);
            if (uscita < pronto) tardi++;
            cattura += Fotogramma;
        }
        return tardi;
    }

    private static IEnumerable<long> Stabili(int quanti, long base_, int seme)
    {
        var casuale = new Random(seme);
        for (var i = 0; i < quanti; i++) yield return base_ + casuale.Next(-500, 500);
    }

    private static IEnumerable<long> ConJitter(int quanti, long base_, int jitter, int seme)
    {
        var casuale = new Random(seme);
        for (var i = 0; i < quanti; i++) yield return base_ + casuale.Next(0, jitter);
    }

    [Fact]
    public void LAttesaCostanteSiTogliePianoPiano()
    {
        // Windows: il lettore tiene ogni campione 80 ms prima di mostrarlo (il primo era arrivato tardi).
        var coda = new CodaAdattiva();
        var passi = new List<long>();
        long margine = 80_000;
        for (var i = 0; i < 300; i++)
        {
            var passo = coda.Aggiungi(margine);
            Assert.InRange(passo, 0, CodaAdattiva.PassoMassimo);
            passi.Add(passo);
            margine -= passo;
        }
        // Per i primi 29 non si fa nulla: non si sa ancora come arriva il video.
        Assert.All(passi.Take(CodaAdattiva.Minimi - 1), p => Assert.Equal(0, p));
        Assert.InRange(margine, CodaAdattiva.ObiettivoWindows, CodaAdattiva.ObiettivoWindows + CodaAdattiva.Isteresi);
        Assert.Equal(80_000 - margine, coda.Spostamento);
    }

    [Fact]
    public void UnLettoreGiaPuntualeNonSiTocca()
    {
        var coda = new CodaAdattiva();
        var casuale = new Random(7);
        for (var i = 0; i < 600; i++)
        {
            // Sempre tra l'obiettivo e l'obiettivo più l'isteresi: niente da fare.
            var margine = CodaAdattiva.ObiettivoWindows + casuale.Next(0, (int)CodaAdattiva.Isteresi);
            Assert.Equal(0, coda.Aggiungi(margine));
        }
        Assert.Equal(0, coda.Spostamento);
    }

    [Fact]
    public void ConLaReteStabileLaCodaEMinima()
    {
        // Il cavo: 8 ms dalla cattura all'immagine pronta, ±0,5 ms. Il primo fotogramma era più lento (fotogramma chiave).
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 1_000_000;
        Simula(coda, [40_000], ref cattura);
        Simula(coda, Stabili(600, 8_000, 1), ref cattura);
        var tardi = Simula(coda, Stabili(300, 8_000, 2), ref cattura);
        Assert.Equal(0, tardi);
        // Pochi millisecondi di attesa: l'obiettivo, l'isteresi e il mezzo millisecondo di variazione.
        Assert.InRange(coda.Profondita, CodaAdattiva.ObiettivoMac, CodaAdattiva.ObiettivoMac + CodaAdattiva.Isteresi + 1_000);
    }

    [Fact]
    public void ConIlJitterLaCodaCresceQuantoBasta()
    {
        // Wi-Fi: 10 ms più da 0 a 30 ms a caso.
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 1_000_000;
        Simula(coda, ConJitter(300, 10_000, 30_000, 3), ref cattura);
        const int dopo = 1_800;
        var tardi = Simula(coda, ConJitter(dopo, 10_000, 30_000, 4), ref cattura);
        // Pochi fotogrammi in ritardo (il 2% tollerato, più poco) e una coda appena più lunga della variazione.
        Assert.True(tardi <= dopo * 4 / 100, $"{tardi} in ritardo su {dopo}");
        Assert.InRange(coda.Profondita, 25_000, 40_000);
    }

    [Fact]
    public void QuandoIlJitterFinisceLaCodaTornaMinima()
    {
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 1_000_000;
        Simula(coda, ConJitter(900, 10_000, 30_000, 5), ref cattura);
        Assert.True(coda.Profondita > 20_000);
        // Dopo 5 secondi (la finestra) di rete stabile scende di 2 ms a fotogramma: in 10 secondi è giù.
        Simula(coda, Stabili(300, 10_000, 6), ref cattura);
        Assert.InRange(coda.Profondita, 0, CodaAdattiva.ObiettivoMac + CodaAdattiva.Isteresi + 1_000);
    }

    /// <summary>Una pausa della rete di 110 ms: tre fotogrammi arrivano insieme dopo, con 110, 77 e 44 ms in più.</summary>
    private static IEnumerable<long> ConPause(int quanti, long base_, int ogni)
    {
        for (var i = 0; i < quanti; i++)
        {
            var nellaPausa = i % ogni;
            yield return nellaPausa switch
            {
                0 => base_ + 110_000,
                1 => base_ + 77_000,
                2 => base_ + 44_000,
                _ => base_,
            };
        }
    }

    [Fact]
    public void UnaPausaIsolataNonFaCrescereLaCoda()
    {
        // Una pausa ogni 10 secondi (300 fotogrammi): nella finestra di 5 secondi ce n'è al massimo una.
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 1_000_000;
        Simula(coda, Stabili(200, 10_000, 8), ref cattura);
        var tardi = Simula(coda, ConPause(1_500, 10_000, 300), ref cattura);
        // Solo i tre fotogrammi di ogni pausa escono tardi (lo scatto resta); la coda non si allunga per tutti gli altri.
        Assert.Equal(15, tardi);
        Assert.InRange(coda.Profondita, 0, CodaAdattiva.ObiettivoMac + CodaAdattiva.Isteresi + 1_000);
    }

    [Fact]
    public void UnaPausaCheTornaFaCrescereLaCoda()
    {
        // Una pausa ogni 2 secondi (la prova di Ledion del 27 ottobre): ora la coda la copre quasi tutta.
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 1_000_000;
        Simula(coda, Stabili(200, 10_000, 10), ref cattura);
        Simula(coda, ConPause(1_200, 10_000, 60), ref cattura);
        Assert.InRange(coda.Profondita, 40_000, CodaAdattiva.Tetto);
    }

    [Fact]
    public void IlTettoFermaLaCrescita()
    {
        // Rete pessima: da 0 a 400 ms di variazione. Oltre i 100 ms meglio uno scatto che altro ritardo.
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 1_000_000;
        Simula(coda, ConJitter(1_800, 10_000, 400_000, 11), ref cattura);
        Assert.InRange(coda.Profondita, 0, CodaAdattiva.Tetto + CodaAdattiva.PassoMassimo);
    }

    [Fact]
    public void UnaPosizioneNonCredibileNonCambiaNulla()
    {
        var coda = new CodaAdattiva();
        for (var i = 0; i < 60; i++)
        {
            // Una posizione ferma a zero (il lettore non la aggiorna): l'anticipo cresce senza fine.
            Assert.Equal(0, coda.Aggiungi(3_000_000 + i * Fotogramma));
        }
        Assert.Equal(0, coda.Spostamento);
    }

    [Fact]
    public void SegueUnaDerivaLentaPerDueOre()
    {
        // Collaudo 38: l'orologio del telefono corre lo 0,1% più del lettore (1 ms ogni secondo, 7,2 s in due ore).
        // Nessun tetto allo spostamento totale: l'attesa resta vicina all'obiettivo per tutta la chiamata.
        var coda = new CodaAdattiva();
        const int fotogrammi = 2 * 60 * 60 * 30;
        long margine = 0;
        for (var i = 1; i <= fotogrammi; i++)
        {
            margine = i * 1_000L / 30 + CodaAdattiva.ObiettivoWindows - coda.Spostamento;
            Assert.InRange(coda.Aggiungi(margine), -CodaAdattiva.PassoMassimo, CodaAdattiva.PassoMassimo);
        }
        Assert.True(coda.Spostamento > 7_100_000, $"Spostamento {coda.Spostamento}");
        // Il «basso» è tra i margini più vecchi della finestra: con la deriva l'ultimo è avanti di al massimo 5 ms (150
        // fotogrammi × 33 µs).
        Assert.InRange(margine, CodaAdattiva.ObiettivoWindows - CodaAdattiva.PassoMassimo,
            CodaAdattiva.ObiettivoWindows + CodaAdattiva.Isteresi + CodaAdattiva.PassoMassimo + 5_000);
        coda.Azzera();
        Assert.Equal(0, coda.Spostamento);
        Assert.Equal(0, coda.Profondita);
    }

    [Fact]
    public void IlPrimoFotogrammaEsceConIlMargineVoluto()
    {
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        Assert.Equal((ulong)(100_000 + 9_000 + CodaAdattiva.ObiettivoMac), coda.Uscita(100_000, 109_000));
        // Pronto prima della cattura, o oltre 10 secondi dopo: non credibile, esce subito.
        Assert.Null(coda.Uscita(200_000, 150_000));
        Assert.Null(coda.Uscita(200_000, 200_000 + 10_000_000));
    }

    [Fact]
    public void OrologiCambiatiDiColpoRipartono()
    {
        var coda = new CodaAdattiva(CodaAdattiva.ObiettivoMac);
        long cattura = 10_000_000;
        Simula(coda, Stabili(100, 10_000, 12), ref cattura);
        // Un pong migliore sposta lo scarto di 3 secondi: il transito ora sembra 3 secondi più lungo.
        var spostata = cattura - 3_000_000;
        var pronto = (ulong)(cattura + 10_000);
        Assert.Equal(pronto + (ulong)CodaAdattiva.ObiettivoMac, coda.Uscita(spostata, pronto));
    }

    [Fact]
    public void SiMostraSoloLUltimaImmagineGiaScaduta()
    {
        Assert.Equal(0, CodaAdattiva.DaScartare([], 100, 1));
        // Tutte nel futuro: nessuna da buttare.
        Assert.Equal(0, CodaAdattiva.DaScartare([200, 300], 100, 1));
        // Una sola scaduta: esce lei.
        Assert.Equal(0, CodaAdattiva.DaScartare([100, 300], 100, 1));
        // Due scadute (arrivate a gruppo dopo una pausa): la prima non serve più.
        Assert.Equal(1, CodaAdattiva.DaScartare([50, 99, 300], 100, 1));
        Assert.Equal(2, CodaAdattiva.DaScartare([10, 20, 30], 100, 1));
        // L'anticipo conta: 101 è al suo momento con 1 µs di anticipo.
        Assert.Equal(1, CodaAdattiva.DaScartare([90, 101, 103], 100, 1));
    }

    [Fact]
    public void LaDecodificaEIlRestoDellAnteprima()
    {
        Assert.Equal(30, PartiLatenza.Decodifica(70, 30, 10));
        // Mediane di secondi diversi: la somma delle parti può superare il totale, ma mai sotto zero.
        Assert.Equal(0, PartiLatenza.Decodifica(50, 40, 20));
        Assert.Null(PartiLatenza.Decodifica(null, 30, 10));
        Assert.Null(PartiLatenza.Decodifica(70, null, 10));
        Assert.Null(PartiLatenza.Decodifica(70, 30, null));
    }
}
