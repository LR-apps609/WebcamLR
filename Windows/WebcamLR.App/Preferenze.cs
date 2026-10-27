using System.Security.Cryptography;
using System.Text.Json;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>I comandi della fotocamera salvati per nome (funzione 23), come sul Mac.</summary>
public sealed record ProfiloFotocamera(string? Obiettivo, double Zoom, bool Torcia, double Esposizione,
    bool BiancoAutomatico, double Bianco, bool EsposizioneManuale, double Iso, int Tempo);

/// <summary>
/// Preferenze della finestra, in %LOCALAPPDATA%\WebcamLR: l'app non è pacchettizzata,
/// quindi ApplicationData non c'è. Un file per valore, così non serve un formato.
/// </summary>
public static class Preferenze
{
    private static readonly string Cartella =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WebcamLR");

    /// <summary>Webcam (1.24): come entra un video di altre proporzioni. Di serie tutto, con le bande nere.</summary>
    public static WebcamLR.Webcam.Inquadratura InquadraturaWebcam
    {
        get => Leggi("webcam-inquadratura") == "riempi" ? WebcamLR.Webcam.Inquadratura.Riempi : WebcamLR.Webcam.Inquadratura.Adatta;
        set => Scrivi("webcam-inquadratura", value == WebcamLR.Webcam.Inquadratura.Riempi ? "riempi" : "adatta");
    }

    // Lo specchio (1.14) non si salva più qui: è uno solo, del telefono, e il PC lo legge dal suo «stato».
    // La modalità avanzata non c'è più: numeri, registro e regole fini stanno a un clic, come sul Mac.

    /// <summary>«Riempi l'inquadratura» (Impostazioni › Schermo): vale solo per l'anteprima in questa finestra.</summary>
    public static bool Riempi
    {
        get => Leggi("riempi") == "1";
        set => Scrivi("riempi", value ? "1" : "0");
    }

    /// <summary>
    /// La vista della finestra (27 ottobre): «essenziale» (solo video e barra) o «completo» (con le colonne). La prima volta
    /// si decide e si salva subito: chi aveva già usato l'app (c'è la chiave del PC, la posizione della finestra o un
    /// telefono fidato) resta su Completo, un'installazione nuova parte da Essenziale. Va letta prima di
    /// <see cref="Identita"/>, che la prima volta crea la chiave.
    /// </summary>
    public static bool VistaEssenziale()
    {
        switch (Leggi("vista"))
        {
            case "essenziale": return true;
            case "completo": return false;
        }
        var giaUsata = new[] { "identita", "finestra", "fidati.json" }.Any(nome => File.Exists(Path.Combine(Cartella, nome)));
        ScriviVista(essenziale: !giaUsata);
        return !giaUsata;
    }

    public static void ScriviVista(bool essenziale) => Scrivi("vista", essenziale ? "essenziale" : "completo");

    /// <summary>L'ultimo livello della sfocatura di «Sfondo» sotto il video (Poco, Medio, Tanto).</summary>
    public static LivelloSfocatura LivelloSfocatura
    {
        get => LivelliSfocatura.Da(Leggi("livello-sfocatura"));
        set => Scrivi("livello-sfocatura", LivelliSfocatura.Id(value));
    }

    /// <summary>
    /// L'ultima scelta di «Sfondo», che un clic sul pulsante riaccende: <see cref="RegoleSfondo.Sfocatura"/> o l'id di uno
    /// sfondo (anche «personale»). Null finché non si è scelto nulla (allora la sfocatura).
    /// </summary>
    public static string? UltimoSfondo
    {
        get => Leggi("ultimo-sfondo");
        set => Scrivi("ultimo-sfondo", value ?? RegoleSfondo.Sfocatura);
    }

    /// <summary>
    /// Gli effetti del motore del PC (effetti sul computer, EffettiComputer.InTesto, JSON): sfondo, filtro, regolazioni, pelle,
    /// calore, luce sul volto, inquadratura, specchio e scritta. Null la prima volta.
    /// </summary>
    public static string? EffettiComputer
    {
        get => Leggi("effetti-computer.json");
        set => Scrivi("effetti-computer.json", value ?? "");
    }

    /// <summary>La copia dell'immagine personale e del logo caricati dal PC (MemoriaImmagini): resta tra i riavvii.</summary>
    public static string CartellaImmagini => Path.Combine(Cartella, "immagini");

    /// <summary>Le sezioni richiudibili della colonna di destra: chiuse di serie, ricordate come sul Mac.</summary>
    public static bool SezioneEffetti
    {
        get => Leggi("sezione-effetti") == "1";
        set => Scrivi("sezione-effetti", value ? "1" : "0");
    }

    public static bool SezioneRegoleFini
    {
        get => Leggi("sezione-regole-fini") == "1";
        set => Scrivi("sezione-regole-fini", value ? "1" : "0");
    }

