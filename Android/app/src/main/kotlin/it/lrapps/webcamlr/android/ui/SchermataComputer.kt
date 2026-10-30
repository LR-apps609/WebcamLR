package it.lrapps.webcamlr.android.ui

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.DesktopWindows
import androidx.compose.material.icons.filled.LaptopMac
import androidx.compose.material.icons.filled.NoPhotography
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.contenuti.InfoApp
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.rete.CercaComputer
import it.lrapps.webcamlr.android.rete.ComputerTrovato
import it.lrapps.webcamlr.android.rete.RicercaCavo
import it.lrapps.webcamlr.android.sistema.Permessi
import it.lrapps.webcamlr.protocollo.Associazione
import it.lrapps.webcamlr.protocollo.Piattaforma
import kotlinx.coroutines.delay

/** Ricollegamento automatico (novità 2): una volta sola per avvio dell'app. */
private object Ricollegamento {
    var fatto = false
}

/** Dopo questi millisecondi senza computer l'aiuto in tre punti (Documenti/Interfaccia finale.md). */
private const val ATTESA_AIUTO_MS = 15_000L

/**
 * Il telefono senza computer (Documenti/Interfaccia finale.md, «Telefono senza computer»): cerca da solo («Cerco il
 * tuo computer…», con QR code, cavo USB e il link per chi non ha ancora WebcamLR sul computer); appena ne trova uno,
 * «Computer trovati» con un tocco per collegarsi; dopo 15 secondi senza nessuno, «Non trovo nessun computer» con tre
 * controlli, «Mandami il link per il computer» e «Prova con il cavo USB». La ricerca continua sempre.
 */
@Composable
fun SchermataComputer(
    collega: (ComputerTrovato) -> Unit,
    apriLettore: () -> Unit,
    apriImpostazioni: () -> Unit,
    apriApp: () -> Unit,
    apriPro: () -> Unit,
    apriDomanda: (String) -> Unit,
    inPrimoPiano: Boolean,
) {
    val context = LocalContext.current
    val cerca = remember { CercaComputer(context) }
    var aiuto by rememberSaveable { mutableStateOf(false) }
    var mostraIndirizzo by remember { mutableStateOf(false) }
    var mostraCavo by remember { mutableStateOf(false) }
    var ricollegaA by remember { mutableStateOf<ComputerTrovato?>(null) }
    var secondi by remember { mutableIntStateOf(3) }

    DisposableEffect(Unit) {
        cerca.avvia()
        onDispose { cerca.ferma() }
    }
    LaunchedEffect(Unit) {
        delay(ATTESA_AIUTO_MS)
        aiuto = true
    }
    // Alla prima comparsa dell'ultimo computer usato parte il conto alla rovescia.
    val ultimo = Impostazioni.ultimoComputer
    val trovatoUltimo = cerca.computer.firstOrNull { it.nome == ultimo }
    LaunchedEffect(trovatoUltimo, inPrimoPiano, mostraIndirizzo) {
        if (trovatoUltimo == null || Ricollegamento.fatto || !inPrimoPiano || mostraIndirizzo) return@LaunchedEffect
        Ricollegamento.fatto = true
        ricollegaA = trovatoUltimo
        for (rimasti in 3 downTo 1) {
            secondi = rimasti
            delay(1_000)
        }
        val scelto = ricollegaA
        ricollegaA = null
        if (scelto != null) collega(scelto)
    }
    fun annullaRicollegamento() {
        Ricollegamento.fatto = true
        ricollegaA = null
    }

    val testoLink = stringResource(R.string.presentazione_computer_messaggio, InfoApp.DOWNLOAD)
    val oggettoLink = stringResource(R.string.presentazione_computer_oggetto)
    val titoloLink = stringResource(R.string.mandami_link)
    val mandaLink = {
        annullaRicollegamento()
        val invio = Intent(Intent.ACTION_SEND).setType("text/plain")
            .putExtra(Intent.EXTRA_SUBJECT, oggettoLink)
            .putExtra(Intent.EXTRA_TEXT, testoLink)
        try {
            context.startActivity(Intent.createChooser(invio, titoloLink))
        } catch (e: ActivityNotFoundException) {
            // Nessuna app per condividere: il link è anche nella sezione App.
        }
    }
    val qr = { annullaRicollegamento(); apriLettore() }
    val cavo = { annullaRicollegamento(); mostraCavo = true }
    val aMano = { annullaRicollegamento(); mostraIndirizzo = true }

    Box(Modifier.fillMaxSize().background(Colori.sfondoSchermata).safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 560.dp).fillMaxSize().padding(horizontal = Spazi.largo, vertical = Spazi.piccolo)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spazi.stretto)) {
                LogoWebcamLR(30.dp)
                MarchioWebcamLR()
                Spacer(Modifier.weight(1f))
                // WebcamLR Pro sempre in vista: «PRO» (o «PRO ✓» se è attivo) apre la pagina Pro.
                PulsantePro { annullaRicollegamento(); apriPro() }
                // Le azioni della barra in alto come in Material 3: icone da 48 dp, senza fondo.
                IconButton(onClick = { annullaRicollegamento(); apriApp() }) {
                    Icon(Icons.AutoMirrored.Filled.HelpOutline, contentDescription = stringResource(R.string.app_e_assistenza), tint = Colori.testo)
                }
                IconButton(onClick = { annullaRicollegamento(); apriImpostazioni() }) {
                    Icon(Icons.Filled.Settings, contentDescription = stringResource(R.string.impostazioni), tint = Colori.testo)
                }
            }
            Spacer(Modifier.height(Spazi.piccolo))
            // P3: fotocamera rifiutata. Dopo il secondo rifiuto Android non chiede più: la strada è Impostazioni.
            if (Permessi.fotocameraNegata) {
                SchedaFotocameraNegata { annullaRicollegamento(); Permessi.apriPaginaApp(context) }
                Spacer(Modifier.height(Spazi.piccolo))
            }
            val trovati = cerca.computer.toList()
            when {
                trovati.isNotEmpty() -> PaginaTrovati(
                    trovati, ricollegaA, secondi,
                    annulla = { annullaRicollegamento() },
                    collega = { scelto -> annullaRicollegamento(); collega(scelto) },
                    qr = qr, aMano = aMano,
                )
                aiuto -> PaginaAiuto(qr = qr, cavo = cavo, mandaLink = mandaLink, aMano = aMano, apriDomanda = apriDomanda)
                else -> PaginaCerco(qr = qr, cavo = cavo, mandaLink = mandaLink, aMano = aMano)
            }
        }
    }

    if (mostraIndirizzo) {
        DialogoIndirizzo(
            chiudi = { mostraIndirizzo = false },
            collega = { associazione ->
                mostraIndirizzo = false
                collega(ComputerTrovato.da(associazione))
            },
        )
    }
    if (mostraCavo) DialogoCavo(chiudi = { mostraCavo = false }, apriDomanda = { mostraCavo = false; apriDomanda("cavo") })
}

