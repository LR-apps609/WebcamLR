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
