using System.Security.Cryptography;
using System.Text;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Chi può collegarsi a questo computer (protocollo 2, «Prova e abbinamento»): i telefoni fidati,
/// chi rimanda il gettone del QR code mostrato ora, oppure chi l'utente conferma con il codice di 4 cifre.
/// </summary>
public sealed class Abbinamento
{
    private readonly object blocco = new();
    private readonly Dictionary<string, string> fidati;
    private readonly Action<IReadOnlyDictionary<string, string>>? salva;
    private string gettone = Sicurezza.NuovoGettone();

    /// <param name="fidati">Impronta del telefono → nome, come salvati l'ultima volta.</param>
    /// <param name="salva">Chiamata a ogni modifica dei telefoni fidati.</param>
    public Abbinamento(IdentitaDispositivo identita, IReadOnlyDictionary<string, string>? fidati = null,
        Action<IReadOnlyDictionary<string, string>>? salva = null)
    {
        Identita = identita;
        this.fidati = new Dictionary<string, string>(fidati ?? new Dictionary<string, string>());
        this.salva = salva;
    }

    public IdentitaDispositivo Identita { get; }

    /// <summary>Il gettone del QR code mostrato ora: cambia dopo ogni uso.</summary>
    public string Gettone
    {
        get { lock (blocco) return gettone; }
    }

    /// <summary>Il gettone è cambiato: il QR code va rifatto.</summary>
    public event Action? GettoneCambiato;

    /// <summary>
    /// Chiede all'utente se accettare un telefono nuovo: (nome del telefono, codice di 4 cifre) → consentito?
    /// Senza, i telefoni nuovi senza gettone vengono rifiutati.
    /// </summary>
    public Func<string, string, CancellationToken, Task<bool>>? ChiediConferma { get; set; }

    /// <summary>
    /// Dopo «Non consentire» (o il tempo scaduto) la stessa impronta non fa ricomparire la domanda per questo tempo
    /// (collaudo 37): chi è in rete non può riaprirla senza fine né portare la finestra davanti durante la chiamata.
    /// </summary>
    public static readonly TimeSpan PausaDopoRifiuto = TimeSpan.FromMinutes(2);

    /// <summary>Millisecondi, per <see cref="PausaDopoRifiuto"/>; nei test si cambia.</summary>
    public Func<long> Orologio { get; set; } = () => Environment.TickCount64;

    private readonly Dictionary<string, long> rifiutati = [];

    /// <summary>Una domanda «Consentire …?» alla volta: la seconda aspetta che la prima sia chiusa (collaudo 33).</summary>
    private readonly SemaphoreSlim unaDomanda = new(1, 1);

    /// <summary>La domanda per questa impronta è stata rifiutata da meno di <see cref="PausaDopoRifiuto"/>.</summary>
    public bool RifiutatoDaPoco(string impronta)
    {
        lock (blocco)
        {
            var adesso = Orologio();
            foreach (var vecchio in rifiutati.Where(r => adesso - r.Value >= (long)PausaDopoRifiuto.TotalMilliseconds).Select(r => r.Key).ToList())
                rifiutati.Remove(vecchio);
            return rifiutati.ContainsKey(impronta);
        }
    }

    /// <summary>L'utente ha detto no (o non ha risposto in tempo) a questa impronta.</summary>
    public void SegnaRifiuto(string impronta)
    {
        lock (blocco) rifiutati[impronta] = Orologio();
    }

    /// <summary>
    /// Chiede la conferma con <see cref="ChiediConferma"/>, una domanda alla volta: se ce n'è già una aperta per un altro
    /// telefono, questa aspetta che sia chiusa (entro <paramref name="scaduto"/>, il tempo del telefono). Il no, o il tempo
    /// scaduto con la domanda aperta, si ricorda (<see cref="PausaDopoRifiuto"/>); non se il telefono è andato via
    /// (<paramref name="telefonoVia"/>) né se il tempo è finito in fila dietro un'altra domanda, che l'utente non ha visto.
    /// </summary>
    public async Task<bool> ConfermaAsync(string impronta, string nome, string codice, CancellationToken scaduto,
        CancellationToken telefonoVia = default)
    {
        if (ChiediConferma is not { } chiedi) return false;
        bool consentito;
        try
        {
            await unaDomanda.WaitAsync(scaduto);
        }
        catch (OperationCanceledException)
        {
            return false;
        }
        try
        {
            try { consentito = await chiedi(nome, codice, scaduto); }
            catch (OperationCanceledException) { consentito = false; }
            if (!consentito && !telefonoVia.IsCancellationRequested) SegnaRifiuto(impronta);
        }
        finally
        {
            unaDomanda.Release();
        }
        return consentito;
    }

    public bool Fidato(string impronta)
    {
        lock (blocco) return fidati.ContainsKey(impronta);
    }

    public IReadOnlyList<(string Impronta, string Nome)> Fidati
    {
        get { lock (blocco) return fidati.Select(coppia => (coppia.Key, coppia.Value)).OrderBy(f => f.Value).ToList(); }
    }

    public void Fida(string impronta, string nome)
    {
        Dictionary<string, string> copia;
        lock (blocco)
        {
            // Già fidato con lo stesso nome (ogni ricollegamento): niente da salvare. Il salvataggio scrive
            // un file e veniva prima del «benvenuto», rallentando ogni avvio (1.11).
            if (fidati.TryGetValue(impronta, out var attuale) && attuale == nome) return;
            fidati[impronta] = nome;
            copia = new Dictionary<string, string>(fidati);
        }
        salva?.Invoke(copia);
    }

    public void Rimuovi(string impronta)
    {
        Dictionary<string, string> copia;
        lock (blocco)
        {
            if (!fidati.Remove(impronta)) return;
            copia = new Dictionary<string, string>(fidati);
        }
        salva?.Invoke(copia);
    }

    /// <summary>Vero se il gettone è quello del QR code attuale; in quel caso il QR cambia.</summary>
    public bool UsaGettone(string? proposto)
    {
        if (string.IsNullOrEmpty(proposto)) return false;
        lock (blocco)
        {
            // Confronto a tempo costante: dalla durata non si indovina il gettone.
            if (!CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(proposto), Encoding.UTF8.GetBytes(gettone)))
                return false;
            gettone = Sicurezza.NuovoGettone();
        }
        GettoneCambiato?.Invoke();
        return true;
    }
}
