package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.protocollo.QualitaCollegamento

/** Il logo: griglia di pixel 3×3 con il centro rosso (come LogoWebcamLR in Stile). */
@Composable
fun LogoWebcamLR(lato: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(lato)) {
        val l = size.minDimension
        drawRoundRect(Colori.logo, cornerRadius = CornerRadius(l * 0.22f))
        val cella = l * 0.16f
        val spazio = l * 0.04f
        val inizio = (l - (3 * cella + 2 * spazio)) / 2
        for (riga in 0 until 3) for (colonna in 0 until 3) {
            val colore = when {
                riga == 1 && colonna == 1 -> Colori.tally
                (riga + colonna) % 2 == 0 -> Color.White.copy(alpha = 0.35f)
                else -> Color.White.copy(alpha = 0.6f)
            }
            drawRoundRect(
                colore,
                topLeft = Offset(inizio + colonna * (cella + spazio), inizio + riga * (cella + spazio)),
                size = Size(cella, cella),
                cornerRadius = CornerRadius(cella * 0.2f),
            )
        }
    }
}

/** «WebcamLR» con «LR» in rosso. */
@Composable
fun MarchioWebcamLR(dimensione: Int) {
    Text(
        buildAnnotatedString {
            append("Webcam")
            withStyle(SpanStyle(color = Colori.tally)) { append("LR") }
        },
        style = Caratteri.titolo(dimensione),
        color = Colori.testo,
        modifier = Modifier.semantics { contentDescription = "WebcamLR" },
    )
}

/** Etichetta di sezione in maiuscolo, come «VIDEO». */
@Composable
fun EtichettaSezione(testo: String, modifier: Modifier = Modifier) {
    Text(
        testo.uppercase(),
        style = Caratteri.etichetta(14),
        color = Colori.testoSecondario,
        modifier = modifier.padding(top = 18.dp, bottom = 6.dp, start = 4.dp),
    )
}

/** I quattro stati, uguali in tutte le app. */
sealed interface StatoPillola {
    /** Un'app sta usando il video: l'unico caso in cui compare il rosso. */
    data class InOnda(val app: String?) : StatoPillola
    data object Collegato : StatoPillola
    data object Riconnessione : StatoPillola
    data object NessunTelefono : StatoPillola
}

@Composable
fun PillolaStato(stato: StatoPillola, testo: String) {
    val (sfondo, coloreTesto) = when (stato) {
        is StatoPillola.InOnda -> Colori.tallyPieno to Color.White
        StatoPillola.Collegato -> Colori.pannelloChiaro to Colori.testo
        StatoPillola.Riconnessione -> Colori.ambraTenue to Colori.ambraTesto
        StatoPillola.NessunTelefono -> Color.Transparent to Colori.testoTenue
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .height(30.dp)
            .clip(RoundedCornerShape(50))
            .background(sfondo)
            .then(if (stato == StatoPillola.NessunTelefono) Modifier.border(1.dp, Colori.bordo, RoundedCornerShape(50)) else Modifier)
            .padding(horizontal = 12.dp),
    ) {
        val punto = when (stato) {
            is StatoPillola.InOnda -> Color.White
            StatoPillola.Collegato -> Colori.verde
            StatoPillola.Riconnessione -> Colori.ambra
            StatoPillola.NessunTelefono -> Colori.testoTenue
        }
        Box(Modifier.size(8.dp).clip(CircleShape).background(punto))
        Text(testo.uppercase(), style = Caratteri.etichetta(16), color = coloreTesto, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Tre tacche e la parola: «▮▮▮ Ottimo». */
@Composable
fun ChipQualita(qualita: QualitaCollegamento, latenzaMs: Int?) {
    val colore = when (qualita) {
        QualitaCollegamento.OTTIMA -> Colori.verde
        QualitaCollegamento.BUONA -> Colori.cianoChiaro
        QualitaCollegamento.DEBOLE -> Colori.ambraTesto
    }
    val descrizione = "Collegamento ${qualita.testo.lowercase()}" + (latenzaMs?.let { ", $it millisecondi" } ?: "")
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = descrizione },
    ) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for (indice in 0 until 3) {
                Box(
                    Modifier
                        .width(3.dp)
                        .height((5 + indice * 3).dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(if (indice < qualita.tacche) colore else Colori.linea),
                )
            }
        }
        Text(qualita.testo, style = Caratteri.etichetta(14), color = colore)
    }
}

/** Una pastiglia scura sopra il video, per numeri e avvisi. */
@Composable
fun Chip(modifier: Modifier = Modifier, contenuto: @Composable RowScope.() -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(Colori.fondo.copy(alpha = 0.78f))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        content = contenuto,
    )
}

/** Pulsante tondo con icona, come quelli della barra di «In onda». */
@Composable
fun PulsanteTondo(icona: ImageVector, etichetta: String, attivo: Boolean = false, abilitato: Boolean = true, azione: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(48.dp)
            .clip(CircleShape)
            .background(if (attivo) Colori.ciano else Colori.pannelloChiaro.copy(alpha = if (abilitato) 1f else 0.4f))
            .clickable(enabled = abilitato, onClickLabel = etichetta, onClick = azione)
            .semantics { contentDescription = etichetta },
    ) {
        Icon(icona, contentDescription = null, tint = if (attivo) Colori.fondo else Colori.testo.copy(alpha = if (abilitato) 1f else 0.4f))
    }
}

/** Il pulsante principale, pieno: «Avanti», «Inquadra il QR code del computer». */
@Composable
fun PulsantePieno(testo: String, modifier: Modifier = Modifier, chiaro: Boolean = false, icona: ImageVector? = null, azione: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (chiaro) Colori.testo else Colori.ciano)
            .clickable(onClick = azione)
            .padding(horizontal = 16.dp),
    ) {
        if (icona != null) {
            Icon(icona, contentDescription = null, tint = Colori.fondo, modifier = Modifier.padding(end = 8.dp))
        }
        Text(testo, style = Caratteri.etichetta(19), color = Colori.fondo)
    }
}

/** Un riquadro di contenuto: sfondo pannello, bordo sottile, angoli arrotondati. */
@Composable
fun Scheda(
    modifier: Modifier = Modifier,
    sfondo: Color = Colori.pannello,
    bordo: Color? = Colori.linea,
    contenuto: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(sfondo)
            .then(if (bordo != null) Modifier.border(BorderStroke(1.dp, bordo), RoundedCornerShape(16.dp)) else Modifier)
            .padding(14.dp),
        content = contenuto,
    )
}
