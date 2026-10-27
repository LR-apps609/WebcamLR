using Xunit;

namespace WebcamLR.Effetti.Test;

public class PreparazioneTest
{
    [Fact]
    public void RiduceConLaMediaEPassaDaBgraARgb()
    {
        // 4×2 BGRA con 4 byte in più per riga (passo 20): due blocchi 2×2, uno rosso e uno blu sfumato.
        const int passo = 20;
        var bgra = new byte[passo * 2];
        void Pixel(int x, int y, byte b, byte g, byte r) { var i = y * passo + x * 4; bgra[i] = b; bgra[i + 1] = g; bgra[i + 2] = r; bgra[i + 3] = 255; }
        Pixel(0, 0, 0, 0, 200); Pixel(1, 0, 0, 0, 200); Pixel(0, 1, 0, 0, 100); Pixel(1, 1, 0, 0, 100);
        Pixel(2, 0, 40, 0, 0); Pixel(3, 0, 80, 0, 0); Pixel(2, 1, 120, 0, 0); Pixel(3, 1, 160, 0, 0);
        bgra[4 * 4] = 99; // il riempimento a fine riga non conta

        var rgb = new float[2 * 1 * 3];
        Preparazione.BgraInRgb(bgra, 4, 2, passo, rgb, 2, 1, 1f, 0f);
        Assert.Equal([150f, 0f, 0f, 0f, 0f, 100f], rgb);

        // Normalizzazione del modello pieno: [-1, 1].
        Preparazione.BgraInRgb(bgra, 4, 2, passo, rgb, 2, 1, 1f / 127.5f, -1f);
        Assert.Equal(150f / 127.5f - 1f, rgb[0], 5);
        Assert.Equal(-1f, rgb[1], 5);
    }

    [Fact]
    public void ImmaginePiuPiccolaDelModelloPrendeIlPixelPiuVicino()
    {
        var bgra = new byte[] { 10, 20, 30, 255, 40, 50, 60, 255 }; // 2×1
        var rgb = new float[4 * 1 * 3];
        Preparazione.BgraInRgb(bgra, 2, 1, 8, rgb, 4, 1, 1f, 0f);
        Assert.Equal([30f, 20f, 10f, 30f, 20f, 10f, 60f, 50f, 40f, 60f, 50f, 40f], rgb);
    }

    [Fact]
    public void ImmagineCortaODestinazionePiccolaSonoErrori()
    {
        var rgb = new float[3];
        Assert.Throws<ArgumentException>(() => Preparazione.BgraInRgb(new byte[7], 2, 1, 8, rgb, 1, 1, 1f, 0f));
        Assert.Throws<ArgumentException>(() => Preparazione.BgraInRgb(new byte[8], 2, 1, 4, rgb, 1, 1, 1f, 0f));
        Assert.Throws<ArgumentException>(() => Preparazione.BgraInRgb(new byte[8], 2, 1, 8, rgb, 2, 1, 1f, 0f));
    }

    [Fact]
    public void PersonaEUnoMenoSfondoConPiuClassi()
    {
        // Due punti, sei classi (somma 1): sfondo 0,9 poi 0,2.
        float[] uscita = [0.9f, 0.02f, 0.02f, 0.02f, 0.02f, 0.02f, 0.2f, 0.3f, 0.1f, 0.1f, 0.2f, 0.1f];
        var persona = new float[2];
        Preparazione.Persona(uscita, 6, persona);
        Assert.Equal(0.1f, persona[0], 5);
        Assert.Equal(0.8f, persona[1], 5);
    }

    [Fact]
    public void ConUnCanaleEDirettamenteLaPersonaNeiLimiti()
    {
        var persona = new float[3];
        Preparazione.Persona([0.25f, 1.2f, -0.1f], 1, persona);
        Assert.Equal([0.25f, 1f, 0f], persona);
    }
}

public class FiltroTemporaleTest
{
    [Fact]
    public void LaPrimaPassaComE()
    {
        var f = new FiltroTemporale();
        float[] m = [0.2f, 0.8f];
        f.Applica(m);
        Assert.Equal([0.2f, 0.8f], m);
    }

    [Fact]
    public void IlTremolioSiSmorzaIlMovimentoPassaSubito()
    {
        var f = new FiltroTemporale();
        f.Applica(new float[] { 0.5f, 0f });
        // +0,02: peso 0,7 + 3 × 0,02 = 0,76 → 0,5 + 0,02 × 0,76. Da 0 a 1: peso 1, subito il nuovo valore.
        float[] m = [0.52f, 1f];
        f.Applica(m);
        Assert.Equal(0.5f + 0.02f * 0.76f, m[0], 5);
        Assert.Equal(1f, m[1]);
    }

    [Fact]
    public void DopoDimenticaRipartePulito()
    {
        var f = new FiltroTemporale();
        f.Applica(new float[] { 0f });
        f.Dimentica();
        float[] m = [0.05f];
        f.Applica(m);
        Assert.Equal(0.05f, m[0]);
    }
}

public class MisuraVelocitaTest
{
    [Fact]
    public void IlRiscaldamentoNonContaEPoiDecideDopoLaProva()
    {
        var m = new MisuraVelocita();
        for (var i = 0; i < MisuraVelocita.Riscaldamento; i++) Assert.False(m.Aggiungi(500));
        Assert.Equal(0, m.MediaMs);
        for (var i = 0; i < MisuraVelocita.Prova - 1; i++) Assert.False(m.Aggiungi(40));
        Assert.True(m.Aggiungi(40));
        Assert.Equal(40, m.MediaMs, 3);
    }

    [Fact]
    public void SottoIlLimiteSiResta()
    {
        var m = new MisuraVelocita();
        for (var i = 0; i < 100; i++) Assert.False(m.Aggiungi(MisuraVelocita.LimiteMs - 5));
    }
}
