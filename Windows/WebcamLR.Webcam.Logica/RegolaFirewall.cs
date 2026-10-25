namespace WebcamLR.Webcam;

/// <summary>
/// La regola del firewall di Windows che lascia arrivare il telefono a WebcamLR sulle reti private (casa, ufficio):
/// la aggiunge e la toglie WebcamLR.Webcam.Installa.exe, da amministratore, con netsh («firewall» e «rimuovi-firewall»,
/// anche dentro «configura» e «disinstalla»). Sulle reti pubbliche no, di proposito: lì la diagnosi dell'app
/// consiglia di rendere privata la rete (WebcamLR.Ricevitore, Diagnosi). Qui solo gli argomenti, provati con i test.
/// </summary>
public static class RegolaFirewall
{
    /// <summary>Il nome della regola in «Windows Defender Firewall con sicurezza avanzata».</summary>
    public const string Nome = "WebcamLR";

    public const string Descrizione = "Lascia arrivare il video del telefono a WebcamLR sulle reti private.";

    /// <summary>
    /// Vero se il percorso è accettabile per una regola: assoluto, senza virgolette, e il programma è WebcamLR.exe.
    /// L'installatore della webcam gira da amministratore: non deve aprire il firewall a un programma qualsiasi.
    /// </summary>
    public static bool ProgrammaValido(string? programma) =>
        !string.IsNullOrWhiteSpace(programma) && !programma.Contains('"') && programma.Length > 3
        && programma[1] == ':' && programma[2] == '\\'
        && programma.EndsWith("\\WebcamLR.exe", StringComparison.OrdinalIgnoreCase);

    /// <summary>netsh: una regola in ingresso, tutti i protocolli e le porte, solo per WebcamLR.exe, solo reti private.</summary>
    public static string ArgomentiAggiungi(string programma) =>
        $"advfirewall firewall add rule name=\"{Nome}\" dir=in action=allow program=\"{programma}\" enable=yes profile=private "
        + $"description=\"{Descrizione}\"";

    /// <summary>netsh: toglie le regole con questo nome per questo programma (prima di aggiungerla di nuovo, e alla disinstallazione).</summary>
    public static string ArgomentiTogli(string programma) =>
        $"advfirewall firewall delete rule name=\"{Nome}\" program=\"{programma}\"";
}
