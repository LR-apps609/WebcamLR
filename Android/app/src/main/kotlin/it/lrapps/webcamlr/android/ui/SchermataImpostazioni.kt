package it.lrapps.webcamlr.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.sistema.RegistroCollegamento

/** Struttura comune delle schermate secondarie: barra con «Indietro» e titolo, contenuto che scorre. */
@Composable
fun SchermataSecondaria(titolo: String, indietro: () -> Unit, contenuto: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().background(Colori.fondo).safeDrawingPadding()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp)) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).clickable(onClickLabel = "Indietro", onClick = indietro)
                    .padding(12.dp).semantics { contentDescription = "Indietro" },
            ) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = Colori.testo) }
            Text(titolo, style = Caratteri.titolo(26), color = Colori.testo, modifier = Modifier.padding(start = 4.dp))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp), content = contenuto)
    }
}

/** Un gruppo di righe su sfondo pannello, come le sezioni delle impostazioni di sistema. */
@Composable
fun Gruppo(contenuto: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Colori.pannello), content = contenuto)
}

@Composable
fun RigaInterruttore(testo: String, valore: Boolean, cambia: (Boolean) -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Switch) { cambia(!valore) }.padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        Text(testo, color = Colori.testo, modifier = Modifier.weight(1f))
        Switch(
            checked = valore, onCheckedChange = cambia,
            colors = SwitchDefaults.colors(checkedTrackColor = Colori.ciano, checkedThumbColor = Colori.fondo),
        )
    }
}

@Composable
fun RigaLink(testo: String, valore: String? = null, azione: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(onClick = azione).padding(horizontal = 14.dp),
    ) {
        Text(testo, color = Colori.testo, modifier = Modifier.weight(1f))
        if (valore != null) Text(valore, style = Caratteri.numeri(13), color = Colori.testoSecondario)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Colori.testoSecondario)
    }
}

@Composable
fun NotaSotto(testo: String) {
    Text(testo, color = Colori.testoSecondario, modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp))
}

/** Scelta tra pochi valori, a pastiglie (risoluzione, fotogrammi, formato). */
@Composable
private fun RigaScelta(titolo: String, opzioni: List<Pair<String, String>>, scelta: String, scegli: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(titolo, color = Colori.testo)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((valore, etichetta) in opzioni) {
                val scelto = valore == scelta
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(12.dp))
                        .background(if (scelto) Colori.cianoTenue else Colori.pannelloScuro)
                        .border(1.dp, if (scelto) Colori.ciano else Colori.linea, RoundedCornerShape(12.dp))
                        .clickable { scegli(valore) }.padding(horizontal = 14.dp)
                        .semantics { selected = scelto },
                ) { Text(etichetta, style = Caratteri.numeriEvidenti(14), color = if (scelto) Colori.cianoChiaro else Colori.testo) }
            }
        }
    }
}

