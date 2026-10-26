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

    public static string FotoSalvata => TestiRicevitore.T("Riprese_FotoSalvata");
    public static string RegistrazioneSalvata => TestiRicevitore.T("Riprese_RegistrazioneSalvata");
    public static string FotogrammaCopiato => TestiRicevitore.T("Riprese_FotogrammaCopiato");
    public static string CopiaNonRiuscita => TestiRicevitore.T("Riprese_CopiaNonRiuscita");
    public static string NessunVideo => TestiRicevitore.T("Riprese_NessunVideo");
    public static string FotoNonSalvata => TestiRicevitore.T("Riprese_FotoNonSalvata");
    public static string RegistrazioneNonCreata => TestiRicevitore.T("Riprese_RegistrazioneNonCreata");
    public static string RegistrazioneTroppoBreve => TestiRicevitore.T("Riprese_TroppoBreve");
    public static string VideoCambiato => TestiRicevitore.T("Riprese_VideoCambiato");
    public static string RegistrazioneInterrotta => TestiRicevitore.T("Riprese_Interrotta");
    public static string TelefonoScollegato => TestiRicevitore.T("Riprese_TelefonoScollegato");
    /// <summary>P21: un altro telefono va nella webcam; la registrazione è di un solo video, quindi si chiude.</summary>
    public static string TelefonoCambiato => TestiRicevitore.T("Riprese_TelefonoCambiato");

    /// <summary>«2026-10-24 alle 14.05.33» («2026-10-24 at 14.05.33» in inglese), come sul Mac.</summary>
    public static string NomeData(DateTime quando) =>
        quando.ToString(TestiRicevitore.T("Riprese_FormatoNomeData"), CultureInfo.InvariantCulture);

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
    /// Byte in parole, in base 1000 come Esplora file e il Finder: «512 KB», «8,4 MB», «1,23 GB» (in inglese «8.4 MB»).
    /// </summary>
    public static string Byte(long byteTotali)
    {
        var b = Math.Max(0, byteTotali);
        if (b < 1_000) return TestiRicevitore.T("Riprese_Byte", b);
        if (b < 1_000_000) return $"{Lingua.Decimale(b / 1e3, "0")} KB";
        if (b < 1_000_000_000) return $"{Lingua.Decimale(b / 1e6, b < 100_000_000 ? "0.0" : "0")} MB";
        return $"{Lingua.Decimale(b / 1e9, "0.00")} GB";
    }

    /// <summary>Il pulsante mentre si registra: «Ferma · 00:12 · 8,4 MB»; nella finestra stretta solo il tempo.</summary>
    public static string TestoRegistrazione(TimeSpan durata, long byteScritti, bool compatto = false) =>
        compatto ? Durata(durata) : TestiRicevitore.T("Riprese_Registrando", Durata(durata), Byte(byteScritti));

    /// <summary>Lo spazio libero da mostrare in ambra, solo sotto i 2 GB.</summary>
    public static long? SpazioScarso(long liberi) => liberi < SpazioMinimo ? liberi : null;

    public static string AvvisoSpazio(long liberi) => TestiRicevitore.T("Riprese_AvvisoSpazio", Byte(liberi));

    public static string SpiegazioneSpazio(long liberi) =>
        TestiRicevitore.T("Riprese_SpiegazioneSpazio", Byte(liberi));

    /// <summary>La frase dopo la fine di una registrazione.</summary>
    public static string Testo(EsitoRegistrazione esito) => esito switch
    {
        EsitoRegistrazione.Salvata => RegistrazioneSalvata,
        EsitoRegistrazione.TroppoBreve => RegistrazioneTroppoBreve,
        EsitoRegistrazione.VideoCambiato => VideoCambiato,
        _ => RegistrazioneInterrotta,
    };
}
