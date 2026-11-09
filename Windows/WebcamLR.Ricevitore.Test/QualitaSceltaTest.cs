using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Qualità 15: Auto, Alta, Massima dal PC (Documenti/Protocollo.md, «Qualità a scelta»).</summary>
public class QualitaSceltaTest
{
    private static readonly IReadOnlyList<FormatoSupportato> FormatiPro =
        [new(1280, 720, 60), new(1920, 1080, 60), new(3840, 2160, 30)];

    private static Capacita ConPro(bool sceltaQualita = true) =>
        new(["principale"], 5, true, Formati: FormatiPro, Pro: true, SceltaQualita: sceltaQualita ? true : null);

    [Fact]
    public void SoloConUnTelefonoCheLaSa()
    {
        Assert.True(QualitaScelta.Disponibile(ConPro()));
        // Telefono vecchio: niente campo, niente scelta nel menu.
        Assert.False(QualitaScelta.Disponibile(ConPro(sceltaQualita: false)));
        Assert.False(QualitaScelta.Disponibile(null));
    }

    [Fact]
    public void LaSpuntaSegueIlTelefono()
    {
        var stato = new StatoTelefono(80, true, Temperatura.Normale, "principale", Qualita: LivelliQualita.Alta);
        Assert.Equal(LivelliQualita.Alta, QualitaScelta.InUso(stato, LivelliQualita.Massima));
        // Prima dello stato: quella scelta sul PC; un valore sconosciuto vale Auto.
        Assert.Equal(LivelliQualita.Massima, QualitaScelta.InUso(null, LivelliQualita.Massima));
        Assert.Equal(LivelliQualita.Auto, QualitaScelta.InUso(stato with { Qualita = "altissima" }, LivelliQualita.Alta));
    }

    [Fact]
    public void MassimaChiedePrimaIlFormatoPiuAlto()
    {
        var attuale = new FormatoVideo(Codec.H264, 1920, 1080, 30);
        // Con Pro il 4K, in HEVC.
        Assert.Equal(new FormatoVideo(Codec.Hevc, 3840, 2160, 30),
            QualitaScelta.FormatoPrima(LivelliQualita.Massima, selezionato: true, ConPro(), attuale));
        // Solo al telefono nella webcam, e solo con Massima.
        Assert.Null(QualitaScelta.FormatoPrima(LivelliQualita.Massima, selezionato: false, ConPro(), attuale));
        Assert.Null(QualitaScelta.FormatoPrima(LivelliQualita.Alta, selezionato: true, ConPro(), attuale));
        // Gratis il telefono dichiara solo 720p 30: è già quello, niente da chiedere.
        var gratis = new Capacita(["principale"], 5, true, Formati: [new(1280, 720, 30)], Pro: false, SceltaQualita: true,
            FormatiPro: [new(1920, 1080, 60)]);
        Assert.Null(QualitaScelta.FormatoPrima(LivelliQualita.Massima, true, gratis, new FormatoVideo(Codec.H264, 1280, 720, 30)));
    }

    [Fact]
    public void UnaRisoluzioneInMassimaPortaAdAlta()
    {
        var massima = new StatoTelefono(80, true, Temperatura.Normale, "principale", Qualita: LivelliQualita.Massima);
        Assert.Equal(LivelliQualita.Alta, QualitaScelta.DopoUnaRisoluzione(ConPro(), massima, LivelliQualita.Massima));
        Assert.Null(QualitaScelta.DopoUnaRisoluzione(ConPro(), massima with { Qualita = LivelliQualita.Auto }, LivelliQualita.Auto));
        Assert.Null(QualitaScelta.DopoUnaRisoluzione(ConPro(sceltaQualita: false), massima, LivelliQualita.Massima));
        Assert.True(QualitaScelta.CambiaRisoluzione(LivelliQualita.Auto, LivelliQualita.Massima));
        Assert.True(QualitaScelta.CambiaRisoluzione(LivelliQualita.Massima, LivelliQualita.Alta));
        Assert.False(QualitaScelta.CambiaRisoluzione(LivelliQualita.Auto, LivelliQualita.Alta));
    }
}
