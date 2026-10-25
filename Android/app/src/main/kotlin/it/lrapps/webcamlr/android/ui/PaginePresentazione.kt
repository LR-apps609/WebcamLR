package it.lrapps.webcamlr.android.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.FlashlightOn
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.ZoomIn
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.contenuti.InfoApp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.roundToInt

// Le quattro pagine della presentazione (come PaginaWebcam, PaginaComputer, PaginaImpostazioni e PaginaPermessi
// dell'iPhone), con i testi per Android.

// MARK: 1. Il tuo telefono diventa la webcam

/**
 * Il telefono sul supporto manda il segnale al computer, dove nella videochiamata il tuo riquadro è quello grande.
 * Sul riquadro si trascina una linea per confrontare la webcam del computer (scura, sgranata) con il telefono.
 */
@Composable
fun PaginaWebcam(ridotte: Boolean, avanti: () -> Unit) {
    val confine = remember { Animatable(0.5f) }
    var toccato by remember { mutableStateOf(false) }
    var ditoVisibile by remember { mutableStateOf(false) }
    val ambito = rememberCoroutineScope()

    // La linea si muove da sola una volta, come se la trascinasse un dito, per far vedere che si può.
    LaunchedEffect(Unit) {
        if (ridotte) return@LaunchedEffect
        delay(1200)
        if (toccato) return@LaunchedEffect
        try {
            ditoVisibile = true
            for ((valore, durata, pausa) in listOf(Triple(0.7f, 800, 200L), Triple(0.32f, 1000, 200L), Triple(0.5f, 700, 100L))) {
                if (toccato) break
                confine.animateTo(valore, tween(durata))
                delay(pausa)
            }
        } finally {
            ditoVisibile = false
        }
    }

    ImpaginazionePagina(
        scena = { modificatore ->
            ScenaWebcam(
                modificatore, confine.value, ditoVisibile, ridotte,
                sposta = { valore ->
                    toccato = true
                    ditoVisibile = false
                    ambito.launch { confine.snapTo(valore.coerceIn(0f, 1f)) }
                },
            )
        },
        contenuto = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.TouchApp, contentDescription = null, tint = Colori.testoSecondario, modifier = Modifier.size(18.dp))
                Text(stringResource(R.string.presentazione_webcam_suggerimento), style = Caratteri.corpo(14), color = Colori.testoSecondario)
            }
            TitoloPresentazione(stringResource(R.string.presentazione_webcam_titolo))
            TestoPresentazione(stringResource(R.string.presentazione_webcam_testo))
        },
        azioni = { PulsantePieno(stringResource(R.string.avanti), azione = avanti) },
    )
}