/** Impostazioni (bozza grafica, telefono 2). Valgono dal prossimo collegamento. Modalità avanzata (1.5). */
@Composable
fun SchermataImpostazioni(indietro: () -> Unit, apriRegistro: () -> Unit) {
    SchermataSecondaria("Impostazioni", indietro) {
        if (Impostazioni.modalitaAvanzata) {
            EtichettaSezione("Video")
            Gruppo {
                RigaScelta("Risoluzione", listOf("720p" to "720p", "1080p" to "1080p", "4K" to "4K"), Impostazioni.risoluzione) { Impostazioni.impostaRisoluzione(it) }
                RigaScelta("Fotogrammi", listOf("24" to "24 fps", "30" to "30 fps", "60" to "60 fps"), Impostazioni.fps.toString()) { Impostazioni.impostaFps(it.toInt()) }
                RigaScelta("Formato", listOf("h264" to "H.264", "hevc" to "HEVC"), Impostazioni.codec) { Impostazioni.impostaCodec(it) }
            }
            NotaSotto("HEVC: stessa qualità con meno dati, utile in 4K; se il telefono non ha il codificatore HEVC si usa H.264. Su Windows serve l'estensione HEVC di Microsoft. 4K e 60 fps dipendono dal telefono: se non li regge, WebcamLR scende da sola.")
        }

        EtichettaSezione("Profili")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((nome, risoluzione, fps) in listOf(Triple("Riunione", "1080p", 30), Triple("Dirette", "1080p", 60), Triple("Ritratto", "4K", 30))) {
                val scelto = Impostazioni.risoluzione == risoluzione && Impostazioni.fps == fps
                Column(
                    Modifier.weight(1f).heightIn(min = 64.dp).clip(RoundedCornerShape(14.dp))
                        .background(if (scelto) Colori.cianoTenue else Colori.pannello)
                        .border(1.dp, if (scelto) Colori.ciano else Colori.linea, RoundedCornerShape(14.dp))
                        .clickable {
                            Impostazioni.impostaRisoluzione(risoluzione)
                            Impostazioni.impostaFps(fps)
                        }
                        .padding(12.dp)
                        .semantics { selected = scelto },
                ) {
                    Text(nome, style = Caratteri.etichetta(17), color = Colori.testo)
                    Text("$risoluzione$fps", style = Caratteri.numeri(12), color = Colori.testoSecondario)
                }
            }
        }
        if (!Impostazioni.modalitaAvanzata) {
            NotaSotto("Risoluzione e formato si scelgono con la modalità avanzata, in fondo.")
        }

        EtichettaSezione("Inquadratura")
        Gruppo {
            RigaInterruttore("Griglia dei terzi", Impostazioni.griglia) { Impostazioni.impostaGriglia(it) }
        }
        NotaSotto("Si vede solo sul telefono, non nel video.")

        EtichettaSezione("Audio")
        Gruppo {
            Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Microfono del telefono", color = Colori.testo, modifier = Modifier.weight(1f))
                Text("In arrivo", style = Caratteri.etichetta(15), color = Colori.testoSecondario)
            }
        }

        EtichettaSezione("Durante l'uso")
        Gruppo {
            RigaInterruttore("Specchia l'immagine inviata", Impostazioni.specchia) { Impostazioni.impostaSpecchia(it) }
            RigaInterruttore("Riduci la qualità se si scalda", Impostazioni.riduciSeCaldo) { Impostazioni.impostaRiduciSeCaldo(it) }
            RigaInterruttore("Oscura lo schermo dopo 30 secondi senza tocchi", Impostazioni.oscuraDaSolo) { Impostazioni.impostaOscuraDaSolo(it) }
            RigaInterruttore("Risparmio batteria: 24 fps sotto il 20%", Impostazioni.risparmioBatteria) { Impostazioni.impostaRisparmioBatteria(it) }
        }

        EtichettaSezione("Avanzate")
        Gruppo {
            RigaInterruttore("Modalità avanzata", Impostazioni.modalitaAvanzata) { Impostazioni.impostaModalitaAvanzata(it) }
            if (Impostazioni.modalitaAvanzata) RigaLink("Registro del collegamento", azione = apriRegistro)
        }
        NotaSotto("Mostra formato e risoluzione, i dati tecnici in «In onda» (millisecondi, risoluzione, formato) e il registro del collegamento.")
        Text(
            "WebcamLR · versione ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
            style = Caratteri.numeri(12), color = Colori.testoSecondario,
            modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

/** Il registro del collegamento (1.5), per chi vuole capire cosa è successo. */
@Composable
fun SchermataRegistro(indietro: () -> Unit) {
    SchermataSecondaria("Registro del collegamento", indietro) {
        val righe = RegistroCollegamento.tutte()
        if (righe.isEmpty()) {
            NotaSotto("Ancora niente: le righe compaiono dal primo collegamento.")
        } else {
            Gruppo {
                for (riga in righe.asReversed()) {
                    Text(riga, style = Caratteri.numeri(12), color = Colori.testoChiaro, modifier = Modifier.padding(horizontal = 14.dp, vertical = 4.dp))
                }
            }
        }
    }
}
