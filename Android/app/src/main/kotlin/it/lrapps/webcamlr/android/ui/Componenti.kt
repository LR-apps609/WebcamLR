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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import it.lrapps.webcamlr.protocollo.TipoCollegamento

/** Il logo (Strumenti/logo.svg): fondo verde scuro in diagonale, griglia 3×3 di quadratini salvia, il centro corallo. */
@Composable
fun LogoWebcamLR(lato: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(lato)) { disegnaLogo(this, size.minDimension, Offset.Zero) }
}

/** Il logo dentro un disegno: `lato` in pixel, a partire da `origine`. */
fun disegnaLogo(scope: androidx.compose.ui.graphics.drawscope.DrawScope, lato: Float, origine: Offset) = with(scope) {
    drawRoundRect(
        Brush.linearGradient(listOf(Colori.sfumaturaChiara, Colori.sfumaturaScura), start = origine, end = origine + Offset(lato, lato)),
        topLeft = origine, size = Size(lato, lato), cornerRadius = CornerRadius(lato * 0.22f),
    )
    // Misure in centesimi del lato: quadratini da 18, passo 23, margine 18.
    val cella = lato * 0.18f
    for (riga in 0 until 3) for (colonna in 0 until 3) {
        drawRoundRect(
            Colori.celleLogo[riga][colonna],
            topLeft = origine + Offset(lato * (0.18f + colonna * 0.23f), lato * (0.18f + riga * 0.23f)),
            size = Size(cella, cella),
            cornerRadius = CornerRadius(lato * 0.04f),
        )
    }
}

/** «WebcamLR» con «LR» nell'accento salvia: il corallo resta solo per «in onda» e la registrazione. */
@Composable
fun MarchioWebcamLR(dimensione: Int) {
    Text(
        buildAnnotatedString {
            append("Webcam")
            withStyle(SpanStyle(color = Colori.accento)) { append("LR") }
        },
        style = Caratteri.titolo(dimensione),
        color = Colori.testo,
        modifier = Modifier.semantics { contentDescription = "WebcamLR" },
    )
}

/** Etichetta di sezione in maiuscolo, come «VIDEO». È un'intestazione per TalkBack. */
@Composable
fun EtichettaSezione(testo: String, modifier: Modifier = Modifier) {
    Text(
        testo.uppercase(),
        style = Caratteri.etichetta(14, spaziatura = 1.1.sp),
        color = Colori.testoSecondario,
        modifier = modifier.padding(top = 20.dp, bottom = 6.dp, start = 4.dp).semantics { heading() },
    )
}

/** Il segno «PRO» accanto a un comando di WebcamLR Pro: testo scuro sull'accento salvia, mai corallo. */
@Composable
fun SegnoPro(grande: Boolean = false, modifier: Modifier = Modifier) {
    val descrizione = stringResource(R.string.pro_funzione)
    Text(
        "PRO",
        style = Caratteri.etichetta(if (grande) 16 else 12, spaziatura = if (grande) 0.6.sp else 0.8.sp),
        color = Colori.fondo,
        maxLines = 1,
        modifier = modifier
            .clip(RoundedCornerShape(if (grande) 5.dp else 4.dp))
            .background(Colori.accento)
            .padding(horizontal = if (grande) 8.dp else 5.dp, vertical = if (grande) 2.dp else 0.dp)
            .semantics { contentDescription = descrizione },
    )
}

/** Le tre tacche della qualità, senza parola: nella riga di stato basta il colore (la parola è nei Dettagli). */
@Composable
fun TaccheQualita(qualita: QualitaCollegamento) {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (indice in 0 until 3) {
            Box(
                Modifier
                    .width(3.dp)
                    .height((5 + indice * 3).dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(if (indice < qualita.tacche) coloreQualita(qualita) else Colori.linea),
            )
        }
    }
}

fun coloreQualita(qualita: QualitaCollegamento) = when (qualita) {
    QualitaCollegamento.OTTIMA -> Colori.verde
    QualitaCollegamento.BUONA -> Colori.accentoChiaro
    QualitaCollegamento.DEBOLE -> Colori.ambraTesto
}

/** «Ottimo», «Buono», «Debole» nella lingua dell'app (il protocollo ha solo l'italiano). */
@Composable
fun testoQualita(qualita: QualitaCollegamento): String = stringResource(
    when (qualita) {
        QualitaCollegamento.OTTIMA -> R.string.qualita_ottima
        QualitaCollegamento.BUONA -> R.string.qualita_buona
        QualitaCollegamento.DEBOLE -> R.string.qualita_debole
    },
)