/** «PRO» in cima alla schermata dei computer: la strada più corta verso WebcamLR Pro. */
@Composable
private fun PulsantePro(azione: () -> Unit) {
    val pro = Pro.attivo()
    val stato = stringResource(if (pro) R.string.pro_riga_attivo else R.string.pro_riga_sblocca)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spazi.stretto),
        modifier = Modifier.heightIn(min = Misure.areaTocco).clip(RoundedCornerShape(Raggi.capsula)).background(Colori.pannelloChiaro)
            .border(1.dp, Colori.contornoSuRialzato, RoundedCornerShape(Raggi.capsula))
            .clickable(role = Role.Button, onClick = azione)
            .semantics(mergeDescendants = true) { contentDescription = "WebcamLR Pro, $stato" }
            .padding(horizontal = Spazi.piccolo),
    ) {
        SegnoPro()
        if (pro) Icon(Icons.Filled.Check, contentDescription = null, tint = Colori.accentoChiaro, modifier = Modifier.size(Misure.iconaPiccola))
    }
}

/** Il contenuto che scorre sopra, i pulsanti fermi in fondo. */
@Composable
private fun ColumnScope.Pagina(contenuto: @Composable ColumnScope.() -> Unit, pulsanti: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(Spazi.medio),
        content = contenuto,
    )
    Column(Modifier.fillMaxWidth().padding(top = Spazi.piccolo), verticalArrangement = Arrangement.spacedBy(Spazi.piccolo), content = pulsanti)
}

