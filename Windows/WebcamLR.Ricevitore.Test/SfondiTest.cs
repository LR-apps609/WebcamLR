using WebcamLR.Protocollo;
using Xunit;

namespace WebcamLR.Ricevitore.Test;

/// <summary>Il pulsante «Sfondo» del PC: sfondi pronti, «La tua immagine», impronte, riduzione e copia salvata (27 ottobre).</summary>
public class SfondiTest
{
    private static StatoTelefono Stato() => new(80, false, Temperatura.Normale, "principale");

    private static Capacita CapacitaNuove(params string[] pronti) =>
        new(["principale"], 5, true, Sfondo: true, SfondiPronti: pronti, Immagini: true);

    [Fact]
    public void NomiDegliSfondiPronti()
    {
        Assert.Equal(["Ufficio luminoso", "Libreria", "Soggiorno", "Studio scuro", "Città di sera", "Parete di cemento", "Piante",
            "Verde WebcamLR"], SfondiPronti.Tutti.Select(RegoleSfondo.Nome));
        Assert.Equal("La tua immagine", RegoleSfondo.Nome(SfondiPronti.Personale));
        Assert.Equal("Spiaggia", RegoleSfondo.Nome("spiaggia"));
    }

    [Fact]
    public void SoloGliSfondiCheIlTelefonoElenca()
    {
        // Nell'ordine del telefono, senza doppi e senza quelli di cui il PC non ha la miniatura.
        Assert.Equal(["citta", "ufficio"], RegoleSfondo.Pronti(CapacitaNuove("citta", "spiaggia", "ufficio", "citta")));
        Assert.Empty(RegoleSfondo.Pronti(new Capacita(["principale"], 5, true, Sfondo: true)));
        Assert.Empty(RegoleSfondo.Pronti(null));
        Assert.True(RegoleSfondo.Immagini(CapacitaNuove()));
        Assert.False(RegoleSfondo.Immagini(new Capacita(["principale"], 5, true, Sfondo: true)));
    }

    [Fact]
    public void ImmagineConLaSpunta()
    {
        IReadOnlyList<string> pronti = ["libreria", "piante"];
        var spento = ValoriEffetti.Iniziali;
        Assert.Null(RegoleSfondo.ImmagineAttuale(spento, pronti));
        Assert.Null(RegoleSfondo.ImmagineAttuale(spento with { Sfondo = ModiSfondo.Sfocato }, pronti));
        var sostituito = spento with { Sfondo = ModiSfondo.Sostituito };
        Assert.Equal("piante", RegoleSfondo.ImmagineAttuale(sostituito with { ImmagineSfondo = "piante" }, pronti));
        Assert.Equal(SfondiPronti.Personale, RegoleSfondo.ImmagineAttuale(sostituito with { ImmagineSfondo = "personale" }, pronti));
        // Un id sconosciuto (o nessuno) vale il primo sfondo pronto, come sul telefono.
        Assert.Equal("libreria", RegoleSfondo.ImmagineAttuale(sostituito with { ImmagineSfondo = "acquario" }, pronti));
        Assert.Equal("libreria", RegoleSfondo.ImmagineAttuale(sostituito, pronti));
        Assert.Null(RegoleSfondo.ImmagineAttuale(sostituito, []));
    }

    [Fact]
    public void IlClicRiaccendeLUltimaScelta()
    {
        IReadOnlyList<string> pronti = ["libreria", "piante"];
        var spento = ValoriEffetti.Iniziali;
        Assert.Equal(ModiSfondo.Nessuno, RegoleSfondo.Clic(spento with { Sfondo = ModiSfondo.Sfocato }, "piante", true, pronti, false));
        Assert.Equal(ModiSfondo.Nessuno, RegoleSfondo.Clic(spento with { Sfondo = ModiSfondo.Sostituito }, "piante", true, pronti, false));
        Assert.Equal(RegoleSfondo.Sfocatura, RegoleSfondo.Clic(spento, null, true, pronti, false));
        Assert.Equal(RegoleSfondo.Sfocatura, RegoleSfondo.Clic(spento, RegoleSfondo.Sfocatura, true, pronti, false));
        Assert.Equal("piante", RegoleSfondo.Clic(spento, "piante", true, pronti, false));
        // Senza Pro gli sfondi non partono: resta la sfocatura, che è gratis.
        Assert.Equal(RegoleSfondo.Sfocatura, RegoleSfondo.Clic(spento, "piante", false, pronti, false));
        // Uno sfondo che il telefono non ha più, o la tua immagine che non c'è: la sfocatura.
        Assert.Equal(RegoleSfondo.Sfocatura, RegoleSfondo.Clic(spento, "cemento", true, pronti, false));
        Assert.Equal(RegoleSfondo.Sfocatura, RegoleSfondo.Clic(spento, SfondiPronti.Personale, true, pronti, false));
        Assert.Equal(SfondiPronti.Personale, RegoleSfondo.Clic(spento, SfondiPronti.Personale, true, pronti, true));
    }

