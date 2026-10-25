package it.lrapps.webcamlr.android.ui

import android.Manifest
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R

/**
 * La presentazione alla prima apertura, come quella dell'iPhone (PresentazioneVista.swift): quattro pagine con scene
 * disegnate e animate, una cosa da toccare in ognuna, le barrette in stile «storie» che si riempiono nel tempo di
 * ogni pagina e «Salta» in alto a destra, che porta all'ultima pagina. I permessi si spiegano prima che Android li
 * chieda: fotocamera, microfono e notifiche con «Inizia». Con «Rimuovi animazioni» le pagine si scambiano in
 * dissolvenza e le scene stanno ferme. `fine` è chiamata dopo le risposte ai permessi.
 */
@Composable
fun Presentazione(fine: () -> Unit) {
    val ridotte = ricordaAnimazioniRidotte()
    var pagina by rememberSaveable { mutableIntStateOf(0) }
    var chiedendo by remember { mutableStateOf(false) }
    val riempimento = remember { Animatable(0f) }
    val ultima = DURATE.lastIndex

    val permessi = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        // Qualsiasi risposta va bene: senza fotocamera l'app lo dice al primo collegamento e la richiede.
        chiedendo = false
        fine()
    }
    fun inizia() {
        if (chiedendo) return
        chiedendo = true
        val elenco = buildList {
            add(Manifest.permission.CAMERA)
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        permessi.launch(elenco.toTypedArray())
    }
    fun vai(nuova: Int) {
        if (nuova != pagina) pagina = nuova.coerceIn(0, ultima)
    }

    BackHandler(enabled = pagina > 0) { vai(pagina - 1) }
    // La barretta della pagina attuale riparte da zero e si riempie nel tempo della pagina.
    LaunchedEffect(pagina) {
        riempimento.snapTo(0f)
        riempimento.animateTo(1f, tween(DURATE[pagina] * 1000, easing = LinearEasing))
    }

    Box(Modifier.fillMaxSize().background(Colori.sfondoSchermata).safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
        AnimatedContent(
            targetState = pagina,
            transitionSpec = {
                if (ridotte) {
                    fadeIn(tween(350)) togetherWith fadeOut(tween(350))
                } else if (targetState > initialState) {
                    (slideInHorizontally { it } + fadeIn()) togetherWith (slideOutHorizontally { -it } + fadeOut())
                } else {
                    (slideInHorizontally { -it } + fadeIn()) togetherWith (slideOutHorizontally { it } + fadeOut())
                }
            },
            label = "pagina",
            modifier = Modifier.widthIn(max = 640.dp).fillMaxSize(),
        ) { attuale ->
            when (attuale) {
                0 -> PaginaWebcam(ridotte) { vai(1) }
                1 -> PaginaComputer(ridotte) { vai(2) }
                2 -> PaginaProfili(ridotte) { vai(3) }
                else -> PaginaPermessi(ridotte, chiedendo) { inizia() }
            }
        }
        Intestazione(
            pagina = pagina,
            totale = DURATE.size,
            riempimento = riempimento.asState(),
            salta = if (pagina < ultima) ({ vai(ultima) }) else null,
        )
    }
}

/** Quanto dura ogni pagina, in secondi: riempie la sua barretta. */
private val DURATE = listOf(10, 8, 10, 5)

/** Lo spazio lasciato in cima a ogni pagina per le barrette e «Salta». */
private val SPAZIO_INTESTAZIONE = 60.dp

@Composable
private fun Intestazione(pagina: Int, totale: Int, riempimento: State<Float>, salta: (() -> Unit)?) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
    ) {
        BarreAvanzamento(pagina, totale, riempimento)
        Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
        AnimatedVisibility(visible = salta != null, enter = fadeIn(), exit = fadeOut()) {
            val descrizione = stringResource(R.string.presentazione_salta_descrizione)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .heightIn(min = 40.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Colori.pannelloChiaro.copy(alpha = 0.9f))
                    .border(1.dp, Colori.bordo, RoundedCornerShape(50))
                    .clickable(role = Role.Button, onClickLabel = descrizione) { salta?.invoke() }
                    .padding(horizontal = 16.dp, vertical = 6.dp),
            ) {
                Text(stringResource(R.string.presentazione_salta), style = Caratteri.corpoForte(16), color = Colori.testo, maxLines = 1)
            }
        }
    }
}

/** L'avanzamento in stile «storie»: una barretta per pagina, quella attuale si riempie nel tempo della pagina. */
@Composable
private fun BarreAvanzamento(pagina: Int, totale: Int, riempimento: State<Float>) {
    val descrizione = stringResource(R.string.presentazione_pagina, pagina + 1, totale)
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.semantics {
            contentDescription = descrizione
            liveRegion = LiveRegionMode.Polite
        },
    ) {
        for (indice in 0 until totale) {
            Box(Modifier.width(30.dp).height(5.dp).clip(RoundedCornerShape(50)).background(Colori.linea)) {
                Box(
                    Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(
                            when {
                                indice < pagina -> 1f
                                indice == pagina -> riempimento.value.coerceIn(0f, 1f)
                                else -> 0f
                            },
                        )
                        .background(Colori.accento),
                )
            }
        }
    }
}

/**
 * Una pagina: la scena disegnata in alto, il testo sotto (scorre se il carattere è grande) e i pulsanti fermi in
 * fondo. In orizzontale su schermi bassi la scena va a sinistra e il testo a destra.
 */
