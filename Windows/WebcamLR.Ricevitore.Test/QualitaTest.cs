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