    [Fact]
    public void LaTuaImmagineSiRimandaSoloSeIlTelefonoNeHaUnAltra()
    {
        // Si mostra con una copia sul PC (e un telefono che la può ricevere) o con un'immagine sul telefono.
        Assert.True(RegoleSfondo.PersonaleDisponibile("aaaa", true, null));
        Assert.False(RegoleSfondo.PersonaleDisponibile("aaaa", false, null));
        Assert.True(RegoleSfondo.PersonaleDisponibile(null, false, "bbbb"));
        Assert.False(RegoleSfondo.PersonaleDisponibile(null, true, null));

        Assert.False(RegoleSfondo.DaRimandare("aaaa", true, "aaaa"));
        Assert.True(RegoleSfondo.DaRimandare("aaaa", true, "bbbb"));
        Assert.True(RegoleSfondo.DaRimandare("aaaa", true, null));
        Assert.False(RegoleSfondo.DaRimandare("aaaa", false, "bbbb"));
        Assert.False(RegoleSfondo.DaRimandare(null, true, "bbbb"));
    }

    [Fact]
    public void ComandiDelloSfondo()
    {
        var effetti = new ControlloEffetti();
        effetti.Capacita(CapacitaNuove("libreria"));
        var comando = effetti.SostituisciSfondo("libreria", 0);
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Sostituito, ImmagineSfondo: "libreria"), comando);
        Assert.Equal("libreria", effetti.Valori.ImmagineSfondo);
        Assert.True(effetti.Valori.SfondoAcceso);
        // Uno stato partito prima non riporta indietro l'immagine appena scelta.
        Assert.False(effetti.Stato(Stato() with { Sfondo = ModiSfondo.Sfocato, ImmagineSfondo = "piante" }, 100));
        Assert.Equal("libreria", effetti.Valori.ImmagineSfondo);
        // Dopo la protezione lo stato vince, e porta anche le impronte di immagine personale e logo.
        Assert.True(effetti.Stato(Stato() with { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = "personale",
            ImmaginePersonale = "0123456789abcdef", Logo = "fedcba9876543210" }, 5000));
        Assert.Equal(SfondiPronti.Personale, effetti.Valori.ImmagineSfondo);
        Assert.Equal("0123456789abcdef", effetti.Valori.ImmaginePersonale);
        Assert.Equal("fedcba9876543210", effetti.Valori.Logo);
        // Logo tolto sul telefono: lo stato non lo porta più.
        Assert.True(effetti.Stato(Stato() with { Sfondo = ModiSfondo.Sostituito, ImmagineSfondo = "personale",
            ImmaginePersonale = "0123456789abcdef" }, 6000));
        Assert.Null(effetti.Valori.Logo);

        Assert.Equal(new Comando(Sfondo: ModiSfondo.Nessuno), effetti.TogliSfondo(7000));
        Assert.False(effetti.Valori.SfondoAcceso);
    }

    [Fact]
    public void UnireITipiNuoviDelComando()
    {
        var unito = Comandi.Unisci(new Comando(Sfondo: ModiSfondo.Sostituito, ImmagineSfondo: "piante"), new Comando(TogliLogo: true));
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Sostituito, ImmagineSfondo: "piante", TogliLogo: true), unito);
    }

    [Fact]
    public void SenzaProNienteSfondiPronti()
    {
        var comando = RegolePro.SenzaPro(new Comando(Sfondo: ModiSfondo.Sostituito, ImmagineSfondo: "piante"));
        Assert.True(RegolePro.Vuoto(comando));
        // Togliere il logo resta possibile.
        Assert.Equal(new Comando(TogliLogo: true), RegolePro.SenzaPro(new Comando(TogliLogo: true)));
    }

    [Fact]
    public void MisureRidotte()
    {
        Assert.Equal((1920u, 1080u), RiduzioneImmagine.Misure(4032, 2268, RiduzioneImmagine.LatoSfondo));
        Assert.Equal((1440u, 1920u), RiduzioneImmagine.Misure(3024, 4032, RiduzioneImmagine.LatoSfondo));
        // Mai ingrandita.
        Assert.Equal((800u, 600u), RiduzioneImmagine.Misure(800, 600, RiduzioneImmagine.LatoSfondo));
        Assert.Equal((512u, 128u), RiduzioneImmagine.Misure(2048, 512, RiduzioneImmagine.LatoLogo));
        Assert.Equal((512u, 1u), RiduzioneImmagine.Misure(100_000, 10, RiduzioneImmagine.LatoLogo));
        Assert.Equal((1u, 1u), RiduzioneImmagine.Misure(0, 10, RiduzioneImmagine.LatoLogo));
    }

    [Fact]
    public void LaCopiaRestaTraIRiavvii()
    {
        var cartella = Path.Combine(Path.GetTempPath(), "webcamlr-sfondi-" + Guid.NewGuid().ToString("N"));
        try
        {
            var memoria = new MemoriaImmagini(cartella);
            Assert.Null(memoria.Impronta(UsoImmagine.Sfondo));
            Assert.Null(memoria.Leggi(UsoImmagine.Logo));

            byte[] jpeg = [0xFF, 0xD8, 0xFF, 1, 2, 3];
            var impronta = memoria.Salva(UsoImmagine.Sfondo, jpeg);
            Assert.Equal(PacchettoImmagine.ImprontaDi(jpeg), impronta);
            Assert.Equal(16, impronta.Length);
            Assert.Null(memoria.Impronta(UsoImmagine.Logo));

            // Riaperta (riavvio dell'app): stessa impronta, stessi byte.
            var riaperta = new MemoriaImmagini(cartella);
            Assert.Equal(impronta, riaperta.Impronta(UsoImmagine.Sfondo));
            Assert.Equal(jpeg, riaperta.Leggi(UsoImmagine.Sfondo));

            // Una nuova sostituisce la precedente.
            byte[] altra = [0xFF, 0xD8, 0xFF, 9];
            Assert.NotEqual(impronta, riaperta.Salva(UsoImmagine.Sfondo, altra));
            Assert.Equal(altra, new MemoriaImmagini(cartella).Leggi(UsoImmagine.Sfondo));

            Assert.Throws<ArgumentException>(() => riaperta.Salva(UsoImmagine.Logo, []));
        }
        finally
        {
            if (Directory.Exists(cartella)) Directory.Delete(cartella, true);
        }
    }

    [Fact]
    public void SpecchiaESfondoSoloConLaFrontale()
    {
        var frontale = Stato() with { Obiettivo = SoloFrontale.Frontale, Specchia = true, Sfondo = ModiSfondo.Sfocato };
        var effetti = new ControlloEffetti();
        effetti.Stato(frontale, 0);
        Assert.False(SoloFrontale.Posteriore(frontale));
        Assert.Equal((true, true), SoloFrontale.Accesi(effetti.Valori, true, frontale));

        // Posteriore: grigi e spenti, qualunque cosa dica lo stato (anche un telefono che non li spegne da sé).
        foreach (var obiettivo in new[] { "principale", "grandangolo", "tele", "macro" })
        {
            var posteriore = frontale with { Obiettivo = obiettivo };
            Assert.True(SoloFrontale.Posteriore(posteriore));
            Assert.Equal((false, false), SoloFrontale.Accesi(effetti.Valori, true, posteriore));
        }

        // Il telefono spegne lo sfondo con la posteriore e lo riaccende tornando alla frontale: il pulsante segue lo stato.
        effetti.Stato(frontale with { Obiettivo = "principale", Specchia = false, Sfondo = ModiSfondo.Nessuno }, 5000);
        Assert.True(effetti.Stato(frontale, 10_000));
        Assert.Equal((true, true), SoloFrontale.Accesi(effetti.Valori, true, frontale));
        Assert.Equal((false, true), SoloFrontale.Accesi(effetti.Valori with { Specchia = false }, true, frontale));

        // Senza stato (non ancora arrivato) o senza telefono pronto: non è «posteriore», ma spenti.
        Assert.False(SoloFrontale.Posteriore(null));
        Assert.Equal((false, false), SoloFrontale.Accesi(effetti.Valori, false, null));
    }

    [Fact]
    public void CambiareLivelloNonSpegneMaiLaSfocatura()
    {
        var effetti = new ControlloEffetti();
        effetti.Stato(Stato() with { Sfondo = ModiSfondo.Sfocato, IntensitaSfondo = 0.55 }, 0);

        // Medio → Poco → Tanto: ogni volta un solo comando, sempre «sfocato» con l'intensità, mai «nessuno».
        foreach (var (livello, quando) in new[] { (LivelloSfocatura.Poco, 5000L), (LivelloSfocatura.Tanto, 5100L) })
        {
            var comando = effetti.Sfoca(LivelliSfocatura.Intensita(livello), quando);
            Assert.Equal(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: LivelliSfocatura.Intensita(livello)), comando);
            Assert.True(effetti.Valori.SfondoSfocato);
        }

        // Con il cursore dell'intensità in attesa, il livello parte insieme a lui: ancora «sfocato», con il livello scelto.
        effetti.Cambia(new Comando(IntensitaSfondo: 0.4), 5200);
        Assert.Equal(new Comando(Sfondo: ModiSfondo.Sfocato, IntensitaSfondo: 0.25), effetti.Sfoca(0.25, 5300));
        Assert.Null(effetti.Scaduto());

        // Uno stato vecchio, partito prima del comando, non spegne la sfocatura né rimette il livello di prima.
        Assert.False(effetti.Stato(Stato() with { Sfondo = ModiSfondo.Nessuno, IntensitaSfondo = 1.0 }, 5400));
        Assert.True(effetti.Valori.SfondoSfocato);
        Assert.Equal(0.25, effetti.Valori.IntensitaSfondo);
    }
}