    /// <summary>«Più tardi» su questa versione («1.0.1 (3)»): il pulsante torna solo con una versione ancora più nuova.</summary>
    public static string? AggiornamentoRimandato
    {
        get => Leggi("aggiornamento-rimandato");
        set => Scrivi("aggiornamento-rimandato", value ?? "");
    }

    /// <summary>
    /// La schermata d'attesa della webcam (WebcamLR Pro, come sul Mac): «webcamlr» (di serie), «nero», «immagine»,
    /// «sfocata». Senza Pro vale sempre «webcamlr».
    /// </summary>
    public static string SchermataAttesa
    {
        get => Leggi("schermata-attesa") is { Length: > 0 } valore ? valore : "webcamlr";
        set => Scrivi("schermata-attesa", value);
    }

    /// <summary>L'immagine personale della schermata d'attesa, copiata qui (PNG o JPEG).</summary>
    public static string FileImmagineAttesa => Path.Combine(Cartella, "immagine-attesa");

    /// <summary>La scritta (P17): l'ultimo nome e ruolo scritti, per ritrovarli nelle caselle.</summary>
    public static string NomeScritta
    {
        get => Leggi("scritta-nome") ?? "";
        set => Scrivi("scritta-nome", value);
    }

    public static string RuoloScritta
    {
        get => Leggi("scritta-ruolo") ?? "";
        set => Scrivi("scritta-ruolo", value);
    }

    /// <summary>Il testo del gobbo (P06), per ritrovarlo alla prossima apertura.</summary>
    public static string TestoGobbo
    {
        get => Leggi("gobbo.txt") ?? "";
        set => Scrivi("gobbo.txt", value);
    }

    /// <summary>Dimensione e posizione della finestra (round 2, funzione 47).</summary>
    public static PosizioneFinestra? Finestra
    {
        get => PosizioneFinestra.DaTesto(Leggi("finestra"));
        set { if (value is not null) Scrivi("finestra", value.Testo()); }
    }

    public static Dictionary<string, ProfiloFotocamera> Profili
    {
        get
        {
            var testo = Leggi("profili.json");
            if (testo is null) return [];
            try { return JsonSerializer.Deserialize<Dictionary<string, ProfiloFotocamera>>(testo) ?? []; }
            catch (JsonException) { return []; }
        }
        set => Scrivi("profili.json", JsonSerializer.Serialize(value));
    }

    /// <summary>
    /// La chiave permanente del PC (collegamento sicuro, 0.10), cifrata con DPAPI per l'utente di Windows:
    /// copiare il file su un altro PC o un altro utente non serve a niente. Se manca o è illeggibile, se ne crea una nuova
    /// (i telefoni lo vedranno come un PC diverso e chiederanno di riabbinarsi).
    /// </summary>
    public static IdentitaDispositivo Identita()
    {
        var file = Path.Combine(Cartella, "identita");
        try
        {
            var chiaro = ProtectedData.Unprotect(File.ReadAllBytes(file), null, DataProtectionScope.CurrentUser);
            return IdentitaDispositivo.DaPkcs8(chiaro);
        }
        catch (Exception) { }

        var nuova = IdentitaDispositivo.Nuova();
        try
        {
            Directory.CreateDirectory(Cartella);
            File.WriteAllBytes(file, ProtectedData.Protect(nuova.EsportaPkcs8(), null, DataProtectionScope.CurrentUser));
        }
        catch (Exception) { }
        return nuova;
    }

    /// <summary>Telefoni fidati: impronta → nome.</summary>
    public static Dictionary<string, string> TelefoniFidati
    {
        get
        {
            var testo = Leggi("fidati.json");
            if (testo is null) return [];
            try { return JsonSerializer.Deserialize<Dictionary<string, string>>(testo) ?? []; }
            catch (JsonException) { return []; }
        }
        set => Scrivi("fidati.json", JsonSerializer.Serialize(value));
    }

    /// <summary>L'interruttore «Microfono del telefono» (W2): la scelta resta, come sul Mac.</summary>
    public static bool MicrofonoTelefono
    {
        get => Leggi("microfono-telefono") == "1";
        set => Scrivi("microfono-telefono", value ? "1" : "0");
    }

    /// <summary>
    /// L'uscita audio del microfono (ID di Windows); "" = nessuna, scelta dall'utente; null = mai scelta (allora il primo
    /// cavo audio virtuale, se c'è).
    /// </summary>
    public static string? UscitaMicrofono
    {
        get => Leggi("microfono-uscita");
        set => Scrivi("microfono-uscita", value ?? "");
    }

    private static string? Leggi(string nome)
    {
        try { return File.ReadAllText(Path.Combine(Cartella, nome)).Trim(); }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    private static void Scrivi(string nome, string valore)
    {
        try
        {
            Directory.CreateDirectory(Cartella);
            File.WriteAllText(Path.Combine(Cartella, nome), valore);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