@Composable
private fun ScenaWebcam(modifier: Modifier, confine: Float, ditoVisibile: Boolean, ridotte: Boolean, sposta: (Float) -> Unit) {
    val tempo = ricordaTempo(ridotte)
    // La grana della webcam scadente cambia 12 volte al secondo.
    var seme by remember { mutableLongStateOf(7L) }
    LaunchedEffect(ridotte) {
        if (ridotte) return@LaunchedEffect
        while (true) {
            delay(83)
            seme++
        }
    }
    val descrizione = stringResource(R.string.presentazione_webcam_scena)
    val valore = stringResource(if (confine < 0.5f) R.string.presentazione_webcam_valore_telefono else R.string.presentazione_webcam_valore_computer)
    val etichettaComputer = stringResource(R.string.presentazione_webcam_del_computer)
    val etichettaTelefono = stringResource(R.string.presentazione_telefono)
    val densita = LocalDensity.current

    BoxWithConstraints(
        modifier.semantics {
            contentDescription = descrizione
            stateDescription = valore
            progressBarRangeInfo = ProgressBarRangeInfo(confine, 0f..1f, steps = 3)
            setProgress { nuovo -> sposta(nuovo); true }
        },
    ) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val computer = min(w * 0.84f, h * 1.2f)
        val origineComputer = Offset(w - computer, 4f)
        val telefono = computer * 0.13f
        val altezzaTelefono = telefono * (Proporzioni.TELEFONO + Proporzioni.SUPPORTO)
        val vetro = vetroPortatile(origineComputer, computer)
        val spazio = with(densita) { 4.dp.toPx() }
        val grande = Rect(
            vetro.left + spazio, vetro.top + spazio,
            vetro.left + spazio + (vetro.width - spazio * 3) * 0.7f, vetro.bottom - spazio,
        )
        val geometria by rememberUpdatedState(grande)

        Canvas(
            Modifier.fillMaxSize().pointerInput(Unit) {
                awaitEachGesture {
                    val giu = awaitFirstDown(requireUnconsumed = false)
                    val riquadro = geometria
                    if (!riquadro.inflate(spazio * 3).contains(giu.position)) return@awaitEachGesture
                    giu.consume()
                    sposta((giu.position.x - riquadro.left) / riquadro.width)
                    while (true) {
                        val evento = awaitPointerEvent()
                        val dito = evento.changes.firstOrNull() ?: break
                        if (!dito.pressed) break
                        sposta((dito.position.x - riquadro.left) / riquadro.width)
                        dito.consume()
                    }
                }
            },
        ) {
            disegnaPortatile(origineComputer, computer) { schermo ->
                // Le altre tre persone, piccole, a destra.
                val piccoli = Rect(grande.right + spazio, schermo.top + spazio, schermo.right - spazio, schermo.bottom - spazio)
                val altezzaPiccolo = (piccoli.height - spazio * 2) / 3
                val maglie = listOf(Colori.salvia, Colori.salviaScura, Colori.testoSecondario)
                val sfondi = listOf(Colori.pannello, Colori.pannelloScuro, Colori.pannelloChiaro)
                for (indice in 0 until 3) {
                    val riquadro = Rect(Offset(piccoli.left, piccoli.top + indice * (altezzaPiccolo + spazio)), Size(piccoli.width, altezzaPiccolo))
                    ritagliato(riquadro, 4f) {
                        drawRect(sfondi[indice], riquadro.topLeft, riquadro.size)
                        disegnaPersona(Offset(riquadro.center.x, riquadro.bottom), riquadro.height * 0.78f, pelle = Colori.salviaTenue, maglia = maglie[indice])
                    }
                }
                // Il tuo riquadro: a destra il telefono, nitido; a sinistra la webcam del computer.
                ritagliato(grande, 6f) {
                    disegnaStanza(grande, luceVolto = 0.7f)
                    val x = grande.left + grande.width * confine
                    clipRect(grande.left, grande.top, x, grande.bottom) {
                        disegnaStanza(grande, sfocaSfondo = 0.6f)
                        disegnaWebcamScadente(grande, seme)
                    }
                    drawRect(Colori.testo, Offset(x - 1f, grande.top), Size(2f, grande.height))
                    val raggio = with(densita) { 13.dp.toPx() }
                    val centro = Offset(x, grande.center.y)
                    drawCircle(Colori.sfumaturaScura.copy(alpha = 0.5f), raggio + 2f, centro + Offset(0f, 1.5f))
                    drawCircle(Colori.testo, raggio, centro)
                    freccettaDoppia(centro, raggio * 0.45f)
                }
            }
            disegnaTelefonoSuSupporto(Offset(6f, h - altezzaTelefono), telefono)
            val lato = telefono * 1.8f
            disegnaOnde(Offset(telefono + 8f, h - altezzaTelefono + telefono * 0.4f), lato, (tempo.value * 0.7f) % 1f, ridotte)
        }

        // Etichette e «in onda» sopra il riquadro grande: testo vero, piccolo e fisso.
        with(densita) {
            if (confine > 0.25f) {
                Box(
                    Modifier.offset { IntOffset((grande.left + 5f).roundToInt(), (grande.top + 5f).roundToInt()) }
                        .size(width = (grande.width * 0.46f).toDp(), height = 40.dp),
                ) { EtichettaDisegno(etichettaComputer) }
            }
            if (confine < 0.75f) {
                Box(Modifier.offset { IntOffset((grande.right - 5f).roundToInt() - 70.dp.roundToPx(), (grande.top + 5f).roundToInt()) }.size(width = 70.dp, height = 40.dp), contentAlignment = Alignment.TopEnd) {
                    EtichettaDisegno(etichettaTelefono)
                }
            }
            Box(Modifier.offset { IntOffset((grande.left + 5f).roundToInt(), (grande.bottom - 5f).roundToInt() - 16.dp.roundToPx()) }) {
                PuntoInOnda(ridotte)
            }
            if (ditoVisibile) {
                val x = grande.left + grande.width * confine
                Icon(
                    Icons.Filled.TouchApp, contentDescription = null, tint = Colori.testo,
                    modifier = Modifier.offset { IntOffset(x.roundToInt(), (grande.center.y + 10.dp.toPx()).roundToInt()) }.size(26.dp),
                )
            }
        }
    }
}

