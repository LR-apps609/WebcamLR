using System.Text;

namespace WebcamLR.Ricevitore;

/// <summary>Che cosa dice adb di un telefono Android collegato (la seconda colonna di «adb devices»).</summary>
public enum StatoDispositivoAdb
{
    /// <summary>«device»: debug USB consentito, si può aprire il canale.</summary>
    Pronto,
    /// <summary>«unauthorized»: sul telefono c'è la domanda «Consentire il debug USB?», ancora senza risposta.</summary>
    NonAutorizzato,
    /// <summary>«authorizing», «connecting»: adb sta ancora parlando con il telefono, tra un attimo si sa.</summary>
    InCorso,
    /// <summary>«offline»: il telefono non risponde ad adb (spesso basta staccare e riattaccare il cavo).</summary>
    NonRaggiungibile,
    /// <summary>Tutto il resto («no permissions», «recovery», «bootloader», «sideload»…): non si usa.</summary>
    Altro,
}

/// <summary>Un telefono nell'elenco di adb: il numero di serie e lo stato.</summary>
public sealed record DispositivoAdb(string Seriale, StatoDispositivoAdb Stato)
{
    /// <summary>
    /// Vero se il telefono è sul cavo USB: adb elenca anche il debug wireless («192.168.1.5:5555» o
    /// «adb-…._adb-tls-connect._tcp») e gli emulatori («emulator-5554»), che per WebcamLR non sono il cavo.
    /// </summary>
    public bool ViaUsb => ProtocolloAdb.ViaUsb(Seriale);
}

/// <summary>Il server di adb ha risposto «FAIL» con il suo messaggio.</summary>
public sealed class RifiutoAdb(string messaggio) : Exception(messaggio);

/// <summary>
/// Il minimo del protocollo con il server di adb (Documenti/Protocollo.md, «Cavo USB con Android: adb»), scritto da zero:
/// nessuna libreria di adb, solo la connessione TCP con il server che gira sul computer (127.0.0.1:5037).
/// Ogni richiesta è la sua lunghezza in 4 cifre esadecimali e il testo ASCII («000chost:version»); la risposta comincia
/// con «OKAY» o con «FAIL» seguito da un messaggio con la stessa lunghezza in testa. Pura logica sui flussi: si prova
/// con i test, senza adb.
/// </summary>
public static class ProtocolloAdb
{
    /// <summary>Il server di adb, avviato da adb stesso, da Android Studio, da scrcpy…</summary>
    public const int PortaServer = 5037;
    /// <summary>Oltre questa lunghezza un blocco di adb non è credibile (4 cifre esadecimali: al massimo 65535).</summary>
    public const int LunghezzaMassima = 0xFFFF;

    /// <summary>Una richiesta: lunghezza in 4 cifre esadecimali e testo, per esempio «0012host:track-devices».</summary>
    public static byte[] Richiesta(string servizio)
    {
        var testo = Encoding.ASCII.GetBytes(servizio);
        if (testo.Length > LunghezzaMassima) throw new ArgumentException("Richiesta adb troppo lunga", nameof(servizio));
        return Encoding.ASCII.GetBytes(testo.Length.ToString("x4")).Concat(testo).ToArray();
    }

    /// <summary>
    /// La risposta a una richiesta: vero con «OKAY»; con «FAIL» lancia <see cref="RifiutoAdb"/> con il messaggio del
    /// server. Falso se la connessione si chiude prima. Legge solo i byte della risposta: dopo l'«OKAY» di «tcp:52741»
    /// quello che segue è già la connessione con il telefono.
    /// </summary>
    public static async Task<bool> LeggiEsitoAsync(Stream flusso, CancellationToken annullato)
    {
        var esito = new byte[4];
        if (!await LeggiTuttoAsync(flusso, esito, annullato)) return false;
        var testo = Encoding.ASCII.GetString(esito);
        if (testo == "OKAY") return true;
        if (testo == "FAIL") throw new RifiutoAdb(await LeggiBloccoAsync(flusso, annullato) ?? "");
        throw new FormatException($"Risposta adb non prevista: «{testo}»");
    }

    /// <summary>Un blocco con la lunghezza in testa (4 cifre esadecimali); null se la connessione si chiude prima.</summary>
    public static async Task<string?> LeggiBloccoAsync(Stream flusso, CancellationToken annullato)
    {
        var intestazione = new byte[4];
        if (!await LeggiTuttoAsync(flusso, intestazione, annullato)) return null;
        var lunghezza = Lunghezza(intestazione);
        var corpo = new byte[lunghezza];
        if (!await LeggiTuttoAsync(flusso, corpo, annullato)) return null;
        return Encoding.UTF8.GetString(corpo);
    }

    /// <summary>Le 4 cifre esadecimali della lunghezza; lancia FormatException se non lo sono.</summary>
    public static int Lunghezza(ReadOnlySpan<byte> quattro)
    {
        if (quattro.Length != 4) throw new FormatException("Lunghezza adb di 4 cifre");
        var valore = 0;
        foreach (var b in quattro)
        {
            var cifra = b switch
            {
                >= (byte)'0' and <= (byte)'9' => b - '0',
                >= (byte)'a' and <= (byte)'f' => b - 'a' + 10,
                >= (byte)'A' and <= (byte)'F' => b - 'A' + 10,
                _ => throw new FormatException($"Lunghezza adb non esadecimale: {Encoding.ASCII.GetString(quattro)}"),
            };
            valore = valore * 16 + cifra;
        }
        return valore;
    }

