using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>I test controllano i testi italiani: la lingua si fissa prima di tutto, qualunque sia quella del sistema.</summary>
internal static class LinguaDeiTest
{
    [ModuleInitializer]
    internal static void Imposta() => Lingua.Imposta(Lingua.Italiano);
}

/// <summary>Testi in italiano e inglese (W2): Risorse/Testi.resx e Risorse/Testi.en.resx.</summary>
public class LinguaTest
{
    private static readonly Regex Segnaposto = new(@"\{(\d+)(?:[:,][^}]*)?\}");

    private static IReadOnlyList<string> Segnaposti(string testo) =>
        Segnaposto.Matches(testo).Select(m => m.Groups[1].Value).Distinct().OrderBy(n => n).ToList();

    [Fact]
    public void OgniChiaveCeInTutteEDueLeLingue()
    {
        var italiano = TestiRicevitore.Voci(Lingua.Italiano);
        var inglese = TestiRicevitore.Voci(Lingua.Inglese);
        Assert.True(italiano.Count > 150, $"solo {italiano.Count} voci italiane");
        Assert.Empty(italiano.Keys.Except(inglese.Keys));
        Assert.Empty(inglese.Keys.Except(italiano.Keys));
        foreach (var (chiave, testo) in italiano)
        {
            Assert.False(string.IsNullOrWhiteSpace(testo), chiave);
            Assert.False(string.IsNullOrWhiteSpace(inglese[chiave]), chiave);
            Assert.True(Segnaposti(testo).SequenceEqual(Segnaposti(inglese[chiave])), $"{chiave}: valori diversi");
            // In inglese le virgolette sono “…” (Documenti/Glossario.md).
            Assert.DoesNotContain("«", inglese[chiave]);
        }
    }

    [Fact]
    public void ScegliItalianoSoloPerLeCultureItaliane()
    {
        Assert.Same(Lingua.Italiano, Lingua.Scegli(new CultureInfo("it-IT")));
        Assert.Same(Lingua.Italiano, Lingua.Scegli(new CultureInfo("it-CH")));
        Assert.Same(Lingua.Italiano, Lingua.Scegli(new CultureInfo("it")));
        Assert.Same(Lingua.Inglese, Lingua.Scegli(new CultureInfo("en-GB")));
        Assert.Same(Lingua.Inglese, Lingua.Scegli(new CultureInfo("de-DE")));
        Assert.Same(Lingua.Inglese, Lingua.Scegli(CultureInfo.InvariantCulture));
    }

    [Fact]
    public void InIngleseITestiCambianoEINumeriHannoIlPunto()
    {
        Assert.Equal("Collegato a Pixel 8", DescrizioneStato.Riga(StatoCollegamento.Collegato, "Pixel 8"));
        using (Lingua.Provvisoria(Lingua.Inglese))
        {
            Assert.Equal("Connected to Pixel 8 · Excellent", DescrizioneStato.Riga(StatoCollegamento.Collegato, "Pixel 8", 40));
            Assert.Equal("No phone", DescrizioneStato.Riga(StatoCollegamento.NessunTelefono, null));
            Assert.Equal("Startup: 0.9 s", MisuraAvvio.TestoDi(TimeSpan.FromMilliseconds(900)));
            Assert.Equal("8.4 MB", Riprese.Byte(8_400_000));
            Assert.Equal("1,234 / 20,000 characters", MemoriaGobbo.TestoCaratteri(1234));
            Assert.Equal("“Pixel” didn’t connect: disconnect one of the two phones and try again.", ElencoTelefoni.MessaggioPieno("Pixel"));
            Assert.Equal("Meeting", ProfiloPronto.Riunione.Nome);
            Assert.All(DomandeFrequenti.Tutte, d => Assert.DoesNotContain("«", d.Risposta));
            Assert.Equal("October 25, 2026", new VersionePubblicata("1.0", null, "2026-10-25", null, null).DataLeggibile);
        }
        // Fuori dal blocco si torna all'italiano.
        Assert.Equal("Avvio: 0,9 s", MisuraAvvio.TestoDi(TimeSpan.FromMilliseconds(900)));
        Assert.Equal("8,4 MB", Riprese.Byte(8_400_000));
    }

    [Fact]
    public void LaDiagnosiParlaInglese()
    {
        using var _ = Lingua.Provvisoria(new CultureInfo("fr-FR"));
        var problemi = Diagnosi.Problemi(new SituazioneRete(false, ProfiloRete.Sconosciuto, StatoFirewall.Sconosciuto, StatoCavo.InAscolto, false));
        Assert.Equal("The PC isn’t connected to a network", problemi[0].Titolo);
        Assert.Equal("Open Wi-Fi settings", problemi[0].Azione!.Testo);
    }
}
