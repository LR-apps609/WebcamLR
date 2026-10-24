/// Costanti di rete condivise da tutte le app (vedi Documenti/Protocollo.md).
public enum Servizio {
    /// Servizio Bonjour pubblicato dal computer.
    public static let tipoBonjour = "_webcamlr._tcp"
    /// Porta TCP preferita; quella vera viaggia nell'annuncio Bonjour.
    public static let portaPredefinita: UInt16 = 52740
    public static let versioneProtocollo = 2
    /// Pausa intelligente: secondi senza app che usano la webcam e senza anteprima visibile prima di fermare il video.
    public static let secondiPrimaDellaPausa = 10
}
