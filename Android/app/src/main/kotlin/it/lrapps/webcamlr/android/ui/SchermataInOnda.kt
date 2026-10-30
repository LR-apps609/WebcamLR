package it.lrapps.webcamlr.android.ui

import android.app.Activity
import android.content.Context
import android.content.res.Configuration
import android.graphics.RectF
import android.os.Build
import android.os.SystemClock
import android.view.RoundedCorner
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.union
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
import androidx.compose.material.icons.filled.Cameraswitch
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
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material3.AlertDialog
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
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
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
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
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.logica.ControlloPostura
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sistema.Permessi
import it.lrapps.webcamlr.android.sistema.RegistroCollegamento
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.android.sessione.SessioneTelefono.Stato
import it.lrapps.webcamlr.android.video.ObiettivoAndroid
import it.lrapps.webcamlr.protocollo.ChiediEffetto
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.MotiviPausa
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import it.lrapps.webcamlr.protocollo.Temperatura
import it.lrapps.webcamlr.protocollo.TipoCollegamento
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sqrt

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
fun SchermataInOnda(
    sessione: SessioneTelefono,
    chiudi: () -> Unit,
    apriAltro: (VoceAltro) -> Unit,
    /** Vero quando «Scollega» nella notifica ha aperto l'app: si mostra la domanda della X. */
    richiestaScollega: Boolean = false,
    /** La domanda è a schermo: chi chiama spegne [richiestaScollega]. */
    richiestaVista: () -> Unit = {},
) {
    val context = LocalContext.current
    val vista = LocalView.current
    val verticale = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    val ambito = rememberCoroutineScope()
    // G2.2 e G2.8: ogni avviso nel registro; con TalkBack gli avvisi non si chiudono da soli.
    val avvisi = remember {
        CodaAvvisi(ambito, conLettore = { conTalkBack(context) }) { avviso ->
            RegistroCollegamento.aggiungi(Testi.testo(R.string.registro_avviso, avviso.testo))
        }
    }
    var ultimoTocco by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    var foglio by remember { mutableStateOf<Foglio?>(null) }
    var domanda by remember { mutableStateOf<String?>(null) }
    var vistaPulita by remember { mutableStateOf(false) }
    var confermaScollega by remember { mutableStateOf(false) }
    // Doppio tocco sull'anteprima in onda: non cambia fotocamera, lo dice un avviso (un numero nuovo a ogni gesto).
    var numeroDoppioTocco by remember { mutableIntStateOf(0) }
    var doppioToccoInOnda by remember { mutableStateOf(false) }
    LaunchedEffect(numeroDoppioTocco) {
        if (numeroDoppioTocco == 0) return@LaunchedEffect
        doppioToccoInOnda = true
        // Poco più dei 6 secondi dell'avviso.
        delay(7_000)
        doppioToccoInOnda = false
    }
    // P8: Specchia o Sfoca sfondo toccati con la posteriore: un avviso dice perché (un numero nuovo a ogni tocco).
    var numeroSoloFrontale by remember { mutableIntStateOf(0) }
    var soloFrontaleChiesto by remember { mutableStateOf(false) }
    LaunchedEffect(numeroSoloFrontale) {
        if (numeroSoloFrontale == 0) return@LaunchedEffect
        soloFrontaleChiesto = true
        delay(7_000)
        soloFrontaleChiesto = false
    }
    // G2.8: TalkBack acceso o spento mentre si è in onda: gli avvisi smettono (o riprendono) di chiudersi da soli.
    DisposableEffect(Unit) {
        val accessibilita = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        val ascolto = AccessibilityManager.TouchExplorationStateChangeListener { avvisi.lettoreCambiato() }
        accessibilita?.addTouchExplorationStateChangeListener(ascolto)
        onDispose { accessibilita?.removeTouchExplorationStateChangeListener(ascolto) }
    }

    // P1: Indietro in onda non scollega più da solo. Con lo schermo oscurato lo riaccende e basta; altrimenti la stessa
    // domanda della X. Un foglio aperto (ModalBottomSheet) o la domanda stessa si chiudono da sé, prima di arrivare qui.
    BackHandler {
        if (sessione.oscurato) {
            sessione.oscurato = false
            ultimoTocco = SystemClock.elapsedRealtime()
        } else {
            confermaScollega = true
        }
    }
    // «Scollega» nella notifica apre l'app qui, sulla domanda della X (MainActivity, [richiestaScollega]).
    LaunchedEffect(richiestaScollega) {
        if (!richiestaScollega) return@LaunchedEffect
        foglio = null
        if (sessione.oscurato) sessione.oscurato = false
        ultimoTocco = SystemClock.elapsedRealtime()
        confermaScollega = true
        richiestaVista()
    }

    // Schermo sempre acceso e barre di sistema nascoste mentre si è in onda. L'anteprima va da bordo a bordo, anche
    // attorno al foro della fotocamera (ritaglio del display), in verticale e in orizzontale: i comandi stanno nelle
    // zone sicure (vedi [margineSicuro]).
    DisposableEffect(Unit) {
        val finestra = (context as? Activity)?.window
        finestra?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val ritaglioPrima = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) finestra?.attributes?.layoutInDisplayCutoutMode else null
        if (finestra != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            finestra.attributes = finestra.attributes.apply {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        finestra?.let { WindowCompat.setDecorFitsSystemWindows(it, false) }
        val controllo = finestra?.let { WindowCompat.getInsetsController(it, vista) }
        controllo?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controllo?.hide(WindowInsetsCompat.Type.systemBars())
        onDispose {
            finestra?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (finestra != null && ritaglioPrima != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                finestra.attributes = finestra.attributes.apply { layoutInDisplayCutoutMode = ritaglioPrima }
            }
            // Da Android 15 (targetSdk 35) tutta l'app è già da bordo a bordo: si torna com'era solo prima.
            if (Build.VERSION.SDK_INT < 35) finestra?.let { WindowCompat.setDecorFitsSystemWindows(it, true) }
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

    val avvisiAttivi = avvisiAttivi(
        sessione, verticale, numeroDoppioTocco.takeIf { doppioToccoInOnda }, numeroSoloFrontale.takeIf { soloFrontaleChiesto },
    )
    // In verticale, con il foro o la tacca in alto al centro, la riga in alto sta ai suoi lati (vedi [misuraOrecchie]).
    val orecchie = misuraOrecchie()
    LaunchedEffect(avvisiAttivi.map { it.id }) { avvisi.aggiorna(avvisiAttivi) }
    // G2.2: il testo cambia con la condizione (la batteria scende): l'avviso a schermo e l'icona lo seguono.
    LaunchedEffect(avvisiAttivi.map { it.testo }) { avvisi.aggiornaTesti(avvisiAttivi) }

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
        AreaVideo(sessione, doppioToccoInOnda = { numeroDoppioTocco++ })

        // La X chiede conferma prima di scollegare (Ledion, 27 ottobre); la stessa domanda per Indietro e per «Scollega»
        // nella notifica. Dice cosa si ferma davvero: l'app che usa il video. Durante il codice di conferma non c'è
        // ancora un video: si annulla il collegamento.
        if (confermaScollega) {
            val inAttesaDelCodice = sessione.codiceConferma != null
            val app = sessione.inOnda?.app
            AlertDialog(
                onDismissRequest = { confermaScollega = false },
                title = {
                    Text(if (inAttesaDelCodice) stringResource(R.string.annulla_collegamento_domanda, sessione.computer.nome) else stringResource(R.string.scollega_domanda))
                },
                text = if (inAttesaDelCodice) null else {
                    {
                        Text(
                            if (app != null) stringResource(R.string.scollega_spiegazione_app, app) else stringResource(R.string.scollega_spiegazione),
                            style = Stili.corpo, color = Colori.testoChiaro,
                        )
                    }
                },
                confirmButton = {
                    PulsanteLink(stringResource(if (inAttesaDelCodice) R.string.annulla_collegamento else R.string.scollega)) {
                        confermaScollega = false
                        chiudi()
                    }
                },
                dismissButton = {
                    PulsanteLink(stringResource(if (inAttesaDelCodice) R.string.continua_ad_aspettare else R.string.annulla), tenue = true) {
                        confermaScollega = false
                    }
                },
            )
        }

        AnimatedVisibility(visible = !vistaPulita, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxSize()) {
                // Solo i margini sicuri veri (foro della fotocamera, barre): in orizzontale il lato senza foro non ne ha.
                Box(Modifier.fillMaxSize().margineSicuro()) {
                    // In alto: la pillola di stato a sinistra, Impostazioni e Scollega a filo nell'angolo in alto a destra
                    // (in orizzontale e sui telefoni senza ritaglio in alto al centro), staccati di poco dal bordo.
                    if (orecchie == null) Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Spazi.stretto),
                        modifier = Modifier.fillMaxWidth().align(Alignment.TopEnd).padding(start = Spazi.piccolo, end = Spazi.stretto, top = Spazi.stretto),
                    ) {
                        // La pillola prende lo spazio che resta, così i due pulsanti stanno sempre in fondo a destra; in
                        // verticale si distende, in orizzontale resta corta, a sinistra.
                        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                            RigaStato(sessione, distesa = verticale, modifier = if (verticale) Modifier.fillMaxWidth() else Modifier) { foglio = Foglio.Dettagli }
                        }
                        // G2.2: gli avvisi chiusi la cui causa c'è ancora, come icone ambra.
                        IconeAvvisi(avvisi)
                        Row(horizontalArrangement = Arrangement.spacedBy(Spazi.stretto)) {
                            PulsanteTondo(Icons.Filled.Settings, stringResource(R.string.impostazioni), sopraIlVideo = true) { foglio = Foglio.Impostazioni }
                            PulsanteTondo(Icons.Filled.Close, stringResource(R.string.scollega), sopraIlVideo = true) { confermaScollega = true }
                        }
                    }
                    Box(Modifier.fillMaxSize().padding(horizontal = Spazi.piccolo, vertical = Spazi.piccolo)) {
                        // Avvisi e pannelli a sinistra della colonna, tra la pillola e gli obiettivi.
                        Column(
                            Modifier.fillMaxSize().absolutePadding(top = orecchie?.sporgenza ?: SOTTO_LA_RIGA, right = larghezzaColonna(verticale) + Spazi.stretto, bottom = SOPRA_GLI_OBIETTIVI),
                            verticalArrangement = Arrangement.spacedBy(Spazi.stretto),
                        ) {
                            // Con la riga nelle orecchie le icone degli avvisi ridotti stanno qui, subito sotto il foro.
                            if (orecchie != null) IconeAvvisi(avvisi)
                            if (sessione.aeafBloccati) {
                                val descrizione = stringResource(R.string.aeaf_bloccati_descrizione)
                                Box(
                                    Modifier.clip(RoundedCornerShape(Raggi.capsula)).background(Colori.ambra)
                                        .semantics { contentDescription = descrizione }.padding(horizontal = Spazi.piccolo, vertical = Spazi.minimo),
                                ) { Text(stringResource(R.string.aeaf_bloccati), style = Stili.etichetta, color = Colori.fondo) }
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

                        // A destra la colonna dei pulsanti tondi, sempre: anche con il telefono in una lingua da destra a
                        // sinistra (la direzione del testo non la sposta).
                        ColonnaComandi(
                            sessione, grande = verticale,
                            modifier = Modifier.align(AbsoluteAlignment.CenterRight).padding(top = SOTTO_LA_RIGA, bottom = SOPRA_GLI_OBIETTIVI),
                            soloFrontale = { numeroSoloFrontale++ },
                        )
                    }
                }
                orecchie?.let { o ->
                    RigaOrecchie(
                        sessione, o,
                        apriDettagli = { foglio = Foglio.Dettagli },
                        apriImpostazioni = { foglio = Foglio.Impostazioni },
                        scollega = { confermaScollega = true },
                    )
                }
                // In basso gli obiettivi, centrati sull'asse dello schermo: in orizzontale il foro della fotocamera sta da
                // un lato solo, quindi qui il margine è lo stesso a sinistra e a destra.
                Box(
                    Modifier.fillMaxSize().margineSicuro(simmetrico = true).padding(bottom = if (verticale) Spazi.ampio else Spazi.medio),
                    contentAlignment = Alignment.BottomCenter,
                ) { SelettoreObiettivo(sessione) }
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
            scrimColor = Veli.coloreLieve,
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
                        apriDomanda = { id ->
                            domanda = id
                            foglio = Foglio.Domanda
                        },
                    ),
                )
                Foglio.Pro -> FoglioPro(chiudiFoglio)
                Foglio.Domanda -> FoglioDomanda(domanda, chiudiFoglio)
            }
        }
    }
}

