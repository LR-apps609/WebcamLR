package it.lrapps.webcamlr.android.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.RectF
import android.os.SystemClock
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Accessibility
import androidx.compose.material.icons.filled.BatteryAlert
import androidx.compose.material.icons.filled.BlurOn
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Flip
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.logica.ControlloPostura
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.android.sessione.SessioneTelefono.Stato
import it.lrapps.webcamlr.android.video.ObiettivoAndroid
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.MotiviPausa
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import it.lrapps.webcamlr.protocollo.Temperatura
import it.lrapps.webcamlr.protocollo.TipoCollegamento
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/** I fogli che «In onda» apre sopra il video, uno alla volta. */
private enum class Foglio { Dettagli, Impostazioni, Pro, Domanda }

/** In orizzontale, dopo questi millisecondi senza tocchi, «vista pulita»: resta solo «IN ONDA». */
private const val VISTA_PULITA_MS = 5_000L

/**
 * «In onda» (Documenti/Interfaccia finale.md): in alto la pillola di stato («● IN ONDA · MACBOOK AIR … Ottima», un
 * tocco apre i «Dettagli») con Impostazioni e Scollega; a destra la colonna di pulsanti tondi Specchia · Sfoca sfondo ·
 * Microfono · Pausa · Luce (sul volto); gli obiettivi in basso. Un avviso alla volta che si chiude da solo. La torcia
 * sta nelle Impostazioni; effetti, assistente e controlli Pro si comandano dal computer. Griglia, livella e riquadro del fuoco stanno solo
 * sul video, mai sulle bande nere.
 * In orizzontale, dopo qualche secondo senza tocchi, «vista pulita»: solo «IN ONDA», un tocco riporta i comandi (non
 * con un foglio aperto, con TalkBack o mentre c'è qualcosa da dire: errore, conferma, riconnessione).
 * La sessione nasce quando si sceglie il computer (MainActivity): qui si mostra e si comanda. Lo schermo resta acceso;
 * dopo 30 secondi senza tocchi si oscura (luminosità al minimo e nero), come sull'iPhone.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SchermataInOnda(sessione: SessioneTelefono, chiudi: () -> Unit, apriAltro: (VoceAltro) -> Unit) {
    val context = LocalContext.current
    val vista = LocalView.current
    val verticale = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    val ambito = rememberCoroutineScope()
    val avvisi = remember { CodaAvvisi(ambito) }
    var ultimoTocco by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    var foglio by remember { mutableStateOf<Foglio?>(null) }
    var domanda by remember { mutableStateOf<String?>(null) }
    var vistaPulita by remember { mutableStateOf(false) }

    // Schermo sempre acceso e barre di sistema nascoste mentre si è in onda.
    DisposableEffect(Unit) {
        val finestra = (context as? Activity)?.window
        finestra?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val controllo = finestra?.let { WindowCompat.getInsetsController(it, vista) }
        controllo?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controllo?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            finestra?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            controllo?.show(WindowInsetsCompat.Type.systemBars())
            finestra?.attributes = finestra?.attributes?.apply { screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE }
            avvisi.ferma()
        }
    }
    // Oscurato: luminosità al minimo; il video continua, il disegno dell'anteprima si ferma.
    LaunchedEffect(sessione.oscurato) {
        val finestra = (context as? Activity)?.window ?: return@LaunchedEffect
        finestra.attributes = finestra.attributes.apply {
            screenBrightness = if (sessione.oscurato) 0.01f else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        }
        sessione.renderizzatore.anteprimaAttiva = !sessione.oscurato
    }
    // Dopo 30 secondi senza tocchi, con il video che va, lo schermo si oscura da solo. Non con un foglio aperto
    // (si riparte alla chiusura) e non con TalkBack, che sotto il nero non troverebbe più i comandi.
    LaunchedEffect(ultimoTocco, sessione.stato, Impostazioni.oscuraDaSolo, foglio) {
        if (!Impostazioni.oscuraDaSolo || foglio != null || sessione.stato != Stato.Collegato || conTalkBack(context)) return@LaunchedEffect
        delay(30_000)
        if (sessione.stato == Stato.Collegato) sessione.oscurato = true
    }
    // Vista pulita: solo in orizzontale, collegati, senza fogli, senza TalkBack e senza nulla da confermare.
    val pulitaPossibile = !verticale && foglio == null && sessione.stato == Stato.Collegato && sessione.codiceConferma == null
    LaunchedEffect(ultimoTocco, pulitaPossibile) {
        if (!pulitaPossibile || conTalkBack(context)) {
            vistaPulita = false
            return@LaunchedEffect
        }
        delay(VISTA_PULITA_MS)
        vistaPulita = true
    }

    val avvisiAttivi = avvisiAttivi(sessione, verticale)
    LaunchedEffect(avvisiAttivi.map { it.id }) { avvisi.aggiorna(avvisiAttivi) }

    Box(
        Modifier
            .fillMaxSize()
            // Il nero delle bande attorno al video, come nella Fotocamera: non è un colore dell'interfaccia.
            .background(Color.Black)
            // Qualsiasi tocco, anche sui pulsanti, fa ripartire i 30 secondi; il tocco non si consuma.
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent(PointerEventPass.Initial)
                        ultimoTocco = SystemClock.elapsedRealtime()
                    }
                }
            },
    ) {
        AreaVideo(sessione)

        AnimatedVisibility(visible = !vistaPulita, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            // Solo i margini sicuri veri (tacca, barre): in orizzontale il lato senza tacca non ne ha.
            Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                // In alto: la pillola di stato a sinistra, Impostazioni e Scollega a filo nell'angolo in alto a destra
                // (in verticale e in orizzontale), staccati di poco dal bordo.
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth().align(Alignment.TopEnd).padding(start = 12.dp, end = 6.dp, top = 6.dp),
                ) {
                    // La pillola prende lo spazio che resta, così i due pulsanti stanno sempre in fondo a destra; in
                    // verticale si distende, in orizzontale resta corta, a sinistra.
                    Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                        RigaStato(sessione, distesa = verticale, modifier = if (verticale) Modifier.fillMaxWidth() else Modifier) { foglio = Foglio.Dettagli }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        PulsanteSopraIlVideo(Icons.Filled.Settings, stringResource(R.string.impostazioni)) { foglio = Foglio.Impostazioni }
                        PulsanteSopraIlVideo(Icons.Filled.Close, stringResource(R.string.scollega), azione = chiudi)
                    }
                }
                Box(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 10.dp)) {
                    // Avvisi e pannelli a sinistra della colonna, tra la pillola e gli obiettivi.
                    Column(
                        Modifier.fillMaxSize().padding(top = 54.dp, end = if (verticale) 80.dp else 76.dp, bottom = 58.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        if (sessione.aeafBloccati) {
                            val descrizione = stringResource(R.string.aeaf_bloccati_descrizione)
                            Box(
                                Modifier.heightIn(min = 26.dp).clip(RoundedCornerShape(50)).background(Colori.ambra)
                                    .semantics { contentDescription = descrizione }.padding(horizontal = 10.dp, vertical = 3.dp),
                            ) { Text(stringResource(R.string.aeaf_bloccati), style = Caratteri.etichetta(15), color = Colori.fondo) }
                        }
                        // Un avviso alla volta.
                        val avviso = avvisi.attuale
                        AnimatedVisibility(visible = avviso != null, enter = fadeIn(), exit = fadeOut()) {
                            if (avviso != null) VistaAvviso(avviso) { avvisi.chiudi() }
                        }
                        // Il promemoria della postura, solo quando non c'è già un altro avviso: uno alla volta.
                        if (avviso == null) BannerPostura(sessione)
                        // Il pulsante «Pausa», la faccia in giù, il calore: uno stato vero, resta finché dura.
                        BannerPausa(sessione)
                        Spacer(Modifier.weight(1f))
                        when (val stato = sessione.stato) {
                            is Stato.Errore -> PannelloErrore(sessione, stato.descrizione, chiudi) { id ->
                                domanda = id
                                foglio = Foglio.Domanda
                            }
                            else -> {
                                val codice = sessione.codiceConferma
                                if (codice != null) {
                                    PannelloConferma(sessione, codice)
                                } else if (sessione.inizioRiconnessione != null && (stato is Stato.Riconnessione || stato is Stato.Collegamento)) {
                                    BannerRiconnessione(sessione)
                                }
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        if (sessione.prontaCam2) {
                            PulsanteUsaProspettiva(Modifier.align(Alignment.CenterHorizontally)) { sessione.usaProspettiva() }
                        }
                    }

                    // A destra la colonna dei pulsanti tondi, in basso gli obiettivi.
                    ColonnaComandi(sessione, grande = verticale, modifier = Modifier.align(Alignment.CenterEnd).padding(top = 54.dp, bottom = 58.dp))
                    Box(Modifier.align(Alignment.BottomCenter).padding(bottom = if (verticale) 24.dp else 4.dp)) { SelettoreObiettivo(sessione) }
                }
            }
        }

        if (vistaPulita) {
            VistaPulita(sessione) {
                vistaPulita = false
                ultimoTocco = SystemClock.elapsedRealtime()
            }
        }

        if (sessione.oscurato) {
            SchermoOscurato(sessione) {
                sessione.oscurato = false
                ultimoTocco = SystemClock.elapsedRealtime()
            }
        }
    }

    // I fogli, alti. Effetti, assistente e controlli Pro si comandano dal computer.
    val aperto = foglio
    if (aperto != null) key(aperto) {
        val stato = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        val chiudiFoglio = { foglio = null }
        ModalBottomSheet(
            onDismissRequest = chiudiFoglio,
            sheetState = stato,
            containerColor = Colori.fondo,
            contentColor = Colori.testo,
            scrimColor = Color.Black.copy(alpha = 0.45f),
        ) {
            when (aperto) {
                Foglio.Dettagli -> FoglioDettagli(sessione, chiudiFoglio)
                Foglio.Impostazioni -> FoglioImpostazioni(
                    sessione,
                    chiudi = chiudiFoglio,
                    azioni = AzioniImpostazioni(
                        apriPro = { foglio = Foglio.Pro },
                        apriAltro = { voce ->
                            if (voce == VoceAltro.Aiuto) {
                                // Le domande frequenti in un foglio: il video resta lì sotto.
                                domanda = null
                                foglio = Foglio.Domanda
                            } else {
                                foglio = null
                                apriAltro(voce)
                            }
                        },
                    ),
                )
                Foglio.Pro -> FoglioPro(chiudiFoglio)
                Foglio.Domanda -> FoglioDomanda(domanda, chiudiFoglio)
            }
        }
    }
}

private fun conTalkBack(context: Context): Boolean {
    val accessibilita = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
    return accessibilita?.isTouchExplorationEnabled == true
}

// MARK: Il video

/**
 * L'anteprima a tutto schermo: il Renderizzatore ci disegna il video inviato, intero, con le bande e girato per lo
 * schermo. Griglia, livella, riquadro del fuoco e zoom stanno solo nel rettangolo del video
 * ([SessioneTelefono.rettangoloVideo]), mai sulle bande. I gesti su tutta l'anteprima (le coordinate che la sessione
 * si aspetta): tocco = messa a fuoco, tocco lungo = Blocco AE/AF, doppio tocco = cambia fotocamera, pizzico = zoom.
 */
