package it.lrapps.webcamlr.android.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.QuestionAnswer
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.contenuti.DomandeFrequenti
import it.lrapps.webcamlr.android.contenuti.Guida
import it.lrapps.webcamlr.android.contenuti.InfoApp
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.IdentitaTelefono
import it.lrapps.webcamlr.android.dati.Impostazioni
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Sezione App: WebcamLR Pro, domande frequenti, guida, segnalazioni, computer conosciuti e informazioni, come sull'iPhone.
 * Niente «Accedi»: la 1.0 è senza account.
 */
@Composable
fun SchermataApp(indietro: () -> Unit, apriPro: () -> Unit, apriDomande: () -> Unit, apriGuida: () -> Unit, apriSegnala: () -> Unit) {
    val context = LocalContext.current
    var conosciuti by remember { mutableStateOf(ComputerConosciuti.tutti) }
    val pro = Pro.attivo()
    // «Togli computer» non chiede prima: toglie subito e per 8 secondi «Annulla» lo rimette (anche l'ultimo usato).
    val avvisoTolto = remember { SnackbarHostState() }
    val ambito = rememberCoroutineScope()
    var compitoTolto by remember { mutableStateOf<Job?>(null) }
    Box(Modifier.fillMaxSize()) {
        SchermataSecondaria("WebcamLR", indietro) {
            EtichettaSezione("WebcamLR Pro")
            Gruppo {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp).clickable(role = Role.Button, onClick = apriPro)
                        .semantics(mergeDescendants = true) {}.padding(horizontal = 14.dp, vertical = 10.dp),
                ) {
                    SegnoPro(grande = true)
                    Column(Modifier.weight(1f)) {
                        Text("WebcamLR Pro", style = Caratteri.corpoForte(17), color = Colori.testo)
                        Text(
                            stringResource(if (pro) R.string.app_pro_attivo else R.string.app_pro_invito),
                            style = Caratteri.corpo(14), color = if (pro) Colori.accentoChiaro else Colori.testoSecondario,
                        )
                    }
                }
            }

            // Solo nelle versioni di prova (Android Studio): Pro acceso o spento senza comprare, per provare i limiti
            // senza Play Console. Nella versione pubblicata la sezione non c'è e NegozioPro.simula non fa niente.
            if (BuildConfig.DEBUG) {
                EtichettaSezione(stringResource(R.string.prova_debug))
                Gruppo {
                    RigaInterruttore(stringResource(R.string.simula_pro), pro) { Pro.simula(it) }
                    RigaLink(stringResource(R.string.simula_pro_vero)) { Pro.simula(null) }
                }
                NotaSotto(stringResource(R.string.simula_pro_nota))
            }

            EtichettaSezione(stringResource(R.string.assistenza))
            Gruppo {
                RigaLink(stringResource(R.string.domande_frequenti), icona = Icons.Filled.QuestionAnswer, azione = apriDomande)
                RigaLink(stringResource(R.string.guida), icona = Icons.AutoMirrored.Filled.MenuBook, azione = apriGuida)
                RigaLink(stringResource(R.string.segnala_bug), icona = Icons.Filled.BugReport, azione = apriSegnala)
            }

            EtichettaSezione(stringResource(R.string.computer_conosciuti))
            Gruppo {
                if (conosciuti.isEmpty()) {
                    Text(stringResource(R.string.computer_conosciuti_vuoto), style = Caratteri.corpo(15), color = Colori.testoSecondario, modifier = Modifier.padding(14.dp))
                } else {
                    for (voce in conosciuti) {
                        val togli = stringResource(R.string.togli_computer, voce.nome)
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(start = 14.dp)) {
                            Column(Modifier.weight(1f).padding(vertical = 10.dp).semantics(mergeDescendants = true) {}) {
                                Text(voce.nome, style = Caratteri.corpoForte(16), color = Colori.testo)
                                Text(stringResource(R.string.codice_sicurezza, voce.impronta.take(8)), style = Caratteri.numeri(12), color = Colori.testoSecondario)
                            }
                            IconButton(onClick = {
                                val eraUltimo = Impostazioni.ultimoComputer == voce.nome
                                ComputerConosciuti.dimentica(voce.nome)
                                if (eraUltimo) Impostazioni.ultimoComputer = null
                                conosciuti = ComputerConosciuti.tutti
                                // Un altro computer tolto prima: il suo «Annulla» finisce qui, resta tolto.
                                compitoTolto?.cancel()
                                compitoTolto = ambito.launch {
                                    val risposta = withTimeoutOrNull(DURATA_ANNULLA_MS) {
                                        avvisoTolto.showSnackbar(
                                            message = context.getString(R.string.computer_tolto, voce.nome),
                                            actionLabel = context.getString(R.string.annulla_azione),
                                            duration = SnackbarDuration.Indefinite,
                                        )
                                    }
                                    if (risposta == SnackbarResult.ActionPerformed) {
                                        ComputerConosciuti.salva(voce.impronta, voce.nome)
                                        if (eraUltimo) Impostazioni.ultimoComputer = voce.nome
                                        conosciuti = ComputerConosciuti.tutti
                                    }
                                }
                            }) { Icon(Icons.Filled.Delete, contentDescription = togli, tint = Colori.testoSecondario) }
                        }
                    }
                }
            }
            NotaSotto(stringResource(R.string.computer_conosciuti_nota))

            EtichettaSezione(stringResource(R.string.informazioni))
            Gruppo {
                RigaValore(stringResource(R.string.versione), "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                RigaLink(stringResource(R.string.privacy), icona = Icons.Filled.PanTool) { apriIndirizzo(context, InfoApp.PRIVACY) }
                RigaLink(stringResource(R.string.sito), icona = Icons.Filled.Language) { apriIndirizzo(context, InfoApp.SITO) }
            }
            NotaSotto(stringResource(R.string.licenze))
            if (IdentitaTelefono.soloPerQuestaVolta) {
                NotaSotto(stringResource(R.string.identita_non_salvata))
            }
            Spacer(Modifier.height(20.dp))
            Text(stringResource(R.string.app_di_lr_apps), style = Caratteri.etichetta(16), color = Colori.testoChiaro, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Text(
                stringResource(R.string.stessa_famiglia, InfoApp.altreAppLR.joinToString(" · ")),
                style = Caratteri.corpo(14), color = Colori.testoSecondario, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
        }
    SnackbarHost(avvisoTolto, Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(16.dp)) { dati ->
        Snackbar(dati, containerColor = Colori.pannelloChiaro, contentColor = Colori.testo, actionColor = Colori.accentoChiaro)
    }
    }
}