/**
 * Le «orecchie» ai lati del ritaglio in alto al centro (foro, isola o tacca): in verticale la riga in alto sta alla
 * stessa altezza del ritaglio, come ora e batteria nella barra di stato, mai sopra o sotto. A sinistra la pillola corta
 * «● Wi-Fi», a destra Impostazioni e Scollega. Le misure vengono dal rettangolo vero del ritaglio
 * ([android.view.DisplayCutout.getBoundingRects]), non da una stima, e dagli angoli arrotondati dello schermo.
 */
private class Orecchie(
    /** Distanza dall'alto della riga (alta [ALTEZZA_ORECCHIE]), centrata sul ritaglio finché non esce dallo schermo. */
    val alto: Dp,
    val margineSinistro: Dp,
    val margineDestro: Dp,
    /** Spazio per la pillola, dal margine sinistro al ritaglio. */
    val larghezzaSinistra: Dp,
    /** Di quanto la riga scende sotto il margine sicuro in alto (di solito niente): lì sotto partono gli avvisi. */
    val sporgenza: Dp,
)

/** Altezza della riga nelle orecchie: l'area di tocco minima dei pulsanti. */
private val ALTEZZA_ORECCHIE = Misure.areaTocco

/** I pulsanti nelle orecchie: un po' più piccoli a vedersi, l'area di tocco resta [ALTEZZA_ORECCHIE]. */
private val DIAMETRO_ORECCHIE = Misure.tondoOrecchie

