using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Gli sfondi dal PC (27 ottobre), come sul Mac (Mac/Sorgenti/Sfondi.swift): il pulsante «Sfondo» sotto il video, gli
/// sfondi pronti con le miniature, «Carica un'immagine…» e il logo della scritta. Il telefono fa il lavoro: il PC sceglie,
/// riduce e manda (pacchetto immagine, tipo 4, solo se <c>capacita.immagini</c>; Documenti/Protocollo.md).
/// Qui la logica senza interfaccia, provata con i test.
/// </summary>
public static class SceltaSfondo
{
    /// <summary>L'ultima scelta del pulsante quando è la sfocatura (con l'ultimo livello); altrimenti è l'id di uno sfondo.</summary>
    public const string Sfocatura = "sfocatura";

    /// <summary>Il nome mostrato di uno sfondo; gli identificativi sono fissi nel protocollo.</summary>
    public static string Nome(string id) => id switch
    {
        SfondiPronti.Ufficio => TestiRicevitore.T("SfondoPronto_Ufficio"),
        SfondiPronti.Libreria => TestiRicevitore.T("SfondoPronto_Libreria"),
        SfondiPronti.Soggiorno => TestiRicevitore.T("SfondoPronto_Soggiorno"),
        SfondiPronti.Studio => TestiRicevitore.T("SfondoPronto_Studio"),
        SfondiPronti.Citta => TestiRicevitore.T("SfondoPronto_Citta"),
        SfondiPronti.Cemento => TestiRicevitore.T("SfondoPronto_Cemento"),
        SfondiPronti.Piante => TestiRicevitore.T("SfondoPronto_Piante"),
        SfondiPronti.Lrapps => TestiRicevitore.T("SfondoPronto_Lrapps"),
        SfondiPronti.Personale => TestiRicevitore.T("SfondoPronto_Personale"),
        "" => TestiRicevitore.T("SfondoPronto_Personale"),
        _ => char.ToUpperInvariant(id[0]) + id[1..],
    };

    /// <summary>
    /// Gli sfondi pronti da mostrare: quelli di <c>capacita.sfondiPronti</c>, nell'ordine del telefono, senza doppi e solo
    /// quelli di cui il PC ha la miniatura (un id sconosciuto, da un telefono più nuovo, non si mostra).
    /// </summary>
    public static IReadOnlyList<string> Pronti(Capacita? capacita) =>
        (capacita?.SfondiPronti ?? []).Where(id => SfondiPronti.Tutti.Contains(id)).Distinct().ToList();

    /// <summary>Il telefono accetta il pacchetto immagine: solo allora il PC lo manda (un telefono vecchio chiuderebbe).</summary>
    public static bool Immagini(Capacita? capacita) => capacita?.Immagini == true;

    /// <summary>
    /// Con lo sfondo sostituito, l'immagine che il telefono mostra (quella con la spunta): un id sconosciuto o assente vale
    /// il primo sfondo pronto. Null con lo sfondo spento o sfocato.
    /// </summary>
    public static string? ImmagineAttuale(ValoriEffetti valori, IReadOnlyList<string> pronti)
    {
        if (valori.Sfondo != ModiSfondo.Sostituito) return null;
        if (valori.ImmagineSfondo is { } id && (id == SfondiPronti.Personale || pronti.Contains(id))) return id;
        return pronti.Count > 0 ? pronti[0] : null;
    }

    /// <summary>
    /// «La tua immagine» si mostra se il PC ne ha una copia (e il telefono può riceverla) o se il telefono ne ha una
    /// (<c>stato.immaginePersonale</c>).
    /// </summary>
    public static bool PersonaleDisponibile(string? improntaSalvata, bool immagini, string? improntaTelefono) =>
        (improntaSalvata is not null && immagini) || improntaTelefono is not null;

    /// <summary>
    /// Scegliendo «La tua immagine»: la copia del PC va rimandata prima del comando se il telefono ne ha un'altra (impronta
    /// diversa) o nessuna, e se il telefono accetta le immagini.
    /// </summary>
    public static bool DaRimandare(string? improntaSalvata, bool immagini, string? improntaTelefono) =>
        immagini && improntaSalvata is not null && improntaSalvata != improntaTelefono;

