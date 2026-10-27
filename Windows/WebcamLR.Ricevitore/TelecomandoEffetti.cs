using WebcamLR.Effetti;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Il telefono come telecomando degli effetti del PC (Protocollo.md, «Effetti sul computer»), come <c>decidiEffetti</c> e
/// <c>mandaStatoEffetti</c> del Mac (Mac/Sorgenti/Ricevitore.swift): uno per telefono, si azzera a ogni sessione
/// (<see cref="NuovaSessione"/>). Alla prima <c>capacita</c> della sessione si decide: con
/// <c>capacita.effettiSulComputer</c> il telefono riceve <c>comando.effettiSulComputer</c> e poi <c>effetti</c>; un telefono
/// di prima riceve il comando che spegne i suoi effetti (<see cref="RegoleEffettiComputer.SpegniEffettiDelTelefono"/>).
/// Poi <c>effetti</c> parte solo quando cambia. Non è thread-safe: la usa solo il thread dell'interfaccia.
/// </summary>
public sealed class TelecomandoEffetti
{
    /// <summary>Vero = telecomando, falso = telefono di prima, null = non ancora deciso in questa sessione.</summary>
    public bool? Attivo { get; private set; }

    /// <summary>L'ultimo <c>effetti</c> mandato in questa sessione.</summary>
    public EffettiComputer? Inviati { get; private set; }

    /// <summary>Sessione nuova: si decide di nuovo alla sua prima <c>capacita</c> (il telefono lo tiene solo per la sessione).</summary>
    public void NuovaSessione()
    {
        Attivo = null;
        Inviati = null;
    }

    /// <summary>Una <c>capacita</c>: i messaggi da mandare, in ordine. Decide solo la prima della sessione; le altre niente.</summary>
    /// <param name="stato">Lo stato degli effetti per questo telefono (<see cref="RegoleTelecomando.Stato"/>).</param>
    /// <param name="sulComputer">L'interruttore degli effetti sul computer: spento, il PC non decide nulla (come prima).</param>
    public IReadOnlyList<Messaggio> Decidi(Capacita capacita, EffettiComputer stato, bool sulComputer = RegoleEffettiComputer.EffettiSulComputer)
    {
        if (!sulComputer || Attivo is not null) return [];
        if (capacita.EffettiSulComputer != true)
        {
            Attivo = false;
            return [RegoleEffettiComputer.SpegniEffettiDelTelefono];
        }
        Attivo = true;
        Inviati = stato;
        return [new Comando(EffettiSulComputer: true), stato];
    }

    /// <summary>
    /// L'<c>effetti</c> da mandare adesso a un telecomando: solo se è cambiato dall'ultimo mandato (<paramref name="sempre"/>:
    /// anche se non è cambiato). Null = niente da mandare (anche per un telefono che non è un telecomando).
    /// </summary>
    public EffettiComputer? DaMandare(EffettiComputer stato, bool sempre = false)
    {
        if (Attivo != true || (!sempre && stato == Inviati)) return null;
        Inviati = stato;
        return stato;
    }

    /// <summary>
    /// Dimentica l'ultimo mandato, prima di applicare un <c>chiedi-effetto</c>: la risposta parte sempre, una volta sola
    /// (con il giro dei cambi, o con il <see cref="DaMandare"/> che segue).
    /// </summary>
    public void Dimentica() => Inviati = null;
}

/// <summary>Le regole del telecomando: cosa dice <c>effetti</c> e cosa fa un <c>chiedi-effetto</c>, come i pulsanti del PC.</summary>
public static class RegoleTelecomando
{
    /// <summary>
    /// Specchio, sfondo e luce sul volto come li fa davvero il motore per questo telefono (<see cref="RegoleMotore"/>):
    /// specchio e sfondo solo con la frontale, sfondo sostituito solo con Pro e un'immagine, mai sopra Ritratto o Luce da
    /// studio del telefono.
    /// </summary>
    /// <param name="immagineSfondo">Con lo sfondo sostituito: l'immagine che il PC ha (null = nessuna).</param>
    public static EffettiComputer Stato(ValoriEffetti scelti, bool pro, StatoTelefono? stato, string? immagineSfondo)
    {
        var motore = RegoleMotore.Da(scelti, pro, stato, immagineSfondo, logo: false);
        var sfondo = motore.SfondoAcceso ? motore.Sfondo : ModiSfondo.Nessuno;
        return new EffettiComputer(motore.Specchia, sfondo, motore.LuceVolto);
    }

    /// <summary>
    /// Il comando per le scelte del PC da un <c>chiedi-effetto</c> (tutti e tre gratis, come i pulsanti del PC): specchio e
    /// sfondo solo con la frontale; «sfocato» accende la sfocatura con <paramref name="ultimoLivello"/> (l'ultimo scelto sul
    /// PC), ma non sopra Ritratto del telefono; «nessuno» spegne lo sfondo (sfocato o sostituito); un altro valore si
    /// ignora; la luce non si accende sopra Luce da studio. Null se non resta niente da applicare.
    /// </summary>
    public static Comando? Comando(ChiediEffetto richiesta, StatoTelefono? stato, LivelloSfocatura ultimoLivello)
    {
        var frontale = !SoloFrontale.Posteriore(stato);
        var specchia = frontale ? richiesta.Specchia : null;
        bool? luce = richiesta.LuceVolto is bool accesa && (!accesa || !EffettiDelSistema.Luce(stato)) ? accesa : null;
        string? sfondo = null;
        double? intensita = null;
        if (frontale && richiesta.Sfondo == ModiSfondo.Nessuno)
        {
            sfondo = ModiSfondo.Nessuno;
        }
        else if (frontale && richiesta.Sfondo == ModiSfondo.Sfocato && !EffettiDelSistema.Sfocatura(stato))
        {
            sfondo = ModiSfondo.Sfocato;
            intensita = LivelliSfocatura.Intensita(ultimoLivello);
        }
        var comando = new Comando(Specchia: specchia, Sfondo: sfondo, IntensitaSfondo: intensita, LuceVolto: luce);
        return comando == new Comando() ? null : comando;
    }
}
