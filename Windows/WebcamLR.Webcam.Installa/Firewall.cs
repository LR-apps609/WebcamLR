using System.Diagnostics;

namespace WebcamLR.Webcam.Installa;

/// <summary>
/// La regola del firewall per WebcamLR.exe (<see cref="RegolaFirewall"/>), con netsh di Windows: c'è su ogni Windows 10
/// e 11 e non serve COM. Si toglie prima quella vecchia con lo stesso nome e programma: reinstallare non ne aggiunge
/// una seconda. Da amministratore.
/// </summary>
internal static class Firewall
{
    public static int Aggiungi(string programma, Action<string> registro)
    {
        if (!RegolaFirewall.ProgrammaValido(programma))
        {
            registro($"Firewall: percorso non accettato: {programma}");
            return CodiciInstallazione.ArgomentiErrati;
        }
        Netsh(RegolaFirewall.ArgomentiTogli(programma), registro);
        return Netsh(RegolaFirewall.ArgomentiAggiungi(programma), registro) == 0
            ? CodiciInstallazione.Riuscita : CodiciInstallazione.FirewallFallito;
    }

    /// <summary>Riuscita anche se la regola non c'era (netsh risponde 1 con «Nessuna regola corrisponde»).</summary>
    public static int Togli(string programma, Action<string> registro)
    {
        if (!RegolaFirewall.ProgrammaValido(programma))
        {
            registro($"Firewall: percorso non accettato: {programma}");
            return CodiciInstallazione.ArgomentiErrati;
        }
        Netsh(RegolaFirewall.ArgomentiTogli(programma), registro);
        return CodiciInstallazione.Riuscita;
    }

    private static int Netsh(string argomenti, Action<string> registro)
    {
        try
        {
            var netsh = Path.Combine(Environment.SystemDirectory, "netsh.exe");
            using var processo = Process.Start(new ProcessStartInfo(netsh, argomenti)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            });
            if (processo is null) return -1;
            var uscita = processo.StandardOutput.ReadToEnd().Trim();
            processo.WaitForExit(30_000);
            registro($"netsh {argomenti}: {processo.ExitCode} {uscita.ReplaceLineEndings(" ")}");
            return processo.ExitCode;
        }
        catch (Exception errore)
        {
            registro($"netsh non parte: {errore.Message}");
            return -1;
        }
    }
}