/** La freccia ↔ dentro la maniglia della linea. */
private fun DrawScope.freccettaDoppia(centro: Offset, lato: Float) {
    val percorso = Path().apply {
        moveTo(centro.x - lato, centro.y)
        lineTo(centro.x - lato * 0.35f, centro.y - lato * 0.55f)
        lineTo(centro.x - lato * 0.35f, centro.y + lato * 0.55f)
        close()
        moveTo(centro.x + lato, centro.y)
        lineTo(centro.x + lato * 0.35f, centro.y - lato * 0.55f)
        lineTo(centro.x + lato * 0.35f, centro.y + lato * 0.55f)
        close()
    }
    drawPath(percorso, Colori.fondo)
}

// MARK: 2. Scarica WebcamLR sul computer

private enum class Sistema { MAC, WINDOWS }

/**
 * Un portatile (Mac) e un monitor (Windows) disegnati senza marchi; una freccia scende nello schermo, la barra si
 * riempie e compare il logo di WebcamLR. Toccando un computer lo scaricamento riparte lì. Sotto, l'indirizzo del sito
 * e «Mandami il link» per mandarselo (condivisione di Android) e aprirlo sul computer.
 */
@Composable
fun PaginaComputer(ridotte: Boolean, avanti: () -> Unit) {
    val context = LocalContext.current
    var scelto by remember { mutableStateOf(Sistema.MAC) }
    val scaricati = remember { mutableStateListOf<Sistema>() }
    val freccia = remember { Animatable(0f) }
    val frecciaVisibile = remember { Animatable(0f) }
    val barra = remember { Animatable(0f) }
    val comparsa = remember { mapOf(Sistema.MAC to Animatable(0f), Sistema.WINDOWS to Animatable(0f)) }
    var giro by remember { mutableIntStateOf(0) }
    var toccato by remember { mutableStateOf(false) }

    suspend fun scarica(sistema: Sistema) {
        scelto = sistema
        scaricati.remove(sistema)
        comparsa.getValue(sistema).snapTo(0f)
        freccia.snapTo(0f)
        frecciaVisibile.snapTo(0f)
        barra.snapTo(0f)
        if (ridotte) {
            scaricati.add(sistema)
            comparsa.getValue(sistema).animateTo(1f, tween(400))
            return
        }
        delay(300)
        frecciaVisibile.animateTo(1f, tween(200))
        freccia.animateTo(1f, tween(800, easing = FastOutLinearInEasing))
        frecciaVisibile.animateTo(0f, tween(200))
        barra.animateTo(1f, tween(1300))
        scaricati.add(sistema)
        comparsa.getValue(sistema).animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessMediumLow))
    }

    // Al primo giro scarica sul Mac e poi su Windows; dopo un tocco, solo sul computer toccato.
    LaunchedEffect(giro) {
        if (toccato) {
            scarica(scelto)
        } else {
            scarica(Sistema.MAC)
            delay(700)
            scarica(Sistema.WINDOWS)
        }
    }

    val testoCondividi = stringResource(R.string.presentazione_computer_messaggio, InfoApp.DOWNLOAD)
    val oggettoCondividi = stringResource(R.string.presentazione_computer_oggetto)
    val titoloCondividi = stringResource(R.string.presentazione_computer_manda)

    ImpaginazionePagina(
        scena = { modificatore ->
            ScenaComputer(
                modificatore, scelto, scaricati, freccia.value, frecciaVisibile.value, barra.value,
                comparsaMac = comparsa.getValue(Sistema.MAC).value, comparsaWindows = comparsa.getValue(Sistema.WINDOWS).value,
                tocca = { sistema ->
                    toccato = true
                    scelto = sistema
                    giro++
                },
            )
        },
        contenuto = {
            TitoloPresentazione(stringResource(R.string.presentazione_computer_titolo))
            val etichettaIndirizzo = stringResource(R.string.presentazione_computer_indirizzo)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(14.dp)).background(Colori.pannello)
                    .border(1.dp, Colori.linea, RoundedCornerShape(14.dp)).padding(horizontal = 14.dp, vertical = 8.dp)
                    .semantics(mergeDescendants = true) { contentDescription = etichettaIndirizzo + ": " + InfoApp.INDIRIZZO_BREVE },
            ) {
                Icon(Icons.Filled.Language, contentDescription = null, tint = Colori.accento)
                SelectionContainer {
                    Text(InfoApp.INDIRIZZO_BREVE, style = Caratteri.numeriEvidenti(15), color = Colori.testo, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            PulsanteSecondario(titoloCondividi, icona = Icons.Filled.Share) {
                val invio = Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, oggettoCondividi)
                    .putExtra(Intent.EXTRA_TEXT, testoCondividi)
                try {
                    context.startActivity(Intent.createChooser(invio, titoloCondividi))
                } catch (e: ActivityNotFoundException) {
                    // Nessuna app per condividere: l'indirizzo resta scritto qui sopra.
                }
            }
            TestoPresentazione(stringResource(R.string.presentazione_computer_poi), colore = Colori.testoSecondario, dimensione = 16)
        },
        azioni = { PulsantePieno(stringResource(R.string.avanti), azione = avanti) },
    )
}

