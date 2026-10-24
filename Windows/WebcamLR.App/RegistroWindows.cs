using Microsoft.Win32;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// La chiave Run dell'utente (HKCU), senza permessi di amministratore.
/// Un registro bloccato da criteri aziendali vale come «spento»: l'interruttore non deve chiudere l'app.
/// </summary>
public sealed class RegistroWindows : IRegistroAvvio
{
    private const string Chiave = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public string? Leggi(string nome)
    {
        try
        {
            using var chiave = Registry.CurrentUser.OpenSubKey(Chiave);
            return chiave?.GetValue(nome) as string;
        }
        catch (Exception) { return null; }
    }

    public void Scrivi(string nome, string valore)
    {
        try
        {
            using var chiave = Registry.CurrentUser.CreateSubKey(Chiave, writable: true);
            chiave.SetValue(nome, valore, RegistryValueKind.String);
        }
        catch (Exception) { }
    }

    public void Elimina(string nome)
    {
        try
        {
            using var chiave = Registry.CurrentUser.OpenSubKey(Chiave, writable: true);
            chiave?.DeleteValue(nome, throwOnMissingValue: false);
        }
        catch (Exception) { }
    }
}
