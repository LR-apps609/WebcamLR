package it.lrapps.webcamlr.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.protocollo.QualitaCollegamento

/** Il contenuto di un foglio di «In onda»: titolo con «Fine» (e «Indietro»), il resto scorre. */
@Composable
private fun CorpoFoglio(titolo: String, chiudi: () -> Unit, indietro: (() -> Unit)? = null, contenuto: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        BarraTitolo(titolo, indietro = indietro, fine = chiudi)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Spazi.medio).padding(bottom = Spazi.largo), content = contenuto)
    }
}

// MARK: Dettagli

/** «Dettagli»: i numeri tolti da sopra il video, con un tocco sulla riga di stato. Si aggiornano dal vivo. */
@Composable
fun FoglioDettagli(sessione: SessioneTelefono, chiudi: () -> Unit) {
    var registro by remember { mutableStateOf(false) }
    BackHandler(enabled = registro) { registro = false }
    if (registro) {
        CorpoFoglio(stringResource(R.string.registro), chiudi, indietro = { registro = false }) { ContenutoRegistro() }
        return
    }
    CorpoFoglio(stringResource(R.string.dettagli), chiudi) {
        EtichettaSezione(stringResource(R.string.dettagli_collegamento))
        Gruppo {
            RigaValore(stringResource(R.string.dettagli_computer), sessione.computer.nome)
            sessione.tipoCollegamento?.let { RigaValore(stringResource(R.string.dettagli_tipo), testoTipoCollegamento(it)) }
            // L'app che usa la webcam sul computer (la pillola di «In onda» mostra il nome del computer).
            sessione.inOnda?.app?.let { RigaValore(stringResource(R.string.dettagli_in_onda), it) }
            val latenza = sessione.latenzaMs
            RigaValore(
                stringResource(R.string.dettagli_qualita),
                latenza?.let { "${testoQualita(QualitaCollegamento.da(it, sessione.perditeRecenti))} · $it ms" } ?: "— ms",
            )
        }
        EtichettaSezione(stringResource(R.string.video))
        Gruppo {
            val formato = sessione.formato
            // Il formato davvero inviato e, se è più basso di quello chiesto dal computer, il motivo in breve.
            val motivi = sessione.motiviRiduzioneMostrati?.let { testoMotiviRiduzione(it) }
            RigaValore(
                stringResource(R.string.formato),
                formato?.let {
                    "${SessioneTelefono.nomeQualita(it.larghezza, it.altezza)} · ${it.fps} fps · ${SessioneTelefono.nomeCodec(it)}" +
                        (motivi?.let { m -> " · $m" } ?: "")
                } ?: "—",
            )
            sessione.avvioSecondi.ora()?.let { secondi ->
                RigaValore(stringResource(R.string.dettagli_avvio), String.format(Testi.locale, "%.1f s", secondi))
            }
            RigaValore(stringResource(R.string.dettagli_zoom), String.format(Testi.locale, "%.1f×", sessione.zoom))
            // Il computer fa gli effetti di immagine: il telefono manda la fotocamera così com'è.
            if (sessione.effettiSulComputer.ora()) {
                RigaValore(stringResource(R.string.effetti), stringResource(R.string.dettagli_effetti_sul_computer))
            }
            // Esposizione manuale dal computer o dai controlli Pro: la luce non si adatta più da sola.
            if (sessione.iso > 0 || sessione.tempo > 0) {
                val parti = buildList {
                    if (sessione.iso > 0) add("ISO ${sessione.iso.toInt()}")
                    if (sessione.tempo > 0) add("1/${maxOf(sessione.tempo, formato?.fps ?: 30)} s")
                }
                RigaValore(stringResource(R.string.dettagli_esposizione_manuale), parti.joinToString(" · "))
            }
        }
        // L'anteprima di «In onda» è ritagliata per riempire lo schermo: lo si dice, il video inviato resta intero.
        NotaSotto(stringResource(R.string.dettagli_anteprima_ritagliata))
        EtichettaSezione(stringResource(R.string.dettagli_telefono))
        Gruppo {
            val batteria = when {
                sessione.batteria < 0 -> "—"
                sessione.inCarica -> stringResource(R.string.dettagli_batteria_in_carica, sessione.batteria)
                else -> "${sessione.batteria}%"
            }
            RigaValore(stringResource(R.string.dettagli_batteria), batteria)
            RigaValore(stringResource(R.string.dettagli_temperatura), descrizioneTemperatura(sessione.temperatura))
            // Il misuratore, aggiornato ogni secondo mentre il video va al computer.
            sessione.prestazioni?.let { RigaPrestazioni(SessioneTelefono.testoPrestazioni(it)) }
        }
        Spacer(Modifier.size(Spazi.medio))
        Gruppo {
            RigaLink(stringResource(R.string.registro), icona = Icons.AutoMirrored.Filled.ListAlt) { registro = true }
        }
    }
}

/** «Prestazioni»: come [RigaValore], ma il valore (lungo) va sotto il titolo e può andare a capo. */
@Composable
private fun RigaPrestazioni(valore: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(Spazi.minimo),
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = Spazi.medio, vertical = Spazi.stretto).semantics(mergeDescendants = true) {},
    ) {
        Text(stringResource(R.string.dettagli_prestazioni), style = Stili.corpo, color = Colori.testo)
        Text(valore, style = Stili.numeri, color = Colori.testoChiaro)
    }
}

// MARK: Domande

/** La risposta che spiega un errore, in un foglio con tutte le domande frequenti. */
@Composable
fun FoglioDomanda(aperta: String?, chiudi: () -> Unit) {
    CorpoFoglio(stringResource(R.string.domande_frequenti), chiudi) {
        ContenutoDomande(aperta)
    }
}
