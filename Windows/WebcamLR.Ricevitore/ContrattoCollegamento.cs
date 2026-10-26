using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// L'unico punto che legge e scrive i campi del protocollo per la scelta della strada (Documenti/Protocollo.md, «Scelta
/// del collegamento»: <c>capacita.sceltaCollegamento</c>, <c>comando.collegamento</c>, <c>stato.collegamento</c>). Il resto
/// del ricevitore e la finestra usano <see cref="StradeTelefono"/> e <see cref="PreferenzaCollegamento"/>.
/// </summary>
public static class ContrattoCollegamento
{
    /// <summary>Il telefono sa cambiare strada e accetta la preferenza dal computer.</summary>
    public static bool SaScegliere(Capacita? capacita) => capacita?.SceltaCollegamento == true;

    /// <summary>Le strade dallo stato del telefono; null se il telefono non le manda (versione di prima).</summary>
    public static StradeTelefono? Strade(StatoTelefono? stato)
    {
        if (stato?.Collegamento is not { } collegamento) return null;
        var strade = collegamento.Strade
            .Where(s => !string.IsNullOrEmpty(s.Tipo))
            .Select(s => new StradaNota(s.Tipo, s.Ms is > 0 ? s.Ms : null))
            .ToList();
        return new StradeTelefono(collegamento.Attivo ?? "", PreferenzaCollegamento.Normalizza(collegamento.Preferenza), strade);
    }

    /// <summary>
    /// Per «Collegato · Wi-Fi» o «Collegato · USB» in alto: vero sul cavo; falso su Wi-Fi, hotspot, Wi-Fi diretto e cavo di
    /// rete. Dalla strada che il telefono dice in <c>stato.collegamento.attivo</c>; da un telefono che non la dice, da come
    /// è arrivata la connessione (<paramref name="tipo"/>). Null se non si sa.
    /// </summary>
    public static bool? ViaCavo(StatoTelefono? stato, TipoCollegamento? tipo)
    {
        if (stato?.Collegamento?.Attivo is { Length: > 0 } attivo) return attivo == StradeCollegamento.Cavo;
        return tipo is { } t ? t == TipoCollegamento.CavoUsb : null;
    }

    /// <summary>Il comando con la preferenza (sconosciuta = «automatico»).</summary>
    public static Comando Comando(string preferenza) => new(Collegamento: PreferenzaCollegamento.Normalizza(preferenza));
}