@Composable
private fun AreaVideo(sessione: SessioneTelefono) {
    val dimensioni = sessione.dimensioniVideo.ora()
    val configurazione = LocalConfiguration.current
    val livella by ricordaLivella(PreferenzeInterfaccia.livella)
    var puntoFuoco by remember { mutableStateOf<Offset?>(null) }
    var zoomVisibile by remember { mutableStateOf(false) }
    var ultimoPizzico by remember { mutableLongStateOf(0L) }
    LaunchedEffect(puntoFuoco, sessione.aeafBloccati) {
        if (puntoFuoco != null && !sessione.aeafBloccati) {
            delay(1_500)
            puntoFuoco = null
        }
    }
    // Lo zoom si legge al centro solo mentre si pizzica, come nella Fotocamera.
    LaunchedEffect(ultimoPizzico) {
        if (ultimoPizzico == 0L) return@LaunchedEffect
        zoomVisibile = true
        delay(1_200)
        zoomVisibile = false
    }
    val descrizione = stringResource(R.string.anteprima_descrizione)
    val cambia = stringResource(R.string.cambia_fotocamera)

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val densita = LocalDensity.current
        val larghezzaVista = constraints.maxWidth.toFloat()
        val altezzaVista = constraints.maxHeight.toFloat()
        // Il rettangolo dipende anche dalle rotazioni del Renderizzatore, che non si osservano: si rilegge ogni mezzo
        // secondo (RectF confronta i valori, quindi non si ridisegna se non cambia).
        var rettangolo by remember { mutableStateOf(RectF(0f, 0f, larghezzaVista, altezzaVista)) }
        LaunchedEffect(larghezzaVista, altezzaVista, dimensioni, configurazione.orientation) {
            while (true) {
                val r = sessione.rettangoloVideo(larghezzaVista, altezzaVista)
                rettangolo = if (r.width() > 1f && r.height() > 1f) r else RectF(0f, 0f, larghezzaVista, altezzaVista)
                delay(500)
            }
        }
        AnteprimaVideo(sessione.renderizzatore, Modifier.fillMaxSize())
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(sessione) {
                    detectTapGestures(
                        onTap = { punto ->
                            puntoFuoco = punto
                            sessione.metteAFuoco(punto.x / size.width, punto.y / size.height, blocca = false)
                        },
                        onDoubleTap = { sessione.cambiaFotocamera() },
                        onLongPress = { punto ->
                            puntoFuoco = punto
                            sessione.metteAFuoco(punto.x / size.width, punto.y / size.height, blocca = true)
                        },
                    )
                }
                .pointerInput(sessione) {
                    detectTransformGestures { _, _, scala, _ ->
                        if (scala != 1f) {
                            sessione.impostaZoom(sessione.zoom * scala)
                            ultimoPizzico = SystemClock.elapsedRealtime()
                        }
                    }
                }
                .semantics {
                    contentDescription = descrizione
                    customActions = listOf(CustomAccessibilityAction(cambia) { sessione.cambiaFotocamera(); true })
                },
        )
        // Tutto ciò che sta sopra il video, nel suo rettangolo.
        val r = rettangolo
        Box(
            Modifier
                .offset { IntOffset(r.left.roundToInt(), r.top.roundToInt()) }
                .size(with(densita) { r.width().toDp() }, with(densita) { r.height().toDp() }),
        ) {
            if (Impostazioni.griglia) GrigliaTerzi()
            livella?.let { LineaLivella(it) }
            puntoFuoco?.let { punto ->
                Canvas(Modifier.fillMaxSize()) {
                    val lato = 84.dp.toPx()
                    // Il punto toccato è nella vista intera: si porta nel video e il riquadro resta tutto dentro.
                    val x = (punto.x - r.left).coerceIn(lato / 2, maxOf(lato / 2, size.width - lato / 2))
                    val y = (punto.y - r.top).coerceIn(lato / 2, maxOf(lato / 2, size.height - lato / 2))
                    drawRoundRect(
                        Colori.ambra, topLeft = Offset(x - lato / 2, y - lato / 2), size = Size(lato, lato),
                        cornerRadius = CornerRadius(4.dp.toPx()), style = Stroke(width = 2.dp.toPx()),
                    )
                }
            }
            AnimatedVisibility(visible = zoomVisibile, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.Center)) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.heightIn(min = 34.dp).clip(RoundedCornerShape(50)).background(Colori.fondo.copy(alpha = 0.78f)).padding(horizontal = 12.dp),
                ) {
                    Text(String.format(Testi.locale, "%.1f×", sessione.zoom), style = Caratteri.numeriEvidenti(17), color = Colori.testo)
                }
            }
        }
    }
}

