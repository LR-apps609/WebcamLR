namespace WebcamLR.Ricevitore;

/// <summary>
/// I valori di HKCU\Software\Microsoft\Windows\CurrentVersion\Run, dietro un'interfaccia
/// così la regola si prova senza il registro di Windows.
/// </summary>
public interface IRegistroAvvio
{
    string? Leggi(string nome);
    void Scrivi(string nome, string valore);
    void Elimina(string nome);
}

/// <summary>
/// «Avvia con Windows» (round 2, funzione 40): una voce in Run che lancia l'exe con <c>--avvio</c>,
/// così all'accesso l'app parte nascosta, solo con l'icona accanto all'orologio.
/// </summary>
public sealed class AvvioConWindows(IRegistroAvvio registro, string percorsoEseguibile)
{
    public const string NomeValore = "WebcamLR";
    public const string Argomento = "--avvio";

    /// <summary>Il comando scritto nel registro, con le virgolette per i percorsi con spazi.</summary>
    public string Comando => $"\"{percorsoEseguibile}\" {Argomento}";

    /// <summary>
    /// Vero se Windows avvia proprio questo exe. Una voce che punta altrove (exe spostato, un'altra copia)
    /// non conta e non si tocca da sola: accendendo l'interruttore si riscrive con il percorso di adesso.
    /// </summary>
    public bool Attivo =>
        registro.Leggi(NomeValore) is { } valore && valore.Contains(percorsoEseguibile, StringComparison.OrdinalIgnoreCase);

    public void Imposta(bool attivo)
    {
        if (attivo) registro.Scrivi(NomeValore, Comando);
        else registro.Elimina(NomeValore);
    }

    /// <summary>Vero se l'app è stata lanciata da Windows all'accesso.</summary>
    public static bool AvviatoDaWindows(IEnumerable<string> argomenti) =>
        argomenti.Any(argomento => argomento.Equals(Argomento, StringComparison.OrdinalIgnoreCase));
}