/** Lo stacco tra il ritaglio e ciò che gli sta accanto. */
private val STACCO_DAL_RITAGLIO = Spazi.stretto

/** Dove partono avvisi e colonna, sotto la riga in alto (pulsanti tondi e il loro margine). */
private val SOTTO_LA_RIGA = Misure.tondo + Spazi.stretto

/** Dove finiscono avvisi e colonna, sopra gli obiettivi. */
private val SOPRA_GLI_OBIETTIVI = Misure.tondo + Spazi.stretto

/** Lo spazio attorno ai pulsanti della colonna: più largo in verticale. */
private fun spazioColonna(verticale: Boolean) = if (verticale) Spazi.piccolo else Spazi.stretto

/** La larghezza della colonna dei comandi: un pulsante tondo e lo spazio ai due lati. */
private fun larghezzaColonna(verticale: Boolean) = Misure.tondo + spazioColonna(verticale) * 2

/**
 * Le [Orecchie], oppure `null` (resta la riga di oggi, sotto il ritaglio): in orizzontale, prima di Android 9, senza
 * un ritaglio in alto al centro (nessun foro, o foro in un angolo) o se ingranaggio e X non ci stanno a destra.
 */
@Composable
private fun misuraOrecchie(): Orecchie? {
    val densita = LocalDensity.current
    val direzione = LocalLayoutDirection.current
    val verticale = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    // I margini di Compose si leggono anche per ricomporre quando cambiano quelli della finestra, che non si osservano.
    val zone = WindowInsets.displayCutout.union(WindowInsets.systemBars)
    val sinistraZone = zone.getLeft(densita, direzione)
    val destraZone = zone.getRight(densita, direzione)
    val altoZone = zone.getTop(densita)
    val vista = LocalView.current
    if (!verticale || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
    val margini = vista.rootWindowInsets ?: return null
    val ritaglioSchermo = margini.displayCutout ?: return null
    val larghezza = vista.rootView.width
    if (larghezza <= 0) return null
    // Il ritaglio che tocca il bordo in alto, centrato (con un po' di tolleranza) e stretto: foro, isola o tacca.
    val ritaglio = ritaglioSchermo.boundingRects.firstOrNull { r ->
        !r.isEmpty && r.top <= r.height() / 2 && r.width() < larghezza / 2 &&
            abs(r.exactCenterX() - larghezza / 2f) <= larghezza * 0.1f
    } ?: return null
    val barraStato = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        margini.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.statusBars()).top
    } else {
        0
    }
    val altoSicuro = maxOf(altoZone, ritaglioSchermo.safeInsetTop, barraStato)
    with(densita) {
        val altezza = ALTEZZA_ORECCHIE.toPx()
        val alto = maxOf(0f, ritaglio.exactCenterY() - altezza / 2)
        // Negli angoli arrotondati dello schermo il bordo rientra: quanto, all'altezza del bordo visibile della riga.
        val bordoVisibile = alto + (ALTEZZA_ORECCHIE - DIAMETRO_ORECCHIE).toPx() / 2
        fun rientro(angolo: Int): Float {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0f
            val raggio = margini.getRoundedCorner(angolo)?.radius?.toFloat() ?: return 0f
            if (bordoVisibile >= raggio) return 0f
            val verticaleDalCentro = raggio - bordoVisibile
            return raggio - sqrt(raggio * raggio - verticaleDalCentro * verticaleDalCentro)
        }
        val sinistro = maxOf(Spazi.piccolo.toPx(), sinistraZone.toFloat(), rientro(RoundedCorner.POSITION_TOP_LEFT) + Spazi.minimo.toPx())
        val destro = maxOf(Spazi.stretto.toPx(), destraZone.toFloat(), rientro(RoundedCorner.POSITION_TOP_RIGHT) + Spazi.minimo.toPx())
        val stacco = STACCO_DAL_RITAGLIO.toPx()
        val orecchiaSinistra = ritaglio.left - stacco - sinistro
        val orecchiaDestra = larghezza - ritaglio.right - stacco - destro
        // A destra due aree di tocco intere; a sinistra almeno il punto con l'icona Wi-Fi o USB.
        if (orecchiaDestra < (ALTEZZA_ORECCHIE * 2 + Spazi.minimo).toPx() || orecchiaSinistra < ALTEZZA_ORECCHIE.toPx()) return null
        return Orecchie(
            alto = alto.toDp(),
            margineSinistro = sinistro.toDp(),
            margineDestro = destro.toDp(),
            larghezzaSinistra = orecchiaSinistra.toDp(),
            sporgenza = maxOf(0f, alto + altezza - altoSicuro).toDp(),
        )
    }
}

/**
 * Le zone sicure di «In onda»: fuori dal foro della fotocamera o dalla tacca (ritaglio del display) e dalle barre di
 * sistema, in verticale e in orizzontale, nelle due rotazioni. Mai testo o pulsanti lì sotto. `simmetrico`: a sinistra
 * e a destra lo stesso margine (il più grande dei due), così ciò che è centrato resta sull'asse dello schermo.
 * Oltre ai margini di Compose si leggono quelli veri della finestra (il ritaglio anche con le barre nascoste) e, in
 * verticale, l'altezza della barra di stato anche se è nascosta: tutta la riga in alto sta sotto il foro o l'isola.
 */
@Composable
private fun Modifier.margineSicuro(simmetrico: Boolean = false): Modifier {
    val zone = WindowInsets.displayCutout.union(WindowInsets.systemBars)
    val densita = LocalDensity.current
    val direzione = LocalLayoutDirection.current
    val verticale = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    val margini = LocalView.current.rootWindowInsets
    val ritaglio = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) margini?.displayCutout else null
    val barraStato = if (verticale && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        margini?.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.statusBars())?.top ?: 0
    } else {
        0
    }
    val sinistra = maxOf(zone.getLeft(densita, direzione), ritaglio?.safeInsetLeft ?: 0)
    val destra = maxOf(zone.getRight(densita, direzione), ritaglio?.safeInsetRight ?: 0)
    val alto = maxOf(zone.getTop(densita), ritaglio?.safeInsetTop ?: 0, barraStato)
    val basso = maxOf(zone.getBottom(densita), ritaglio?.safeInsetBottom ?: 0)
    val lato = maxOf(sinistra, destra)
    return with(densita) {
        absolutePadding(
            left = (if (simmetrico) lato else sinistra).toDp(),
            top = alto.toDp(),
            right = (if (simmetrico) lato else destra).toDp(),
            bottom = basso.toDp(),
        )
    }
}

