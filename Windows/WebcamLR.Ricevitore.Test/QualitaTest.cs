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
}
