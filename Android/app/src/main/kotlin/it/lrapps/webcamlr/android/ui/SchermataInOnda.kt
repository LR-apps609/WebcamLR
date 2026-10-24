package it.lrapps.webcamlr.android.ui

import android.app.Activity
import android.content.res.Configuration
import android.os.SystemClock
import android.view.WindowManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cameraswitch
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Flip
import androidx.compose.material.icons.filled.FlashlightOff
import androidx.compose.material.icons.filled.FlashlightOn
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sessione.SessioneTelefono.Stato
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import it.lrapps.webcamlr.protocollo.Temperatura
import kotlinx.coroutines.delay

/**
 * «In onda» (bozza grafica, telefono 3) e schermo oscurato (telefono 6). La sessione nasce quando si sceglie il
 * computer (MainActivity): qui si mostra e si comanda. Lo schermo resta acceso; dopo 30 secondi senza tocchi
 * si oscura (luminosità al minimo e nero), come sull'iPhone.
 */
@Composable
fun SchermataInOnda(sessione: SessioneTelefono, chiudi: () -> Unit, apriDomanda: (String) -> Unit) {
    val context = LocalContext.current
    val vista = LocalView.current
    val verticale = LocalConfiguration.current.orientation == Configuration.ORIENTATION_PORTRAIT
    var ultimoTocco by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    var zoomIniziale by remember { mutableStateOf(1.0) }
    var puntoFuoco by remember { mutableStateOf<Offset?>(null) }

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
    // Dopo 30 secondi senza tocchi, con il video che va, lo schermo si oscura da solo.
    LaunchedEffect(ultimoTocco, sessione.stato, Impostazioni.oscuraDaSolo) {
        if (!Impostazioni.oscuraDaSolo || sessione.stato != Stato.Collegato) return@LaunchedEffect
        delay(30_000)
        if (sessione.stato == Stato.Collegato) sessione.oscurato = true
    }
    LaunchedEffect(puntoFuoco, sessione.aeafBloccati) {
        if (puntoFuoco != null && !sessione.aeafBloccati) {
            delay(1_500)
            puntoFuoco = null
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AnteprimaVideo(sessione.renderizzatore, Modifier.fillMaxSize())
        // I gesti sull'anteprima: tocco = messa a fuoco, tocco lungo = Blocco AE/AF, doppio tocco = cambia fotocamera,
        // pizzico = zoom.
        Box(
            Modifier.fillMaxSize()
                .pointerInput(sessione) {
                    detectTapGestures(
                        onPress = { ultimoTocco = SystemClock.elapsedRealtime() },
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
                        ultimoTocco = SystemClock.elapsedRealtime()
                        if (scala != 1f) sessione.impostaZoom(sessione.zoom * scala)
                    }
                }
                .semantics { contentDescription = "Anteprima della fotocamera. Tocca per mettere a fuoco, tocca due volte per cambiare fotocamera." },
        )
        puntoFuoco?.let { punto ->
            Canvas(Modifier.fillMaxSize()) {
                val lato = 84.dp.toPx()
                drawRect(
                    Colori.ambra, topLeft = Offset(punto.x - lato / 2, punto.y - lato / 2),
                    size = androidx.compose.ui.geometry.Size(lato, lato),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2.dp.toPx()),
                )
            }
        }
        if (Impostazioni.griglia) GrigliaTerzi()

        Row(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 12.dp, vertical = 10.dp)) {
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Sovrapposizioni(sessione, verticale)
                Spacer(Modifier.weight(1f))
                when (val stato = sessione.stato) {
                    is Stato.Errore -> PannelloErrore(sessione, stato.descrizione, chiudi, apriDomanda)
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
                SelettoreObiettivo(sessione)
            }
            BarraComandi(sessione, chiudi)
        }

        if (sessione.oscurato) SchermoOscurato(sessione) { sessione.oscurato = false; ultimoTocco = SystemClock.elapsedRealtime() }
    }
}