private fun conTalkBack(context: Context): Boolean {
    val accessibilita = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
    return accessibilita?.isTouchExplorationEnabled == true
}

// MARK: Il video

/**
 * L'anteprima a tutto schermo: il Renderizzatore ci disegna il video inviato girato per lo schermo e ingrandito fino a
 * riempirlo, come la Fotocamera (niente bande nere; i bordi in più si tagliano solo qui, il computer riceve il video
 * intero). Griglia, livella, riquadro del fuoco e zoom stanno nella parte del video che si vede
 * ([SessioneTelefono.rettangoloVideo]). I gesti su tutta l'anteprima (la sessione toglie il ritaglio): tocco = messa a
 * fuoco, tocco lungo = Blocco AE/AF, doppio tocco = cambia fotocamera, pizzico = zoom.
 */
@Composable
private fun AreaVideo(sessione: SessioneTelefono, doppioToccoInOnda: () -> Unit) {
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
    // In onda il doppio tocco non cambia fotocamera: la descrizione per TalkBack non lo promette.
    val descrizione = stringResource(if (sessione.inOnda != null) R.string.anteprima_descrizione_in_onda else R.string.anteprima_descrizione)
    val avvisaDoppioTocco by rememberUpdatedState(doppioToccoInOnda)
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
                        // In onda un doppio tocco per sbaglio (anche pulendo lo schermo) non gira la ripresa: lo dice un
                        // avviso con il gesto giusto. Fuori onda cambia fotocamera, come prima.
                        onDoubleTap = { if (sessione.inOnda != null) avvisaDoppioTocco() else sessione.cambiaFotocamera() },
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
                    modifier = Modifier.clip(RoundedCornerShape(Raggi.capsula)).background(Veli.coloreMedio).padding(horizontal = Spazi.piccolo),
                ) {
                    Text(String.format(Testi.locale, "%.1f×", sessione.zoom), style = Stili.numeriCorpo, color = Colori.testo, modifier = Modifier.padding(vertical = Spazi.stretto))
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
 * Ciò che dice la pillola di stato: testo, testo breve, colore del punto ed etichetta completa per TalkBack. G2.1:
 * `tono` in onda (corallo pieno) o in pausa (ambra), per la [PillolaStato] da lontano; `null` negli altri stati.
 */
private data class StatoPillola(val testo: String, val breve: String, val punto: Color, val etichetta: String, val tono: TonoPillola? = null)

@Composable
private fun statoPillola(sessione: SessioneTelefono): StatoPillola {
    val stato = sessione.stato
    val inOnda = sessione.inOnda
    val cam2 = sessione.prontaCam2
    // A1: video in pausa (qualsiasi motivo): «In pausa» in ambra, mai il corallo di «In onda».
    val motivoPausa = sessione.pausa.ora()
    val inPausa = stato == Stato.Collegato && motivoPausa != null
    val testo = when {
        inPausa -> stringResource(R.string.pausa_titolo)
        cam2 -> stringResource(R.string.pronta_cam2)
        stato == Stato.Collegato && inOnda != null -> stringResource(R.string.stato_in_onda_app, sessione.computer.nome)
        stato == Stato.Collegato -> stringResource(R.string.stato_collegato_a, sessione.computer.nome)
        stato == Stato.Collegamento -> stringResource(R.string.stato_collegamento)
        // Non più «Riconnessione 2/5»: i secondi li aggiunge la riga, come il banner.
        stato is Stato.Riconnessione -> stringResource(R.string.stato_mi_ricollego)
        else -> stringResource(R.string.stato_scollegato)
    }
    val breve = when {
        inPausa -> testo
        cam2 -> stringResource(R.string.pronta_cam2)
        stato == Stato.Collegato && inOnda != null -> stringResource(R.string.in_onda)
        stato == Stato.Collegato -> stringResource(R.string.stato_collegato)
        else -> testo
    }
    val tono = when {
        inPausa -> TonoPillola.PAUSA
        !cam2 && stato == Stato.Collegato && inOnda != null -> TonoPillola.IN_ONDA
        else -> null
    }
    val punto = when {
        inPausa -> Colori.ambra
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
    return StatoPillola(testo, breve, punto, etichetta, tono)
}

/**
 * La pillola di stato: «● IN ONDA · MACBOOK AIR … Ottima» (col punto corallo solo quando un'app usa la webcam),
 * altrimenti «● COLLEGATO · MACBOOK AIR». `distesa`: prende tutta la riga, con la qualità in fondo a destra (in
 * verticale). Un tocco apre i «Dettagli». Se il nome non ci sta resta «In onda» o «Collegato»: mai troncato.
 */
@Composable
private fun RigaStato(sessione: SessioneTelefono, distesa: Boolean, modifier: Modifier = Modifier, apriDettagli: () -> Unit) {
    val stato = sessione.stato
    val (testo, breve, punto, etichetta, tono) = statoPillola(sessione)
    val latenza = sessione.latenzaMs
    val qualita = QualitaCollegamento.da(latenza ?: 0, sessione.perditeRecenti)
    val parolaQualita = testoQualita(qualita)
    val suggerimento = stringResource(R.string.mostra_dettagli)
    var usaBreve by remember(testo) { mutableStateOf(false) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spazi.stretto),
        modifier = modifier
            .heightIn(min = 40.dp)
            .clip(RoundedCornerShape(Raggi.capsula))
            .background(Veli.coloreMedio)
            .clickable(role = Role.Button, onClickLabel = suggerimento, onClick = apriDettagli)
            .semantics(mergeDescendants = true) {
                contentDescription = etichetta
                liveRegion = LiveRegionMode.Polite
            }
            .padding(start = if (tono != null) Spazi.stretto else Spazi.medio, end = Spazi.medio, top = Spazi.stretto, bottom = Spazi.stretto),
    ) {
        val misura = { risultato: androidx.compose.ui.text.TextLayoutResult -> if (risultato.hasVisualOverflow && !usaBreve) usaBreve = true }
        if (tono != null) {
            // G2.1: in onda (o in pausa) la pillola piena, «IN ONDA» sempre scritto; se non ci sta si toglie il nome.
            Box(Modifier.weight(1f, fill = distesa), contentAlignment = Alignment.CenterStart) {
                PillolaStato(if (usaBreve) breve else testo, tono, misuraTesto = misura)
            }
        } else {
            Box(Modifier.size(Misure.punto).clip(CircleShape).background(punto))
            Text(
                (if (usaBreve) breve else testo).uppercase(),
                style = Stili.etichetta,
                color = Colori.testo,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.weight(1f, fill = distesa),
                onTextLayout = misura,
            )
        }
        SecondiRiconnessione(sessione)
        if (stato == Stato.Collegato) {
            // «Wi-Fi» o «USB»: per quale strada arriva il video (non nella vista pulita).
            sessione.tipoCollegamento?.let { tipo ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.minimo)) {
                    Icon(iconaCollegamento(tipo), contentDescription = null, tint = Colori.testoSecondario, modifier = Modifier.size(14.dp))
                    Text(stradaBreve(tipo), style = Stili.sezione, color = Colori.testoSecondario, maxLines = 1, softWrap = false)
                }
            }
            if (latenza != null) Text(parolaQualita, style = Stili.notaForte, color = coloreQualita(qualita), maxLines = 1)
        }
    }
}

