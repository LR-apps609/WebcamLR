package it.lrapps.webcamlr.android.ui

import android.os.Handler
import android.os.Looper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.video.Cattura
import it.lrapps.webcamlr.android.video.LettoreQR
import it.lrapps.webcamlr.android.video.Renderizzatore
import it.lrapps.webcamlr.protocollo.Associazione

/** «Inquadra il QR code del computer»: fotocamera posteriore, ZXing sui fotogrammi, nessun servizio Google. */
@Composable
fun SchermataLettoreQR(letto: (Associazione) -> Unit, chiudi: () -> Unit) {
    val context = LocalContext.current
    val renderizzatore = remember { Renderizzatore() }
    var avviso by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) {
        val principale = Handler(Looper.getMainLooper())
        val cattura = Cattura(context)
        val obiettivo = cattura.obiettivi.firstOrNull { it.nome == "principale" } ?: cattura.obiettivi.firstOrNull()
        var lettore: LettoreQR? = null
        if (obiettivo == null) {
            avviso = context.getString(R.string.qr_nessuna_fotocamera)
        } else {
            try {
                val dimensione = cattura.dimensionePer(obiettivo, 1280, 720)
                val superficie = renderizzatore.avvia(dimensione.width, dimensione.height, cattura.orientamentoDi(obiettivo))
                val yuv = cattura.dimensioneYuv(obiettivo)
                val nuovo = LettoreQR(
                    yuv.width, yuv.height,
                    suLetto = { associazione ->
                        // Sul thread del lettore: la fotocamera si chiude prima che la sessione la riapra,
                        // altrimenti su alcuni telefoni la seconda apertura trova la fotocamera ancora occupata.
                        cattura.chiudiEAspetta()
                        principale.post { letto(associazione) }
                    },
                    suAltroQR = { principale.post { avviso = context.getString(R.string.qr_altro) } },
                )
                lettore = nuovo
                cattura.apri(obiettivo, 30, listOf(superficie, nuovo.superficie)) { errore ->
                    if (errore != null) principale.post { avviso = errore }
                }
            } catch (e: Exception) {
                avviso = context.getString(R.string.qr_fotocamera_spenta)
            }
        }
        onDispose {
            cattura.chiudiEAspetta()
            cattura.termina()
            lettore?.chiudi()
            renderizzatore.ferma()
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AnteprimaVideo(renderizzatore, Modifier.fillMaxSize())
        // Il mirino: un quadrato chiaro al centro.
        Box(
            Modifier.align(Alignment.Center).size(240.dp)
                .border(3.dp, Colori.testo.copy(alpha = 0.9f), RoundedCornerShape(24.dp)),
        )
        Column(
            Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.qr_titolo), style = Caratteri.titolo(30), color = Colori.testo, modifier = Modifier.weight(1f))
                PulsanteTondo(Icons.Filled.Close, stringResource(R.string.chiudi), azione = chiudi)
            }
            Spacer(Modifier.weight(1f))
            Scheda(sfondo = Colori.fondo.copy(alpha = 0.85f), bordo = null, modifier = Modifier.fillMaxWidth()) {
                Text(
                    avviso ?: stringResource(R.string.qr_istruzioni),
                    style = Caratteri.corpo(15),
                    color = if (avviso != null) Colori.ambraTesto else Colori.testoChiaro,
                )
            }
        }
    }
}