/** Quanto resta «Annulla» dopo «Togli computer». */
private const val DURATA_ANNULLA_MS = 8_000L

fun apriIndirizzo(context: Context, indirizzo: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(indirizzo)))
    } catch (e: ActivityNotFoundException) {
        Toast.makeText(context, context.getString(R.string.nessun_browser, indirizzo), Toast.LENGTH_LONG).show()
    }
}

/** Domande frequenti, con ricerca, senza Internet. `aperta`: la risposta da mostrare subito (da un errore). */
@Composable
fun SchermataDomande(aperta: String?, indietro: () -> Unit) {
    SchermataSecondaria(stringResource(R.string.domande_frequenti), indietro) {
        ContenutoDomande(aperta)
    }
}

@Composable
fun ColumnScope.ContenutoDomande(aperta: String?) {
    val inglese = linguaInglese()
    var ricerca by rememberSaveable { mutableStateOf("") }
    var espansa by rememberSaveable { mutableStateOf(aperta) }
    OutlinedTextField(
        value = ricerca, onValueChange = { ricerca = it },
        placeholder = { Text(stringResource(R.string.cerca_domande), style = Caratteri.corpo(15)) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        singleLine = true,
        textStyle = Caratteri.corpo(16),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Colori.accento, unfocusedBorderColor = Colori.linea, cursorColor = Colori.accento,
            focusedContainerColor = Colori.pannello, unfocusedContainerColor = Colori.pannello,
        ),
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
    )
    val trovate = DomandeFrequenti.tutte(inglese).filter { it.corrisponde(ricerca) }.sortedByDescending { it.id == aperta }
    if (trovate.isEmpty()) NotaSotto(stringResource(R.string.nessuna_risposta, ricerca))
    val apertaTesto = stringResource(R.string.risposta_aperta)
    val chiusaTesto = stringResource(R.string.risposta_chiusa)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (domanda in trovate) {
            val aperto = espansa == domanda.id
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Colori.pannello).border(1.dp, Colori.linea, RoundedCornerShape(16.dp))
                    .clickable(role = Role.Button) { espansa = if (aperto) null else domanda.id }
                    .semantics { stateDescription = if (aperto) apertaTesto else chiusaTesto }
                    .padding(14.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(domanda.domanda, style = Caratteri.corpoForte(16), color = Colori.testo, modifier = Modifier.weight(1f))
                    Icon(if (aperto) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null, tint = Colori.testoSecondario)
                }
                if (aperto) {
                    Spacer(Modifier.height(8.dp))
                    Text(domanda.risposta, style = Caratteri.corpo(15), color = Colori.testoChiaro)
                }
            }
        }
    }
}