@Composable
private fun Sovrapposizioni(sessione: SessioneTelefono, verticale: Boolean) {
    val stato = sessione.stato
    val (pillola, testoPillola) = when {
        stato == Stato.Collegato && sessione.inOnda != null ->
            StatoPillola.InOnda(sessione.inOnda?.app) to (sessione.inOnda?.app?.let { "In onda · $it" } ?: "In onda")
        stato == Stato.Collegato -> StatoPillola.Collegato to "Collegato · ${sessione.computer.nome}"
        stato == Stato.Collegamento -> StatoPillola.Riconnessione to "Collegamento…"
        stato is Stato.Riconnessione -> StatoPillola.Riconnessione to "Riconnessione ${stato.tentativo}/${SessioneTelefono.TENTATIVI_MASSIMI}"
        else -> StatoPillola.NessunTelefono to "Scollegato"
    }
    val qualita = QualitaCollegamento.da(sessione.latenzaMs ?: 0, sessione.perditeRecenti)
    val testoBatteria = (if (sessione.batteria >= 0) "${sessione.batteria}%" else "—") + " · temperatura ${descrizione(sessione.temperatura)}"

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PillolaStato(pillola, testoPillola)
        if (stato == Stato.Collegato) {
            Chip {
                val latenza = sessione.latenzaMs
                if (latenza != null) {
                    ChipQualita(qualita, latenza)
                    if (Impostazioni.modalitaAvanzata) Text("$latenza ms", style = Caratteri.numeri(12), color = Colori.testoSecondario)
                } else {
                    Text("— ms", style = Caratteri.numeri(12), color = Colori.testoChiaro)
                }
                sessione.tipoCollegamento?.let { Text(it.testo, style = Caratteri.etichetta(14), color = Colori.testoChiaro) }
                if (Impostazioni.modalitaAvanzata) {
                    sessione.formato?.let {
                        Text("${minOf(it.larghezza, it.altezza)}p${it.fps} · ${SessioneTelefono.nomeCodec(it)}", style = Caratteri.numeri(12), color = Colori.testoChiaro)
                    }
                }
                if (sessione.zoom > 1.05) {
                    Text(String.format(java.util.Locale.ITALY, "%.1f×", sessione.zoom), style = Caratteri.numeri(12), color = Colori.testoChiaro)
                }
                if (sessione.iso > 0 || sessione.tempo > 0) {
                    val parti = buildList {
                        if (sessione.iso > 0) add("ISO ${sessione.iso.toInt()}")
                        if (sessione.tempo > 0) add("1/${maxOf(sessione.tempo, sessione.formato?.fps ?: 30)} s")
                    }
                    Text(parti.joinToString(" · "), style = Caratteri.numeri(12), color = Colori.ambraTesto)
                }
            }
        }
        Chip { Text(testoBatteria, style = Caratteri.numeri(12), color = Colori.testoChiaro) }
        if (sessione.aeafBloccati) {
            Box(Modifier.clip(RoundedCornerShape(50)).background(Colori.ambra).padding(horizontal = 10.dp, vertical = 3.dp)) {
                Text("AE/AF bloccati", style = Caratteri.etichetta(15), color = Colori.fondo)
            }
        }
        if (sessione.reteDebole && stato == Stato.Collegato) {
            Chip { Text("Rete lenta: qualità abbassata da sola", color = Colori.ambraTesto) }
        }
        val consiglio = sessione.tipoCollegamento?.consiglioSeDebole
        if (stato == Stato.Collegato && (qualita == QualitaCollegamento.DEBOLE || sessione.reteDebole) && consiglio != null) {
            Chip { Text(consiglio.replace("Con il cavo USB", "Con il tethering USB"), color = Colori.testoChiaro) }
        }
        if (sessione.qualitaRidotta) Chip { Text("Telefono molto caldo: qualità ridotta a 720p", color = Colori.ambraTesto) }
        if (sessione.batteriaBassa) {
            Chip {
                Text(
                    if (sessione.risparmioBatteria) "Batteria al ${sessione.batteria}%: 24 fps per risparmiare, collega il caricatore"
                    else "Batteria al ${sessione.batteria}%: collega il caricatore",
                    color = Colori.ambraTesto,
                )
            }
        }
        if (verticale) Chip { Text("Gira il telefono in orizzontale per un'inquadratura larga", color = Colori.testoChiaro) }
    }
}

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
    val secondi = ((adesso - inizio) / 1000).coerceAtLeast(0)
    val testo = when {
        !sessione.reteDisponibile -> "Nessuna rete: mi ricollego appena torna il Wi-Fi…"
        sessione.giaCollegato -> "Computer perso, mi ricollego…"
        else -> "Non riesco a collegarmi a ${sessione.computer.nome}, riprovo…"
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(16.dp))
            .background(Colori.ambraTenue.copy(alpha = 0.95f)).padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        CircularProgressIndicator(color = Colori.ambraTesto, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(testo, style = Caratteri.etichetta(16), color = Colori.ambraTesto)
            Text(if (secondi == 1L) "da 1 secondo" else "da $secondi secondi", style = Caratteri.numeri(12), color = Colori.ambraTesto)
        }
        Box(
            Modifier.clip(RoundedCornerShape(50)).background(Colori.ciano).clickable { sessione.riprova() }
                .padding(horizontal = 14.dp, vertical = 8.dp),
        ) { Text("Riprova ora", style = Caratteri.etichetta(15), color = Colori.fondo) }
    }
}

