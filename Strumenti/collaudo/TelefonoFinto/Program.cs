using System.Security.Cryptography;
using WebcamLR.Collaudo;
using WebcamLR.Protocollo;

// TelefonoFinto: un iPhone simulato per provare il ricevitore WebcamLR vero (l'app Windows, o il Ricevitore nei test)
// sulla stessa macchina. Uso e opzioni: Strumenti/collaudo/windows/LEGGIMI.md e «TelefonoFinto --aiuto».

Opzioni opzioni;
try
{
    opzioni = Opzioni.Leggi(args);
}
catch (ArgumentException errore)
{
    Console.Error.WriteLine($"TelefonoFinto: {errore.Message}");
    Console.Error.WriteLine("Usa --aiuto per l'elenco delle opzioni.");
    return 64;
}
if (opzioni.Aiuto)
{
    Console.WriteLine(Opzioni.Testo);
    return 0;
}

var bloccoScrittura = new object();
StreamWriter? registro = opzioni.FileRegistro is { } percorso ? new StreamWriter(percorso, append: true) { AutoFlush = true } : null;
void Scrivi(string riga)
{
    var testo = $"[{DateTime.Now:HH:mm:ss.fff}] [{opzioni.Nome}] {riga}";
    lock (bloccoScrittura)
    {
        Console.WriteLine(testo);
        registro?.WriteLine(testo);
    }
}

// Dal QR code (immagine o testo): indirizzo, porta, impronta del computer e gettone.
try
{
    string? testoQr = opzioni.Collegamento;
    if (opzioni.FileQr is { } fileQr)
    {
        testoQr = LettoreQr.Leggi(fileQr);
        if (testoQr is null)
        {
            Scrivi($"ERRORE: nessun QR code leggibile in {fileQr}");
            return 6;
        }
        Scrivi($"QR letto: {testoQr}");
    }
    if (testoQr is not null)
    {
        var associazione = Associazione.Leggi(testoQr) ?? throw new ArgumentException($"Non è un QR di WebcamLR: {testoQr}");
        opzioni.ApplicaQr(associazione);
    }
}
catch (Exception errore) when (errore is IOException or InvalidDataException or ArgumentException)
{
    Scrivi($"ERRORE nel QR: {errore.Message}");
    return 6;
}

using var identita = CaricaIdentita(opzioni, Scrivi);
using var annulla = new CancellationTokenSource();
Console.CancelKeyPress += (_, evento) =>
{
    evento.Cancel = true;
    annulla.Cancel();
};
// Dalla riga di comando di PowerShell (Stop-Process) non arriva Ctrl+C: anche un file «ferma» accanto al registro chiude bene.
if (opzioni.FileFerma is { } ferma)
    _ = Task.Run(async () =>
    {
        while (!annulla.IsCancellationRequested)
        {
            if (File.Exists(ferma)) { annulla.Cancel(); break; }
            await Task.Delay(250);
        }
    });

var inizio = DateTime.UtcNow;
TimeSpan Restante() => opzioni.Durata - (DateTime.UtcNow - inizio);
var interrompiDopo = opzioni.InterrompiDopo;
Esito esito;
var tentativo = 0;
while (true)
{
    tentativo++;
    var telefono = new Telefono(opzioni, identita, Scrivi);
    esito = await telefono.SessioneAsync(Restante(), interrompiDopo, annulla.Token);
    interrompiDopo = null; // si interrompe una volta sola
    if (annulla.IsCancellationRequested || Restante() <= TimeSpan.Zero) break;
    var riprova = esito switch
    {
        Esito.Interrotta => opzioni.RiconnettiDopo is not null,
        Esito.ErroreRete or Esito.ChiusaDalComputer => opzioni.RiconnettiSempre,
        _ => false,
    };
    if (!riprova) break;
    var pausa = esito == Esito.Interrotta && opzioni.ModoInterruzione == "chiusura" ? opzioni.RiconnettiDopo!.Value : TimeSpan.FromSeconds(2);
    Scrivi($"Nuovo tentativo di collegamento tra {pausa.TotalSeconds:0.#} s (tentativo {tentativo + 1})");
    try { await Task.Delay(pausa, annulla.Token); } catch (OperationCanceledException) { break; }
}
Scrivi($"FINE: {esito} (codice {(int)esito})");
registro?.Dispose();
return (int)esito;

static IdentitaDispositivo CaricaIdentita(Opzioni opzioni, Action<string> scrivi)
{
    // Come un telefono vero l'identità resta tra un avvio e l'altro (un telefono già fidato entra subito), una per nome.
    var file = opzioni.FileIdentita ?? Path.Combine(Path.GetTempPath(), "TelefonoFinto",
        string.Concat(opzioni.Nome.Select(c => char.IsLetterOrDigit(c) ? c : '_')) + ".chiave");
    if (!opzioni.IdentitaNuova && File.Exists(file))
    {
        try { return IdentitaDispositivo.DaPkcs8(File.ReadAllBytes(file)); }
        catch (CryptographicException) { scrivi($"Identità in {file} illeggibile: se ne crea una nuova"); }
    }
    var nuova = IdentitaDispositivo.Nuova();
    try
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllBytes(file, nuova.EsportaPkcs8());
        scrivi($"Identità nuova salvata in {file}");
    }
    catch (IOException) { }
    return nuova;
}