/**
 * «Mi ricollego…» con i secondi, come il banner (al posto di «Riconnessione 2/5»). I secondi non entrano
 * nell'etichetta per TalkBack: la riga è una regione viva e li annuncerebbe a ogni secondo.
 */
@Composable
private fun SecondiRiconnessione(sessione: SessioneTelefono) {
    val inizio = sessione.inizioRiconnessione
    if (sessione.stato !is Stato.Riconnessione || inizio == null) return
    var adesso by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(inizio) {
        while (true) {
            adesso = SystemClock.elapsedRealtime()
            delay(1_000)
        }
    }
    val secondi = ((adesso - inizio) / 1000).coerceAtLeast(0)
    Text(
        stringResource(R.string.secondi_breve, secondi.toInt()),
        style = Stili.numeri, color = Colori.ambraTesto, maxLines = 1, softWrap = false,
        modifier = Modifier.clearAndSetSemantics { },
    )
}

/**
 * La riga in alto nelle orecchie (vedi [Orecchie]): a sinistra la pillola corta, a destra Impostazioni e Scollega.
 * Sempre a sinistra e a destra dello schermo, anche in una lingua da destra a sinistra, come la colonna dei comandi.
 */
@Composable
private fun RigaOrecchie(
    sessione: SessioneTelefono,
    orecchie: Orecchie,
    apriDettagli: () -> Unit,
    apriImpostazioni: () -> Unit,
    scollega: () -> Unit,
) {
    Box(Modifier.fillMaxWidth().absolutePadding(top = orecchie.alto).height(ALTEZZA_ORECCHIE)) {
        Box(
            Modifier.align(AbsoluteAlignment.CenterLeft).absolutePadding(left = orecchie.margineSinistro)
                .widthIn(max = orecchie.larghezzaSinistra),
        ) { PillolaOrecchia(sessione, apriDettagli) }
        Row(
            horizontalArrangement = Arrangement.spacedBy(Spazi.minimo),
            modifier = Modifier.align(AbsoluteAlignment.CenterRight).absolutePadding(right = orecchie.margineDestro),
        ) {
            PulsanteTondo(Icons.Filled.Settings, stringResource(R.string.impostazioni), sopraIlVideo = true, diametro = DIAMETRO_ORECCHIE, azione = apriImpostazioni)
            PulsanteTondo(Icons.Filled.Close, stringResource(R.string.scollega), sopraIlVideo = true, diametro = DIAMETRO_ORECCHIE, azione = scollega)
        }
    }
}

/**
 * La pillola corta nell'orecchia sinistra: «● Wi-Fi» o «● USB», col punto della pillola di sempre (verde collegato,
 * corallo in onda, ambra in riconnessione). Se la parola non ci sta resta il punto con l'icona. Il testo lungo (stato,
 * nome del computer, qualità) sta nei «Dettagli», che si aprono con un tocco, e nell'etichetta per TalkBack.
 */