/**
 * Prima volta con questo computer: lo stesso codice di conferma compare sul computer, che chiede
 * «Consentire …?». Si aspetta finché l'utente non risponde.
 */
@Composable
private fun PannelloConferma(sessione: SessioneTelefono, codice: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(18.dp))
            .background(Colori.fondo.copy(alpha = 0.94f)).border(1.dp, Colori.ciano, RoundedCornerShape(18.dp)).padding(18.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            androidx.compose.material3.Icon(Icons.Filled.Lock, contentDescription = null, tint = Colori.ciano)
            Text("Conferma sul computer", style = Caratteri.titolo(28), color = Colori.testo)
        }
        Text(
            "Su ${sessione.computer.nome} consenti questo telefono, se il codice di conferma è lo stesso:",
            color = Colori.testoChiaro,
        )
        Text(
            codice.toCharArray().joinToString(" "),
            style = Caratteri.numeriEvidenti(46),
            color = Colori.testo,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Colori.pannelloScuro).padding(vertical = 8.dp)
                .semantics { contentDescription = "Codice di conferma ${codice.toCharArray().joinToString(" ")}" },
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(color = Colori.ciano, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
            Text("Aspetto la risposta, fino a un minuto", color = Colori.testoSecondario)
        }
    }
}

@Composable
private fun PannelloErrore(sessione: SessioneTelefono, descrizione: String, chiudi: () -> Unit, apriDomanda: (String) -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.widthIn(max = 420.dp).clip(RoundedCornerShape(16.dp))
            .background(Colori.fondo.copy(alpha = 0.92f)).padding(16.dp),
    ) {
        Text(sessione.titoloErrore, style = Caratteri.titolo(24), color = Colori.testo)
        Text(descrizione, color = Colori.testoTenue)
        sessione.domandaErrore?.let { domanda ->
            Text(
                "Perché succede?", style = Caratteri.etichetta(16), color = Colori.cianoChiaro,
                modifier = Modifier.clickable { apriDomanda(domanda) }.padding(vertical = 4.dp),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            // Identità cambiata: riprovare non serve, si riabbina con il QR code dalla lista dei computer.
            if (!sessione.erroreDefinitivo) {
                Box(
                    Modifier.clip(RoundedCornerShape(50)).background(Colori.ciano).clickable { sessione.riprova() }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                ) { Text("Riprova", style = Caratteri.etichetta(16), color = Colori.fondo) }
            }
            TextButton(onClick = chiudi) { Text("Torna ai computer", style = Caratteri.etichetta(16), color = Colori.testo) }
        }
    }
}

@Composable
private fun SelettoreObiettivo(sessione: SessioneTelefono) {
    val obiettivi = sessione.obiettivi
    if (obiettivi.size < 2) return
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.clip(RoundedCornerShape(50)).background(Colori.fondo.copy(alpha = 0.7f)).padding(4.dp),
        ) {
            for (obiettivo in obiettivi) {
                val scelto = obiettivo == sessione.obiettivo
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.height(36.dp).widthIn(min = 44.dp).clip(RoundedCornerShape(50))
                        .background(if (scelto) Colori.cianoTenue else Color.Transparent)
                        .clickable(onClickLabel = obiettivo.etichetta) { sessione.scegli(obiettivo) }
                        .padding(horizontal = 10.dp),
                ) {
                    Text(obiettivo.etichetta, style = Caratteri.numeriEvidenti(if (scelto) 14 else 13), color = if (scelto) Colori.cianoChiaro else Colori.testo)
                }
            }
        }
    }
}

