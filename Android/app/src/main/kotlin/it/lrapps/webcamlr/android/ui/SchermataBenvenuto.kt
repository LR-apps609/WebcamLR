package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

/**
 * Benvenuto (novità 16): tre schermate alla prima apertura. I permessi si spiegano prima che Android li chieda:
 * la fotocamera alla fine di queste schermate, le notifiche al primo collegamento.
 */
@Composable
fun SchermataBenvenuto(fine: () -> Unit) {
    var pagina by rememberSaveable { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize().background(Colori.fondo).safeDrawingPadding()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (pagina) {
                0 -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        LogoWebcamLR(56.dp)
                        MarchioWebcamLR(34)
                    }
                    Text("Il tuo telefono diventa la webcam", style = Caratteri.titolo(38), color = Colori.testo)
                    Text(
                        "WebcamLR manda il video della fotocamera del telefono al Mac o al PC, per videochiamate, lezioni e dirette. Molto più nitido della webcam del computer, con pochissimo ritardo.",
                        color = Colori.testoChiaro,
                    )
                }
                1 -> {
                    Icona(Icons.Filled.Wifi)
                    Text("Sulla stessa rete Wi-Fi", style = Caratteri.titolo(38), color = Colori.testo)
                    Text(
                        "Apri WebcamLR anche sul computer e tieni telefono e computer sulla stessa rete Wi-Fi: il computer compare qui da solo, basta toccarlo.",
                        color = Colori.testoChiaro,
                    )
                    Text("Se non compare, inquadra il QR code che WebcamLR mostra sul computer.", color = Colori.testoSecondario)
                }
                else -> {
                    Icona(Icons.Filled.Lock)
                    Text("Due permessi", style = Caratteri.titolo(38), color = Colori.testo)
                    Permesso(Icons.Filled.CameraAlt, "Fotocamera", "Per mandare il video al computer. Senza, WebcamLR non può funzionare.")
                    Permesso(Icons.Filled.Notifications, "Notifiche", "Per l'avviso «Video al computer» con «Scollega», mentre il video continua a schermo spento.")
                    Text(
                        "Toccando «Inizia» Android ti chiede la fotocamera: rispondi «Consenti» (o «Mentre usi l'app»). Puoi cambiarli quando vuoi in Impostazioni › App › WebcamLR.",
                        color = Colori.testoSecondario,
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.Center) {
            for (indice in 0..2) {
                Box(
                    Modifier.padding(4.dp).size(8.dp).clip(CircleShape)
                        .background(if (indice == pagina) Colori.ciano else Colori.linea),
                )
            }
        }
        PulsantePieno(
            if (pagina < 2) "Avanti" else "Inizia",
            modifier = Modifier.padding(horizontal = 20.dp).padding(bottom = 12.dp),
        ) {
            if (pagina < 2) pagina++ else fine()
        }
    }
}

@Composable
private fun Icona(icona: ImageVector) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.size(64.dp).clip(RoundedCornerShape(16.dp)).background(Colori.cianoTenue),
    ) {
        Icon(icona, contentDescription = null, tint = Colori.ciano, modifier = Modifier.size(30.dp))
    }
}

@Composable
private fun Permesso(icona: ImageVector, titolo: String, testo: String) {
    Scheda(bordo = null) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(Colori.cianoTenue),
            ) {
                Icon(icona, contentDescription = null, tint = Colori.ciano)
            }
            Column {
                Text(titolo, style = Caratteri.etichetta(18), color = Colori.testo)
                Spacer(Modifier.height(2.dp))
                Text(testo, color = Colori.testoChiaro)
            }
        }
    }
}