/** Linee dei terzi, appena visibili: si disegnano nel riquadro del video. */
@Composable
private fun GrigliaTerzi() {
    Canvas(Modifier.fillMaxSize()) {
        val colore = Colori.testo.copy(alpha = 0.22f)
        for (i in 1..2) {
            drawLine(colore, Offset(size.width * i / 3, 0f), Offset(size.width * i / 3, size.height), strokeWidth = 1.dp.toPx())
            drawLine(colore, Offset(0f, size.height * i / 3), Offset(size.width, size.height * i / 3), strokeWidth = 1.dp.toPx())
        }
    }
}

/** Livella al centro del video: la linea segue l'orizzonte e diventa verde entro ±1°. */
@Composable
private fun LineaLivella(scostamento: Float) {
    val dritto = kotlin.math.abs(scostamento) < 1f
    val colore = if (dritto) Colori.verde else Colori.testo.copy(alpha = 0.75f)
    Canvas(Modifier.fillMaxSize()) {
        val centro = Offset(size.width / 2, size.height / 2)
        val spessore = 2.dp.toPx()
        // Due tacche ferme ai lati: il riferimento del telefono.
        val distanza = 84.dp.toPx()
        val tacca = 18.dp.toPx()
        drawLine(colore, Offset(centro.x - distanza - tacca, centro.y), Offset(centro.x - distanza, centro.y), strokeWidth = spessore)
        drawLine(colore, Offset(centro.x + distanza, centro.y), Offset(centro.x + distanza + tacca, centro.y), strokeWidth = spessore)
        rotate(if (dritto) 0f else scostamento, pivot = centro) {
            val mezza = 60.dp.toPx()
            drawLine(colore, Offset(centro.x - mezza, centro.y), Offset(centro.x + mezza, centro.y), strokeWidth = spessore)
        }
    }
}

