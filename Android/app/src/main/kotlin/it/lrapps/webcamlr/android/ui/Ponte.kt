package it.lrapps.webcamlr.android.ui

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import it.lrapps.webcamlr.android.acquisti.NegozioPro
import it.lrapps.webcamlr.android.acquisti.StatoPro
import kotlinx.coroutines.flow.StateFlow

/*
 * Il ponte tra l'interfaccia e il resto dell'app. I comandi si chiamano direttamente sulla sessione
 * (impostaSpecchio, scegliSfondo, impostaAudio, impostaPausaUtente, applica, applicaImpostazioni…); qui restano solo
 * la lettura dei flussi da Compose e WebcamLR Pro da un posto solo.
 */

/** Il valore attuale di un flusso della sessione o del negozio, osservato da Compose. */
@Composable
fun <T> StateFlow<T>.ora(): T {
    val valore by collectAsState()
    return valore
}

/** WebcamLR Pro dall'interfaccia: un solo posto per il negozio di Google Play. */
object Pro {
    @Composable
    fun attivo(): Boolean = NegozioPro.pro.ora()

    @Composable
    fun stato(): StatoPro = NegozioPro.stato.ora()

    fun acquista(activity: Activity) = NegozioPro.acquista(activity)

    fun ripristina() = NegozioPro.ripristina()

    fun riprovaProdotto() = NegozioPro.riprovaProdotto()

    /** Solo nelle versioni di prova: Pro acceso o spento senza comprare; null = di nuovo l'acquisto vero. */
    fun simula(attivo: Boolean?) = NegozioPro.simula(attivo)

    /** Gratis: al massimo 720p a 30 fps (come LimitiGratis dell'iPhone e di logica/LimitiGratis.kt). */
    const val FPS_GRATIS = 30
    const val RISOLUZIONE_GRATIS = "720p"
}
