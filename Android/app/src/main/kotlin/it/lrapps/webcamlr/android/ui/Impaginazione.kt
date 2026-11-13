package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

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

/**
 * Un dialogo con un campo di testo che resta sopra la tastiera, con l'aspetto dell'`AlertDialog` di Material 3. Collaudo
 * 20 (t09 B4): l'`AlertDialog` non riceve i margini della tastiera e con il carattere grande il campo e «Collega»
 * finivano sotto. Qui la finestra del dialogo è a tutto schermo e il riquadro sta nello spazio libero da barre e
 * tastiera: titolo, testo e campo scorrono, i pulsanti restano in fondo al riquadro; il campo con il fuoco si porta
 * da solo in vista. Indietro o un tocco fuori dal riquadro chiudono.
 */
@Composable
fun DialogoSopraLaTastiera(
    titolo: String,
    chiudi: () -> Unit,
    pulsanti: @Composable () -> Unit,
    contenuto: @Composable ColumnScope.() -> Unit,
) {
    Dialog(onDismissRequest = chiudi, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        BoxWithConstraints(
            contentAlignment = Alignment.Center,
            modifier = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)
                .pointerInput(chiudi) { detectTapGestures { chiudi() } },
        ) {
            // Poco spazio sopra la tastiera (orizzontale con il carattere grande): margini stretti e i pulsanti
            // scorrono con il resto, così resta in vista il campo che si sta scrivendo (il tasto → della tastiera
            // fa lo stesso di «Collega»).
            val stretto = maxHeight < ALTEZZA_DIALOGO_STRETTO
            val margine = if (stretto) Spazi.piccolo else Spazi.largo
            val riga = @Composable {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Spazi.stretto, Alignment.End),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().padding(top = if (stretto) Spazi.stretto else Spazi.largo),
                ) { pulsanti() }
            }
            Surface(
                shape = AlertDialogDefaults.shape,
                color = AlertDialogDefaults.containerColor,
                tonalElevation = AlertDialogDefaults.TonalElevation,
                modifier = Modifier.padding(horizontal = Spazi.medio, vertical = if (stretto) 0.dp else Spazi.medio)
                    .widthIn(min = 280.dp, max = 560.dp)
                    // Un tocco sul riquadro non lo chiude.
                    .pointerInput(Unit) { detectTapGestures { } }
                    .semantics { paneTitle = titolo },
            ) {
                Column(Modifier.padding(horizontal = Spazi.largo, vertical = margine)) {
                    Column(
                        Modifier.weight(1f, fill = false).fillMaxWidth().verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(Spazi.stretto),
                    ) {
                        Text(
                            titolo, style = MaterialTheme.typography.headlineSmall, color = AlertDialogDefaults.titleContentColor,
                            modifier = Modifier.padding(bottom = Spazi.piccolo).semantics { heading() },
                        )
                        contenuto()
                        if (stretto) riga()
                    }
                    if (!stretto) riga()
                }
            }
        }
    }
}

/** Sotto questa altezza libera il [DialogoSopraLaTastiera] stringe i margini e fa scorrere anche i pulsanti. */
private val ALTEZZA_DIALOGO_STRETTO = 220.dp