@Composable
fun ImpaginazionePagina(
    quotaScena: Float = 0.44f,
    scena: @Composable (Modifier) -> Unit,
    contenuto: @Composable ColumnScope.() -> Unit,
    azioni: @Composable () -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val orizzontale = maxWidth > maxHeight && maxHeight < 520.dp
        if (orizzontale) {
            Row(Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                Box(Modifier.weight(1f).fillMaxHeight().padding(top = SPAZIO_INTESTAZIONE, bottom = 8.dp)) {
                    scena(Modifier.fillMaxSize())
                }
                Column(Modifier.weight(1f).fillMaxHeight()) {
                    Column(
                        Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = SPAZIO_INTESTAZIONE, bottom = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                        content = contenuto,
                    )
                    Box(Modifier.padding(top = 8.dp)) { azioni() }
                }
            }
        } else {
            val altezzaScena: Dp = (maxHeight * quotaScena).coerceIn(170.dp, 340.dp)
            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = 12.dp)) {
                Column(
                    Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(top = SPAZIO_INTESTAZIONE, bottom = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    scena(Modifier.fillMaxWidth().height(altezzaScena))
                    contenuto()
                }
                Box(Modifier.padding(top = 10.dp)) { azioni() }
            }
        }
    }
}

/** Titolo di una pagina, in Barlow Condensed; per TalkBack è un'intestazione. */
@Composable
fun TitoloPresentazione(testo: String) {
    Text(testo, style = Caratteri.titolo(36), color = Colori.testo, modifier = Modifier.fillMaxWidth().semantics { heading() })
}

@Composable
fun TestoPresentazione(testo: String, colore: androidx.compose.ui.graphics.Color = Colori.testoChiaro, dimensione: Int = 17) {
    Text(testo, style = Caratteri.corpo(dimensione), color = colore, modifier = Modifier.fillMaxWidth())
}

/** Una scelta a capsula: scelta nell'accento tenue con il bordo accento, le altre sul pannello. */
@Composable
fun ChipPresentazione(titolo: String, scelto: Boolean, modifier: Modifier = Modifier, suggerimento: String? = null, azione: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(50))
            .background(if (scelto) Colori.accentoTenue else Colori.pannello)
            .border(if (scelto) 1.5.dp else 1.dp, if (scelto) Colori.accento else Colori.linea, RoundedCornerShape(50))
            .clickable(role = Role.Button, onClickLabel = suggerimento, onClick = azione)
            .semantics { selected = scelto }
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        Text(
            titolo, style = Caratteri.corpoForte(16), color = if (scelto) Colori.accentoChiaro else Colori.testo,
            maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Il puntino corallo «in onda» su un riquadro video: l'unico corallo della presentazione. */
@Composable
fun PuntoInOnda(ridotte: Boolean, modifier: Modifier = Modifier) {
    val opacita = if (ridotte) {
        1f
    } else {
        val transizione = rememberInfiniteTransition(label = "inOnda")
        val valore by transizione.animateFloat(
            initialValue = 1f, targetValue = 0.45f,
            animationSpec = infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "punto",
        )
        valore
    }
    val piccolo = with(LocalDensity.current) { 9.dp.toSp() }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = modifier.clip(RoundedCornerShape(50)).background(Colori.sfumaturaScura.copy(alpha = 0.75f)).padding(horizontal = 5.dp, vertical = 1.dp),
    ) {
        Box(Modifier.size(6.dp).alpha(opacita).clip(CircleShape).background(Colori.tally))
        Text(stringResource(R.string.in_onda).uppercase(), style = Caratteri.etichetta(9).copy(fontSize = piccolo), color = Colori.testo, maxLines = 1)
    }
}

/** Un'etichetta piccola dentro un disegno: non cresce con il carattere di sistema (il testo della pagina sì). */
@Composable
fun EtichettaDisegno(testo: String, modifier: Modifier = Modifier) {
    val piccolo = with(LocalDensity.current) { 10.dp.toSp() }
    Text(
        testo.uppercase(),
        style = Caratteri.etichetta(10).copy(fontSize = piccolo, lineHeight = piccolo),
        color = Colori.testo,
        maxLines = 2,
        modifier = modifier.clip(RoundedCornerShape(4.dp)).background(Colori.sfumaturaScura.copy(alpha = 0.7f)).padding(horizontal = 5.dp, vertical = 2.dp),
    )
}

/** Il tempo che passa, in secondi, letto solo nel disegno (niente ricomposizioni a ogni fotogramma). Fermo a 0,4 s. */
@Composable
fun ricordaTempo(fermo: Boolean): State<Float> {
    val tempo = remember { mutableFloatStateOf(0.4f) }
    LaunchedEffect(fermo) {
        if (fermo) return@LaunchedEffect
        val inizio = withFrameNanos { it }
        while (true) {
            withFrameNanos { adesso -> tempo.floatValue = (adesso - inizio) / 1_000_000_000f }
        }
    }
    return tempo
}

/** Un comando invisibile sopra una parte del disegno, per il tocco e per TalkBack. */
fun Modifier.comandoSopraDisegno(etichetta: String, stato: String?, scelto: Boolean, azione: () -> Unit): Modifier =
    this
        .clickable(role = Role.Button, onClick = azione)
        .semantics {
            contentDescription = etichetta
            if (stato != null) stateDescription = stato
            selected = scelto
        }
