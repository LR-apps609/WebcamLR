package it.lrapps.webcamlr.android.ui

import android.app.Activity
import android.util.Size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import it.lrapps.webcamlr.android.acquisti.NegozioPro
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.MotiviPausa

/*
 * Il ponte tra l'interfaccia e il resto dell'app (round A1): le API nuove di sessione e acquisti che l'interfaccia
 * usa, tutte qui. Le scrive l'altra metà del round (ramo a1-core); se un nome cambia, si allinea solo questo file.
 *
 * SessioneTelefono (StateFlow nuovi, accanto agli stati Compose che c'erano già: stato, computer, latenzaMs,
 * torciaAccesa, zoom, iso, tempo, aeafBloccati, batteria, temperatura, oscurato…):
 *   specchiato: StateFlow<Boolean>          impostaSpecchio(Boolean)
 *   sfondo: StateFlow<String>               scegliSfondo(String)      valori di ModiSfondo
 *   audioRichiesto: StateFlow<Boolean>      impostaAudio(Boolean)
 *   pausa: StateFlow<String?>               impostaPausaUtente(Boolean)  valori di MotiviPausa, null = niente pausa
 *   dimensioniVideo: StateFlow<Size>        il video come appare su questo schermo (già girato); 0×0 = non si sa
 *   applica(Comando)                        pubblica: la stessa strada dei comandi del computer (controlli Pro,
 *                                           inquadratura, luce sul volto, postura)
 *   torcia: c'erano già torciaAccesa (stato Compose), haTorcia e cambiaTorcia(): usati quelli.
 *
 * NegozioPro (object, pacchetto acquisti, Google Play Billing):
 *   pro: StateFlow<Boolean>   prodottoPrezzo: StateFlow<String?>   inAttesa: StateFlow<Boolean>
 *   acquista(Activity)        ripristina()
 */

@Composable
fun SessioneTelefono.specchiatoOra(): Boolean {
    val valore by specchiato.collectAsState()
    return valore
}

@Composable
fun SessioneTelefono.sfondoOra(): String {
    val valore by sfondo.collectAsState()
    return valore
}

@Composable
fun SessioneTelefono.audioOra(): Boolean {
    val valore by audioRichiesto.collectAsState()
    return valore
}

/** Il motivo della pausa ([MotiviPausa]), null se il video va. */
@Composable
fun SessioneTelefono.pausaOra(): String? {
    val valore by pausa.collectAsState()
    return valore
}

@Composable
fun SessioneTelefono.dimensioniVideoOra(): Size {
    val valore by dimensioniVideo.collectAsState()
    return valore
}

fun SessioneTelefono.cambiaSpecchio(acceso: Boolean) = impostaSpecchio(acceso)

fun SessioneTelefono.cambiaSfondo(modo: String) = scegliSfondo(modo)

fun SessioneTelefono.cambiaAudio(acceso: Boolean) = impostaAudio(acceso)

fun SessioneTelefono.cambiaPausa(inPausa: Boolean) = impostaPausaUtente(inPausa)

fun SessioneTelefono.mandaComando(comando: Comando) = applica(comando)

/** Il pulsante «Pausa» mette in pausa l'utente; le altre pause (faccia in giù, nessuna app) si tolgono da sole. */
fun pausaDellUtente(motivo: String?) = motivo == MotiviPausa.UTENTE

fun sfondoSfocato(modo: String) = modo == ModiSfondo.SFOCATO

/** WebcamLR Pro dall'interfaccia: un solo posto per il negozio di Google Play. */
object Pro {
    @Composable
    fun attivo(): Boolean {
        val valore by NegozioPro.pro.collectAsState()
        return valore
    }

    @Composable
    fun prezzo(): String? {
        val valore by NegozioPro.prodottoPrezzo.collectAsState()
        return valore
    }

    @Composable
    fun inAttesa(): Boolean {
        val valore by NegozioPro.inAttesa.collectAsState()
        return valore
    }

    fun acquista(activity: Activity) = NegozioPro.acquista(activity)

    fun ripristina() = NegozioPro.ripristina()

    /** Gratis: al massimo 720p a 30 fps (come LimitiGratis dell'iPhone). */
    const val FPS_GRATIS = 30
    const val RISOLUZIONE_GRATIS = "720p"
}