@Composable
fun testoTipoCollegamento(tipo: TipoCollegamento): String = stringResource(
    when (tipo) {
        TipoCollegamento.WIFI -> R.string.collegamento_wifi
        // Su Android il cavo è il tethering USB: la rete sul cavo.
        TipoCollegamento.CAVO_USB -> R.string.collegamento_cavo_usb
        TipoCollegamento.WIFI_DIRETTO -> R.string.collegamento_wifi_diretto
        TipoCollegamento.CAVO_DI_RETE -> R.string.collegamento_cavo_rete
        TipoCollegamento.HOTSPOT -> R.string.collegamento_hotspot
    },
)

/** Il consiglio quando il collegamento è debole e ne esiste uno migliore; null sul cavo. */
@Composable
fun consiglioSeDebole(tipo: TipoCollegamento): String? = when (tipo) {
    TipoCollegamento.WIFI, TipoCollegamento.HOTSPOT -> stringResource(R.string.consiglio_cavo)
    TipoCollegamento.WIFI_DIRETTO -> stringResource(R.string.consiglio_cavo_o_rete)
    TipoCollegamento.CAVO_USB, TipoCollegamento.CAVO_DI_RETE -> null
}

/** Una pastiglia scura sopra il video. */
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

/**
 * Pulsante tondo con icona, come quelli della barra di «In onda». Acceso: fondo e icona nell'accento (mai corallo).
 * Per TalkBack è un interruttore con lo stato detto a voce quando `acceso` non è null.
 */
@Composable
fun PulsanteTondo(
    icona: ImageVector,
    etichetta: String,
    attivo: Boolean = false,
    abilitato: Boolean = true,
    statoAcceso: String? = null,
    modifier: Modifier = Modifier,
    azione: () -> Unit,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(48.dp)
            .alpha(if (abilitato) 1f else 0.45f)
            .clip(CircleShape)
            .background(if (attivo) Colori.accentoTenue else Colori.pannelloChiaro)
            .then(if (attivo) Modifier.border(1.5.dp, Colori.accento, CircleShape) else Modifier)
            .clickable(enabled = abilitato, role = Role.Button, onClickLabel = etichetta, onClick = azione)
            .semantics {
                contentDescription = etichetta
                if (statoAcceso != null) stateDescription = statoAcceso
            },
    ) {
        Icon(icona, contentDescription = null, tint = if (attivo) Colori.accentoChiaro else Color.White)
    }
}

/** Il pulsante principale, pieno nell'accento con il testo scuro: «Avanti», «Inquadra il QR code del computer». */
@Composable
fun PulsantePieno(
    testo: String,
    modifier: Modifier = Modifier,
    chiaro: Boolean = false,
    icona: ImageVector? = null,
    abilitato: Boolean = true,
    inCorso: Boolean = false,
    azione: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .alpha(if (abilitato) 1f else 0.55f)
            .clip(RoundedCornerShape(16.dp))
            .background(if (chiaro) Colori.testo else Colori.accento)
            .clickable(enabled = abilitato && !inCorso, role = Role.Button, onClick = azione)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        if (inCorso) {
            CircularProgressIndicator(color = Colori.fondo, strokeWidth = 2.dp, modifier = Modifier.padding(end = 10.dp).size(18.dp))
        } else if (icona != null) {
            Icon(icona, contentDescription = null, tint = Colori.fondo, modifier = Modifier.padding(end = 10.dp))
        }
        Text(testo, style = Caratteri.corpoForte(18), color = Colori.fondo, textAlign = TextAlign.Center)
    }
}

/** Il pulsante secondario: fondo accento tenue, bordo accento, testo accento chiaro («Mandami il link»). */
@Composable
fun PulsanteSecondario(testo: String, modifier: Modifier = Modifier, icona: ImageVector? = null, azione: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 50.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Colori.accentoTenue)
            .border(1.dp, Colori.accento.copy(alpha = 0.6f), RoundedCornerShape(16.dp))
            .clickable(role = Role.Button, onClick = azione)
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        if (icona != null) Icon(icona, contentDescription = null, tint = Colori.accentoChiaro, modifier = Modifier.padding(end = 10.dp))
        Text(testo, style = Caratteri.corpoForte(17), color = Colori.accentoChiaro, textAlign = TextAlign.Center)
    }
}

/** Una pillola d'azione piccola nell'accento pieno, testo scuro: «Riprova ora», «Collega». */
@Composable
fun PillolaAzione(testo: String, modifier: Modifier = Modifier, azione: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .heightIn(min = 40.dp)
            .clip(RoundedCornerShape(50))
            .background(Colori.accento)
            .clickable(role = Role.Button, onClick = azione)
            .padding(horizontal = 16.dp, vertical = 6.dp),
    ) { Text(testo, style = Caratteri.corpoForte(15), color = Colori.fondo, maxLines = 1, overflow = TextOverflow.Ellipsis) }
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
