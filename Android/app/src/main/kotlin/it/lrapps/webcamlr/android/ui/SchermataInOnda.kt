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
import androidx.compose.material.icons.filled.FlashlightOff
import androidx.compose.material.icons.filled.FlashlightOn
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.logica.ControlloPostura
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sessione.SessioneTelefono.Stato
import it.lrapps.webcamlr.android.video.ObiettivoAndroid
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.MotiviPausa
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import it.lrapps.webcamlr.protocollo.Temperatura
import it.lrapps.webcamlr.protocollo.TipoCollegamento
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/** I fogli che «In onda» apre sopra il video, uno alla volta. */
private enum class Foglio { Dettagli, Impostazioni, Effetti, Assistente, ControlliPro, Pro, Domanda }

/**
 * «In onda», come sull'iPhone dopo la 1.14: sopra il video solo una riga di stato (i numeri sono nei «Dettagli», con
 * un tocco sulla riga), un avviso alla volta che si chiude da solo, e sei pulsanti: Specchia, Sfoca sfondo, Microfono,
 * Torcia (solo se c'è), Pausa, Impostazioni; «Scollega» a parte, in fondo. Effetti, assistente e controlli Pro si
 * aprono dalle Impostazioni. Griglia, livella e riquadro del fuoco stanno solo sul video, mai sulle bande nere.
 * La sessione nasce quando si sceglie il computer (MainActivity): qui si mostra e si comanda. Lo schermo resta acceso;
 * dopo 30 secondi senza tocchi si oscura (luminosità al minimo e nero), come sull'iPhone.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SchermataInOnda(sessione: SessioneTelefono, chiudi: () -> Unit) {
    val context = LocalContext.current
    val vista = LocalView.current
    val verticale = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    val ambito = rememberCoroutineScope()
    val avvisi = remember { CodaAvvisi(ambito) }
    var ultimoTocco by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    var foglio by remember { mutableStateOf<Foglio?>(null) }
    var domanda by remember { mutableStateOf<String?>(null) }

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

        Row(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                RigaStato(sessione) { foglio = Foglio.Dettagli }
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
                // Il pulsante «Pausa», la faccia in giù, nessuna app: uno stato vero, resta finché dura.
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
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { SelettoreObiettivo(sessione) }
            }
            BarraComandi(sessione, chiudi = chiudi) { foglio = Foglio.Impostazioni }
        }

        if (sessione.oscurato) {
            SchermoOscurato(sessione) {
                sessione.oscurato = false
                ultimoTocco = SystemClock.elapsedRealtime()
            }
        }
    }

    // I fogli: a metà schermo Effetti e Controlli Pro (si vede l'anteprima sopra), gli altri alti.
    val aperto = foglio
    if (aperto != null) key(aperto) {
        val aMeta = aperto == Foglio.Effetti || aperto == Foglio.ControlliPro
        val stato = rememberModalBottomSheetState(skipPartiallyExpanded = !aMeta)
        val chiudiFoglio = { foglio = null }
        ModalBottomSheet(
            onDismissRequest = chiudiFoglio,
            sheetState = stato,
            containerColor = Colori.fondo,
            contentColor = Colori.testo,
            scrimColor = Color.Black.copy(alpha = if (aMeta) 0.15f else 0.45f),
        ) {
            when (aperto) {
                Foglio.Dettagli -> FoglioDettagli(sessione, chiudiFoglio)
                Foglio.Impostazioni -> FoglioImpostazioni(
                    sessione,
                    chiudi = chiudiFoglio,
                    apriFoglio = { scelto ->
                        foglio = when (scelto) {
                            FoglioSessione.Effetti -> Foglio.Effetti
                            FoglioSessione.Assistente -> Foglio.Assistente
                            FoglioSessione.ControlliPro -> Foglio.ControlliPro
                        }
                    },
                    apriPro = { foglio = Foglio.Pro },
                )
                Foglio.Effetti -> FoglioEffetti(sessione, chiudiFoglio) { foglio = Foglio.Pro }
                Foglio.Assistente -> FoglioAssistente(sessione, chiudiFoglio) { foglio = Foglio.Pro }
                Foglio.ControlliPro -> FoglioControlliPro(sessione, chiudiFoglio) { foglio = Foglio.Pro }
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
                    Text(String.format(java.util.Locale.getDefault(), "%.1f×", sessione.zoom), style = Caratteri.numeriEvidenti(17), color = Colori.testo)
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
 * Una riga sola: «● Collegato · MacBook» (o «● In onda», col punto corallo solo allora), il collegamento e le tacche
 * della qualità. Un tocco apre i «Dettagli». Se il nome non ci sta resta «Collegato»: mai troncato.
 */
