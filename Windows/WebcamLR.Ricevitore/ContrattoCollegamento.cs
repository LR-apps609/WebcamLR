using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// L'unico punto che legge e scrive i campi del protocollo per la scelta della strada (Documenti/Protocollo.md:
/// <c>capacita.sceltaCollegamento</c>, <c>comando.collegamento</c>, <c>stato.collegamento</c>). Il resto del ricevitore
/// e la finestra usano <see cref="StradeTelefono"/> e <see cref="PreferenzaCollegamento"/>.
///
/// PROVVISORIO (interfaccia finale, 26 ottobre): i campi li aggiunge al protocollo C# un altro ramo, in parallelo.
/// Il progetto definisce CONTRATTO_COLLEGAMENTO da solo quando WebcamLR.Protocollo/Messaggi.cs li contiene
/// (WebcamLR.Ricevitore.csproj), così questo file compila prima e dopo l'unione. Dopo l'unione: togliere il ramo
/// #else, l'#if e la condizione nel .csproj.
/// </summary>
public static class ContrattoCollegamento
{
#if CONTRATTO_COLLEGAMENTO
    /// <summary>Vero se il protocollo di questa versione ha i campi della scelta della strada.</summary>
    public const bool Presente = true;

    /// <summary>Il telefono sa cambiare strada e accetta la preferenza dal computer.</summary>
    public static bool SaScegliere(Capacita? capacita) => capacita?.SceltaCollegamento == true;

    /// <summary>Le strade dallo stato del telefono; null se il telefono non le manda.</summary>
    public static StradeTelefono? Strade(StatoTelefono? stato)
    {
        if (stato?.Collegamento is not { } collegamento) return null;
        var strade = (collegamento.Strade ?? [])
            .Where(s => !string.IsNullOrEmpty(s?.Tipo))
            .Select(s => new StradaNota(s.Tipo, s.Ms is > 0 ? s.Ms : null))
            .ToList();
        return new StradeTelefono(collegamento.Attivo ?? "", PreferenzaCollegamento.Normalizza(collegamento.Preferenza), strade);
    }

    /// <summary>Il comando con la preferenza; null se questa versione del protocollo non lo conosce.</summary>
    public static Comando? Comando(string preferenza) =>
        new Comando() { Collegamento = PreferenzaCollegamento.Normalizza(preferenza) };
#else
    public const bool Presente = false;

    public static bool SaScegliere(Capacita? capacita) => false;

    public static StradeTelefono? Strade(StatoTelefono? stato) => null;

    public static Comando? Comando(string preferenza) => null;
#endif
}