@Composable
private fun ScenaComputer(
    modifier: Modifier,
    scelto: Sistema,
    scaricati: List<Sistema>,
    freccia: Float,
    frecciaVisibile: Float,
    barra: Float,
    comparsaMac: Float,
    comparsaWindows: Float,
    tocca: (Sistema) -> Unit,
) {
    val densita = LocalDensity.current
    val accento = Colori.accento
    val frecciaPainter = rememberVectorPainter(Icons.Filled.ArrowDownward)
    val scaricata = stringResource(R.string.presentazione_computer_scaricata)
    val daScaricare = stringResource(R.string.presentazione_computer_da_scaricare)
    BoxWithConstraints(modifier) {
        val w = constraints.maxWidth.toFloat()
        val etichetta = with(densita) { 28.dp.toPx() }
        val h = constraints.maxHeight.toFloat() - etichetta
        val unita = min(w, h * 1.3f)
        val larghezzaMac = unita * 0.52f
        val larghezzaWin = unita * 0.4f
        val spazioTra = unita * 0.08f
        val inizio = (w - (larghezzaMac + spazioTra + larghezzaWin)) / 2
        val origineMac = Offset(inizio, h - larghezzaMac * Proporzioni.PORTATILE)
        val origineWin = Offset(inizio + larghezzaMac + spazioTra, h - larghezzaWin * Proporzioni.MONITOR)

        Canvas(Modifier.fillMaxSize()) {
            disegnaPortatile(origineMac, larghezzaMac) { schermo ->
                schermoComputer(schermo, Sistema.MAC, larghezzaMac, scelto, barra, comparsaMac)
            }
            disegnaMonitor(origineWin, larghezzaWin) { schermo ->
                schermoComputer(schermo, Sistema.WINDOWS, larghezzaWin, scelto, barra, comparsaWindows)
            }
            if (frecciaVisibile > 0f) {
                val (origine, larghezza) = if (scelto == Sistema.MAC) origineMac to larghezzaMac else origineWin to larghezzaWin
                val raggio = 15.dp.toPx()
                val centro = Offset(origine.x + larghezza / 2, origine.y - larghezza * 0.12f + freccia * larghezza * 0.42f)
                drawCircle(accento.copy(alpha = frecciaVisibile), raggio, centro)
                translate(centro.x - raggio * 0.6f, centro.y - raggio * 0.6f) {
                    with(frecciaPainter) {
                        draw(Size(raggio * 1.2f, raggio * 1.2f), alpha = frecciaVisibile, colorFilter = ColorFilter.tint(Colori.fondo))
                    }
                }
            }
        }
        // I due computer si toccano (e TalkBack li legge), con il nome sotto.
        for (sistema in Sistema.entries) {
            val (origine, larghezza, altezza) = if (sistema == Sistema.MAC) {
                Triple(origineMac, larghezzaMac, larghezzaMac * Proporzioni.PORTATILE)
            } else {
                Triple(origineWin, larghezzaWin, larghezzaWin * Proporzioni.MONITOR)
            }
            val nome = if (sistema == Sistema.MAC) "Mac" else "Windows"
            val attivo = sistema == scelto
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .offset { IntOffset(origine.x.roundToInt(), origine.y.roundToInt()) }
                    .size(width = with(densita) { larghezza.toDp() }, height = with(densita) { (altezza + etichetta).toDp() })
                    .clip(RoundedCornerShape(8.dp))
                    .comandoSopraDisegno(nome, if (sistema in scaricati) scaricata else daScaricare, attivo) { tocca(sistema) },
            ) {
                Box(Modifier.weight(1f))
                Text(nome, style = Caratteri.corpoForte(15), color = if (attivo) Colori.accento else Colori.testoSecondario, maxLines = 1)
            }
        }
    }
}