/**
 * Le strade per collegarsi quando la ricerca non basta, uguali in «Cerco» e in «Non trovo nessun computer»: un nome e
 * uno stile ciascuna, tutte secondarie bordate (il primario pieno, se c'è, è un problema da risolvere): «Inquadra il
 * QR code», «Usa il cavo USB», «Mandami il link per il computer»; «Collega a mano (indirizzo)» come link tenue.
 */
@Composable
private fun StradePerCollegarsi(qr: () -> Unit, cavo: () -> Unit, mandaLink: () -> Unit, aMano: () -> Unit) {
    PulsanteSecondario(stringResource(R.string.inquadra_qr_breve), icona = Icons.Filled.QrCodeScanner, azione = qr)
    PulsanteSecondario(stringResource(R.string.usa_cavo_usb), icona = Icons.Filled.Usb, azione = cavo)
    PulsanteSecondario(stringResource(R.string.mandami_link), icona = Icons.Filled.Share, azione = mandaLink)
    PulsanteLink(stringResource(R.string.collega_a_mano), Modifier.fillMaxWidth(), tenue = true) { aMano() }
}

// MARK: Cerco

@Composable
private fun ColumnScope.PaginaCerco(qr: () -> Unit, cavo: () -> Unit, mandaLink: () -> Unit, aMano: () -> Unit) {
    Pagina(
        contenuto = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spazi.medio)) {
                Radar(Modifier.padding(top = Spazi.medio))
                Text(
                    stringResource(R.string.cerco_computer), style = Stili.titoloGrande, color = Colori.testo, textAlign = TextAlign.Center,
                    modifier = Modifier.semantics {
                        heading()
                        liveRegion = LiveRegionMode.Polite
                    },
                )
                Text(stringResource(R.string.cerco_computer_testo), style = Stili.corpo, color = Colori.testoSecondario, textAlign = TextAlign.Center)
            }
        },
        // Si aspetta: nessun primario pieno, il radar dice che cerca.
        pulsanti = { StradePerCollegarsi(qr = qr, cavo = cavo, mandaLink = mandaLink, aMano = aMano) },
    )
}

/** Tre cerchi che si allargano attorno al computer, come un radar; fermi con «Rimuovi animazioni». */
@Composable
private fun Radar(modifier: Modifier = Modifier) {
    val ridotte = ricordaAnimazioniRidotte()
    val giro = rememberInfiniteTransition(label = "radar")
    val fase by giro.animateFloat(0f, 1f, infiniteRepeatable(tween(2_400, easing = LinearEasing), RepeatMode.Restart), label = "fase")
    Box(modifier.size(200.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(200.dp)) {
            val centro = Offset(size.width / 2, size.height / 2)
            val massimo = size.minDimension / 2
            for (indice in 0 until 3) {
                val passo = if (ridotte) (indice + 1) / 3f else ((indice / 3f) + fase) % 1f
                val raggio = massimo * (0.38f + 0.62f * passo)
                val alfa = if (ridotte) 0.5f - indice * 0.13f else (1f - passo) * 0.55f
                drawCircle(Colori.accento.copy(alpha = alfa), radius = raggio, center = centro, style = Stroke(width = 1.dp.toPx()))
            }
        }
        // Un computer qualsiasi (Mac o Windows): l'icona generica, non quella di Windows.
        Icon(Icons.Filled.Computer, contentDescription = null, tint = Colori.accento, modifier = Modifier.size(54.dp))
    }
}

// MARK: Trovati

@Composable
private fun ColumnScope.PaginaTrovati(
    trovati: List<ComputerTrovato>,
    ricollegaA: ComputerTrovato?,
    secondi: Int,
    annulla: () -> Unit,
    collega: (ComputerTrovato) -> Unit,
    qr: () -> Unit,
    aMano: () -> Unit,
) {
    Pagina(
        contenuto = {
            Text(stringResource(R.string.computer_trovati), style = Stili.titoloGrande, color = Colori.testo, modifier = Modifier.semantics { heading() })
            ricollegaA?.let { computer ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo),
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Raggi.pannello)).background(Colori.accentoTenue)
                        .border(1.dp, Colori.accento, RoundedCornerShape(Raggi.pannello)).padding(horizontal = Spazi.medio, vertical = Spazi.stretto)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                ) {
                    CircularProgressIndicator(color = Colori.accento, strokeWidth = 2.dp, modifier = Modifier.size(Misure.iconaPiccola))
                    Text(stringResource(R.string.ricollego_tra, computer.nome, secondi), style = Stili.corpo, color = Colori.testo, modifier = Modifier.weight(1f))
                    PulsanteLink(stringResource(R.string.annulla)) { annulla() }
                }
            }
            // Il primo è in evidenza: quello usato l'ultima volta, se c'è.
            val ultimo = Impostazioni.ultimoComputer
            val ordinati = trovati.sortedByDescending { it.nome == ultimo }
            ordinati.forEachIndexed { indice, computer -> RigaComputer(computer, evidente = indice == 0) { collega(computer) } }
            Text(stringResource(R.string.computer_nuovo_nota), style = Stili.nota, color = Colori.testoSecondario, modifier = Modifier.padding(horizontal = Spazi.minimo))
        },
        pulsanti = {
            PulsanteSecondario(stringResource(R.string.inquadra_qr_breve), icona = Icons.Filled.QrCodeScanner, azione = qr)
            PulsanteLink(stringResource(R.string.collega_a_mano), Modifier.fillMaxWidth(), tenue = true) { aMano() }
        },
    )
}