    /// <summary>
    /// L'elenco di «host:devices» e «host:track-devices»: una riga per telefono, numero di serie e stato separati da una
    /// tabulazione («R58N12ABCDE\tdevice»). Va bene anche il formato lungo di «-l» (spazi e campi «model:…» in più).
    /// Righe vuote o senza stato si saltano.
    /// </summary>
    public static IReadOnlyList<DispositivoAdb> LeggiElenco(string testo)
    {
        var elenco = new List<DispositivoAdb>();
        foreach (var grezza in testo.Split('\n'))
        {
            var riga = grezza.TrimEnd('\r');
            if (riga.Trim().Length == 0) continue;
            string seriale, stato;
            var tab = riga.IndexOf('\t');
            if (tab > 0)
            {
                seriale = riga[..tab].Trim();
                stato = riga[(tab + 1)..].Trim();
            }
            else
            {
                var parti = riga.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                if (parti.Length < 2) continue;
                seriale = parti[0];
                // «no permissions» è di due parole; con il formato lungo dopo lo stato vengono i campi «chiave:valore».
                stato = string.Join(' ', parti.Skip(1).TakeWhile(p => !p.Contains(':')));
            }
            if (seriale.Length == 0 || stato.Length == 0) continue;
            elenco.Add(new DispositivoAdb(seriale, Stato(stato)));
        }
        return elenco;
    }

    public static StatoDispositivoAdb Stato(string grezzo) => grezzo.Trim() switch
    {
        "device" => StatoDispositivoAdb.Pronto,
        "unauthorized" => StatoDispositivoAdb.NonAutorizzato,
        "authorizing" or "connecting" => StatoDispositivoAdb.InCorso,
        "offline" => StatoDispositivoAdb.NonRaggiungibile,
        _ => StatoDispositivoAdb.Altro,
    };

    /// <summary>Il debug wireless (indirizzo:porta o servizio mDNS) e gli emulatori non sono il cavo USB.</summary>
    public static bool ViaUsb(string seriale) =>
        seriale.Length > 0
        && !seriale.Contains(':')
        && !seriale.StartsWith("emulator-", StringComparison.Ordinal)
        && !seriale.Contains("._adb-tls-", StringComparison.Ordinal);

    /// <summary>Per aprire un canale: prima il telefono («host:transport:…»), poi la sua porta («tcp:52741»).</summary>
    public static string RichiestaTelefono(string seriale) => "host:transport:" + seriale;

    public static string RichiestaPorta(ushort porta) => "tcp:" + porta;

    private static async Task<bool> LeggiTuttoAsync(Stream flusso, byte[] buffer, CancellationToken annullato)
    {
        var letti = 0;
        while (letti < buffer.Length)
        {
            var n = await flusso.ReadAsync(buffer.AsMemory(letti), annullato);
            if (n == 0) return false;
            letti += n;
        }
        return true;
    }
}

/// <summary>
/// Dove cercare adb sul PC quando il suo server non risponde (Documenti/Cavo USB Android.md, «Distribuzione»): prima la
/// copia scaricata da WebcamLR, poi quelle dell'Android SDK (Android Studio) e infine il PATH. Pura logica: chi chiama
/// passa le variabili d'ambiente e il controllo dei file.
/// </summary>
public static class TrovaAdb
{
    /// <summary>La cartella dove WebcamLR scaricherebbe gli «Strumenti della piattaforma» di Google.</summary>
    public const string CartellaScaricata = "platform-tools";

    /// <summary>I percorsi possibili, in ordine, senza doppioni.</summary>
    /// <param name="variabile">Legge una variabile d'ambiente (null se non c'è).</param>
    /// <param name="cartellaApp">La cartella dei dati di WebcamLR (per esempio %LOCALAPPDATA%\WebcamLR); null se non c'è.</param>
    /// <param name="nomeFile">«adb.exe» su Windows, «adb» altrove.</param>
    public static IReadOnlyList<string> Candidati(Func<string, string?> variabile, string? cartellaApp, string nomeFile = "adb.exe",
        char separatorePath = ';')
    {
        var candidati = new List<string>();
        void Aggiungi(string? cartella)
        {
            if (string.IsNullOrWhiteSpace(cartella)) return;
            var percorso = Path.Combine(cartella.Trim().Trim('"'), nomeFile);
            if (!candidati.Contains(percorso, StringComparer.OrdinalIgnoreCase)) candidati.Add(percorso);
        }
        if (cartellaApp is not null) Aggiungi(Path.Combine(cartellaApp, CartellaScaricata));
        foreach (var nome in new[] { "ANDROID_HOME", "ANDROID_SDK_ROOT" })
            if (variabile(nome) is { } sdk) Aggiungi(Path.Combine(sdk, "platform-tools"));
        if (variabile("LOCALAPPDATA") is { } locale) Aggiungi(Path.Combine(locale, "Android", "sdk", "platform-tools"));
        foreach (var cartella in (variabile("PATH") ?? "").Split(separatorePath, StringSplitOptions.RemoveEmptyEntries)) Aggiungi(cartella);
        return candidati;
    }

    /// <summary>Il primo candidato che esiste (su Windows maiuscole e minuscole nei percorsi non contano: «Android\Sdk»); null se adb non c'è.</summary>
    public static string? Primo(IEnumerable<string> candidati, Func<string, bool> esiste) => candidati.FirstOrDefault(esiste);
}