    /// <summary>
    /// Il clic sul pulsante «Sfondo»: <see cref="ModiSfondo.Nessuno"/> se lo sfondo è acceso; altrimenti l'ultima scelta.
    /// Uno sfondo (l'id) solo se c'è ancora e se il telefono ha Pro; in tutti gli altri casi <see cref="Sfocatura"/>, che è
    /// gratis.
    /// </summary>
    public static string Clic(ValoriEffetti valori, string? ultima, bool pro, IReadOnlyList<string> pronti, bool personaleDisponibile)
    {
        if (valori.SfondoAcceso) return ModiSfondo.Nessuno;
        if (!pro || ultima is null || ultima == Sfocatura) return Sfocatura;
        var disponibile = ultima == SfondiPronti.Personale ? personaleDisponibile : pronti.Contains(ultima);
        return disponibile ? ultima : Sfocatura;
    }
}

/// <summary>Le misure di un'immagine ridotta prima di mandarla al telefono.</summary>
public static class RiduzioneImmagine
{
    /// <summary>Lato lungo dello sfondo personale (JPEG, qualità <see cref="QualitaJpeg"/>).</summary>
    public const uint LatoSfondo = 1920;

    /// <summary>Lato lungo del logo (PNG, con la trasparenza).</summary>
    public const uint LatoLogo = 512;

    public const float QualitaJpeg = 0.85f;

    /// <summary>
    /// Il lato lungo al massimo <paramref name="latoMassimo"/>, le proporzioni tenute, mai ingrandita, almeno 1 pixel per
    /// lato.
    /// </summary>
    public static (uint Larghezza, uint Altezza) Misure(uint larghezza, uint altezza, uint latoMassimo)
    {
        if (larghezza == 0 || altezza == 0) return (1, 1);
        var lungo = Math.Max(larghezza, altezza);
        if (lungo <= latoMassimo) return (larghezza, altezza);
        var scala = (double)latoMassimo / lungo;
        return (Math.Max(1, (uint)Math.Round(larghezza * scala)), Math.Max(1, (uint)Math.Round(altezza * scala)));
    }
}

/// <summary>
/// L'immagine personale e il logo caricati dal PC: una copia già ridotta nella cartella dell'app, che resta tra i riavvii,
/// con la sua impronta (<see cref="PacchettoImmagine.ImprontaDi"/>). Si usa dal thread dell'interfaccia.
/// </summary>
public sealed class MemoriaImmagini
{
    private readonly string cartella;
    private readonly Dictionary<UsoImmagine, string?> impronte = [];

    public MemoriaImmagini(string cartella)
    {
        this.cartella = cartella;
        foreach (var uso in new[] { UsoImmagine.Sfondo, UsoImmagine.Logo })
            impronte[uso] = Leggi(uso) is { } dati ? PacchettoImmagine.ImprontaDi(dati) : null;
    }

    /// <summary>Il file della copia: «sfondo-personale.jpg» o «logo.png».</summary>
    public string Percorso(UsoImmagine uso) =>
        Path.Combine(cartella, uso == UsoImmagine.Logo ? "logo.png" : "sfondo-personale.jpg");

    /// <summary>L'impronta della copia; null se non ce n'è una.</summary>
    public string? Impronta(UsoImmagine uso) => impronte.GetValueOrDefault(uso);

    /// <summary>I byte della copia; null se non c'è o non si legge.</summary>
    public byte[]? Leggi(UsoImmagine uso)
    {
        try { return File.Exists(Percorso(uso)) ? File.ReadAllBytes(Percorso(uso)) : null; }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>Sostituisce la copia; restituisce l'impronta nuova. Un file vuoto o oltre gli 8 MiB del protocollo non si salva.</summary>
    public string Salva(UsoImmagine uso, byte[] dati)
    {
        if (dati.Length == 0 || dati.Length > PacchettoImmagine.DimensioneMassima)
            throw new ArgumentException("Immagine vuota o troppo grande", nameof(dati));
        Directory.CreateDirectory(cartella);
        var temporaneo = Percorso(uso) + ".nuovo";
        File.WriteAllBytes(temporaneo, dati);
        File.Move(temporaneo, Percorso(uso), overwrite: true);
        var impronta = PacchettoImmagine.ImprontaDi(dati);
        impronte[uso] = impronta;
        return impronta;
    }
}