// MARK: La riga di stato

/**
 * La pillola di stato: «● IN ONDA · MACBOOK AIR … Ottima» (col punto corallo solo quando un'app usa la webcam),
 * altrimenti «● COLLEGATO · MACBOOK AIR». `distesa`: prende tutta la riga, con la qualità in fondo a destra (in
 * verticale). Un tocco apre i «Dettagli». Se il nome non ci sta resta «In onda» o «Collegato»: mai troncato.
 */
@Composable
private fun RigaStato(sessione: SessioneTelefono, distesa: Boolean, modifier: Modifier = Modifier, apriDettagli: () -> Unit) {
    val stato = sessione.stato
    val inOnda = sessione.inOnda
    val cam2 = sessione.prontaCam2
    val testo = when {
        cam2 -> stringResource(R.string.pronta_cam2)
        stato == Stato.Collegato && inOnda != null -> stringResource(R.string.stato_in_onda_app, sessione.computer.nome)
        stato == Stato.Collegato -> stringResource(R.string.stato_collegato_a, sessione.computer.nome)
        stato == Stato.Collegamento -> stringResource(R.string.stato_collegamento)
        stato is Stato.Riconnessione -> stringResource(R.string.stato_riconnessione_tentativo, stato.tentativo, SessioneTelefono.TENTATIVI_MASSIMI)
        else -> stringResource(R.string.stato_scollegato)
    }
    val breve = when {
        cam2 -> stringResource(R.string.pronta_cam2)
        stato == Stato.Collegato && inOnda != null -> stringResource(R.string.in_onda)
        stato == Stato.Collegato -> stringResource(R.string.stato_collegato)
        stato is Stato.Riconnessione -> stringResource(R.string.stato_riconnessione)
        else -> testo
    }
    val punto = when {
        // Con più telefoni, quello che non è nella webcam: salvia, mai corallo.
        cam2 -> Colori.accento
        // Il corallo solo quando un'app usa davvero la webcam.
        stato == Stato.Collegato && inOnda != null -> Colori.tally
        stato == Stato.Collegato -> Colori.verde
        stato == Stato.Collegamento || stato is Stato.Riconnessione -> Colori.ambra
        else -> Colori.testoTenue
    }
    val latenza = sessione.latenzaMs
    val qualita = QualitaCollegamento.da(latenza ?: 0, sessione.perditeRecenti)
    val parolaQualita = testoQualita(qualita)
    val conQualita = if (stato == Stato.Collegato && latenza != null) stringResource(R.string.stato_con_qualita, testo, parolaQualita.lowercase()) else testo
    val tipoAttuale = sessione.tipoCollegamento
    val etichetta = if (stato == Stato.Collegato && tipoAttuale != null) "$conQualita, ${stradaBreve(tipoAttuale)}" else conQualita
    val suggerimento = stringResource(R.string.mostra_dettagli)
    var usaBreve by remember(testo) { mutableStateOf(false) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = modifier
            .heightIn(min = 40.dp)
            .clip(RoundedCornerShape(50))
            .background(Colori.fondo.copy(alpha = 0.8f))
            .clickable(role = Role.Button, onClickLabel = suggerimento, onClick = apriDettagli)
            .semantics(mergeDescendants = true) {
                contentDescription = etichetta
                liveRegion = LiveRegionMode.Polite
            }
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(punto))
        Text(
            (if (usaBreve) breve else testo).uppercase(),
            style = Caratteri.etichetta(15, spaziatura = 0.9.sp),
            color = Colori.testo,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier.weight(1f, fill = distesa),
            onTextLayout = { risultato -> if (risultato.hasVisualOverflow && !usaBreve) usaBreve = true },
        )
        if (stato == Stato.Collegato) {
            // «Wi-Fi» o «USB»: per quale strada arriva il video (non nella vista pulita).
            sessione.tipoCollegamento?.let { tipo ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(iconaCollegamento(tipo), contentDescription = null, tint = Colori.testoSecondario, modifier = Modifier.size(14.dp))
                    Text(stradaBreve(tipo), style = Caratteri.etichetta(13, spaziatura = 0.6.sp), color = Colori.testoSecondario, maxLines = 1, softWrap = false)
                }
            }
            if (latenza != null) Text(parolaQualita, style = Caratteri.corpoEvidente(13), color = coloreQualita(qualita), maxLines = 1)
        }
    }
}

/**
 * Con più telefoni, su quello che non è nella webcam (interfaccia finale, «Due telefoni»): grande, in basso,
 * nell'accento salvia. La scelta si vede solo quando il computer manda il nuovo `in-onda`.
 */
@Composable
private fun PulsanteUsaProspettiva(modifier: Modifier = Modifier, azione: () -> Unit) {
    val suggerimento = stringResource(R.string.usa_prospettiva_suggerimento)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier.widthIn(max = 520.dp).fillMaxWidth().heightIn(min = 60.dp)
            .clip(RoundedCornerShape(16.dp)).background(Colori.accento)
            .clickable(role = Role.Button, onClick = azione)
            .semantics { stateDescription = suggerimento }
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Text(stringResource(R.string.usa_prospettiva), style = Caratteri.corpoForte(17), color = Colori.fondo, maxLines = 2)
    }
}