/** Lo schermo: una barra in alto (Mac) o in basso (Windows), poi lo scaricamento e il logo. */
private fun DrawScope.schermoComputer(schermo: Rect, sistema: Sistema, larghezza: Float, scelto: Sistema, barra: Float, comparsa: Float) {
    val altezzaBarra = maxOf(3f, larghezza * 0.035f)
    val y = if (sistema == Sistema.MAC) schermo.top else schermo.bottom - altezzaBarra
    drawRect(Colori.pannelloChiaro, Offset(schermo.left, y), Size(schermo.width, altezzaBarra))
    if (comparsa > 0f) {
        val lato = larghezza * 0.2f * (0.6f + 0.4f * comparsa.coerceAtMost(1.15f))
        val origine = Offset(schermo.center.x - lato / 2, schermo.center.y - lato / 2)
        // Il logo compare crescendo; con la dissolvenza si disegna in un livello trasparente.
        drawContext.canvas.saveLayer(schermo, androidx.compose.ui.graphics.Paint().apply { alpha = comparsa.coerceIn(0f, 1f) })
        disegnaLogo(this, lato, origine)
        drawContext.canvas.restore()
    } else if (scelto == sistema && barra > 0f) {
        val lunghezza = larghezza * 0.5f
        val spessore = maxOf(4f, larghezza * 0.03f)
        val origine = Offset(schermo.center.x - lunghezza / 2, schermo.center.y - spessore / 2)
        drawRoundRect(Colori.linea, origine, Size(lunghezza, spessore), CornerRadius(spessore / 2))
        drawRoundRect(Colori.accento, origine, Size(lunghezza * barra, spessore), CornerRadius(spessore / 2))
    }
}

// MARK: 3. Le impostazioni extra sono sul computer

private enum class Profilo(val nome: Int, val descrizione: Int) {
    RIUNIONE(R.string.profilo_riunione, R.string.profilo_riunione_descrizione),
    LEZIONE(R.string.profilo_lezione, R.string.profilo_lezione_descrizione),
    DIRETTA(R.string.profilo_diretta, R.string.profilo_diretta_descrizione),
    COLLOQUIO(R.string.profilo_colloquio, R.string.profilo_colloquio_descrizione),
}

/**
 * Il telefono fa soprattutto da telecomando, profili ed effetti si scelgono nella finestra del computer. Quattro
 * profili da toccare cambiano l'anteprima disegnata.
 */
