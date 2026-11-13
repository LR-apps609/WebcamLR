using Xunit;

namespace WebcamLR.Effetti.Test;

/// <summary>La scala dei livelli (Qualità 6) con tempi finti: quando scende, quando risale, quanto aspetta.</summary>
public class SceltaLivelloTest
{
    private const ulong A30 = 33_333;
    private const ulong A60 = 16_667;

    /// <summary>Fotogrammi a 30 fps in una finestra: si chiude al primo con almeno 2 s dal primo della finestra.</summary>
    private const int PerFinestra = 62;

    /// <summary>Il tempo fino a un cambio è di <paramref name="finestre"/> finestre (2,07 s l'una a 30 fps).</summary>
    private static void DopoFinestre(int finestre, double secondi) => Assert.InRange(secondi, finestre * 2.0, finestre * 2.1);

    /// <summary>Un video finto: fotogrammi a passo fisso, con i tempi di maschera e resa che si vogliono.</summary>
    private sealed class Video(SceltaLivello scelta, ulong passo = A30)
    {
        public ulong Adesso = 1_000_000;
        public readonly List<(CambioLivello Cambio, ulong Quando)> Cambi = [];

        public CambioLivello? Fotogramma(double mascheraMs, double resaMs)
        {
            Adesso += passo;
            scelta.Intervallo(passo);
            var cambio = scelta.Aggiungi(mascheraMs, resaMs, Adesso);
            if (cambio is { } c) Cambi.Add((c, Adesso));
            return cambio;
        }

        /// <summary>I fotogrammi di <paramref name="secondi"/> secondi; il primo cambio, se c'è (e si ferma lì).</summary>
        public CambioLivello? Per(double secondi, double mascheraMs, double resaMs)
        {
            var fine = Adesso + (ulong)(secondi * 1_000_000);
            while (Adesso < fine)
            {
                if (Fotogramma(mascheraMs, resaMs) is { } c) return c;
            }
            return null;
        }

        /// <summary>Quanti secondi passano fino al prossimo cambio (al massimo <paramref name="limite"/>).</summary>
        public double FinoAlCambio(double mascheraMs, double resaMs, double limite = 600)
        {
            var inizio = Adesso;
            Assert.NotNull(Per(limite, mascheraMs, resaMs));
            return (Adesso - inizio) / 1_000_000.0;
        }

        /// <summary>Esattamente <paramref name="quante"/> finestre di misura (a 30 fps 62 fotogrammi l'una, 2,07 s); null se nessun cambio.</summary>
        public CambioLivello? Finestre(int quante, double mascheraMs, double resaMs)
        {
            CambioLivello? primo = null;
            for (var i = 0; i < quante * PerFinestra; i++) primo ??= Fotogramma(mascheraMs, resaMs);
            return primo;
        }

        public void Scalda()
        {
            for (var i = 0; i < SceltaLivello.FotogrammiDiRiscaldamento; i++) Assert.Null(Fotogramma(500, 500));
        }
    }

    private static (SceltaLivello Scelta, Video Video) Nuova(LivelloResa iniziale = LivelloResa.Pieno, ulong passo = A30, int fps = 0)
    {
        var scelta = new SceltaLivello(iniziale);
        scelta.Fps(fps);
        var video = new Video(scelta, passo);
        video.Scalda();
        return (scelta, video);
    }

    [Fact]
    public void ScendePrestoEDelGradinoGiusto()
    {
        var (scelta, video) = Nuova();
        // A 30 fps con 10/12 ms c'è posto: per un minuto non cambia nulla (sotto la quota di risalita, ma è già al pieno).
        Assert.Null(video.Finestre(29, 10, 12));
        Assert.Equal(LivelloResa.Pieno, scelta.Livello);

        // La resa troppo lenta: il bordo leggero, alla fine della prima finestra (2 s e poco più).
        DopoFinestre(1, video.FinoAlCambio(10, 40));
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);
        var cambio = video.Cambi[^1].Cambio;
        Assert.False(cambio.Salita);
        Assert.Equal(LivelloResa.Pieno, cambio.Da);
        Assert.InRange(cambio.FotogrammaMs, 33, 34);
        Assert.Equal(40, cambio.ResaMs, 3);