/** Impostazioni e Scollega in alto a destra: tondi, scuri e trasparenti sopra il video. */
@Composable
private fun PulsanteSopraIlVideo(icona: ImageVector, etichetta: String, azione: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.size(44.dp).clip(CircleShape).background(Colori.fondo.copy(alpha = 0.8f))
            .clickable(role = Role.Button, onClickLabel = etichetta, onClick = azione)
            .semantics { contentDescription = etichetta },
    ) {
        Icon(icona, contentDescription = null, tint = Colori.testo, modifier = Modifier.size(21.dp))
    }
}

/**
 * La vista pulita in orizzontale: resta solo «● IN ONDA» (o «● COLLEGATO») e un suggerimento in basso; un tocco
 * ovunque riporta i comandi. Non compare con TalkBack (vedi [SchermataInOnda]).
 */
@Composable
private fun VistaPulita(sessione: SessioneTelefono, mostraComandi: () -> Unit) {
    val cam2 = sessione.prontaCam2
    val inOnda = !cam2 && sessione.inOnda != null
    val etichetta = stringResource(R.string.mostra_comandi)
    Box(
        Modifier.fillMaxSize()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClickLabel = etichetta, onClick = mostraComandi)
            .safeDrawingPadding().padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.align(Alignment.TopStart).padding(start = 30.dp, top = 6.dp).clip(RoundedCornerShape(50))
                .background(Colori.fondo.copy(alpha = 0.6f)).padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(if (cam2) Colori.accento else if (inOnda) Colori.tally else Colori.verde))
            Text(
                stringResource(if (cam2) R.string.pronta_cam2 else if (inOnda) R.string.in_onda else R.string.stato_collegato).uppercase(),
                style = Caratteri.etichetta(14, spaziatura = 0.9.sp), color = Colori.testo, maxLines = 1,
            )
        }
        Text(
            stringResource(R.string.tocca_per_i_comandi),
            style = Caratteri.corpo(13),
            color = Colori.testo.copy(alpha = 0.75f),
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp).clip(RoundedCornerShape(50))
                .background(Colori.fondo.copy(alpha = 0.5f)).padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
}

/** La strada in una parola, per la pillola: «Wi-Fi» o «USB» (e «Ethernet» per il raro cavo di rete). */
@Composable
private fun stradaBreve(tipo: TipoCollegamento): String = stringResource(
    when (tipo) {
        TipoCollegamento.CAVO_USB -> R.string.pillola_usb
        TipoCollegamento.CAVO_DI_RETE -> R.string.pillola_ethernet
        TipoCollegamento.WIFI, TipoCollegamento.HOTSPOT, TipoCollegamento.WIFI_DIRETTO -> R.string.pillola_wifi
    },
)

private fun iconaCollegamento(tipo: TipoCollegamento) = when (tipo) {
    TipoCollegamento.CAVO_USB, TipoCollegamento.CAVO_DI_RETE -> Icons.Filled.Usb
    TipoCollegamento.HOTSPOT, TipoCollegamento.WIFI_DIRETTO -> Icons.Filled.WifiTethering
    TipoCollegamento.WIFI -> Icons.Filled.Wifi
}

// MARK: Gli avvisi

/** Le condizioni da dire adesso, una per argomento. La coda le mostra una alla volta, senza ripetersi. */
@Composable
private fun avvisiAttivi(sessione: SessioneTelefono, verticale: Boolean): List<CodaAvvisi.Avviso> {
    val microfono = sessione.avvisoMicrofono.ora()
    if (sessione.stato != Stato.Collegato) return emptyList()
    val elenco = mutableListOf<CodaAvvisi.Avviso>()
    if (microfono != null) {
        elenco += CodaAvvisi.Avviso("microfono", microfono, Icons.Filled.MicOff, suggerimento = false, priorita = 5)
    }
    if (sessione.qualitaRidotta) {
        elenco += CodaAvvisi.Avviso("caldo", stringResource(R.string.avviso_caldo), Icons.Filled.Thermostat, suggerimento = false, priorita = 4)
    }
    if (sessione.batteriaBassa) {
        val testo = if (sessione.risparmioBatteria) stringResource(R.string.avviso_batteria_risparmio, sessione.batteria) else stringResource(R.string.avviso_batteria, sessione.batteria)
        elenco += CodaAvvisi.Avviso("batteria", testo, Icons.Filled.BatteryAlert, suggerimento = false, priorita = 4)
    }
    // Rete lenta e consiglio del cavo in una frase sola: mai due avvisi sulla stessa cosa.
    val consiglio = sessione.tipoCollegamento?.let { consiglioSeDebole(it) }
    val latenza = sessione.latenzaMs
    val debole = latenza != null && QualitaCollegamento.da(latenza, sessione.perditeRecenti) == QualitaCollegamento.DEBOLE
    val rete = when {
        sessione.reteDebole && consiglio != null -> stringResource(R.string.avviso_rete_lenta_consiglio, consiglio)
        sessione.reteDebole -> stringResource(R.string.avviso_rete_lenta)
        debole && consiglio != null -> consiglio
        else -> null
    }
    if (rete != null) {
        elenco += CodaAvvisi.Avviso("rete", rete, Icons.Filled.NetworkCheck, suggerimento = false, priorita = 3)
    }
    if (verticale) {
        elenco += CodaAvvisi.Avviso("orizzontale", stringResource(R.string.avviso_orizzontale), Icons.Filled.ScreenRotation, suggerimento = true, priorita = 1)
    }
    return elenco
}