@Composable
private fun PillolaOrecchia(sessione: SessioneTelefono, apriDettagli: () -> Unit) {
    val (_, breve, punto, etichetta, tono) = statoPillola(sessione)
    val tipo = sessione.tipoCollegamento
    val suggerimento = stringResource(R.string.mostra_dettagli)
    var soloIcona by remember(tipo) { mutableStateOf(false) }
    var piccola by remember(breve) { mutableStateOf(false) }
    Box(
        contentAlignment = Alignment.CenterStart,
        modifier = Modifier
            .heightIn(min = ALTEZZA_ORECCHIE)
            .widthIn(min = ALTEZZA_ORECCHIE)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClickLabel = suggerimento,
                onClick = apriDettagli,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = etichetta
                liveRegion = LiveRegionMode.Polite
            },
    ) {
        // G2.1: in onda (o in pausa) «IN ONDA» sempre scritto nella pillola piena, anche qui (prima solo «● Wi-Fi»);
        // la strada resta nei Dettagli e per TalkBack. Se non ci sta, la pillola più piccola.
        if (tono != null) {
            PillolaStato(
                breve, tono, misura = if (piccola) MisuraPillola.PICCOLA else MisuraPillola.NORMALE,
                misuraTesto = { risultato -> if (risultato.hasVisualOverflow) piccola = true },
            )
        } else Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spazi.stretto),
            modifier = Modifier.heightIn(min = DIAMETRO_ORECCHIE).clip(RoundedCornerShape(Raggi.capsula))
                .background(Veli.coloreMedio).padding(horizontal = Spazi.piccolo),
        ) {
            Box(Modifier.size(Misure.punto).clip(CircleShape).background(punto))
            if (tipo != null) {
                if (soloIcona) {
                    Icon(iconaCollegamento(tipo), contentDescription = null, tint = Colori.testo, modifier = Modifier.size(16.dp))
                } else {
                    Text(
                        stradaBreve(tipo),
                        style = Stili.etichetta,
                        color = Colori.testo,
                        maxLines = 1,
                        softWrap = false,
                        onTextLayout = { risultato -> if (risultato.hasVisualOverflow) soloIcona = true },
                    )
                }
            }
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
    PulsantePieno(
        stringResource(R.string.usa_prospettiva),
        modifier.widthIn(max = 520.dp).semantics { stateDescription = suggerimento },
        azione = azione,
    )
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
    val (testo, breve, _, _, tono) = statoPillola(sessione)
    var usaBreve by remember(testo) { mutableStateOf(false) }
    Box(
        Modifier.fillMaxSize()
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClickLabel = etichetta, onClick = mostraComandi)
            // Lo stesso margine ai due lati: il suggerimento in basso resta sull'asse dello schermo.
            .margineSicuro(simmetrico = true).padding(horizontal = Spazi.piccolo, vertical = Spazi.piccolo),
    ) {
        // G2.1: in onda (o in pausa) la pillola grande, etichetta 56 in una capsula alta almeno 88; se non ci sta, senza
        // il nome. Gli altri stati restano piccoli.
        if (tono != null) {
            PillolaStato(
                if (usaBreve) breve else testo, tono, misura = MisuraPillola.GRANDE,
                modifier = Modifier.align(Alignment.TopStart).padding(start = Spazi.ampio, top = Spazi.stretto),
                misuraTesto = { risultato -> if (risultato.hasVisualOverflow && !usaBreve) usaBreve = true },
            )
        } else Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spazi.stretto),
            modifier = Modifier.align(Alignment.TopStart).padding(start = Spazi.ampio, top = Spazi.stretto).clip(RoundedCornerShape(Raggi.capsula))
                .background(Veli.coloreLieve).padding(horizontal = Spazi.piccolo, vertical = Spazi.stretto),
        ) {
            Box(Modifier.size(Misure.punto).clip(CircleShape).background(if (cam2) Colori.accento else if (inOnda) Colori.tally else Colori.verde))
            Text(
                stringResource(if (cam2) R.string.pronta_cam2 else if (inOnda) R.string.in_onda else R.string.stato_collegato).uppercase(),
                style = Stili.sezione, color = Colori.testo, maxLines = 1,
            )
        }
        Text(
            stringResource(R.string.tocca_per_i_comandi),
            style = Stili.nota,
            color = Colori.testoTenue,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = Spazi.stretto).clip(RoundedCornerShape(Raggi.capsula))
                .background(Veli.coloreLieve).padding(horizontal = Spazi.piccolo, vertical = Spazi.stretto),
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
private fun avvisiAttivi(sessione: SessioneTelefono, verticale: Boolean, doppioTocco: Int?, soloFrontale: Int?): List<CodaAvvisi.Avviso> {
    val microfono = sessione.avvisoMicrofono.ora()
    val microfonoNonConsentito = sessione.microfonoNonConsentito.ora()
    val chiamata = sessione.chiamataInCorso.ora()
    val annuncio = sessione.annuncio.ora()
    if (sessione.stato != Stato.Collegato) return emptyList()
    val elenco = mutableListOf<CodaAvvisi.Avviso>()
    // Risposta a un gesto (doppio tocco in onda): si vede subito, al posto di quello a schermo.
    if (doppioTocco != null) {
        elenco += CodaAvvisi.Avviso("doppio-tocco-$doppioTocco", stringResource(R.string.avviso_doppio_tocco_in_onda), Icons.Filled.TouchApp, suggerimento = true, priorita = 8, subito = true)
    }
    // P8: Specchia o Sfoca sfondo toccati con la posteriore.
    if (soloFrontale != null) {
        elenco += CodaAvvisi.Avviso("solo-frontale-$soloFrontale", stringResource(R.string.avviso_solo_frontale), Icons.Filled.Cameraswitch, suggerimento = true, priorita = 8, subito = true)
    }
    // Fissi: restano finché la causa c'è.
    if (sessione.servizioRifiutato) {
        // P4: con le restrizioni della batteria la causa più probabile è quella, e si toglie da Impostazioni.
        if (Permessi.senzaLimitiBatteria) {
            elenco += CodaAvvisi.Avviso("servizio", stringResource(R.string.avviso_servizio_rifiutato), Icons.Filled.Lock, suggerimento = false, priorita = 7, fisso = true)
        } else {
            elenco += CodaAvvisi.Avviso(
                "servizio", stringResource(R.string.batteria_limitata), Icons.Filled.BatteryAlert, suggerimento = false, priorita = 7,
                fisso = true, azione = CodaAvvisi.Azione.BATTERIA,
            )
        }
    }
    if (chiamata) {
        elenco += CodaAvvisi.Avviso("chiamata", stringResource(R.string.chiamata_in_corso), Icons.Filled.MicOff, suggerimento = false, priorita = 6, fisso = true)
    }
    // Una notizia buona («Microfono di nuovo attivo.», «Il video si era fermato per…»): un argomento nuovo ogni volta.
    if (annuncio != null) {
        val icona = if (annuncio.delMicrofono) Icons.Filled.Mic else Icons.Filled.PlayArrow
        elenco += CodaAvvisi.Avviso("annuncio-${annuncio.numero}", annuncio.testo, icona, suggerimento = true, priorita = 6)
    }
    // P3: permesso del microfono negato. Resta con «Apri Impostazioni» finché non si tocca (poi è un'icona).
    if (microfonoNonConsentito) {
        elenco += CodaAvvisi.Avviso(
            "microfono-negato", stringResource(R.string.microfono_non_consentito), Icons.Filled.MicOff, suggerimento = false, priorita = 5,
            fisso = true, persiste = true, azione = CodaAvvisi.Azione.IMPOSTAZIONI_APP,
        )
    }
    if (microfono != null) {
        elenco += CodaAvvisi.Avviso("microfono", microfono, Icons.Filled.MicOff, suggerimento = false, priorita = 5, persiste = true)
    }
    if (sessione.qualitaRidotta) {
        elenco += CodaAvvisi.Avviso("caldo", stringResource(R.string.avviso_caldo), Icons.Filled.Thermostat, suggerimento = false, priorita = 4, persiste = true)
    }
    // A3: al 10% un avviso nuovo (un altro argomento), che si vede di nuovo anche se quello del 20% era un'icona.
    if (sessione.batteriaBassa && sessione.batteria <= 10) {
        elenco += CodaAvvisi.Avviso("batteria-10", stringResource(R.string.avviso_batteria_10), Icons.Filled.BatteryAlert, suggerimento = false, priorita = 5, persiste = true)
    } else if (sessione.batteriaBassa) {
        val testo = if (sessione.risparmioBatteria) stringResource(R.string.avviso_batteria_risparmio, sessione.batteria) else stringResource(R.string.avviso_batteria, sessione.batteria)
        elenco += CodaAvvisi.Avviso("batteria", testo, Icons.Filled.BatteryAlert, suggerimento = false, priorita = 4, persiste = true)
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
        elenco += CodaAvvisi.Avviso("rete", rete, Icons.Filled.NetworkCheck, suggerimento = false, priorita = 3, persiste = true)
    }
    if (verticale) {
        elenco += CodaAvvisi.Avviso("orizzontale", stringResource(R.string.avviso_orizzontale), Icons.Filled.ScreenRotation, suggerimento = true, priorita = 1)
    }
    return elenco
}

@Composable
private fun VistaAvviso(avviso: CodaAvvisi.Avviso, chiudi: () -> Unit) {
    val context = LocalContext.current
    Avviso(
        avviso.testo,
        icona = avviso.icona,
        coloreIcona = if (avviso.suggerimento) Colori.accentoChiaro else Colori.ambraTesto,
        chiudi = chiudi,
        // P3 e P4: «Apri Impostazioni» sotto il testo.
        azione = avviso.azione?.let { azione ->
            {
                PulsantePieno(stringResource(R.string.apri_impostazioni), piccolo = true) {
                    when (azione) {
                        CodaAvvisi.Azione.IMPOSTAZIONI_APP -> Permessi.apriPaginaApp(context)
                        CodaAvvisi.Azione.BATTERIA -> Permessi.apriBatteria(context)
                    }
                }
            }
        },
    )
}

