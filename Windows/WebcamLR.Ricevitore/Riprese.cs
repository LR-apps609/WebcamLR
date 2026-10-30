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

    /// <summary>
    /// Sotto questi minuti di registrazione rimasti (spazio libero diviso per i byte al secondo della registrazione in
    /// corso) compare l'avviso «Spazio quasi finito» (windows.md 1.4).
    /// </summary>
    public const int MinutiMinimi = 10;

    /// <summary>Prima di questi secondi di registrazione i byte al secondo non dicono ancora nulla.</summary>
    public static readonly TimeSpan DurataPerStimare = TimeSpan.FromSeconds(5);

    /// <summary>Con meno di così libero dopo un errore di scrittura, l'errore è il disco pieno.</summary>
    public const long SpazioQuasiNullo = 64_000_000;

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
    /// <summary>Il telefono nella webcam è in pausa «sottofondo»: può restare via fino a 10 minuti, la registrazione si chiude.</summary>
    public static string TelefonoInSottofondo => TestiRicevitore.T("Riprese_TelefonoInSottofondo");

    /// <summary>
    /// La domanda prima di un comando che chiude la registrazione (windows.md 1.6: obiettivo, qualità, profilo, telefono
    /// nella webcam), con «Continua» e «Annulla» (quello predefinito).
    /// </summary>
    public static string DomandaRegistrando => TestiRicevitore.T("Riprese_DomandaRegistrando");
    public static string Continua => TestiRicevitore.T("Riprese_Continua");
    public static string Annulla => TestiRicevitore.T("Riprese_Annulla");

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

    /// <summary>
    /// I minuti di registrazione che restano sul disco al ritmo attuale (byte scritti diviso durata), arrotondati per
    /// difetto; null nei primi secondi, quando il ritmo non si sa ancora.
    /// </summary>
    public static int? MinutiRimasti(long liberi, long byteScritti, TimeSpan durata)
    {
        if (durata < DurataPerStimare || byteScritti <= 0) return null;
        var byteAlSecondo = byteScritti / durata.TotalSeconds;
        return (int)Math.Clamp(Math.Floor(Math.Max(0, liberi) / byteAlSecondo / 60), 0, int.MaxValue);
    }

    /// <summary>I minuti da mostrare in ambra, solo sotto <see cref="MinutiMinimi"/>; altrimenti null.</summary>
    public static int? SpazioScarso(long liberi, long byteScritti, TimeSpan durata) =>
        MinutiRimasti(liberi, byteScritti, durata) is int minuti && minuti < MinutiMinimi ? minuti : null;

    /// <summary>«Spazio quasi finito: restano circa 7 minuti»; con un minuto o meno «resta circa un minuto».</summary>
    public static string AvvisoSpazio(int minuti) =>
        minuti <= 1 ? TestiRicevitore.T("Riprese_AvvisoSpazioUnMinuto") : TestiRicevitore.T("Riprese_AvvisoSpazio", minuti);

    public static string SpiegazioneSpazio(long liberi) =>
        TestiRicevitore.T("Riprese_SpiegazioneSpazio", Byte(liberi));

    /// <summary>La frase dopo la fine di una registrazione (per quelle salvate in parte, <see cref="Testo(FineRegistrazione)"/>).</summary>
    public static string Testo(EsitoRegistrazione esito) => esito switch
    {
        EsitoRegistrazione.Salvata => RegistrazioneSalvata,
        EsitoRegistrazione.TroppoBreve => RegistrazioneTroppoBreve,
        EsitoRegistrazione.VideoCambiato => VideoCambiato,
        _ => RegistrazioneInterrotta,
    };

    /// <summary>
    /// La frase dopo la fine di una registrazione, con quanto è salvato se un errore l'ha fermata: «Disco pieno:
    /// registrazione fermata. Ho salvato i primi 12:31 in Video › WebcamLR.»
    /// </summary>
    public static string Testo(FineRegistrazione fine) => fine.Esito switch
    {
        EsitoRegistrazione.DiscoPieno => TestiRicevitore.T("Riprese_DiscoPieno", DurataArrotondata(fine.Durata)),
        EsitoRegistrazione.ErroreDiScrittura => TestiRicevitore.T("Riprese_ErroreDiScrittura", DurataArrotondata(fine.Durata)),
        _ => Testo(fine.Esito),
    };

    /// <summary>Al secondo più vicino: 60 fotogrammi da 33,333 ms fanno 1,99998 s, cioè «00:02».</summary>
    private static string DurataArrotondata(TimeSpan durata) => Durata(TimeSpan.FromSeconds(Math.Round(durata.TotalSeconds)));

    /// <summary>
    /// Vero se l'errore di scrittura è il disco pieno: i codici di Windows (ERROR_DISK_FULL, ERROR_HANDLE_DISK_FULL) o
    /// ENOSPC altrove, oppure meno di <see cref="SpazioQuasiNullo"/> libero subito dopo.
    /// </summary>
    public static bool EDiscoPieno(Exception errore, long? spazioLibero)
    {
        const int DiscoPienoWindows = 0x70, HandleDiscoPienoWindows = 0x27, SpazioFinitoPosix = 28;
        var codice = errore.HResult;
        if ((codice & 0xFFFF0000) == 0x80070000 && (codice & 0xFFFF) is DiscoPienoWindows or HandleDiscoPienoWindows) return true;
        if (codice is DiscoPienoWindows or HandleDiscoPienoWindows && OperatingSystem.IsWindows()) return true;
        if (codice == SpazioFinitoPosix && !OperatingSystem.IsWindows()) return true;
        return spazioLibero is long liberi && liberi < SpazioQuasiNullo;
    }
}