@Composable
fun PaginaProfili(ridotte: Boolean, avanti: () -> Unit) {
    var profilo by rememberSaveable { mutableStateOf(Profilo.RIUNIONE) }
    val animazione = if (ridotte) tween<Float>(250) else spring<Float>(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow)
    val luce by animateFloatAsState(
        when (profilo) {
            Profilo.RIUNIONE -> 0.85f
            Profilo.LEZIONE -> 0.3f
            Profilo.DIRETTA -> 0.6f
            Profilo.COLLOQUIO -> 0.75f
        },
        animazione, label = "luce",
    )
    val sfocatura by animateFloatAsState(if (profilo == Profilo.COLLOQUIO) 1f else 0f, animazione, label = "sfocatura")
    val scala by animateFloatAsState(
        when (profilo) {
            Profilo.LEZIONE -> 0.68f
            Profilo.COLLOQUIO -> 1.05f
            else -> 1f
        },
        animazione, label = "scala",
    )
    val scrivania by animateFloatAsState(if (profilo == Profilo.LEZIONE) 1f else 0f, animazione, label = "scrivania")

    ImpaginazionePagina(
        scena = { modificatore ->
            ScenaImpostazioni(modificatore, profilo, luce, sfocatura, scala, scrivania)
        },
        contenuto = {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val inRiga = maxWidth >= 430.dp && LocalDensity.current.fontScale <= 1.15f
                if (inRiga) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (voce in Profilo.entries) {
                            ChipPresentazione(stringResource(voce.nome), voce == profilo, suggerimento = stringResource(voce.descrizione)) { profilo = voce }
                        }
                    }
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (coppia in Profilo.entries.chunked(2)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                for (voce in coppia) {
                                    ChipPresentazione(
                                        stringResource(voce.nome), voce == profilo, Modifier.weight(1f),
                                        suggerimento = stringResource(voce.descrizione),
                                    ) { profilo = voce }
                                }
                            }
                        }
                    }
                }
            }
            AnimatedContent(targetState = profilo, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "descrizione") { voce ->
                Text(stringResource(voce.descrizione), style = Caratteri.corpo(14), color = Colori.testoSecondario, modifier = Modifier.fillMaxWidth())
            }
            TitoloPresentazione(stringResource(R.string.presentazione_impostazioni_titolo))
            TestoPresentazione(stringResource(R.string.presentazione_impostazioni_testo))
            val colonne = LocalDensity.current.fontScale > 1.3f
            val telefono: @Composable (Modifier) -> Unit = { m ->
                ColonnaDove(Icons.Filled.PhoneAndroid, stringResource(R.string.presentazione_sul_telefono), stringResource(R.string.presentazione_sul_telefono_testo), m)
            }
            val computer: @Composable (Modifier) -> Unit = { m ->
                ColonnaDove(Icons.Filled.Computer, stringResource(R.string.presentazione_sul_computer), stringResource(R.string.presentazione_sul_computer_testo), m)
            }
            if (colonne) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    telefono(Modifier.fillMaxWidth())
                    computer(Modifier.fillMaxWidth())
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.height(IntrinsicSize.Min)) {
                    telefono(Modifier.weight(1f).fillMaxHeight())
                    computer(Modifier.weight(1f).fillMaxHeight())
                }
            }
        },
        azioni = { PulsantePieno(stringResource(R.string.avanti), azione = avanti) },
    )
}

@Composable
private fun ColonnaDove(icona: ImageVector, titolo: String, testo: String, modifier: Modifier) {
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = modifier.clip(RoundedCornerShape(14.dp)).background(Colori.pannello).border(1.dp, Colori.linea, RoundedCornerShape(14.dp))
            .padding(12.dp).semantics(mergeDescendants = true) {},
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icona, contentDescription = null, tint = Colori.accento, modifier = Modifier.size(20.dp))
            Text(titolo, style = Caratteri.corpoForte(16), color = Colori.testo)
        }
        Text(testo, style = Caratteri.corpo(15), color = Colori.testoChiaro)
    }
}

