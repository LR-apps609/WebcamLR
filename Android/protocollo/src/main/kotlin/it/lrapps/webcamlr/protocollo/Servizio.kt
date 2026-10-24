package it.lrapps.webcamlr.protocollo

/** Costanti di rete condivise da tutte le app (vedi Documenti/Protocollo.md). */
object Servizio {
    /** Servizio mDNS pubblicato dal computer (NsdManager lo vuole senza il punto finale). */
    const val TIPO_BONJOUR = "_webcamlr._tcp"

    /** Porta TCP preferita; quella vera viaggia nell'annuncio. */
    const val PORTA_PREDEFINITA = 52740

    const val VERSIONE_PROTOCOLLO = 2
}
