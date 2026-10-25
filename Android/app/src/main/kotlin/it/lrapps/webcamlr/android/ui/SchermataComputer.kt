package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LaptopMac
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.filled.WifiFind
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.rete.CercaComputer
import it.lrapps.webcamlr.android.rete.ComputerTrovato
import it.lrapps.webcamlr.protocollo.Associazione
import it.lrapps.webcamlr.protocollo.Piattaforma
import kotlinx.coroutines.delay

/** Ricollegamento automatico (novità 2): una volta sola per avvio dell'app. */
private object Ricollegamento {
    var fatto = false
}

/** «Scegli il computer» (bozza grafica, telefono 1). */
@Composable
fun SchermataComputer(
    collega: (ComputerTrovato) -> Unit,
    apriLettore: () -> Unit,
    apriImpostazioni: () -> Unit,
    apriApp: () -> Unit,
    apriDomanda: (String) -> Unit,
    inPrimoPiano: Boolean,
) {
    val context = LocalContext.current
    val cerca = remember { CercaComputer(context) }
    var mostraAiuto by rememberSaveable { mutableStateOf(false) }
    var mostraIndirizzo by remember { mutableStateOf(false) }
    var ricollegaA by remember { mutableStateOf<ComputerTrovato?>(null) }
    var secondi by remember { mutableIntStateOf(3) }

    DisposableEffect(Unit) {
        cerca.avvia()
        onDispose { cerca.ferma() }
    }
    LaunchedEffect(Unit) {
        delay(8_000)
        mostraAiuto = true
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

    Box(Modifier.fillMaxSize().background(Colori.sfondoSchermata).safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 640.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                LogoWebcamLR(34.dp)
                MarchioWebcamLR(26)
                Spacer(Modifier.weight(1f))
                PulsanteTondo(Icons.Filled.Info, stringResource(R.string.app_e_assistenza)) { annullaRicollegamento(); apriApp() }
                PulsanteTondo(Icons.Filled.Settings, stringResource(R.string.impostazioni)) { annullaRicollegamento(); apriImpostazioni() }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.scegli_computer), style = Caratteri.titolo(40), color = Colori.testo, modifier = Modifier.semantics { heading() })
                Text(stringResource(R.string.scegli_computer_testo), style = Caratteri.corpo(16), color = Colori.testoSecondario)
            }

            val trovati = cerca.computer.size
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Colori.pannelloScuro)
                    .border(1.dp, Colori.linea, RoundedCornerShape(12.dp)).padding(horizontal = 14.dp, vertical = 10.dp)
                    .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
            ) {
                Icon(Icons.Filled.WifiFind, contentDescription = null, tint = Colori.accento)
                Text(
                    stringResource(if (cerca.stato == CercaComputer.Stato.ERRORE) R.string.ricerca_ferma else R.string.ricerca_in_corso),
                    style = Caratteri.corpo(15),
                    color = Colori.testo,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    if (trovati == 1) stringResource(R.string.trovato_uno) else stringResource(R.string.trovati, trovati),
                    style = Caratteri.numeri(12), color = Colori.testoSecondario,
                )
            }

            ricollegaA?.let { computer ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Colori.accentoTenue)
                        .border(1.dp, Colori.accento, RoundedCornerShape(16.dp)).padding(horizontal = 14.dp, vertical = 6.dp)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                ) {
                    CircularProgressIndicator(color = Colori.accento, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
                    Text(stringResource(R.string.ricollego_tra, computer.nome, secondi), style = Caratteri.corpo(15), color = Colori.testo, modifier = Modifier.weight(1f))
                    TextButton(onClick = { annullaRicollegamento() }) { Text(stringResource(R.string.annulla), style = Caratteri.corpoForte(15), color = Colori.accentoChiaro) }
                }
            }

            if (mostraAiuto && cerca.computer.isEmpty()) SchedaAiuto(apriDomanda)

            for (computer in cerca.computer) {
                RigaComputer(computer) { annullaRicollegamento(); collega(computer) }
            }

            SchedaCavo(apriDomanda)

            Spacer(Modifier.height(8.dp))
            PulsantePieno(stringResource(R.string.inquadra_qr), chiaro = true, icona = Icons.Filled.QrCodeScanner) {
                annullaRicollegamento()
                apriLettore()
            }
            TextButton(
                onClick = { annullaRicollegamento(); mostraIndirizzo = true },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            ) {
                Text(stringResource(R.string.inserisci_indirizzo), style = Caratteri.corpoForte(16), color = Colori.accentoChiaro)
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
}