@Composable
private fun VistaAvviso(avviso: CodaAvvisi.Avviso, chiudi: () -> Unit) {
    val suggerimento = stringResource(R.string.tocca_per_chiudere)
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .widthIn(max = 420.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Colori.pannello.copy(alpha = 0.94f))
            .clickable(onClickLabel = suggerimento, onClick = chiudi)
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Icon(
            avviso.icona, contentDescription = null, modifier = Modifier.size(18.dp),
            tint = if (avviso.suggerimento) Colori.accentoChiaro else Colori.ambraTesto,
        )
        Text(avviso.testo, style = Caratteri.corpoEvidente(14), color = Colori.testo)
    }
}

/** Il promemoria della postura: sparisce da solo (lo toglie la sessione) o con un tocco. */
@Composable
private fun BannerPostura(sessione: SessioneTelefono) {
    val avviso = sessione.avvisoPostura.ora() ?: return
    val (titolo, consiglio) = when (avviso) {
        ControlloPostura.Avviso.VICINO -> R.string.postura_vicino_titolo to R.string.postura_vicino_consiglio
        ControlloPostura.Avviso.FUORI -> R.string.postura_fuori_titolo to R.string.postura_fuori_consiglio
    }
    val suggerimento = stringResource(R.string.tocca_per_chiudere)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(16.dp)).background(Colori.pannello.copy(alpha = 0.94f))
            .clickable(onClickLabel = suggerimento) { sessione.nascondiAvvisoPostura() }
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Icon(Icons.Filled.Accessibility, contentDescription = null, tint = Colori.accentoChiaro)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(titolo), style = Caratteri.corpoForte(15), color = Colori.testo)
            Text(stringResource(consiglio), style = Caratteri.corpo(13), color = Colori.testoSecondario)
        }
    }
}

/** La pausa: piccola, non blocca nulla, resta finché dura. */
@Composable
private fun BannerPausa(sessione: SessioneTelefono) {
    val motivo = sessione.pausa.ora()
    if (sessione.stato != Stato.Collegato || motivo == null) return
    val (titolo, spiegazione) = when (motivo) {
        MotiviPausa.FACCIA_IN_GIU -> R.string.pausa_faccia_in_giu_titolo to R.string.pausa_faccia_in_giu_spiegazione
        MotiviPausa.NESSUNA_APP -> R.string.pausa_nessuna_app_titolo to R.string.pausa_nessuna_app_spiegazione
        MotiviPausa.UTENTE -> R.string.pausa_titolo to R.string.pausa_utente_spiegazione
        else -> R.string.pausa_titolo to R.string.pausa_spiegazione
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(16.dp)).background(Colori.pannello.copy(alpha = 0.94f))
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Icon(Icons.Filled.PauseCircle, contentDescription = null, tint = Colori.accentoChiaro)
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(titolo), style = Caratteri.corpoForte(15), color = Colori.testo)
            Text(stringResource(spiegazione), style = Caratteri.corpo(13), color = Colori.testoSecondario)
        }
    }
}

// MARK: Riconnessione, conferma, errore

/** Riconnessione chiara: da quanti secondi si cerca il computer, e «Riprova ora». */
@Composable
private fun BannerRiconnessione(sessione: SessioneTelefono) {
    val inizio = sessione.inizioRiconnessione ?: return
    var adesso by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(inizio) {
        while (true) {
            adesso = SystemClock.elapsedRealtime()
            delay(1_000)
        }
    }
    val secondi = ((adesso - inizio) / 1000).coerceAtLeast(0).toInt()
    val testo = when {
        !sessione.reteDisponibile -> stringResource(R.string.riconnessione_nessuna_rete)
        sessione.giaCollegato -> stringResource(R.string.riconnessione_computer_perso)
        else -> stringResource(R.string.riconnessione_non_riesco, sessione.computer.nome)
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(16.dp))
            .background(Colori.ambraTenue.copy(alpha = 0.95f)).padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        CircularProgressIndicator(color = Colori.ambraTesto, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(testo, style = Caratteri.corpoForte(15), color = Colori.ambraTesto)
            Text(
                if (secondi == 1) stringResource(R.string.da_un_secondo) else stringResource(R.string.da_secondi, secondi),
                style = Caratteri.numeri(12), color = Colori.ambraTesto,
            )
        }
        PillolaAzione(stringResource(R.string.riprova_ora)) { sessione.riprova() }
    }
}

/**
 * Prima volta con questo computer: lo stesso codice di conferma compare sul computer, che chiede «Consentire …?».
 * Si aspetta finché l'utente non risponde.
 */
@Composable
private fun PannelloConferma(sessione: SessioneTelefono, codice: String) {
    val cifre = codice.toCharArray().joinToString(" ")
    val descrizioneCodice = stringResource(R.string.codice_conferma_descrizione, cifre)
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(18.dp))
            .background(Colori.fondo.copy(alpha = 0.94f)).border(1.dp, Colori.accento, RoundedCornerShape(18.dp)).padding(18.dp)
            .verticalScroll(rememberScrollState()),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.Lock, contentDescription = null, tint = Colori.accento)
            Text(stringResource(R.string.conferma_titolo), style = Caratteri.titolo(28), color = Colori.testo)
        }
        Text(stringResource(R.string.conferma_testo, sessione.computer.nome), style = Caratteri.corpo(15), color = Colori.testoChiaro)
        Text(
            cifre,
            style = Caratteri.numeriEvidenti(46),
            color = Colori.testo,
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Colori.pannelloScuro).padding(vertical = 8.dp)
                .semantics { contentDescription = descrizioneCodice },
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(color = Colori.accento, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
            Text(stringResource(R.string.conferma_attesa), style = Caratteri.corpo(13), color = Colori.testoSecondario)
        }
    }
}

