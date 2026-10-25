package it.lrapps.webcamlr.android.logica

import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.Filtri
import it.lrapps.webcamlr.protocollo.FormatoSupportato
import it.lrapps.webcamlr.protocollo.ModiSfondo

/** Un numero dalla rete o dall'interfaccia, portato nei limiti; `NaN` e infiniti diventano `ripiego`. */
fun limita(valore: Double, minimo: Double, massimo: Double, ripiego: Double = minimo): Double =
    if (valore.isFinite()) valore.coerceIn(minimo, massimo) else ripiego

/**
 * I limiti della versione gratuita, applicati dalla sessione quando WebcamLR Pro non c'è
 * (Documenti/Protocollo.md, «WebcamLR Pro»; come `LimitiGratis` di iPhone/Sorgenti/NegozioPro.swift).
 */
object LimitiGratis {
    /** 720p a 30 fps: 1080p, 4K e 60 fps sono di WebcamLR Pro. */
    const val LARGHEZZA = 1280
    const val ALTEZZA = 720
    const val FPS = 30

    /** `capacita.formati` senza Pro: solo fino a 720p (lato lungo), al massimo a 30 fps. */
    fun formati(formati: List<FormatoSupportato>): List<FormatoSupportato> =
        formati.filter { maxOf(it.larghezza, it.altezza) <= LARGHEZZA }
            .map { it.copy(fpsMassimo = minOf(it.fpsMassimo, FPS)) }

    /**
     * Un `comando` senza i campi che accenderebbero una funzione Pro: filtri, regolazioni, sfondo sostituito,
     * ritocco, inquadratura automatica, scritta, volto e scrivania, ISO, tempo e bianco manuali. Spegnere (filtro
     * `naturale`, valori a 0, scritta vuota, `false`) resta sempre possibile; tutto il resto passa com'è.
     */
    fun soloGratis(ricevuto: Comando): Comando {
        var comando = ricevuto
        if (comando.filtro != null && comando.filtro != Filtri.NATURALE) comando = comando.copy(filtro = null)
        comando.regolazioni?.let { r ->
            val accese = listOf(r.luminosita, r.contrasto, r.saturazione, r.nitidezza).any { (it ?: 0.0) != 0.0 }
            if (accese) comando = comando.copy(regolazioni = null)
        }
        if (comando.sfondo == ModiSfondo.SOSTITUITO) comando = comando.copy(sfondo = null)
        if ((comando.pelle ?: 0.0) != 0.0) comando = comando.copy(pelle = null)
        if (comando.inquadratura == true) comando = comando.copy(inquadratura = null)
        if (comando.scritta != null && comando.scritta!!.nome.isNotBlank()) comando = comando.copy(scritta = null)
        if (comando.doppiaVista == true) comando = comando.copy(doppiaVista = null)
        if ((comando.iso ?: 0.0) != 0.0) comando = comando.copy(iso = null)
        if ((comando.tempo ?: 0) != 0) comando = comando.copy(tempo = null)
        if ((comando.bianco ?: 0) != 0) comando = comando.copy(bianco = null)
        return comando
    }
}