@Composable
private fun RigaStato(sessione: SessioneTelefono, apriDettagli: () -> Unit) {
    val stato = sessione.stato
    val inOnda = sessione.inOnda
    val testo = when {
        stato == Stato.Collegato && inOnda != null -> inOnda.app?.let { stringResource(R.string.stato_in_onda_app, it) } ?: stringResource(R.string.in_onda)
        stato == Stato.Collegato -> stringResource(R.string.stato_collegato_a, sessione.computer.nome)
        stato == Stato.Collegamento -> stringResource(R.string.stato_collegamento)
        stato is Stato.Riconnessione -> stringResource(R.string.stato_riconnessione_tentativo, stato.tentativo, SessioneTelefono.TENTATIVI_MASSIMI)
        else -> stringResource(R.string.stato_scollegato)
    }
    val breve = when {
        stato == Stato.Collegato && inOnda != null -> stringResource(R.string.in_onda)
        stato == Stato.Collegato -> stringResource(R.string.stato_collegato)
        stato is Stato.Riconnessione -> stringResource(R.string.stato_riconnessione)
        else -> testo
    }
    val punto = when {
        // Il corallo solo quando un'app usa davvero la webcam.
        stato == Stato.Collegato && inOnda != null -> Colori.tally
        stato == Stato.Collegato -> Colori.verde
        stato == Stato.Collegamento || stato is Stato.Riconnessione -> Colori.ambra
        else -> Colori.testoTenue
    }
    val latenza = sessione.latenzaMs
    val qualita = QualitaCollegamento.da(latenza ?: 0, sessione.perditeRecenti)
    val parolaQualita = testoQualita(qualita)
    val etichetta = if (stato == Stato.Collegato && latenza != null) stringResource(R.string.stato_con_qualita, testo, parolaQualita.lowercase()) else testo
    val suggerimento = stringResource(R.string.mostra_dettagli)
    var usaBreve by remember(testo) { mutableStateOf(false) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .heightIn(min = 34.dp)
            .clip(RoundedCornerShape(50))
            .background(Colori.fondo.copy(alpha = 0.78f))
            .clickable(role = Role.Button, onClickLabel = suggerimento, onClick = apriDettagli)
            .semantics(mergeDescendants = true) {
                contentDescription = etichetta
                liveRegion = LiveRegionMode.Polite
            }
            .padding(horizontal = 12.dp, vertical = 4.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(punto))
        Text(
            (if (usaBreve) breve else testo).uppercase(),
            style = Caratteri.etichetta(16),
            color = Colori.testo,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier.weight(1f, fill = false),
            onTextLayout = { risultato -> if (risultato.hasVisualOverflow && !usaBreve) usaBreve = true },
        )
        if (stato == Stato.Collegato) {
            sessione.tipoCollegamento?.let { tipo ->
                Icon(iconaCollegamento(tipo), contentDescription = null, tint = Colori.testoSecondario, modifier = Modifier.size(14.dp))
            }
            if (latenza != null) TaccheQualita(qualita)
        }
    }
}

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
 * Sei pulsanti in alto, «Scollega» da solo in fondo. In orizzontale sui telefoni più bassi i pulsanti non stanno
 * tutti: allora la barra scorre.
 */
