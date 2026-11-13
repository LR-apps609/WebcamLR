package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp

/*
 * Collaudo 20 (t09, testo al 200% su telefoni piccoli): impaginazioni che si adattano invece di schiacciare. Una riga
 * a misura fissa con il carattere grande andava a capo una lettera per riga («Q/u/a/l/i/t/à») o perdeva l'ultimo
 * elemento (l'ingranaggio della schermata principale).
 */

/**
 * Due elementi uno accanto all'altro se ci stanno interi su una riga; altrimenti il secondo va sotto il primo, tutti e
 * due a sinistra e a tutta larghezza (possono andare a capo). Accanto, il secondo sta in fondo a destra se
 * `secondoAllaFine` (come il valore di una riga «nome · valore»), altrimenti subito dopo il primo.
 */
@Composable
fun AcapoSeServe(
    modifier: Modifier = Modifier,
    spazio: Dp = Spazi.piccolo,
    spazioSotto: Dp = Spazi.minimo,
    secondoAllaFine: Boolean = true,
    primo: @Composable () -> Unit,
    secondo: @Composable () -> Unit,
) {
    Layout(
        content = {
            Box { primo() }
            Box { secondo() }
        },
        modifier = modifier,
    ) { misurabili, vincoli ->
        val (unoM, dueM) = misurabili
        val distanza = spazio.roundToPx()
        val larghezzaUno = unoM.maxIntrinsicWidth(Constraints.Infinity)
        val larghezzaDue = dueM.maxIntrinsicWidth(Constraints.Infinity)
        val accanto = !vincoli.hasBoundedWidth || larghezzaUno + distanza + larghezzaDue <= vincoli.maxWidth
        if (accanto) {
            val due = dueM.measure(Constraints(maxWidth = larghezzaDue))
            val unoMassimo = if (vincoli.hasBoundedWidth) (vincoli.maxWidth - due.width - distanza).coerceAtLeast(0) else Constraints.Infinity
            val uno = unoM.measure(Constraints(maxWidth = unoMassimo))
            val naturale = uno.width + distanza + due.width
            val larghezza = if (vincoli.hasBoundedWidth && secondoAllaFine) vincoli.maxWidth else naturale.coerceIn(vincoli.minWidth, vincoli.maxWidth)
            val altezza = maxOf(uno.height, due.height).coerceIn(vincoli.minHeight, vincoli.maxHeight)
            layout(larghezza, altezza) {
                uno.placeRelative(0, (altezza - uno.height) / 2)
                due.placeRelative(if (secondoAllaFine) larghezza - due.width else uno.width + distanza, (altezza - due.height) / 2)
            }
        } else {
            val limite = Constraints(maxWidth = vincoli.maxWidth)
            val uno = unoM.measure(limite)
            val due = dueM.measure(limite)
            val sotto = spazioSotto.roundToPx()
            val altezza = (uno.height + sotto + due.height).coerceIn(vincoli.minHeight, vincoli.maxHeight)
            layout(vincoli.maxWidth, altezza) {
                uno.placeRelative(0, 0)
                due.placeRelative(0, uno.height + sotto)
            }
        }
    }
}

/**
 * Il contenuto su una riga, intero, solo se ci sta: altrimenti non si disegna e lascia il suo posto vuoto. Per un
 * elemento che si può togliere senza perdere niente (il nome «WebcamLR» accanto al logo), così quelli che servono
 * restano interi.
 */
@Composable
fun SoloSeCiSta(modifier: Modifier = Modifier, contenuto: @Composable () -> Unit) {
    Layout(content = { Box(contentAlignment = Alignment.CenterStart) { contenuto() } }, modifier = modifier) { misurabili, vincoli ->
        val dentro = misurabili.first().measure(Constraints(maxHeight = vincoli.maxHeight))
        val ciSta = !vincoli.hasBoundedWidth || dentro.width <= vincoli.maxWidth
        if (ciSta) {
            val larghezza = dentro.width.coerceIn(vincoli.minWidth, vincoli.maxWidth)
            val altezza = dentro.height.coerceIn(vincoli.minHeight, vincoli.maxHeight)
            layout(larghezza, altezza) { dentro.placeRelative(0, (altezza - dentro.height) / 2) }
        } else {
            layout(vincoli.minWidth, vincoli.minHeight) {}
        }
    }
}
