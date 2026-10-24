namespace WebcamLR.Protocollo;

/// <summary>Costanti di rete condivise da tutte le app (vedi Documenti/Protocollo.md).</summary>
public static class Servizio
{
    /// <summary>Servizio Bonjour/mDNS pubblicato dal computer.</summary>
    public const string TipoBonjour = "_webcamlr._tcp";

    /// <summary>Porta TCP preferita; quella vera viaggia nell'annuncio.</summary>
    public const ushort PortaPredefinita = 52740;

    public const int VersioneProtocollo = 2;

    /// <summary>Pausa intelligente: secondi senza app che usano la webcam e senza anteprima visibile prima di fermare il video.</summary>
    public const int SecondiPrimaDellaPausa = 10;
}