@Composable
private fun BarraComandi(sessione: SessioneTelefono, chiudi: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxHeight().verticalScroll(rememberScrollState())
            .clip(RoundedCornerShape(30.dp)).background(Colori.fondo.copy(alpha = 0.82f)).padding(vertical = 12.dp, horizontal = 8.dp),
    ) {
        PulsanteTondo(
            if (sessione.torciaAccesa) Icons.Filled.FlashlightOn else Icons.Filled.FlashlightOff,
            "Torcia", attivo = sessione.torciaAccesa, abilitato = sessione.haTorcia,
        ) { sessione.cambiaTorcia() }
        PulsanteTondo(Icons.Filled.Cameraswitch, "Cambia fotocamera") { sessione.cambiaFotocamera() }
        PulsanteTondo(Icons.Filled.Flip, "Specchia l'immagine inviata", attivo = Impostazioni.specchia) {
            Impostazioni.impostaSpecchia(!Impostazioni.specchia)
            sessione.aggiornaSpecchio()
        }
        PulsanteTondo(Icons.Filled.DarkMode, "Oscura lo schermo") { sessione.oscurato = true }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(48.dp).clip(CircleShape).border(1.dp, Colori.bordo, CircleShape)
                .clickable(onClickLabel = "Scollega", onClick = chiudi)
                .semantics { contentDescription = "Scollega" },
        ) {
            androidx.compose.material3.Icon(Icons.Filled.Close, contentDescription = null, tint = Color.White)
        }
    }
}

@Composable
private fun GrigliaTerzi() {
    Canvas(Modifier.fillMaxSize()) {
        val colore = Color.White.copy(alpha = 0.35f)
        for (i in 1..2) {
            drawLine(colore, Offset(size.width * i / 3, 0f), Offset(size.width * i / 3, size.height), strokeWidth = 1.dp.toPx())
            drawLine(colore, Offset(0f, size.height * i / 3), Offset(size.width, size.height * i / 3), strokeWidth = 1.dp.toPx())
        }
    }
}

/** Schermo nero durante l'uso (funzione 32): il video continua, lo schermo non consuma. Doppio tocco per riaccenderlo. */
@Composable
private fun SchermoOscurato(sessione: SessioneTelefono, riaccendi: () -> Unit) {
    val collegato = sessione.stato == Stato.Collegato
    val colorePunto = when {
        !collegato -> Colori.ambra.copy(alpha = 0.7f)
        sessione.inOnda != null -> Colori.tally
        else -> Colori.verde.copy(alpha = 0.7f)
    }
    val testoStato = when {
        !collegato -> "Riconnessione…"
        sessione.inOnda != null -> "In onda su ${sessione.computer.nome}"
        else -> "Collegato a ${sessione.computer.nome}"
    }
    val qualita = sessione.latenzaMs?.let { QualitaCollegamento.da(it, sessione.perditeRecenti).testo } ?: "—"
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .pointerInput(sessione) { detectTapGestures(onDoubleTap = { riaccendi() }) }
            .semantics(mergeDescendants = true) { contentDescription = "$testoStato. Tocca due volte per riaccendere lo schermo." },
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(colorePunto))
                Text(testoStato, style = Caratteri.etichetta(22), color = Colori.testoSecondario)
            }
            Text(
                listOfNotNull(
                    qualita,
                    sessione.tipoCollegamento?.testo,
                    if (sessione.batteria >= 0) "batteria ${sessione.batteria}%" else "batteria —",
                    "temperatura ${descrizione(sessione.temperatura)}",
                ).joinToString("   "),
                style = Caratteri.numeri(13), color = Colori.testoSecondario,
            )
            Spacer(Modifier.height(18.dp))
            Text("Tocca due volte per riaccendere lo schermo", color = Colori.testoSecondario)
        }
    }
}

private fun descrizione(temperatura: Temperatura) = when (temperatura) {
    Temperatura.NORMALE -> "normale"
    Temperatura.CALDA -> "calda"
    Temperatura.MOLTO_CALDA -> "molto calda"
    Temperatura.CRITICA -> "critica"
}