/** «MacBook Air di Ledion — macOS · Wi-Fi · già usato», tutta la riga si tocca. */
@Composable
private fun RigaComputer(computer: ComputerTrovato, evidente: Boolean, collega: () -> Unit) {
    val conosciuto = ComputerConosciuti.impronta(computer.nome) != null
    val descrizione = listOfNotNull(
        when (computer.piattaforma) {
            Piattaforma.MAC -> "macOS" // testo tecnico
            Piattaforma.WINDOWS -> "Windows" // testo tecnico
            else -> null
        },
        stringResource(if (computer.viaCavo) R.string.collegamento_cavo_usb else R.string.collegamento_wifi),
        stringResource(if (conosciuto) R.string.computer_gia_usato else R.string.computer_nuovo),
    ).joinToString(" · ")
    val etichetta = stringResource(R.string.collega_a, computer.nome)
    val forma = RoundedCornerShape(Raggi.pannello)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spazi.medio),
        modifier = Modifier.fillMaxWidth().clip(forma).background(if (evidente) Colori.pannelloChiaro else Colori.pannello)
            .border(if (evidente) 1.5.dp else 1.dp, if (evidente) Colori.accento else Colori.contornoControllo, forma)
            .clickable(role = Role.Button, onClickLabel = etichetta, onClick = collega)
            .padding(Spazi.medio)
            .semantics(mergeDescendants = true) { contentDescription = "$etichetta, $descrizione" },
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(Misure.areaTocco).clip(RoundedCornerShape(Raggi.controllo)).background(if (evidente) Colori.pannello else Colori.fondo),
        ) {
            Icon(
                when (computer.piattaforma) {
                    Piattaforma.WINDOWS -> Icons.Filled.DesktopWindows
                    Piattaforma.MAC -> Icons.Filled.LaptopMac
                    else -> Icons.Filled.Computer
                },
                contentDescription = null, tint = if (evidente) Colori.accento else Colori.testoSecondario,
            )
        }
        Column(Modifier.weight(1f)) {
            Text(computer.nome, style = Stili.comando, color = Colori.testo)
            Text(descrizione, style = Stili.nota, color = Colori.testoSecondario)
        }
        Text(
            stringResource(R.string.collega), style = Stili.comando,
            color = if (evidente) Colori.accento else Colori.testoSecondario,
        )
    }
}

// MARK: Aiuto dopo 15 secondi