@Composable
private fun BarraComandi(sessione: SessioneTelefono, chiudi: () -> Unit, apriImpostazioni: () -> Unit) {
    val specchiato = sessione.specchiato.ora()
    val sfondo = sessione.sfondo.ora()
    val audio = sessione.audioRichiesto.ora()
    val inPausa = sessione.pausa.ora() == MotiviPausa.UTENTE
    val sfocato = sfondo == ModiSfondo.SFOCATO
    // «Sfoca sfondo» solo se il telefono sa separare la persona dallo sfondo (maschera pronta).
    val sfondoPossibile = sessione.funzioni.ora().sfondo
    // La torcia solo dove c'è: con la frontale sparisce, non resta grigia (si rilegge quando cambia l'obiettivo).
    val torciaDisponibile = sessione.obiettivo != null && sessione.haTorcia
    val controlliManuali = sessione.iso > 0 || sessione.tempo > 0
    val acceso = stringResource(R.string.acceso)
    val spento = stringResource(R.string.spento)

    Column(
        modifier = Modifier.fillMaxHeight(),
        verticalArrangement = Arrangement.SpaceBetween,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier
                .weight(1f, fill = false)
                .clip(RoundedCornerShape(30.dp))
                .background(Colori.fondo.copy(alpha = 0.82f))
                .verticalScroll(rememberScrollState())
                .padding(vertical = 12.dp, horizontal = 8.dp),
        ) {
            // Specchia il video che arriva al computer, subito; nell'accento quando è acceso.
            PulsanteTondo(Icons.Filled.Flip, stringResource(R.string.specchia), attivo = specchiato, statoAcceso = if (specchiato) acceso else spento) {
                sessione.impostaSpecchio(!specchiato)
            }
            // Un tocco: sfocato o niente, con l'intensità scelta nel foglio Effetti (anche dal computer).
            if (sfondoPossibile) {
                PulsanteTondo(Icons.Filled.BlurOn, stringResource(R.string.sfoca_sfondo), attivo = sfocato, statoAcceso = if (sfocato) acceso else spento) {
                    sessione.scegliSfondo(if (sfocato) ModiSfondo.NESSUNO else ModiSfondo.SFOCATO)
                }
            }
            // Il microfono del telefono verso il computer. Senza permesso la sessione lo fa chiedere a MainActivity
            // (permessoMicrofonoDaChiedere), anche quando lo accende il computer.
            PulsanteTondo(
                if (audio) Icons.Filled.Mic else Icons.Filled.MicOff, stringResource(R.string.microfono_al_computer),
                attivo = audio, statoAcceso = if (audio) acceso else spento,
            ) { sessione.impostaAudio(!audio) }
            if (torciaDisponibile) {
                PulsanteTondo(
                    if (sessione.torciaAccesa) Icons.Filled.FlashlightOn else Icons.Filled.FlashlightOff, stringResource(R.string.torcia),
                    attivo = sessione.torciaAccesa, statoAcceso = stringResource(if (sessione.torciaAccesa) R.string.accesa else R.string.spenta),
                ) { sessione.cambiaTorcia() }
            }
            // Il video si ferma, il collegamento resta (come a faccia in giù).
            PulsanteTondo(
                if (inPausa) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                stringResource(if (inPausa) R.string.riprendi else R.string.pausa), attivo = inPausa,
            ) { sessione.impostaPausaUtente(!inPausa) }
            // Le Impostazioni, e da lì effetti, inquadratura, assistente e controlli Pro.
            PulsanteTondo(Icons.Filled.Settings, stringResource(R.string.impostazioni), attivo = controlliManuali, azione = apriImpostazioni)
        }
        Spacer(Modifier.height(10.dp))
        val scollega = stringResource(R.string.scollega)
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.padding(horizontal = 8.dp).size(48.dp).clip(CircleShape).background(Colori.fondo.copy(alpha = 0.82f))
                .border(1.dp, Colori.bordo, CircleShape)
                .clickable(role = Role.Button, onClickLabel = scollega, onClick = chiudi)
                .semantics { contentDescription = scollega },
        ) {
            Icon(Icons.Filled.Close, contentDescription = null, tint = Colori.testo)
        }
    }
}

// MARK: Schermo oscurato

/** Schermo nero durante l'uso: il video continua, lo schermo non consuma. Doppio tocco per riaccenderlo. */
@Composable
private fun SchermoOscurato(sessione: SessioneTelefono, riaccendi: () -> Unit) {
    val collegato = sessione.stato == Stato.Collegato
    val colorePunto = when {
        !collegato -> Colori.ambra.copy(alpha = 0.7f)
        // Anche a schermo spento il corallo compare solo quando un'app usa davvero la webcam.
        sessione.inOnda != null -> Colori.tally
        else -> Colori.verde.copy(alpha = 0.7f)
    }
    val testoStato = when {
        !collegato -> stringResource(R.string.oscurato_riconnessione)
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
