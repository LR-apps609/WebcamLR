package it.lrapps.webcamlr.android.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.contenuti.DomandeFrequenti
import it.lrapps.webcamlr.android.contenuti.Guida
import it.lrapps.webcamlr.android.contenuti.InfoApp
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.IdentitaTelefono
import it.lrapps.webcamlr.android.dati.Impostazioni

/** Sezione App (0.12): domande frequenti, guida, segnalazioni, computer conosciuti e informazioni. */
@Composable
fun SchermataApp(indietro: () -> Unit, apriDomande: () -> Unit, apriGuida: () -> Unit, apriSegnala: () -> Unit) {
    val context = LocalContext.current
    var conosciuti by remember { mutableStateOf(ComputerConosciuti.tutti) }
    SchermataSecondaria("WebcamLR", indietro) {
        EtichettaSezione("Assistenza")
        Gruppo {
            RigaLink("Domande frequenti", azione = apriDomande)
            RigaLink("Guida", azione = apriGuida)
            RigaLink("Segnala un bug", azione = apriSegnala)
        }

        EtichettaSezione("Computer conosciuti")
        Gruppo {
            if (conosciuti.isEmpty()) {
                Text("Nessuno per ora: compaiono qui dopo il primo collegamento.", color = Colori.testoSecondario, modifier = Modifier.padding(14.dp))
            } else {
                for (voce in conosciuti) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(start = 14.dp)) {
                        Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                            Text(voce.nome, style = Caratteri.etichetta(17), color = Colori.testo)
                            Text("Codice di sicurezza ${voce.impronta.take(8)}", style = Caratteri.numeri(12), color = Colori.testoSecondario)
                        }
                        IconButton(onClick = {
                            ComputerConosciuti.dimentica(voce.nome)
                            if (Impostazioni.ultimoComputer == voce.nome) Impostazioni.ultimoComputer = null
                            conosciuti = ComputerConosciuti.tutti
                        }) { Icon(Icons.Filled.Delete, contentDescription = "Togli ${voce.nome}", tint = Colori.testoSecondario) }
                    }
                }
            }
        }
        NotaSotto("Togliendo un computer, la prossima volta andrà confermato di nuovo (codice di conferma o QR code).")

        EtichettaSezione("Informazioni")
        Gruppo {
            RigaLink("Versione", "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})") { }
            RigaLink("Privacy") { apriIndirizzo(context, InfoApp.PRIVACY) }
            RigaLink("Sito di WebcamLR") { apriIndirizzo(context, InfoApp.SITO) }
        }
        NotaSotto("Caratteri Barlow Condensed e IBM Plex Mono con licenza SIL Open Font License; lettura dei QR code con ZXing (Apache 2.0). Nessun servizio Google.")
        if (IdentitaTelefono.soloPerQuestaVolta) {
            NotaSotto("Il telefono non è riuscito a salvare i dati di sicurezza di WebcamLR: al prossimo avvio il computer chiederà di nuovo il codice di conferma.")
        }
        Spacer(Modifier.height(20.dp))
        Text("Un'app di LR Apps", style = Caratteri.etichetta(16), color = Colori.testoChiaro, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        Text(
            "Della stessa famiglia: ${InfoApp.altreAppLR.joinToString(" · ")}",
            color = Colori.testoSecondario, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
        )
    }
}

private fun apriIndirizzo(context: Context, indirizzo: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(indirizzo)))
    } catch (e: ActivityNotFoundException) {
        Toast.makeText(context, "Nessun browser installato: apri $indirizzo da un altro dispositivo.", Toast.LENGTH_LONG).show()
    }
}

/** Domande frequenti (1.4), con ricerca, senza Internet. `aperta`: la risposta da mostrare subito (da un errore). */
@Composable
fun SchermataDomande(aperta: String?, indietro: () -> Unit) {
    var ricerca by rememberSaveable { mutableStateOf("") }
    var espansa by rememberSaveable { mutableStateOf(aperta) }
    SchermataSecondaria("Domande frequenti", indietro) {
        OutlinedTextField(
            value = ricerca, onValueChange = { ricerca = it },
            placeholder = { Text("Cerca, per esempio «cavo» o «lento»") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        )
        val trovate = DomandeFrequenti.tutte.filter { it.corrisponde(ricerca) }
            .sortedByDescending { it.id == aperta }
        if (trovate.isEmpty()) {
            NotaSotto("Nessuna risposta per «$ricerca». Prova con un'altra parola, oppure usa «Segnala un bug».")
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (domanda in trovate) {
                val aperto = espansa == domanda.id
                Scheda(modifier = Modifier.clickable { espansa = if (aperto) null else domanda.id }) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(domanda.domanda, style = Caratteri.etichetta(18), color = Colori.testo, modifier = Modifier.weight(1f))
                        Icon(if (aperto) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null, tint = Colori.testoSecondario)
                    }
                    if (aperto) {
                        Spacer(Modifier.height(8.dp))
                        Text(domanda.risposta, color = Colori.testoChiaro)
                    }
                }
            }
        }
    }
}

@Composable
fun SchermataGuida(indietro: () -> Unit) {
    SchermataSecondaria("Guida", indietro) {
        for (sezione in Guida.sezioni) {
            EtichettaSezione(sezione.titolo)
            Scheda {
                sezione.passi.forEachIndexed { indice, passo ->
                    Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("${indice + 1}", style = Caratteri.numeriEvidenti(13), color = Colori.ciano)
                        Text(passo, color = Colori.testoChiaro)
                    }
                }
            }
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
        add("App" to "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        add("Sistema" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        add("Modello" to "${Build.MANUFACTURER} ${Build.MODEL}")
        ultimaLatenzaMs?.let { add("Ultima latenza" to "$it ms") }
        if (Impostazioni.ultimoComputer != null) add("Collegato in passato" to "sì")
    }
    SchermataSecondaria("Segnala un bug", indietro) {
        NotaSotto("Cosa è successo? Più dettagli scrivi (cosa stavi facendo, cosa ti aspettavi), più è facile correggerlo.")
        OutlinedTextField(
            value = descrizione, onValueChange = { descrizione = it },
            minLines = 5,
            modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
        )
        Spacer(Modifier.height(8.dp))
        Gruppo { RigaInterruttore("Includi i dati tecnici", conDati) { conDati = it } }
        if (conDati) {
            Column(Modifier.padding(horizontal = 4.dp, vertical = 6.dp)) {
                for ((nome, valore) in datiTecnici) Text("$nome: $valore", style = Caratteri.numeri(12), color = Colori.testoSecondario)
            }
        }
        Spacer(Modifier.height(12.dp))
        PulsantePieno("Invia") {
            val testo = InfoApp.testoSegnalazione(descrizione, if (conDati) datiTecnici else null)
            val intento = if (InfoApp.EMAIL_ASSISTENZA.isNotEmpty()) {
                Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${InfoApp.EMAIL_ASSISTENZA}"))
                    .putExtra(Intent.EXTRA_SUBJECT, InfoApp.OGGETTO_SEGNALAZIONE).putExtra(Intent.EXTRA_TEXT, testo)
            } else {
                Intent.createChooser(
                    Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, InfoApp.OGGETTO_SEGNALAZIONE).putExtra(Intent.EXTRA_TEXT, testo),
                    "Segnala un bug",
                )
            }
            try {
                context.startActivity(intento)
            } catch (e: ActivityNotFoundException) {
                Toast.makeText(context, "Nessuna app per inviare il testo: copialo e mandalo per email.", Toast.LENGTH_LONG).show()
            }
        }
    }
}
