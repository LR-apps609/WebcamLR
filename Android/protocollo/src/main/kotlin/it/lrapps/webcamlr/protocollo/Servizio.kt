package it.lrapps.webcamlr.protocollo

/** Costanti di rete condivise da tutte le app (vedi Documenti/Protocollo.md). */
object Servizio {
    /** Servizio mDNS pubblicato dal computer (NsdManager lo vuole senza il punto finale). */
    const val TIPO_BONJOUR = "_webcamlr._tcp"

    /** Porta TCP preferita; quella vera viaggia nell'annuncio. */
    const val PORTA_PREDEFINITA = 52740

    const val VERSIONE_PROTOCOLLO = 2

    /** Pausa intelligente: secondi senza app che usano la webcam e senza anteprima visibile prima di fermare il video. */
    const val SECONDI_PRIMA_DELLA_PAUSA = 10
}
