using System.Globalization;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Foto e registrazioni su Windows (P18), come sul Mac (Mac/Sorgenti/Riprese.swift e Fotografia.swift): nomi dei file,
/// tempo e dimensione della registrazione, spazio sul disco e le frasi mostrate sopra il video.
/// </summary>
public static class Riprese
{
    /// <summary>La sottocartella in Immagini (foto) e in Video (registrazioni).</summary>
    public const string Cartella = "WebcamLR";

    /// <summary>Sotto questa soglia di spazio libero compare l'avviso durante la registrazione, come sul Mac.</summary>
    public const long SpazioMinimo = 2_000_000_000;

    /// <summary>Più corta di così la registrazione non si salva.</summary>
    public static readonly TimeSpan DurataMinima = TimeSpan.FromSeconds(1);

    /// <summary>I secondi del timer della foto: 3, 2, 1, poi lo scatto.</summary>
    public const int SecondiTimer = 3;

    public const string FotoSalvata = "Foto salvata in Immagini › WebcamLR";
    public const string RegistrazioneSalvata = "Registrazione salvata in Video › WebcamLR";
    public const string FotogrammaCopiato = "Fotogramma copiato: incollalo dove vuoi";
    public const string CopiaNonRiuscita = "Non riesco a copiare il fotogramma: riprova.";
    public const string NessunVideo = "Non c'è ancora video: collega il telefono e riprova.";
    public const string FotoNonSalvata = "Non riesco a salvare in Immagini › WebcamLR: controlla lo spazio sul disco e riprova.";
    public const string RegistrazioneNonCreata = "Non riesco a creare la registrazione in Video › WebcamLR: controlla lo spazio sul disco e riprova.";
    public const string RegistrazioneTroppoBreve = "Registrazione troppo breve, niente da salvare: riprova e registra per qualche secondo.";
    public const string VideoCambiato = "Il video è cambiato: registrazione fermata e salvata in Video › WebcamLR";
    public const string RegistrazioneInterrotta = "Registrazione interrotta: controlla lo spazio sul disco e riprova.";
    public const string TelefonoScollegato = "Telefono scollegato: registrazione fermata e salvata in Video › WebcamLR";
    /// <summary>P21: un altro telefono va nella webcam; la registrazione è di un solo video, quindi si chiude.</summary>
    public const string TelefonoCambiato = "Hai cambiato telefono: registrazione fermata e salvata in Video › WebcamLR";

    /// <summary>«2026-10-24 alle 14.05.33», come sul Mac.</summary>
    public static string NomeData(DateTime quando) =>
        quando.ToString("yyyy-MM-dd 'alle' HH.mm.ss", CultureInfo.InvariantCulture);

    /// <summary>
    /// «WebcamLR 2026-10-24 alle 14.05.33.png», con « (2)», « (3)»… se esiste già: due foto nello stesso secondo
    /// non si sovrascrivono, e una registrazione non trova il file già lì.
    /// </summary>
    public static string FileLibero(string cartella, string estensione, DateTime quando, Func<string, bool>? esiste = null)
    {
        esiste ??= percorso => File.Exists(percorso) || Directory.Exists(percorso);
        var nome = $"WebcamLR {NomeData(quando)}";
        var file = Path.Combine(cartella, $"{nome}.{estensione}");
        for (var numero = 2; esiste(file); numero++) file = Path.Combine(cartella, $"{nome} ({numero}).{estensione}");
        return file;
    }

    /// <summary>«00:12», «12:34»; da un'ora «1:02:03».</summary>
    public static string Durata(TimeSpan durata)
    {
        var secondi = Math.Max(0, (long)durata.TotalSeconds);
        return secondi < 3600
            ? $"{secondi / 60:00}:{secondi % 60:00}"
            : $"{secondi / 3600}:{secondi / 60 % 60:00}:{secondi % 60:00}";
    }

    /// <summary>
    /// Byte in parole, all'italiana e in base 1000 come Esplora file e il Finder: «512 KB», «8,4 MB», «1,23 GB».
    /// </summary>
    public static string Byte(long byteTotali)
    {
        var it = CultureInfo.GetCultureInfo("it-IT");
        var b = Math.Max(0, byteTotali);
        if (b < 1_000) return $"{b} byte";
        if (b < 1_000_000) return string.Format(it, "{0:0} KB", b / 1e3);
        if (b < 1_000_000_000) return string.Format(it, b < 100_000_000 ? "{0:0.0} MB" : "{0:0} MB", b / 1e6);
        return string.Format(it, "{0:0.00} GB", b / 1e9);
    }

    /// <summary>Il pulsante mentre si registra: «Ferma · 00:12 · 8,4 MB»; nella finestra stretta solo il tempo.</summary>
    public static string TestoRegistrazione(TimeSpan durata, long byteScritti, bool compatto = false) =>
        compatto ? Durata(durata) : $"Ferma · {Durata(durata)} · {Byte(byteScritti)}";

    /// <summary>Lo spazio libero da mostrare in ambra, solo sotto i 2 GB.</summary>
    public static long? SpazioScarso(long liberi) => liberi < SpazioMinimo ? liberi : null;

    public static string AvvisoSpazio(long liberi) => $"Solo {Byte(liberi)} liberi";

    public static string SpiegazioneSpazio(long liberi) =>
        $"Solo {Byte(liberi)} liberi: lo spazio sul disco sta finendo. Ferma la registrazione o libera spazio.";

    /// <summary>La frase dopo la fine di una registrazione.</summary>
    public static string Testo(EsitoRegistrazione esito) => esito switch
    {
        EsitoRegistrazione.Salvata => RegistrazioneSalvata,
        EsitoRegistrazione.TroppoBreve => RegistrazioneTroppoBreve,
        EsitoRegistrazione.VideoCambiato => VideoCambiato,
        _ => RegistrazioneInterrotta,
    };
}