@Composable
private fun ColumnScope.PaginaAiuto(qr: () -> Unit, cavo: () -> Unit, mandaLink: () -> Unit, aMano: () -> Unit, apriDomanda: (String) -> Unit) {
    val context = LocalContext.current
    // Wi-Fi e VPN si rileggono ogni 2 secondi: si vede subito quando l'utente li sistema.
    var rete by remember { mutableStateOf(statoRete(context)) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(2_000)
            rete = statoRete(context)
        }
    }
    // Un solo primario pieno: l'«Apri Impostazioni» del primo problema (la scheda della fotocamera, se c'è, viene prima).
    val primoProblemaWifi = !Permessi.fotocameraNegata && !rete.wifi
    val primoProblemaVpn = !Permessi.fotocameraNegata && rete.wifi && rete.vpn
    Pagina(
        contenuto = {
            Text(stringResource(R.string.non_trovo_computer), style = Stili.titoloGrande, color = Colori.testo, modifier = Modifier.semantics { heading() })
            Text(stringResource(R.string.controlla_tre_cose), style = Stili.corpo, color = Colori.testoSecondario)
            Controllo(1, stringResource(R.string.controllo_app_titolo), stringResource(R.string.controllo_app_testo))
            if (rete.wifi) {
                Controllo(2, stringResource(R.string.controllo_rete_titolo), stringResource(R.string.controllo_rete_testo))
            } else {
                Controllo(2, stringResource(R.string.controllo_rete_titolo), stringResource(R.string.controllo_rete_spento), problema = true, primario = primoProblemaWifi) {
                    apriImpostazioniDiSistema(
                        context,
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS,
                    )
                }
            }
            // Su Android la ricerca non chiede permessi (né «Dispositivi nelle vicinanze» né la posizione): il terzo
            // controllo è quello che più spesso nasconde il computer, una VPN accesa o una rete per ospiti.
            if (rete.vpn) {
                Controllo(3, stringResource(R.string.controllo_vpn_titolo), stringResource(R.string.controllo_vpn_testo), problema = true, primario = primoProblemaVpn) {
                    apriImpostazioniDiSistema(context, Settings.ACTION_VPN_SETTINGS)
                }
            } else {
                Controllo(3, stringResource(R.string.controllo_ospiti_titolo), stringResource(R.string.controllo_ospiti_testo))
            }
            PulsanteLink(stringResource(R.string.aiuto_altre_risposte), Modifier.fillMaxWidth()) { apriDomanda("non-trova") }
        },
        pulsanti = { StradePerCollegarsi(qr = qr, cavo = cavo, mandaLink = mandaLink, aMano = aMano) },
    )
}

/** P3: la fotocamera rifiutata, come un controllo in ambra con «Apri Impostazioni». */
@Composable
private fun SchedaFotocameraNegata(apri: () -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Raggi.pannello)).background(Colori.pannello)
            .border(1.dp, Colori.ambra, RoundedCornerShape(Raggi.pannello)).padding(Spazi.medio)
            .semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        Icon(Icons.Filled.NoPhotography, contentDescription = null, tint = Colori.ambraTesto)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spazi.minimo)) {
            Text(stringResource(R.string.permesso_fotocamera_negato), style = Stili.corpo, color = Colori.testo)
            PulsantePieno(stringResource(R.string.apri_impostazioni), Modifier.padding(top = Spazi.stretto), piccolo = true, tono = TonoPulsante.AMBRA, azione = apri)
        }
    }
}

/**
 * Un controllo numerato. `problema`: in ambra, con «Apri Impostazioni» se c'è `apri`: pieno se è il `primario` della
 * schermata (il primo problema), altrimenti bordato.
 */
@Composable
private fun Controllo(numero: Int, titolo: String, testo: String, problema: Boolean = false, primario: Boolean = false, apri: (() -> Unit)? = null) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(Raggi.pannello)).background(Colori.pannello).padding(Spazi.medio),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(26.dp).clip(CircleShape).background(if (problema) Colori.ambra else Colori.accento),
        ) { Text("$numero", style = Stili.notaForte, color = Colori.fondo) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spazi.minimo)) {
            Text(titolo, style = Stili.comando, color = Colori.testo)
            Text(testo, style = Stili.nota, color = Colori.testoSecondario)
            if (apri != null) {
                if (primario) {
                    PulsantePieno(
                        stringResource(R.string.apri_impostazioni), Modifier.padding(top = Spazi.stretto), piccolo = true,
                        tono = if (problema) TonoPulsante.AMBRA else TonoPulsante.ACCENTO, azione = apri,
                    )
                } else {
                    PulsanteSecondario(
                        stringResource(R.string.apri_impostazioni), Modifier.padding(top = Spazi.stretto), compatto = true, ambra = problema, azione = apri,
                    )
                }
            }
        }
    }
}

/** Il telefono è su una rete Wi-Fi (o è lui l'hotspot, o c'è il cavo); c'è una VPN accesa. */
private data class StatoRete(val wifi: Boolean, val vpn: Boolean)