        // Poi la maschera lenta, ma dimezzata ci starebbe (45 / 2 < 28): la maschera un fotogramma sì e uno no.
        DopoFinestre(1, video.FinoAlCambio(45, 10));
        Assert.Equal(LivelloResa.MascheraAlterna, scelta.Livello);
        // Con la maschera alterna la media è circa la metà (23 ms): resta.
        Assert.Null(video.Per(30, 23, 10));
        Assert.Equal(LivelloResa.MascheraAlterna, scelta.Livello);

        // Non basta neanche così: il modello leggero, poi l'ultimo gradino, poi più niente.
        video.FinoAlCambio(40, 10);
        Assert.Equal(LivelloResa.Veloce, scelta.Livello);
        video.FinoAlCambio(10, 40);
        Assert.Equal(LivelloResa.Minimo, scelta.Livello);
        Assert.Null(video.Per(30, 10, 40));
        Assert.Equal(LivelloResa.Minimo, scelta.Livello);
    }

    [Fact]
    public void MascheraMoltoLentaSubitoAlModelloLeggero()
    {
        // 70 ms di maschera: anche un fotogramma sì e uno no farebbe 35 ms, oltre i 28 di quota. Subito il leggero.
        var (scelta, video) = Nuova();
        video.FinoAlCambio(70, 10);
        Assert.Equal(LivelloResa.Veloce, scelta.Livello);
    }

    [Fact]
    public void LaSceltaSiFaSulleMedie()
    {
        // Collaudo 23: una finestra con la maschera lenta e l'ultimo fotogramma con una maschera breve: il collo è la maschera.
        var (scelta, video) = Nuova();
        Assert.Null(video.Per(1.9, 45, 10));
        Assert.NotNull(video.Per(1, 9, 10));
        Assert.Equal(LivelloResa.MascheraAlterna, scelta.Livello);

        // Al contrario: una sola maschera lenta alla fine non decide, conta la resa (il bordo leggero).
        (scelta, video) = Nuova();
        Assert.Null(video.Per(1.9, 10, 40));
        Assert.NotNull(video.Per(1, 60, 40));
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);
    }

    [Fact]
    public void RisalePianoUnGradinoAllaVolta()
    {
        var (scelta, video) = Nuova(LivelloResa.Veloce);
        // Con margine (sotto la metà del fotogramma) si risale dopo 10 s, non prima.
        DopoFinestre(5, video.FinoAlCambio(5, 10));
        var (cambio, _) = video.Cambi[^1];
        Assert.True(cambio.Salita);
        Assert.Equal(LivelloResa.MascheraAlterna, cambio.A);
        DopoFinestre(5, video.FinoAlCambio(5, 10));
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);
        DopoFinestre(5, video.FinoAlCambio(5, 10));
        Assert.Equal(LivelloResa.Pieno, scelta.Livello);
        // Dal pieno non si sale più.
        Assert.Null(video.Per(60, 5, 10));
    }

    [Fact]
    public void TraLaQuotaDiRisalitaEQuellaDiDiscesaResta()
    {
        // 20 ms su 33: troppo per salire (più della metà), troppo poco per scendere (meno dell'85%).
        var (scelta, video) = Nuova(LivelloResa.BordoLeggero);
        Assert.Null(video.Per(120, 10, 20));
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);

        // Una finestra storta in mezzo al margine fa ripartire il conto dei 10 s.
        (scelta, video) = Nuova(LivelloResa.BordoLeggero);
        Assert.Null(video.Finestre(4, 5, 10));
        Assert.Null(video.Finestre(1, 5, 20));
        DopoFinestre(5, video.FinoAlCambio(5, 10));
    }

    [Fact]
    public void UnaRicadutaFaAspettareIlDoppio()
    {
        var (scelta, video) = Nuova(LivelloResa.BordoLeggero);
        video.FinoAlCambio(5, 10);
        Assert.Equal(LivelloResa.Pieno, scelta.Livello);
        // Il pieno non regge (entro i 30 s di prova): giù, e la prossima risalita aspetta 20 s.
        Assert.Null(video.Finestre(2, 10, 15));
        DopoFinestre(1, video.FinoAlCambio(10, 40));
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);
        Assert.Equal(2 * SceltaLivello.FinestreDiMarginePerSalire, scelta.FinestrePerSalire);
        DopoFinestre(10, video.FinoAlCambio(5, 10));
        // Ricade di nuovo: 40 s.
        video.FinoAlCambio(10, 40);
        DopoFinestre(20, video.FinoAlCambio(5, 10));

        // Questa volta il pieno regge per più di 30 s: l'attesa torna a 10 s per la prossima volta.
        Assert.Null(video.Finestre(15, 10, 15));
        video.FinoAlCambio(10, 40);
        Assert.Equal(SceltaLivello.FinestreDiMarginePerSalire, scelta.FinestrePerSalire);
        DopoFinestre(5, video.FinoAlCambio(5, 10));
    }

    [Fact]
    public void LAttesaNonCresceSenzaFine()
    {
        var (scelta, video) = Nuova(LivelloResa.BordoLeggero);
        for (var i = 0; i < 8; i++)
        {
            video.FinoAlCambio(5, 10);
            video.FinoAlCambio(10, 40);
        }
        Assert.Equal(SceltaLivello.FinestreDiMarginePerSalire << SceltaLivello.RicaduteMassime, scelta.FinestrePerSalire);
        DopoFinestre(80, video.FinoAlCambio(5, 10));
    }

    [Fact]
    public void IlBudgetDipendeDaiFps()
    {
        // A 60 fps un fotogramma dura 17 ms: 20 ms di resa non ci stanno.
        var (scelta, video) = Nuova(passo: A60, fps: 60);
        video.FinoAlCambio(5, 20);
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);
        Assert.InRange(video.Cambi[^1].Cambio.FotogrammaMs, 16.6, 16.8);

        // A 30 fps sì.
        (scelta, video) = Nuova(fps: 30);
        Assert.Null(video.Per(30, 5, 20));

        // Il telefono dice 30 fps ma i fotogrammi arrivano a raffica ogni 17 ms (rete): il fotogramma vale 33 ms.
        (scelta, video) = Nuova(passo: A60, fps: 30);
        Assert.Null(video.Per(30, 5, 20));
        Assert.Equal(1000.0 / 30, scelta.FotogrammaMs!.Value, 3);

        // Senza fps dichiarati, mai sotto 1/60 di secondo anche con intervalli brevissimi.
        (scelta, video) = Nuova(passo: 1_000);
        Assert.Equal(SceltaLivello.FotogrammaMinimoMs, scelta.FotogrammaMs!.Value, 3);
    }

    [Fact]
    public void ConIlProcessorePienoNonRisale()
    {
        // Collaudo 20 (t06 B1): telefono a 30 fps, processore al 100%, la decodifica rallenta e i fotogrammi arrivano al
        // motore ogni 165 ms. Maschera 16 ms e resa 74 ms: prima «margine a 165 ms» e la qualità risaliva. Ora resta giù.
        var (scelta, video) = Nuova(LivelloResa.Minimo, passo: 165_000, fps: 30);
        Assert.Null(video.Per(180, 16, 74));
        Assert.Equal(LivelloResa.Minimo, scelta.Livello);
        Assert.Equal(1000.0 / 30, scelta.FotogrammaMs!.Value, 3);
        Assert.InRange(scelta.ArriviMs!.Value, 164, 166);

        // Anche con effetti leggerissimi: gli arrivi radi sono un PC indietro, non margine.
        (scelta, video) = Nuova(LivelloResa.Minimo, passo: 66_667, fps: 30);
        Assert.Null(video.Per(180, 3, 4));
        Assert.Equal(LivelloResa.Minimo, scelta.Livello);

        // Con gli arrivi regolari e lo stesso lavoro leggero risale dopo cinque finestre, come prima.
        (scelta, video) = Nuova(LivelloResa.Minimo, fps: 30);
        DopoFinestre(SceltaLivello.FinestreDiMarginePerSalire, video.FinoAlCambio(3, 4));
        Assert.Equal(LivelloResa.Veloce, scelta.Livello);
    }

    [Fact]
    public void ConIlProcessorePienoScende()
    {
        // Dal pieno, con i fotogrammi che arrivano ogni 165 ms e la resa a 74 ms: 74 non sta nei 33 ms del telefono
        // (prima il confronto era con 165 ms e non scendeva).
        var (scelta, video) = Nuova(passo: 165_000, fps: 30);
        var cambio = video.Per(10, 16, 74);
        Assert.NotNull(cambio);
        Assert.False(cambio!.Value.Salita);
        Assert.Equal(LivelloResa.BordoLeggero, scelta.Livello);
        Assert.InRange(cambio.Value.FotogrammaMs, 33.3, 33.4);
    }

    [Fact]
    public void UnIntervalloAnomaloNonFaScendere()
    {
        // Collaudo 20: un solo intervallo da 1 ms (due fotogrammi a raffica dopo un intoppo del Wi-Fi) tra 29 da 33 ms.
        var scelta = new SceltaLivello();
        for (var i = 0; i < 29; i++) scelta.Intervallo(33_333);
        scelta.Intervallo(1_000);
        Assert.InRange(scelta.FotogrammaMs!.Value, 33, 34);

        // Fotogrammi che arrivano a coppie (2 ms e 64 ms, in media 33): il fotogramma vale ancora circa 33 ms.
        scelta = new SceltaLivello();
        for (var i = 0; i < 30; i++) scelta.Intervallo(i % 2 == 0 ? 2_000UL : 64_000UL);
        Assert.InRange(scelta.FotogrammaMs!.Value, 30, 36);

        // Una pausa lunga non fa credere a un fotogramma lento.
        scelta = new SceltaLivello();
        for (var i = 0; i < 28; i++) scelta.Intervallo(33_333);
        scelta.Intervallo(400_000);
        scelta.Intervallo(300_000);
        Assert.InRange(scelta.FotogrammaMs!.Value, 33, 34);
    }

    [Fact]
    public void IlRiscaldamentoDellaSchedaVideoNonFaScendere()
    {
        // Collaudo 21: la prima maschera con DirectML compila gli shader (1,5 s), le altre durano 10 ms.
        var scelta = new SceltaLivello();
        var video = new Video(scelta);
        Assert.Null(video.Fotogramma(1500, 12));
        Assert.Null(video.Per(10, 10, 12));
        // Una fonte nuova (riaperta o cambiata) scalda di nuovo.
        scelta.FonteNuova();
        Assert.Null(video.Fotogramma(2000, 12));
        Assert.Null(video.Per(10, 10, 12));
        // E così dopo un azzeramento (telefono girato, sessione nuova), che riparte dal pieno.
        var (altra, altroVideo) = Nuova();
        altroVideo.FinoAlCambio(10, 40);
        altra.Azzera();
        Assert.Equal(LivelloResa.Pieno, altra.Livello);
        Assert.Null(altroVideo.Fotogramma(1500, 12));
        Assert.Null(altroVideo.Per(10, 10, 12));
        Assert.Equal(LivelloResa.Pieno, altra.Livello);
    }

    [Fact]
    public void UnaPausaApreUnaFinestraNuova()
    {
        // Mezza finestra lenta, lo sfondo spento per 5 s, mezza finestra lenta: nessuna finestra intera, niente cambio.
        var (scelta, video) = Nuova();
        Assert.Null(video.Per(1.5, 10, 40));
        video.Adesso += 5_000_000;
        Assert.Null(video.Per(1.5, 10, 12));
        Assert.Equal(LivelloResa.Pieno, scelta.Livello);
    }

    [Fact]
    public void CheCosaCambiaAOgniGradino()
    {
        Assert.True(LivelloResa.Pieno.ConBordoAMeta());
        Assert.False(LivelloResa.BordoLeggero.ConBordoAMeta());
        Assert.False(LivelloResa.BordoLeggero.ConMascheraAlterna());
        Assert.True(LivelloResa.MascheraAlterna.ConMascheraAlterna());
        Assert.False(LivelloResa.MascheraAlterna.ConModelloLeggero());
        Assert.False(LivelloResa.MascheraAlterna.ConBordoBilineare());
        Assert.True(LivelloResa.Veloce.ConModelloLeggero());
        Assert.True(LivelloResa.Veloce.ConBordoBilineare());
        Assert.False(LivelloResa.Veloce.ConMascheraAlterna());
        Assert.True(LivelloResa.Minimo.ConMascheraAlterna());
        Assert.True(LivelloResa.Minimo.ConModelloLeggero());
    }
}
