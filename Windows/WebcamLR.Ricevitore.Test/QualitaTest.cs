using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Le soglie devono restare uguali a quelle di Stile/Sources/Stile/Qualita.swift.</summary>
public class QualitaTest
{
    [Theory]
    [InlineData(38, 0, QualitaCollegamento.Ottima)]
    [InlineData(79, 0, QualitaCollegamento.Ottima)]
    [InlineData(80, 0, QualitaCollegamento.Buona)]
    [InlineData(40, 1, QualitaCollegamento.Buona)]
    [InlineData(149, 9, QualitaCollegamento.Buona)]
    [InlineData(150, 0, QualitaCollegamento.Debole)]
    [InlineData(40, 10, QualitaCollegamento.Debole)]
    public void Soglie(int latenzaMs, int perdite, QualitaCollegamento attesa)
    {
        Assert.Equal(attesa, Qualita.Da(latenzaMs, perdite));
    }

    [Theory]
    // Collaudo 20 (t06 B4): «rete 17–24 ms · decodifica 119–347 ms» con il processore al 100%: è il PC, non il Wi-Fi.
    [InlineData(161, 17, true)]
    [InlineData(373, 24, true)]
    // Rete lenta: la colpa è sua.
    [InlineData(200, 160, false)]
    [InlineData(200, 120, false)]
    // Non debole: niente da spiegare.
    [InlineData(120, 10, false)]
    // Senza la parte di rete non si sa.
    [InlineData(300, null, false)]
    public void ColpaDelPc(int latenzaMs, int? reteMs, bool attesa)
    {
        Assert.Equal(attesa, Qualita.ColpaDelPc(latenzaMs, reteMs));
    }

    [Fact]
    public void TestoETacche()
    {
        Assert.Equal("Ottimo", QualitaCollegamento.Ottima.Testo());
        Assert.Equal(1, QualitaCollegamento.Debole.Tacche());
    }

    [Fact]
    public void RicollegaInH264()
    {
        // Passo 7 (windows.md 2.5): stesso video in H.264; il 4K scende a 1080p 30, nello stesso orientamento.
        Assert.Equal(new FormatoVideo(Codec.H264, 1920, 1080, 60), OpzioneQualita.RichiestaH264(new FormatoVideo(Codec.Hevc, 1920, 1080, 60)));
        Assert.Equal(new FormatoVideo(Codec.H264, 1920, 1080, 30), OpzioneQualita.RichiestaH264(new FormatoVideo(Codec.Hevc, 3840, 2160, 30)));
        Assert.Equal(new FormatoVideo(Codec.H264, 1080, 1920, 30), OpzioneQualita.RichiestaH264(new FormatoVideo(Codec.Hevc, 2160, 3840, 30)));
        Assert.Null(OpzioneQualita.RichiestaH264(new FormatoVideo(Codec.H264, 1920, 1080, 30)));
        Assert.Null(OpzioneQualita.RichiestaH264(null));
    }
}
