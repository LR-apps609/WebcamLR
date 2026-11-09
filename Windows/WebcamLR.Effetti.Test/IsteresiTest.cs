using Xunit;

namespace WebcamLR.Effetti.Test;

/// <summary>Qualità 4: l'isteresi nel tempo della maschera (IsteresiMaschera), come il filtro nel tempo del Mac.</summary>
public class IsteresiTest
{
    private static float[] Fermo(int n) => Enumerable.Repeat(MediaNelMovimento.PesoFermo, n).ToArray();

    [Fact]
    public void UnPuntoIncertoNonSaltaDallAltraParte()
    {
        // Un punto persona (0,55) che poi oscilla tra 0,45 e 0,55: resta persona, sempre sopra 0,5 (il centro della
        // soglia del bordo), invece di passare tra nitido e sfocato a ogni fotogramma.
        var isteresi = new IsteresiMaschera();
        var pesi = Fermo(1);
        foreach (var v in new[] { 0.55f, 0.45f, 0.55f, 0.45f, 0.42f, 0.55f })
        {
            var m = new[] { v };
            isteresi.Applica(m, pesi);
            Assert.InRange(m[0], 0.5f, 1f);
            Assert.Equal(v + IsteresiMaschera.Spinta, m[0], 4);
        }
        // E uno sfondo incerto resta sfondo.
        var sfondo = new IsteresiMaschera();
        foreach (var v in new[] { 0.45f, 0.58f, 0.52f, 0.59f })
        {
            var m = new[] { v };
            sfondo.Applica(m, pesi);
            Assert.InRange(m[0], 0f, 0.5f);
        }
    }

    [Fact]
    public void CambiaStatoOltreLeSoglie()
    {
        var isteresi = new IsteresiMaschera();
        var pesi = Fermo(1);
        var m = new[] { 0.2f };
        isteresi.Applica(m, pesi);
        Assert.Equal(0.1f, m[0], 4);
        m[0] = 0.65f; // sopra 0,6: diventa persona
        isteresi.Applica(m, pesi);
        Assert.Equal(0.75f, m[0], 4);
        m[0] = 0.41f; // sopra 0,4: resta persona
        isteresi.Applica(m, pesi);
        Assert.Equal(0.51f, m[0], 4);
        m[0] = 0.35f; // sotto 0,4: torna sfondo
        isteresi.Applica(m, pesi);
        Assert.Equal(0.25f, m[0], 4);
    }

    [Fact]
    public void DoveLImmagineSiMuoveValeLaMascheraNuova()
    {
        // Peso della media dal movimento a 1 (l'immagine cambia): niente spinta, nessuna scia.
        var isteresi = new IsteresiMaschera();
        var m = new[] { 0.55f, 0.3f };
        isteresi.Applica(m, Fermo(2));
        m[0] = 0.45f;
        m[1] = 0.58f;
        isteresi.Applica(m, [1f, 1f]);
        Assert.Equal(0.45f, m[0], 4);
        Assert.Equal(0.58f, m[1], 4);
        // A metà strada metà spinta.
        var mezzo = (1f + MediaNelMovimento.PesoFermo) / 2;
        m[0] = 0.45f;
        isteresi.Applica(m, [mezzo, mezzo]);
        Assert.Equal(0.45f + IsteresiMaschera.Spinta / 2, m[0], 4);
    }

    [Fact]
    public void ValoriTraZeroEUnoEDimentica()
    {
        var isteresi = new IsteresiMaschera();
        var m = new[] { 0.98f, 0.03f };
        isteresi.Applica(m, Fermo(2));
        Assert.Equal(1f, m[0]);
        Assert.Equal(0f, m[1]);
        // Dopo Dimentica si riparte dal centro: 0,45 è sfondo anche se prima era persona.
        isteresi.Dimentica();
        m = [0.45f, 0.45f];
        isteresi.Applica(m, Fermo(2));
        Assert.Equal(0.35f, m[0], 4);
        Assert.Throws<ArgumentException>(() => isteresi.Applica(new float[2], new float[3]));
    }
}
