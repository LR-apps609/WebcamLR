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

    public static bool Specchia
    {
        get => Leggi("specchia") == "1";
        set => Scrivi("specchia", value ? "1" : "0");
    }

    /// <summary>Webcam (1.24): come entra un video di altre proporzioni. Di serie tutto, con le bande nere.</summary>
    public static WebcamLR.Webcam.Inquadratura InquadraturaWebcam
    {
        get => Leggi("webcam-inquadratura") == "riempi" ? WebcamLR.Webcam.Inquadratura.Riempi : WebcamLR.Webcam.Inquadratura.Adatta;
        set => Scrivi("webcam-inquadratura", value == WebcamLR.Webcam.Inquadratura.Riempi ? "riempi" : "adatta");
    }

    /// <summary>Webcam (1.24): specchia anche per chi guarda. Di serie no: «Specchia» vale solo per l'anteprima.</summary>
    public static bool SpecchiaWebcam
    {
        get => Leggi("webcam-specchia") == "1";
        set => Scrivi("webcam-specchia", value ? "1" : "0");
    }

    /// <summary>Modalità avanzata (1.5): spenta di serie, mostra statistiche, controlli manuali e registro.</summary>
    public static bool ModalitaAvanzata
    {
        get => Leggi("avanzata") == "1";
        set => Scrivi("avanzata", value ? "1" : "0");
    }

    /// <summary>Vero dopo che si è chiuso l'avviso «Per ora solo video.»: non torna.</summary>
    public static bool AvvisoMicrofonoChiuso
    {
        get => Leggi("avviso-microfono-chiuso") == "1";
        set => Scrivi("avviso-microfono-chiuso", value ? "1" : "0");
    }

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