@Composable
private fun ScenaImpostazioni(modifier: Modifier, profilo: Profilo, luce: Float, sfocatura: Float, scala: Float, scrivania: Float) {
    val tasti = listOf(
        rememberVectorPainter(Icons.Filled.Cameraswitch),
        rememberVectorPainter(Icons.Filled.ZoomIn),
        rememberVectorPainter(Icons.Filled.FlashlightOn),
        rememberVectorPainter(Icons.Filled.Pause),
    )
    val descrizione = stringResource(R.string.presentazione_impostazioni_scena, stringResource(profilo.nome), stringResource(profilo.descrizione))
    val densita = LocalDensity.current
    BoxWithConstraints(modifier.semantics { contentDescription = descrizione }) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val computer = min(w * 0.84f, h * 1.25f)
        val origineComputer = Offset(w - computer, 4f)
        val telefono = min(computer * 0.17f, h * 0.4f / Proporzioni.TELEFONO)
        val origineTelefono = Offset(4f, h - telefono * Proporzioni.TELEFONO)
        val spazio = with(densita) { 4.dp.toPx() }
        val diretta = profilo == Profilo.DIRETTA
        Canvas(Modifier.fillMaxSize()) {
            disegnaPortatile(origineComputer, computer) { schermo ->
                val anteprima = Rect(schermo.left + spazio, schermo.top + spazio, schermo.left + spazio + (schermo.width - spazio * 3) * 0.74f, schermo.bottom - spazio)
                ritagliato(anteprima, 4f) {
                    disegnaStanza(anteprima, luceVolto = luce, sfocaSfondo = sfocatura, scalaPersona = scala, scrivania = scrivania)
                }
                // La colonna dei profili, con quello scelto nell'accento.
                val colonna = Rect(anteprima.right + spazio, anteprima.top, schermo.right - spazio, anteprima.bottom)
                val riga = maxOf(10f, colonna.height / 6f)
                for ((indice, voce) in Profilo.entries.withIndex()) {
                    val scelta = voce == profilo
                    val alto = colonna.top + indice * (riga + spazio * 0.6f)
                    if (scelta) drawRoundRect(Colori.accentoTenue, Offset(colonna.left, alto), Size(colonna.width, riga), CornerRadius(3f))
                    drawCircle(if (scelta) Colori.accento else Colori.testoSecondario.copy(alpha = 0.5f), riga * 0.18f, Offset(colonna.left + riga * 0.35f, alto + riga / 2))
                    drawRoundRect(
                        if (scelta) Colori.accentoChiaro else Colori.linea,
                        Offset(colonna.left + riga * 0.65f, alto + riga / 2 - 1.5f), Size(colonna.width - riga * 0.9f, 3f), CornerRadius(1.5f),
                    )
                }
                if (diretta) {
                    drawRoundRect(Colori.sfumaturaScura.copy(alpha = 0.8f), Offset(anteprima.right - 34.dp.toPx(), anteprima.top + 4f), Size(30.dp.toPx(), 12.dp.toPx()), CornerRadius(6.dp.toPx()))
                }
            }
            // Il telefono come telecomando: obiettivo, zoom, torcia, pausa.
            disegnaTelefonoFronte(origineTelefono, telefono) { schermo ->
                val lato = telefono * 0.32f
                val passo = telefono * 0.08f
                val inizioX = schermo.center.x - lato - passo / 2
                val inizioY = schermo.center.y - lato - passo / 2
                for ((indice, painter) in tasti.withIndex()) {
                    val x = inizioX + (indice % 2) * (lato + passo)
                    val y = inizioY + (indice / 2) * (lato + passo)
                    drawCircle(Colori.pannelloChiaro, lato / 2, Offset(x + lato / 2, y + lato / 2))
                    translate(x + lato * 0.25f, y + lato * 0.25f) {
                        with(painter) { draw(Size(lato * 0.5f, lato * 0.5f), colorFilter = ColorFilter.tint(Colori.testoChiaro)) }
                    }
                }
            }
        }
        if (diretta) {
            val piccolo = with(densita) { 8.dp.toSp() }
            val vetro = vetroPortatile(origineComputer, computer)
            val destraAnteprima = vetro.left + spazio + (vetro.width - spazio * 3) * 0.74f
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .offset { IntOffset((destraAnteprima - 34.dp.toPx()).roundToInt(), (vetro.top + spazio + 4f).roundToInt()) }
                    .size(width = 30.dp, height = 12.dp),
            ) {
                Text("60 fps", style = Caratteri.numeriEvidenti(8).copy(fontSize = piccolo), color = Colori.testo, maxLines = 1)
            }
        }
    }
}

// MARK: 4. Goditi l'esperienza

private enum class Permesso { FOTOCAMERA, MICROFONO, NOTIFICHE }

/**
 * I permessi spiegati prima che Android li chieda. Toccando un permesso la scena fa vedere a cosa serve (il video
 * che va al computer, l'audio, l'avviso che tiene vivo il video a schermo spento). «Inizia» li chiede.
 */
@Composable
fun PaginaPermessi(ridotte: Boolean, chiedendo: Boolean, inizia: () -> Unit) {
    var scelto by rememberSaveable { mutableStateOf(Permesso.FOTOCAMERA) }
    ImpaginazionePagina(
        quotaScena = 0.28f,
        scena = { modificatore -> ScenaPermessi(modificatore, scelto, ridotte) },
        contenuto = {
            TitoloPresentazione(stringResource(R.string.presentazione_permessi_titolo))
            TestoPresentazione(stringResource(R.string.presentazione_permessi_testo))
            for (voce in Permesso.entries) {
                val (icona, titolo, testo) = when (voce) {
                    Permesso.FOTOCAMERA -> Triple(Icons.Filled.CameraAlt, R.string.permesso_fotocamera, R.string.permesso_fotocamera_testo)
                    Permesso.MICROFONO -> Triple(Icons.Filled.Mic, R.string.permesso_microfono, R.string.permesso_microfono_testo)
                    Permesso.NOTIFICHE -> Triple(Icons.Filled.Notifications, R.string.permesso_notifiche, R.string.permesso_notifiche_testo)
                }
                SchedaPermesso(icona, stringResource(titolo), stringResource(testo), voce == scelto) { scelto = voce }
            }
            TestoPresentazione(stringResource(R.string.presentazione_permessi_nota), colore = Colori.testoSecondario, dimensione = 14)
        },
        azioni = {
            PulsantePieno(stringResource(R.string.presentazione_inizia), icona = Icons.AutoMirrored.Filled.ArrowForward, abilitato = !chiedendo, inCorso = chiedendo, azione = inizia)
        },
    )
}