@Composable
private fun PannelloErrore(sessione: SessioneTelefono, descrizione: String, chiudi: () -> Unit, apriDomanda: (String) -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(16.dp))
            .background(Colori.fondo.copy(alpha = 0.92f)).padding(16.dp).verticalScroll(rememberScrollState()),
    ) {
        Text(sessione.titoloErrore, style = Caratteri.titolo(24), color = Colori.testo)
        Text(descrizione, style = Caratteri.corpo(15), color = Colori.testoTenue)
        sessione.domandaErrore?.let { domanda ->
            Box(Modifier.heightIn(min = 44.dp).clickable(role = Role.Button) { apriDomanda(domanda) }, contentAlignment = Alignment.CenterStart) {
                Text(stringResource(R.string.perche_succede), style = Caratteri.corpoForte(15), color = Colori.accentoChiaro)
            }
        }
        // Con il testo grande i due pulsanti vanno uno sotto l'altro, senza troncare.
        val grande = LocalDensity.current.fontScale > 1.3f
        val pulsanti: @Composable () -> Unit = {
            // Identità cambiata: riprovare non serve, si riabbina con il QR code dalla lista dei computer.
            if (!sessione.erroreDefinitivo) PillolaAzione(stringResource(R.string.riprova)) { sessione.riprova() }
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(50)).clickable(role = Role.Button, onClick = chiudi).padding(horizontal = 14.dp),
            ) { Text(stringResource(R.string.torna_ai_computer), style = Caratteri.corpoForte(15), color = Colori.testo) }
        }
        if (grande) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { pulsanti() }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { pulsanti() }
        }
    }
}

// MARK: Obiettivi e comandi

/** Gli obiettivi in basso, compatti. Il fondo è quasi pieno: la griglia non si vede passare sotto. */
@Composable
private fun SelettoreObiettivo(sessione: SessioneTelefono) {
    val obiettivi = sessione.obiettivi
    if (obiettivi.size < 2) return
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.clip(RoundedCornerShape(50)).background(Colori.fondo.copy(alpha = 0.9f)).padding(4.dp),
    ) {
        for (obiettivo in obiettivi) {
            val scelto = obiettivo == sessione.obiettivo
            val nome = nomeAccessibile(obiettivo)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.heightIn(min = 40.dp).widthIn(min = 40.dp).clip(RoundedCornerShape(50))
                    .background(if (scelto) Colori.testo else Color.Transparent)
                    .clickable(role = Role.RadioButton, onClickLabel = nome) { sessione.scegli(obiettivo) }
                    .semantics {
                        contentDescription = nome
                        selected = scelto
                    }
                    .padding(horizontal = if (obiettivo.nome == "frontale" || obiettivo.nome == "tele") 10.dp else 4.dp),
            ) {
                Text(etichettaObiettivo(obiettivo), style = Caratteri.numeriEvidenti(if (scelto) 13 else 12), color = if (scelto) Colori.fondo else Colori.testo, maxLines = 1)
            }
        }
    }
}

/** Come sull'iPhone: «0,5×», «1×», «Tele», «Frontale» nella lingua dell'app. */
@Composable
private fun etichettaObiettivo(obiettivo: ObiettivoAndroid): String = when (obiettivo.nome) {
    "grandangolo" -> stringResource(R.string.obiettivo_grandangolo_breve)
    "principale" -> "1×"
    "tele" -> stringResource(R.string.obiettivo_tele_breve)
    else -> stringResource(R.string.obiettivo_frontale_breve)
}

/** Per TalkBack: «0,5×» o «Tele» da soli non dicono molto. */
@Composable
private fun nomeAccessibile(obiettivo: ObiettivoAndroid): String = stringResource(
    when (obiettivo.nome) {
        "grandangolo" -> R.string.obiettivo_grandangolo
        "principale" -> R.string.obiettivo_principale
        "tele" -> R.string.obiettivo_tele
        else -> R.string.obiettivo_frontale
    },
)

/**
 * La colonna di pulsanti tondi a destra (Documenti/Interfaccia finale.md): Specchia · Sfoca sfondo · Microfono ·
 * Pausa · Luce (sul volto). Acceso = pieno nell'accento salvia con l'icona scura, mai corallo. Sfoca sfondo e Luce
 * compaiono solo se il telefono li sa fare. In orizzontale sui telefoni più bassi la colonna scorre.
 */