/** G2.2: gli avvisi chiusi la cui causa c'è ancora, come icone ambra; un tocco riapre l'avviso. */
@Composable
private fun IconeAvvisi(avvisi: CodaAvvisi) {
    val ridotti = avvisi.ridotti
    if (ridotti.isEmpty()) return
    val suggerimento = stringResource(R.string.rileggi_avviso)
    Row {
        for (avviso in ridotti) {
            PulsanteTondo(
                avviso.icona, stringResource(R.string.avviso_icona, avviso.testo), sopraIlVideo = true,
                diametro = Misure.tondoOrecchie, coloreIcona = Colori.ambra, suggerimento = suggerimento,
            ) { avvisi.riapri(avviso.id) }
        }
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
    Avviso(
        stringResource(consiglio), titolo = stringResource(titolo), icona = Icons.Filled.Accessibility,
        chiudi = { sessione.nascondiAvvisoPostura() },
    )
}

/** La pausa: piccola, non blocca nulla, resta finché dura. */
@Composable
private fun BannerPausa(sessione: SessioneTelefono) {
    val motivo = sessione.pausa.ora()
    val causa = sessione.causaInterruzione.ora()
    if (sessione.stato != Stato.Collegato || motivo == null) return
    val (titolo, spiegazione) = when (motivo) {
        MotiviPausa.FACCIA_IN_GIU -> stringResource(R.string.pausa_faccia_in_giu_titolo) to stringResource(R.string.pausa_faccia_in_giu_spiegazione)
        MotiviPausa.NESSUNA_APP -> stringResource(R.string.pausa_nessuna_app_titolo) to stringResource(R.string.pausa_nessuna_app_spiegazione)
        MotiviPausa.UTENTE -> stringResource(R.string.pausa_titolo) to stringResource(R.string.pausa_utente_spiegazione)
        // La fotocamera tolta dal sistema: la causa con cosa fare; riprende da sola quando torna libera.
        MotiviPausa.FOTOCAMERA_INTERROTTA ->
            stringResource(R.string.pausa_fotocamera_interrotta_titolo) to (causa ?: stringResource(R.string.pausa_spiegazione))
        MotiviPausa.SOTTOFONDO -> stringResource(R.string.pausa_sottofondo_titolo) to stringResource(R.string.pausa_spiegazione)
        else -> stringResource(R.string.pausa_titolo) to stringResource(R.string.pausa_spiegazione)
    }
    Avviso(spiegazione, titolo = titolo, icona = Icons.Filled.PauseCircle)
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
    // G2.8: TalkBack legge il banner quando compare o cambia causa (il titolo); non i secondi, che cambiano sempre.
    Avviso(
        if (secondi == 1) stringResource(R.string.da_un_secondo) else stringResource(R.string.da_secondi, secondi),
        titolo = testo, attesa = true, stileTesto = Stili.numeri, azioneALato = true,
        azione = { PulsantePieno(stringResource(R.string.riprova_ora), piccolo = true) { sessione.riprova() } },
    )
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
        verticalArrangement = Arrangement.spacedBy(Spazi.piccolo),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(Raggi.pannello))
            .background(Veli.coloreForte).border(1.dp, Colori.accento, RoundedCornerShape(Raggi.pannello))
            // G2.8: TalkBack legge titolo e codice appena il pannello compare.
            .semantics { liveRegion = LiveRegionMode.Polite }
            .padding(Spazi.medio)
            .verticalScroll(rememberScrollState()),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
            Icon(Icons.Filled.Lock, contentDescription = null, tint = Colori.accento)
            Text(stringResource(R.string.conferma_titolo), style = Stili.titoloGrande, color = Colori.testo)
        }
        Text(stringResource(R.string.conferma_testo, sessione.computer.nome), style = Stili.corpo, color = Colori.testoChiaro)
        Text(
            cifre,
            style = Stili.codice,
            color = Colori.testo,
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Raggi.controllo)).background(Colori.pannelloScuro).padding(vertical = Spazi.stretto)
                .semantics { contentDescription = descrizioneCodice },
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.stretto)) {
            CircularProgressIndicator(color = Colori.accento, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
            Text(stringResource(R.string.conferma_attesa), style = Stili.nota, color = Colori.testoSecondario)
        }
    }
}

