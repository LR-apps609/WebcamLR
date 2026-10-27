using WebcamLR.Protocollo;

namespace WebcamLR.Effetti;

/// <summary>
/// Le scelte che il motore applica, già con le regole di WebcamLR Pro e della fotocamera frontale (le decide
/// <c>RegoleMotore</c> nel ricevitore). Stessi campi e stesso significato di <c>ImpostazioniMotore</c> del Mac
/// (Mac/Sorgenti/MotoreEffetti.swift).
/// </summary>
public sealed record ImpostazioniMotore
{
    public string Filtro { get; init; } = Filtri.Naturale;
    public double Luminosita { get; init; }
    public double Contrasto { get; init; }
    public double Saturazione { get; init; }
    public double Nitidezza { get; init; }

    /// <summary>Uno dei <see cref="ModiSfondo"/>.</summary>
    public string Sfondo { get; init; } = ModiSfondo.Nessuno;

    /// <summary>Sfocato: quanto sfocare (Poco 0,25, Medio 0,55, Tanto 1). Sostituito: quanto è netto il bordo.</summary>
    public double IntensitaSfondo { get; init; } = 0.5;

    /// <summary>Con lo sfondo sostituito: uno degli <see cref="SfondiPronti"/> o <see cref="SfondiPronti.Personale"/>.</summary>
    public string? ImmagineSfondo { get; init; }

    public double Pelle { get; init; }
    public bool LuceVolto { get; init; }
    public bool Inquadratura { get; init; }
    public double Calore { get; init; }
    public bool Specchia { get; init; }

    /// <summary>La scritta (nome vuoto = nessuna) e il logo.</summary>
    public string Nome { get; init; } = "";
    public string Ruolo { get; init; } = "";
    public bool Logo { get; init; }

    public static ImpostazioniMotore Spento { get; } = new();

    public bool SfondoAcceso => Sfondo is ModiSfondo.Sfocato or ModiSfondo.Sostituito;
    public bool ServonoVolti => Pelle > 0.001 || LuceVolto || Inquadratura;
    public bool RegolazioniAccese => Luminosita != 0 || Contrasto != 0 || Saturazione != 0 || Nitidezza != 0;
    public bool ScrittaAccesa => Nome.Trim().Length > 0 || Logo;
    public bool FiltroAcceso => Filtro != Filtri.Naturale && Filtri.Tutti.Contains(Filtro);

    /// <summary>Niente da fare: il video passa com'è (costo zero).</summary>
    public bool Spente => !SfondoAcceso && !ServonoVolti && !FiltroAcceso && !RegolazioniAccese && Calore <= 0.001
        && !Specchia && !ScrittaAccesa;
}

/// <summary>
/// Le scelte e le immagini del motore, condivise da chi le scrive (la finestra, sul suo thread) e da chi le legge (il
/// motore, sui suoi thread). Come <c>StatoEffettiComputer</c> del Mac.
/// </summary>
public sealed class StatoEffettiComputer
{
    /// <summary>Quello che serve a una resa, preso tutto insieme.</summary>
    public sealed record Istantanea(ImpostazioniMotore Impostazioni, (string Id, ImmagineBgra Immagine, int Versione)? Sfondo,
        (ImmagineBgra Immagine, int Versione)? Logo, IDisegnoScritta? Scritta);

    private readonly object blocco = new();
    private ImpostazioniMotore impostazioni = ImpostazioniMotore.Spento;
    private (string Id, ImmagineBgra Immagine, int Versione)? sfondo;
    private (ImmagineBgra Immagine, int Versione)? logo;
    private IDisegnoScritta? scritta;
    private int versione;

    public ImpostazioniMotore Impostazioni
    {
        get { lock (blocco) return impostazioni; }
    }

    public void Imposta(ImpostazioniMotore nuove)
    {
        lock (blocco) impostazioni = nuove;
    }

    /// <summary>L'immagine di uno sfondo (BGRA opaca, di qualsiasi misura: si disegna «a riempire»); null per toglierla.</summary>
    public void ImpostaSfondo(string id, ImmagineBgra? immagine)
    {
        lock (blocco)
        {
            versione++;
            sfondo = immagine is null ? null : (id, immagine, versione);
        }
    }

    /// <summary>Il logo (BGRA con l'alfa non premoltiplicato, come lo dà il decodificatore PNG); null per toglierlo.</summary>
    public void ImpostaLogo(ImmagineBgra? immagine)
    {
        lock (blocco)
        {
            versione++;
            logo = immagine is null ? null : (immagine, versione);
        }
    }

    /// <summary>Chi disegna il sottopancia (sulla piattaforma: caratteri e testo); null = niente scritta.</summary>
    public void ImpostaDisegnoScritta(IDisegnoScritta? disegno)
    {
        lock (blocco) scritta = disegno;
    }

    public Istantanea Prendi()
    {
        lock (blocco) return new(impostazioni, sfondo, logo, scritta);
    }
}

/// <summary>
/// Disegna il sottopancia (barra con nome e ruolo) per un video di quella misura: BGRA con l'alfa premoltiplicato, già
/// alla misura giusta (il motore lo mette in basso a sinistra, dentro i margini di sicurezza). Si chiama solo quando
/// testo o misura cambiano, sul thread della resa.
/// </summary>
public interface IDisegnoScritta
{
    ImmagineBgra? Disegna(string nome, string ruolo, int larghezzaVideo, int altezzaVideo);
}