@Composable
private fun SchedaPermesso(icona: ImageVector, titolo: String, testo: String, attivo: Boolean, scegli: () -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Colori.pannello)
            .border(if (attivo) 1.5.dp else 1.dp, if (attivo) Colori.accento.copy(alpha = 0.7f) else Colori.linea, RoundedCornerShape(16.dp))
            .clickable(onClick = scegli)
            .semantics(mergeDescendants = true) { selected = attivo }
            .padding(12.dp),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(if (attivo) Colori.accentoTenue else Colori.pannelloChiaro),
        ) {
            Icon(icona, contentDescription = null, tint = if (attivo) Colori.accento else Colori.testoSecondario)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(titolo, style = Caratteri.corpoForte(17), color = Colori.testo)
            Text(testo, style = Caratteri.corpo(15), color = Colori.testoChiaro)
        }
    }
}

@Composable
private fun ScenaPermessi(modifier: Modifier, scelto: Permesso, ridotte: Boolean) {
    val tempo = ricordaTempo(ridotte)
    val icone = mapOf(
        Permesso.FOTOCAMERA to rememberVectorPainter(Icons.Filled.CameraAlt),
        Permesso.MICROFONO to rememberVectorPainter(Icons.Filled.Mic),
        Permesso.NOTIFICHE to rememberVectorPainter(Icons.Filled.Notifications),
    )
    val onda = rememberVectorPainter(Icons.Filled.GraphicEq)
    val descrizione = stringResource(
        when (scelto) {
            Permesso.FOTOCAMERA -> R.string.presentazione_permessi_scena_fotocamera
            Permesso.MICROFONO -> R.string.presentazione_permessi_scena_microfono
            Permesso.NOTIFICHE -> R.string.presentazione_permessi_scena_notifiche
        },
    )
    BoxWithConstraints(modifier.semantics { contentDescription = descrizione }) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val computer = min(w * 0.46f, h * 1.3f)
        val telefono = min(w * 0.17f, h * 0.92f / Proporzioni.TELEFONO)
        val origineTelefono = Offset(0f, (h - telefono * Proporzioni.TELEFONO) / 2)
        val origineComputer = Offset(w - computer, (h - computer * Proporzioni.PORTATILE) / 2)
        val flusso = Rect(telefono + 12f, h * 0.2f, w - computer - 12f, h * 0.8f)
        val vetro = vetroPortatile(origineComputer, computer)
        Canvas(Modifier.fillMaxSize()) {
            disegnaTelefonoFronte(origineTelefono, telefono) { schermo ->
                val lato = telefono * 0.36f
                translate(schermo.center.x - lato / 2, schermo.center.y - lato / 2) {
                    with(icone.getValue(scelto)) { draw(Size(lato, lato), colorFilter = ColorFilter.tint(Colori.accento)) }
                }
            }
            val t = tempo.value
            when (scelto) {
                Permesso.FOTOCAMERA -> disegnaFotogrammi(flusso, t)
                Permesso.MICROFONO -> disegnaAudio(flusso, if (ridotte) 0.4f else t)
                Permesso.NOTIFICHE -> disegnaBattito(flusso, t, ridotte)
            }
            disegnaPortatile(origineComputer, computer) { schermo ->
                when (scelto) {
                    Permesso.MICROFONO -> {
                        val lato = computer * 0.2f
                        translate(schermo.center.x - lato / 2, schermo.center.y - lato / 2) {
                            with(onda) { draw(Size(lato, lato), colorFilter = ColorFilter.tint(Colori.accento)) }
                        }
                    }
                    else -> disegnaStanza(schermo, luceVolto = 0.6f)
                }
            }
        }
        if (scelto != Permesso.MICROFONO) {
            Box(Modifier.offset { IntOffset((vetro.left + 3f).roundToInt(), (vetro.bottom - 3f).roundToInt() - 16.dp.roundToPx()) }) {
                PuntoInOnda(ridotte)
            }
        }
    }
}
