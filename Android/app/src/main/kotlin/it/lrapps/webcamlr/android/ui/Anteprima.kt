package it.lrapps.webcamlr.android.ui

import android.app.Activity
import android.content.Context
import android.os.Build
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import it.lrapps.webcamlr.android.video.Renderizzatore

/**
 * L'anteprima della fotocamera: una SurfaceView su cui disegna il [Renderizzatore] (lo stesso fotogramma che va
 * al codificatore, ruotato per lo schermo). Quando la vista sparisce il renderizzatore smette di disegnarci.
 */
@Composable
fun AnteprimaVideo(renderizzatore: Renderizzatore, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    // Si ricalcola a ogni rotazione dello schermo (le modifiche di configurazione non ricreano l'attività).
    val configurazione = LocalConfiguration.current
    LaunchedEffect(configurazione.orientation, configurazione.screenWidthDp) {
        renderizzatore.rotazioneSchermo = rotazioneSchermo(context)
    }
    AndroidView(
        modifier = modifier,
        factory = { contesto ->
            SurfaceView(contesto).apply {
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) = Unit

                    override fun surfaceChanged(holder: SurfaceHolder, formato: Int, larghezza: Int, altezza: Int) {
                        renderizzatore.rotazioneSchermo = rotazioneSchermo(contesto)
                        renderizzatore.impostaAnteprima(holder.surface, larghezza, altezza)
                    }

                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                        renderizzatore.impostaAnteprima(null, 0, 0)
                    }
                })
            }
        },
    )
}

/**
 * Di quanti gradi in senso orario il telefono è girato perché lo schermo sia dritto: `Surface.ROTATION_90` vuol dire
 * telefono girato di 90° in senso antiorario (Android ruota il disegno in senso orario), quindi 270.
 */
fun rotazioneSchermo(context: Context): Int {
    val rotazione = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            (context as? Activity)?.display?.rotation ?: context.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.rotation
        }
    } catch (e: Exception) {
        Surface.ROTATION_0
    }
    val gradi = when (rotazione) {
        Surface.ROTATION_90 -> 90
        Surface.ROTATION_180 -> 180
        Surface.ROTATION_270 -> 270
        else -> 0
    }
    return (360 - gradi) % 360
}