@Suppress("DEPRECATION") // allNetworks: anche l'hotspot del telefono e il cavo, non solo la rete predefinita.
private fun statoRete(context: Context): StatoRete {
    val connessioni = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return StatoRete(wifi = true, vpn = false)
    return try {
        val reti = connessioni.allNetworks.mapNotNull { connessioni.getNetworkCapabilities(it) }
        val wifi = reti.any { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || it.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) } ||
            RicercaCavo.interfacceDelCavo().isNotEmpty()
        val vpn = reti.any { it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) }
        StatoRete(wifi, vpn)
    } catch (e: Exception) {
        StatoRete(wifi = true, vpn = false)
    }
}

private fun apriImpostazioniDiSistema(context: Context, azione: String) {
    try {
        context.startActivity(Intent(azione))
    } catch (e: ActivityNotFoundException) {
        try { context.startActivity(Intent(Settings.ACTION_SETTINGS)) } catch (e2: ActivityNotFoundException) { /* niente impostazioni */ }
    }
}

// MARK: Pulsanti e dialoghi

/**
 * Il cavo su Android è il Tethering USB: una rete sul cavo che non chiede niente al computer. Tre passi e un tasto
 * per le impostazioni del tethering (dove Android lo permette, altrimenti «Rete e Internet»).
 */
@Composable
private fun DialogoCavo(chiudi: () -> Unit, apriDomanda: () -> Unit) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = chiudi,
        icon = { Icon(Icons.Filled.Usb, contentDescription = null, tint = Colori.accento) },
        title = { Text(stringResource(R.string.usa_cavo_usb)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
                listOf(R.string.cavo_passo_1, R.string.cavo_passo_2, R.string.cavo_passo_3).forEachIndexed { indice, passo ->
                    Row(horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo)) {
                        Text("${indice + 1}", style = Stili.numeriEvidenti, color = Colori.accento)
                        Text(stringResource(passo), style = Stili.corpo, color = Colori.testoChiaro)
                    }
                }
                PulsanteLink(stringResource(R.string.come_funziona)) { apriDomanda() }
            }
        },
        confirmButton = {
            PulsanteLink(stringResource(R.string.apri_tethering)) {
                apriTethering(context)
                chiudi()
            }
        },
        dismissButton = { PulsanteLink(stringResource(R.string.chiudi), tenue = true) { chiudi() } },
    )
}

/** Le impostazioni del tethering: non c'è un'azione pubblica, si prova la pagina di sistema e poi «Rete e Internet». */
private fun apriTethering(context: Context) {
    val tethering = Intent().setComponent(ComponentName("com.android.settings", "com.android.settings.TetherSettings"))
    try {
        context.startActivity(tethering)
    } catch (e: Exception) {
        apriImpostazioniDiSistema(context, Settings.ACTION_WIRELESS_SETTINGS)
    }
}

@Composable
private fun DialogoIndirizzo(chiudi: () -> Unit, collega: (Associazione) -> Unit) {
    // P6: l'ultimo indirizzo valido torna proposto (salvato in Impostazioni), con il cursore in fondo.
    var testo by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        val ultimo = Impostazioni.ultimoIndirizzo
        mutableStateOf(TextFieldValue(ultimo, TextRange(ultimo.length)))
    }
    var nonValido by remember { mutableStateOf(false) }
    // Il pulsante «Collega» e il tasto Invio della tastiera fanno la stessa cosa.
    val prova = {
        val associazione = Associazione.daIndirizzoScritto(testo.text)
        if (associazione != null) {
            Impostazioni.ultimoIndirizzo = testo.text.trim()
            collega(associazione)
        } else {
            nonValido = true
        }
    }
    AlertDialog(
        onDismissRequest = chiudi,
        title = { Text(stringResource(R.string.indirizzo_titolo)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spazi.stretto)) {
                Text(stringResource(R.string.indirizzo_testo), style = Stili.corpo, color = Colori.testoChiaro)
                OutlinedTextField(
                    value = testo,
                    onValueChange = { testo = it; nonValido = false },
                    placeholder = { Text("192.168.1.20") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { prova() }, onDone = { prova() }),
                    isError = nonValido,
                    textStyle = Stili.numeriCorpo,
                    colors = coloriCampo(),
                )
                if (nonValido) Text(stringResource(R.string.indirizzo_non_valido), style = Stili.nota, color = Colori.ambraTesto)
            }
        },
        confirmButton = {
            PulsanteLink(stringResource(R.string.collega)) { prova() }
        },
        dismissButton = { PulsanteLink(stringResource(R.string.annulla), tenue = true) { chiudi() } },
    )
}