@Composable
private fun ColonnaComandi(sessione: SessioneTelefono, grande: Boolean, modifier: Modifier = Modifier) {
    val specchiato = sessione.specchiato.ora()
    val sfondo = sessione.sfondo.ora()
    val audio = sessione.audioRichiesto.ora()
    val inPausa = sessione.pausa.ora() == MotiviPausa.UTENTE
    val effetti = sessione.effetti.ora()
    val funzioni = sessione.funzioni.ora()
    val sfocato = sfondo == ModiSfondo.SFOCATO
    val acceso = stringResource(R.string.acceso)
    val spento = stringResource(R.string.spento)
    val lato = if (grande) 50.dp else 46.dp

    Column(
        verticalArrangement = Arrangement.spacedBy(if (grande) 10.dp else 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .clip(RoundedCornerShape(if (grande) 36.dp else 32.dp))
            .background(Colori.fondo.copy(alpha = 0.75f))
            .verticalScroll(rememberScrollState())
            .padding(if (grande) 10.dp else 8.dp),
    ) {
        // Specchia il video che arriva al computer, subito.
        PulsanteColonna(Icons.Filled.Flip, stringResource(R.string.specchia), lato, attivo = specchiato, stato = if (specchiato) acceso else spento) {
            sessione.impostaSpecchio(!specchiato)
        }
        // Un tocco: sfocato o niente, con l'intensità scelta nel foglio Effetti (anche dal computer). Solo se il
        // telefono sa separare la persona dallo sfondo.
        if (funzioni.sfondo) {
            PulsanteColonna(Icons.Filled.BlurOn, stringResource(R.string.sfoca_sfondo), lato, attivo = sfocato, stato = if (sfocato) acceso else spento) {
                sessione.scegliSfondo(if (sfocato) ModiSfondo.NESSUNO else ModiSfondo.SFOCATO)
            }
        }
        // Il microfono del telefono verso il computer. Senza permesso la sessione lo fa chiedere a MainActivity
        // (permessoMicrofonoDaChiedere), anche quando lo accende il computer.
        PulsanteColonna(
            if (audio) Icons.Filled.Mic else Icons.Filled.MicOff, stringResource(R.string.microfono_al_computer), lato,
            attivo = audio, stato = if (audio) acceso else spento,
        ) { sessione.impostaAudio(!audio) }
        // Il video si ferma, il collegamento resta (come a faccia in giù).
        PulsanteColonna(
            if (inPausa) Icons.Filled.PlayArrow else Icons.Filled.Pause,
            stringResource(if (inPausa) R.string.riprendi else R.string.pausa), lato, attivo = inPausa,
        ) { sessione.impostaPausaUtente(!inPausa) }
        // Luce sul volto (gratis): il viso si schiarisce in modo morbido e l'esposizione lo segue. La torcia sta
        // nelle Impostazioni.
        if (funzioni.volti) {
            PulsanteColonna(
                Icons.Filled.WbSunny, stringResource(R.string.luce_volto), lato,
                attivo = effetti.luceVolto, stato = if (effetti.luceVolto) acceso else spento,
            ) { sessione.applica(Comando(luceVolto = !effetti.luceVolto)) }
        }
    }
}

/** Un pulsante della colonna: spento scuro con l'icona chiara, acceso pieno nell'accento con l'icona scura. */
@Composable
private fun PulsanteColonna(icona: ImageVector, etichetta: String, lato: Dp, attivo: Boolean, stato: String? = null, azione: () -> Unit) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(lato)
            .clip(CircleShape)
            .background(if (attivo) Colori.accento else Colori.pannelloChiaro)
            .clickable(role = Role.Button, onClickLabel = etichetta, onClick = azione)
            .semantics {
                contentDescription = etichetta
                if (stato != null) stateDescription = stato
            },
    ) {
        Icon(icona, contentDescription = null, tint = if (attivo) Colori.fondo else Colori.testo, modifier = Modifier.size(22.dp))
    }
}
// MARK: Schermo oscurato

/** Schermo nero durante l'uso: il video continua, lo schermo non consuma. Doppio tocco per riaccenderlo. */
@Composable
private fun SchermoOscurato(sessione: SessioneTelefono, riaccendi: () -> Unit) {
    val collegato = sessione.stato == Stato.Collegato
    val colorePunto = when {
        !collegato -> Colori.ambra.copy(alpha = 0.7f)
        sessione.prontaCam2 -> Colori.accento.copy(alpha = 0.7f)
        // Anche a schermo spento il corallo compare solo quando un'app usa davvero la webcam.
        sessione.inOnda != null -> Colori.tally
        else -> Colori.verde.copy(alpha = 0.7f)
    }
    val testoStato = when {
        !collegato -> stringResource(R.string.oscurato_riconnessione)
        sessione.prontaCam2 -> stringResource(R.string.pronta_cam2)
        sessione.inOnda != null -> stringResource(R.string.oscurato_in_onda, sessione.computer.nome)
        else -> stringResource(R.string.oscurato_collegato, sessione.computer.nome)
    }
    val latenza = sessione.latenzaMs
    val qualita = latenza?.let { "${testoQualita(QualitaCollegamento.da(it, sessione.perditeRecenti))} · $it ms" } ?: "— ms"
    val tipo = sessione.tipoCollegamento?.let { testoTipoCollegamento(it) }
    val batteria = if (sessione.batteria >= 0) stringResource(R.string.oscurato_batteria, sessione.batteria) else stringResource(R.string.oscurato_batteria_ignota)
    val temperatura = stringResource(R.string.oscurato_temperatura, descrizioneTemperatura(sessione.temperatura))
    val riaccendiTesto = stringResource(R.string.riaccendi_schermo)
    val suggerimento = stringResource(R.string.oscurato_suggerimento)
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .pointerInput(sessione) { detectTapGestures(onDoubleTap = { riaccendi() }) }
            // Con TalkBack il doppio tocco arriva come attivazione: riaccende lo schermo.
            .semantics(mergeDescendants = true) {
                contentDescription = "$testoStato. $suggerimento"
                onClick(label = riaccendiTesto) { riaccendi(); true }
            },
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(colorePunto))
                Text(testoStato, style = Caratteri.etichetta(22), color = Colori.testoSecondario, textAlign = TextAlign.Center)
            }
            Text(listOfNotNull(qualita, tipo).joinToString("   "), style = Caratteri.numeri(13), color = Colori.testoSecondario, textAlign = TextAlign.Center)
            Text("$batteria   $temperatura", style = Caratteri.numeri(13), color = Colori.testoSecondario, textAlign = TextAlign.Center)
            Spacer(Modifier.height(18.dp))
            Text(suggerimento, style = Caratteri.corpo(14), color = Colori.testoSecondario, textAlign = TextAlign.Center)
        }
    }
}

@Composable
fun descrizioneTemperatura(temperatura: Temperatura): String = stringResource(
    when (temperatura) {
        Temperatura.NORMALE -> R.string.temperatura_normale
        Temperatura.CALDA -> R.string.temperatura_calda
        Temperatura.MOLTO_CALDA -> R.string.temperatura_molto_calda
        Temperatura.CRITICA -> R.string.temperatura_critica
    },
)