/** La guida: una sezione dopo l'altra, con i passi numerati, e il collegamento alle risposte del sito. */
@Composable
fun SchermataGuida(indietro: () -> Unit) {
    val context = LocalContext.current
    val inglese = linguaInglese()
    SchermataSecondaria(stringResource(R.string.guida), indietro) {
        for (sezione in Guida.sezioni(inglese)) {
            Text(sezione.titolo, style = Caratteri.titolo(22), color = Colori.testo, modifier = Modifier.padding(top = 20.dp, bottom = 8.dp).semantics { heading() })
            Scheda {
                sezione.passi.forEachIndexed { indice, passo ->
                    Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("${indice + 1}", style = Caratteri.numeriEvidenti(13), color = Colori.accento, textAlign = TextAlign.End, modifier = Modifier.width(18.dp))
                        Text(passo, style = Caratteri.corpo(15), color = Colori.testoChiaro)
                    }
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Gruppo {
            RigaLink(stringResource(R.string.altre_risposte_sito), icona = Icons.AutoMirrored.Filled.OpenInNew) { apriIndirizzo(context, InfoApp.AIUTO) }
        }
    }
}

/** «Segnala un bug»: la descrizione e, se si vuole, i dati tecnici (nessun dato personale). */
@Composable
fun SchermataSegnala(ultimaLatenzaMs: Int?, indietro: () -> Unit) {
    val context = LocalContext.current
    var descrizione by rememberSaveable { mutableStateOf("") }
    var conDati by rememberSaveable { mutableStateOf(true) }
    // Solo dati tecnici utili: niente nome del telefono né del computer, niente indirizzi.
    val datiTecnici = buildList {
        add(stringResource(R.string.dato_app) to "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        add(stringResource(R.string.dato_sistema) to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        add(stringResource(R.string.dato_modello) to "${Build.MANUFACTURER} ${Build.MODEL}")
        ultimaLatenzaMs?.let { add(stringResource(R.string.dato_latenza) to "$it ms") }
        if (Impostazioni.ultimoComputer != null) add(stringResource(R.string.dato_collegato_in_passato) to stringResource(R.string.si))
    }
    val intestazione = stringResource(R.string.dati_tecnici_intestazione)
    val titoloScelta = stringResource(R.string.segnala_bug)
    val oggetto = stringResource(R.string.oggetto_segnalazione)
    val nessunaApp = stringResource(R.string.nessuna_app_invio)
    val vuota = descrizione.isBlank()
    val etichettaCampo = stringResource(R.string.descrizione_problema)
    SchermataSecondaria(stringResource(R.string.segnala_bug), indietro) {
        Text(stringResource(R.string.segnala_domanda), style = Caratteri.corpoForte(16), color = Colori.testo, modifier = Modifier.padding(top = 8.dp, bottom = 8.dp))
        OutlinedTextField(
            value = descrizione, onValueChange = { descrizione = it },
            minLines = 5,
            textStyle = Caratteri.corpo(16),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = Colori.accento, unfocusedBorderColor = Colori.linea, cursorColor = Colori.accento,
                focusedContainerColor = Colori.pannello, unfocusedContainerColor = Colori.pannello,
            ),
            modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp).semantics { contentDescription = etichettaCampo },
        )
        Spacer(Modifier.height(12.dp))
        Gruppo { RigaInterruttore(stringResource(R.string.includi_dati), conDati) { conDati = it } }
        if (conDati) {
            Column(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(10.dp)).background(Colori.pannelloScuro).padding(12.dp)) {
                for ((nome, valore) in datiTecnici) {
                    Row(Modifier.fillMaxWidth()) {
                        Text(nome, style = Caratteri.corpo(13), color = Colori.testoSecondario, modifier = Modifier.weight(1f))
                        Text(valore, style = Caratteri.numeri(12), color = Colori.testoTenue)
                    }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        PulsantePieno(stringResource(R.string.invia_segnalazione), icona = Icons.AutoMirrored.Filled.Send, abilitato = !vuota) {
            val testo = InfoApp.testoSegnalazione(descrizione, if (conDati) datiTecnici else null, intestazione)
            val intento = if (InfoApp.EMAIL_ASSISTENZA.isNotEmpty()) {
                Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${InfoApp.EMAIL_ASSISTENZA}"))
                    .putExtra(Intent.EXTRA_SUBJECT, oggetto).putExtra(Intent.EXTRA_TEXT, testo)
            } else {
                Intent.createChooser(
                    Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, oggetto).putExtra(Intent.EXTRA_TEXT, testo),
                    titoloScelta,
                )
            }
            try {
                context.startActivity(intento)
            } catch (e: ActivityNotFoundException) {
                Toast.makeText(context, nessunaApp, Toast.LENGTH_LONG).show()
            }
        }
        NotaSotto(stringResource(R.string.segnala_nota))
    }
}