@Composable
private fun RigaComputer(computer: ComputerTrovato, collega: () -> Unit) {
    val descrizione = when (computer.piattaforma) {
        Piattaforma.MAC -> stringResource(R.string.computer_mac)
        Piattaforma.WINDOWS -> stringResource(R.string.computer_windows)
        else -> stringResource(R.string.collegamento_wifi)
    }
    val etichetta = stringResource(R.string.collega_a, computer.nome)
    // Tutta la riga si tocca, non solo «Collega»: si fa prima, anche con una mano.
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Colori.pannello)
            .border(1.dp, Colori.linea, RoundedCornerShape(16.dp))
            .clickable(role = Role.Button, onClickLabel = etichetta, onClick = collega)
            .padding(14.dp)
            .semantics(mergeDescendants = true) { contentDescription = "$etichetta, $descrizione" },
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(Colori.accentoTenue),
        ) {
            Icon(
                if (computer.piattaforma == Piattaforma.WINDOWS) Icons.Filled.Computer else Icons.Filled.LaptopMac,
                contentDescription = null, tint = Colori.accento,
            )
        }
        Column(Modifier.weight(1f)) {
            Text(computer.nome, style = Caratteri.corpoForte(18), color = Colori.testo)
            Text(descrizione, style = Caratteri.corpo(14), color = Colori.testoSecondario)
        }
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.clip(RoundedCornerShape(50)).background(Colori.accento).padding(horizontal = 14.dp, vertical = 8.dp),
        ) {
            Text(stringResource(R.string.collega), style = Caratteri.corpoForte(15), color = Colori.fondo)
        }
    }
}

/** Le stesse soluzioni della pagina Aiuto del sito, nell'ordine in cui capitano più spesso (funzione 34). */
@Composable
private fun SchedaAiuto(apriDomanda: (String) -> Unit) {
    Scheda(sfondo = Colori.ambraTenue, bordo = null) {
        Text(stringResource(R.string.aiuto_titolo), style = Caratteri.titolo(26), color = Colori.testo, modifier = Modifier.semantics { heading() })
        Spacer(Modifier.height(8.dp))
        val passi = listOf(
            stringResource(R.string.aiuto_1), stringResource(R.string.aiuto_2),
            stringResource(R.string.aiuto_3), stringResource(R.string.aiuto_4),
        )
        passi.forEachIndexed { indice, passo ->
            Row(Modifier.padding(vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${indice + 1}", style = Caratteri.numeriEvidenti(13), color = Colori.ambraTesto)
                Text(passo, style = Caratteri.corpo(15), color = Colori.testoChiaro)
            }
        }
        TextButton(onClick = { apriDomanda("non-trova") }) {
            Text(stringResource(R.string.aiuto_altre_risposte), style = Caratteri.corpoForte(15), color = Colori.accentoChiaro)
        }
    }
}

/** Il cavo USB su Android: tethering USB, una rete sul cavo che non richiede niente sul computer (vedi LEGGIMI). */
@Composable
private fun SchedaCavo(apriDomanda: (String) -> Unit) {
    Scheda(sfondo = Colori.pannelloScuro) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(Colori.pannello),
            ) {
                Icon(Icons.Filled.Usb, contentDescription = null, tint = Colori.testoSecondario)
            }
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.cavo_titolo), style = Caratteri.corpoForte(17), color = Colori.testo)
                Text(stringResource(R.string.cavo_testo), style = Caratteri.corpo(14), color = Colori.testoSecondario)
                TextButton(onClick = { apriDomanda("cavo") }) { Text(stringResource(R.string.come_funziona), style = Caratteri.corpoForte(15), color = Colori.accentoChiaro) }
            }
        }
    }
}

@Composable
private fun DialogoIndirizzo(chiudi: () -> Unit, collega: (Associazione) -> Unit) {
    var testo by rememberSaveable { mutableStateOf("") }
    var nonValido by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = chiudi,
        containerColor = Colori.pannello,
        title = { Text(stringResource(R.string.indirizzo_titolo), style = Caratteri.titolo(26), color = Colori.testo) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.indirizzo_testo), style = Caratteri.corpo(15), color = Colori.testoChiaro)
                OutlinedTextField(
                    value = testo,
                    onValueChange = { testo = it; nonValido = false },
                    placeholder = { Text("192.168.1.20") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    isError = nonValido,
                    textStyle = Caratteri.numeri(16),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = Colori.accento, unfocusedBorderColor = Colori.linea, cursorColor = Colori.accento),
                )
                if (nonValido) Text(stringResource(R.string.indirizzo_non_valido), style = Caratteri.corpo(14), color = Colori.ambraTesto)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val associazione = Associazione.daIndirizzoScritto(testo)
                if (associazione != null) collega(associazione) else nonValido = true
            }) { Text(stringResource(R.string.collega), style = Caratteri.corpoForte(16), color = Colori.accentoChiaro) }
        },
        dismissButton = { TextButton(onClick = chiudi) { Text(stringResource(R.string.annulla), style = Caratteri.corpoForte(16), color = Colori.testoSecondario) } },
    )
}