@Composable
private fun PannelloErrore(sessione: SessioneTelefono, descrizione: String, chiudi: () -> Unit, apriDomanda: (String) -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(Spazi.piccolo),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(Raggi.pannello))
            .background(Veli.coloreForte).padding(Spazi.medio).verticalScroll(rememberScrollState()),
    ) {
        // G2.8: TalkBack legge l'errore e la sua causa appena compaiono.
        Column(
            verticalArrangement = Arrangement.spacedBy(Spazi.piccolo),
            modifier = Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Assertive },
        ) {
            Text(sessione.titoloErrore, style = Stili.titoloGrande, color = Colori.testo)
            Text(descrizione, style = Stili.corpo, color = Colori.testoTenue)
        }
        sessione.domandaErrore?.let { domanda ->
            PulsanteLink(stringResource(R.string.perche_succede)) { apriDomanda(domanda) }
        }
        // Con il testo grande i due pulsanti vanno uno sotto l'altro, senza troncare.
        val grande = LocalDensity.current.fontScale > 1.3f
        val pulsanti: @Composable () -> Unit = {
            // Identità cambiata: riprovare non serve, si riabbina con il QR code dalla lista dei computer.
            if (!sessione.erroreDefinitivo) PulsantePieno(stringResource(R.string.riprova), piccolo = true) { sessione.riprova() }
            PulsanteLink(stringResource(R.string.torna_ai_computer), tenue = true, azione = chiudi)
        }
        if (grande) {
            Column(verticalArrangement = Arrangement.spacedBy(Spazi.stretto)) { pulsanti() }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(Spazi.stretto), verticalAlignment = Alignment.CenterVertically) { pulsanti() }
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
        horizontalArrangement = Arrangement.spacedBy(Spazi.minimo),
        modifier = Modifier.clip(RoundedCornerShape(Raggi.capsula)).background(Veli.coloreForte).padding(Spazi.minimo),
    ) {
        for (obiettivo in obiettivi) {
            val scelto = obiettivo == sessione.obiettivo
            val nome = nomeAccessibile(obiettivo)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.heightIn(min = 40.dp).widthIn(min = 40.dp).clip(RoundedCornerShape(Raggi.capsula))
                    .background(if (scelto) Colori.testo else Color.Transparent)
                    .clickable(role = Role.RadioButton, onClickLabel = nome) { sessione.scegli(obiettivo) }
                    .semantics {
                        contentDescription = nome
                        selected = scelto
                    }
                    .padding(horizontal = if (obiettivo.nome == "frontale" || obiettivo.nome == "tele") Spazi.piccolo else Spazi.minimo),
            ) {
                Text(etichettaObiettivo(obiettivo), style = Stili.numeriEvidenti, color = if (scelto) Colori.fondo else Colori.testo, maxLines = 1)
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
private fun ColonnaComandi(sessione: SessioneTelefono, grande: Boolean, modifier: Modifier = Modifier, soloFrontale: () -> Unit) {
    val specchiato = sessione.specchiato.ora()
    val sfondo = sessione.sfondo.ora()
    val audio = sessione.audioRichiesto.ora()
    val inPausa = sessione.pausa.ora() == MotiviPausa.UTENTE
    val effetti = sessione.effetti.ora()
    val funzioni = sessione.funzioni.ora()
    // Effetti sul computer: Specchia, Sfoca e Luce sono un telecomando del computer e mostrano il suo stato
    // (`effetti`); finché non arriva restano spenti. Microfono e Pausa restano del telefono.
    val sulComputer = sessione.effettiSulComputer.ora()
    val delComputer = sessione.effettiComputer.ora()
    // Specchio e sfondo valgono solo con la frontale: con la posteriore i due pulsanti restano grigi e spenti (la
    // scelta torna tornando alla frontale). Vale anche con gli effetti sul computer, come sul Mac e sull'iPhone.
    val frontale = sessione.conFrontale
    val specchioVisto = if (sulComputer) delComputer?.specchia == true else specchiato && frontale
    val sfocato = if (sulComputer) delComputer != null && delComputer.sfondo != ModiSfondo.NESSUNO else sfondo != ModiSfondo.NESSUNO && frontale
    val luceAccesa = if (sulComputer) delComputer?.luceVolto == true else effetti.luceVolto
    val acceso = stringResource(R.string.acceso)
    val spento = stringResource(R.string.spento)
    val soloConFrontale = stringResource(R.string.avviso_solo_frontale)

    Column(
        verticalArrangement = Arrangement.spacedBy(spazioColonna(grande)),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .clip(RoundedCornerShape(Raggi.capsula))
            .background(Veli.coloreMedio)
            .verticalScroll(rememberScrollState())
            .padding(spazioColonna(grande)),
    ) {
        // Specchia il video che arriva al computer, subito.
        PulsanteTondo(
            Icons.Filled.Flip, stringResource(R.string.specchia), attivo = specchioVisto,
            stato = if (specchioVisto) acceso else spento, abilitato = frontale, motivoSpento = soloConFrontale, toccoSpento = soloFrontale,
        ) {
            if (sulComputer) sessione.chiediEffetto(ChiediEffetto(specchia = !specchioVisto)) else sessione.impostaSpecchio(!specchiato)
        }
        // Un tocco: sfocato o niente, con l'intensità scelta dal computer. Uno sfondo sostituito (scelto sul computer)
        // conta come acceso: il tocco lo spegne. Solo se il telefono sa separare la persona dallo sfondo.
        // Sul computer: «sfocato» accende la sfocatura con l'ultimo livello scelto lì.
        if (funzioni.sfondo || sulComputer) {
            PulsanteTondo(
                Icons.Filled.BlurOn, stringResource(R.string.sfoca_sfondo), attivo = sfocato,
                stato = if (sfocato) acceso else spento, abilitato = frontale, motivoSpento = soloConFrontale, toccoSpento = soloFrontale,
            ) {
                val modo = if (sfocato) ModiSfondo.NESSUNO else ModiSfondo.SFOCATO
                if (sulComputer) sessione.chiediEffetto(ChiediEffetto(sfondo = modo)) else sessione.scegliSfondo(modo)
            }
        }
        // Il microfono del telefono verso il computer. Senza permesso la sessione lo fa chiedere a MainActivity
        // (permessoMicrofonoDaChiedere), anche quando lo accende il computer.
        PulsanteTondo(
            if (audio) Icons.Filled.Mic else Icons.Filled.MicOff, stringResource(R.string.microfono_al_computer),
            attivo = audio, stato = if (audio) acceso else spento,
        ) { sessione.impostaAudio(!audio) }
        // Il video si ferma, il collegamento resta (come a faccia in giù).
        PulsanteTondo(
            if (inPausa) Icons.Filled.PlayArrow else Icons.Filled.Pause,
            stringResource(if (inPausa) R.string.riprendi else R.string.pausa), attivo = inPausa,
        ) { sessione.impostaPausaUtente(!inPausa) }
        // Luce sul volto (gratis): il viso si schiarisce in modo morbido e l'esposizione lo segue. La torcia sta
        // nelle Impostazioni.
        if (funzioni.volti || sulComputer) {
            PulsanteTondo(
                Icons.Filled.WbSunny, stringResource(R.string.luce_volto),
                attivo = luceAccesa, stato = if (luceAccesa) acceso else spento,
            ) {
                if (sulComputer) sessione.chiediEffetto(ChiediEffetto(luceVolto = !luceAccesa)) else sessione.applica(Comando(luceVolto = !luceAccesa))
            }
        }
    }
}

// MARK: Schermo oscurato

/** Schermo nero durante l'uso: il video continua, lo schermo non consuma. Doppio tocco per riaccenderlo. */
@Composable
private fun SchermoOscurato(sessione: SessioneTelefono, riaccendi: () -> Unit) {
    val collegato = sessione.stato == Stato.Collegato
    val motivoPausa = sessione.pausa.ora()
    val inPausa = collegato && motivoPausa != null
    // G2.1: in onda «IN ONDA» corallo pieno, in pausa «IN PAUSA» ambra, grandi da leggere a 2–3 metri.
    val tono = when {
        inPausa -> TonoPillola.PAUSA
        collegato && !sessione.prontaCam2 && sessione.inOnda != null -> TonoPillola.IN_ONDA
        else -> null
    }
    val colorePunto = when {
        !collegato -> Colori.ambra
        sessione.prontaCam2 -> Colori.accento
        // Anche a schermo spento il corallo compare solo quando un'app usa davvero la webcam.
        sessione.inOnda != null -> Colori.tally
        else -> Colori.verde
    }
    val testoStato = when {
        !collegato -> stringResource(R.string.oscurato_riconnessione)
        inPausa -> stringResource(R.string.pausa_titolo)
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
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spazi.medio), modifier = Modifier.padding(Spazi.medio)) {
            if (tono != null) {
                PillolaStato(stringResource(if (tono == TonoPillola.PAUSA) R.string.pausa_titolo else R.string.in_onda), tono, misura = MisuraPillola.GRANDE)
                Text(sessione.computer.nome, style = Stili.titolo, color = Colori.testoSecondario, textAlign = TextAlign.Center)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
                    Box(Modifier.size(Misure.punto).clip(CircleShape).background(colorePunto))
                    Text(testoStato, style = Stili.titolo, color = Colori.testoSecondario, textAlign = TextAlign.Center)
                }
            }
            Text(listOfNotNull(qualita, tipo).joinToString("   "), style = Stili.numeri, color = Colori.testoSecondario, textAlign = TextAlign.Center)
            Text("$batteria   $temperatura", style = Stili.numeri, color = Colori.testoSecondario, textAlign = TextAlign.Center)
            Spacer(Modifier.height(Spazi.medio))
            Text(suggerimento, style = Stili.nota, color = Colori.testoSecondario, textAlign = TextAlign.Center)
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
