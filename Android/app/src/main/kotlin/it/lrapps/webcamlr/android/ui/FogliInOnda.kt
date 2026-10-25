package it.lrapps.webcamlr.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
import java.util.Locale
import kotlin.math.roundToInt

/** Il contenuto di un foglio di «In onda»: titolo con «Fine» (e «Indietro»), il resto scorre. */
@Composable
private fun CorpoFoglio(titolo: String, chiudi: () -> Unit, indietro: (() -> Unit)? = null, contenuto: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        BarraTitolo(titolo, indietro = indietro, fine = chiudi)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp), content = contenuto)
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
            val latenza = sessione.latenzaMs
            RigaValore(
                stringResource(R.string.dettagli_qualita),
                latenza?.let { "${testoQualita(QualitaCollegamento.da(it, sessione.perditeRecenti))} · $it ms" } ?: "— ms",
            )
        }
        EtichettaSezione(stringResource(R.string.video))
        Gruppo {
            val formato = sessione.formato
            RigaValore(
                stringResource(R.string.formato),
                formato?.let { "${minOf(it.larghezza, it.altezza)}p${it.fps} · ${SessioneTelefono.nomeCodec(it)}" } ?: "—",
            )
            RigaValore(stringResource(R.string.dettagli_zoom), String.format(Locale.getDefault(), "%.1f×", sessione.zoom))
            // Esposizione manuale dal computer o dai controlli Pro: la luce non si adatta più da sola.
            if (sessione.iso > 0 || sessione.tempo > 0) {
                val parti = buildList {
                    if (sessione.iso > 0) add("ISO ${sessione.iso.toInt()}")
                    if (sessione.tempo > 0) add("1/${maxOf(sessione.tempo, formato?.fps ?: 30)} s")
                }
                RigaValore(stringResource(R.string.dettagli_esposizione_manuale), parti.joinToString(" · "))
            }
        }
        EtichettaSezione(stringResource(R.string.dettagli_telefono))
        Gruppo {
            val batteria = when {
                sessione.batteria < 0 -> "—"
                sessione.inCarica -> stringResource(R.string.dettagli_batteria_in_carica, sessione.batteria)
                else -> "${sessione.batteria}%"
            }
            RigaValore(stringResource(R.string.dettagli_batteria), batteria)
            RigaValore(stringResource(R.string.dettagli_temperatura), descrizioneTemperatura(sessione.temperatura))
        }
        Spacer(Modifier.size(16.dp))
        Gruppo {
            RigaLink(stringResource(R.string.registro), icona = Icons.AutoMirrored.Filled.ListAlt) { registro = true }
        }
    }
}

// MARK: Effetti

/**
 * «Effetti» a metà schermo: sopra si vede l'anteprima. Sul telefono lo sfondo (sfocato gratis, sostituito con Pro);
 * filtri, ritocco e scritta si scelgono nella finestra di WebcamLR sul computer.
 */
@Composable
fun FoglioEffetti(sessione: SessioneTelefono, chiudi: () -> Unit, apriPro: () -> Unit) {
    val pro = Pro.attivo()
    val sfondo = sessione.sfondoOra()
    CorpoFoglio(stringResource(R.string.effetti), chiudi) {
        NotaSotto(stringResource(R.string.effetti_nota))
        EtichettaSezione(stringResource(R.string.sfondo))
        Gruppo {
            RigaScelta(
                stringResource(R.string.sfondo),
                listOf(
                    Opzione(ModiSfondo.NESSUNO, stringResource(R.string.sfondo_nessuno)),
                    Opzione(ModiSfondo.SFOCATO, stringResource(R.string.sfondo_sfocato)),
                    Opzione(ModiSfondo.SOSTITUITO, stringResource(R.string.sfondo_sostituito), pro = !pro),
                ),
                sfondo,
            ) { scelto -> if (scelto == ModiSfondo.SOSTITUITO && !pro) apriPro() else sessione.cambiaSfondo(scelto) }
        }
        NotaSotto(stringResource(if (pro) R.string.sfondo_nota else R.string.sfondo_nota_gratis))
        EtichettaSezione(stringResource(R.string.effetti_sul_computer))
        Gruppo { RigaInformazione(stringResource(R.string.effetti_sul_computer_testo)) }
    }
}

// MARK: Assistente

/** Le funzioni del volto durante la sessione: inquadratura automatica (Pro), luce sul volto, postura, faccia in giù. */
@Composable
fun FoglioAssistente(sessione: SessioneTelefono, chiudi: () -> Unit, apriPro: () -> Unit) {
    CorpoFoglio(stringResource(R.string.assistente), chiudi) {
        EtichettaSezione(stringResource(R.string.volto))
        Gruppo {
            RigaInterruttore(stringResource(R.string.inquadratura_automatica), PreferenzeInterfaccia.inquadratura, soloPro = true, apriPro = apriPro) { acceso ->
                PreferenzeInterfaccia.impostaInquadratura(acceso)
                sessione.mandaComando(Comando(inquadratura = acceso))
            }
            RigaInterruttore(stringResource(R.string.luce_volto), PreferenzeInterfaccia.luceVolto) { acceso ->
                PreferenzeInterfaccia.impostaLuceVolto(acceso)
                sessione.mandaComando(Comando(luceVolto = acceso))
            }
        }
        NotaSotto(stringResource(R.string.volto_nota))
        Spacer(Modifier.size(8.dp))
        Gruppo {
            RigaInterruttore(stringResource(R.string.promemoria_postura), PreferenzeInterfaccia.postura) { acceso ->
                PreferenzeInterfaccia.impostaPostura(acceso)
                sessione.mandaComando(Comando(postura = acceso))
            }
            RigaInterruttore(stringResource(R.string.pausa_faccia_in_giu), PreferenzeInterfaccia.facciaInGiu) { PreferenzeInterfaccia.impostaFacciaInGiu(it) }
        }
        NotaSotto(stringResource(R.string.postura_nota))
    }
}

// MARK: Controlli Pro

/** I tempi di posa proposti, come denominatori (60 = 1/60 s). */
private val TEMPI = listOf(30, 50, 60, 100, 125, 250, 500, 1000)

/**
 * «Controlli Pro» a metà schermo: compensazione dell'esposizione (gratis); ISO, tempo, bianco e messa a fuoco
 * automatica con WebcamLR Pro. Passano per un [Comando], la stessa strada dei comandi del computer, con gli stessi
 * limiti. Con «AE/AF bloccati» esposizione e messa a fuoco restano ferme finché non si sbloccano.
 */
@Composable
fun FoglioControlliPro(sessione: SessioneTelefono, chiudi: () -> Unit, apriPro: () -> Unit) {
    val pro = Pro.attivo()
    var esposizione by remember { mutableFloatStateOf(0f) }
    var bianco by remember { mutableFloatStateOf(0f) }
    var isoScelto by remember { mutableFloatStateOf(sessione.iso.toFloat().takeIf { it > 0f } ?: 400f) }
    CorpoFoglio(stringResource(R.string.controlli_pro), chiudi) {
        if (sessione.aeafBloccati) {
            Spacer(Modifier.size(8.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Colori.ambraTenue).padding(14.dp),
            ) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = Colori.ambraTesto)
                Text(stringResource(R.string.controlli_aeaf_bloccati), style = Caratteri.corpo(14), color = Colori.ambraTesto)
            }
        }

        EtichettaSezione(stringResource(R.string.esposizione))
        Gruppo {
            Cursore(
                stringResource(R.string.compensazione), esposizione, -2f..2f, passi = 39,
                valore = String.format(Locale.getDefault(), "%+.1f", esposizione).replace("+0,0", "0").replace("+0.0", "0"),
            ) { nuovo ->
                esposizione = nuovo
                sessione.mandaComando(Comando(esposizione = nuovo.toDouble()))
            }
            RigaInterruttore(stringResource(R.string.iso_automatico), sessione.iso <= 0.0, soloPro = true, apriPro = apriPro) { automatico ->
                sessione.mandaComando(Comando(iso = if (automatico) 0.0 else isoScelto.toDouble()))
            }
            if (pro && sessione.iso > 0) {
                Cursore("ISO", isoScelto, 50f..3200f, valore = isoScelto.roundToInt().toString()) { nuovo ->
                    isoScelto = nuovo
                    sessione.mandaComando(Comando(iso = nuovo.roundToInt().toDouble()))
                }
            }
            RigaInterruttore(stringResource(R.string.tempo_automatico), sessione.tempo <= 0, soloPro = true, apriPro = apriPro) { automatico ->
                sessione.mandaComando(Comando(tempo = if (automatico) 0 else maxOf(sessione.formato?.fps ?: 30, 60)))
            }
            if (pro && sessione.tempo > 0) {
                RigaScelta(
                    stringResource(R.string.tempo_di_posa),
                    TEMPI.filter { it >= (sessione.formato?.fps ?: 30) }.take(4).map { Opzione(it.toString(), "1/$it") },
                    sessione.tempo.toString(),
                ) { sessione.mandaComando(Comando(tempo = it.toInt())) }
            }
        }
        NotaSotto(stringResource(if (pro) R.string.controlli_nota else R.string.controlli_nota_gratis))

        EtichettaSezione(stringResource(R.string.bianco))
        Gruppo {
            RigaInterruttore(stringResource(R.string.bianco_automatico), bianco == 0f, soloPro = true, apriPro = apriPro) { automatico ->
                bianco = if (automatico) 0f else 5000f
                sessione.mandaComando(Comando(bianco = bianco.roundToInt()))
            }
            if (pro && bianco > 0f) {
                Cursore(stringResource(R.string.temperatura_colore), bianco, 2500f..7500f, valore = "${(bianco / 100).roundToInt() * 100} K") { nuovo ->
                    bianco = nuovo
                    sessione.mandaComando(Comando(bianco = (nuovo / 100).roundToInt() * 100))
                }
            }
        }

        EtichettaSezione(stringResource(R.string.messa_a_fuoco))
        Gruppo {
            val bloccato = !pro
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
                    .clickable(role = Role.Button) { if (bloccato) apriPro() else sessione.mandaComando(Comando(fuoco = "continuo")) }
                    .padding(horizontal = 14.dp, vertical = 6.dp),
            ) {
                Icon(Icons.Filled.CenterFocusStrong, contentDescription = null, tint = Colori.accento, modifier = Modifier.alpha(if (bloccato) 0.5f else 1f))
                Text(stringResource(R.string.fuoco_automatico), style = Caratteri.corpo(16), color = Colori.testo, modifier = Modifier.weight(1f).alpha(if (bloccato) 0.5f else 1f))
                if (bloccato) SegnoPro()
            }
        }
        NotaSotto(stringResource(R.string.fuoco_nota))
    }
}

/** Un cursore con titolo e valore a destra, come nel foglio «Effetti» dell'iPhone. */
@Composable
private fun Cursore(titolo: String, attuale: Float, intervallo: ClosedFloatingPointRange<Float>, passi: Int = 0, valore: String, cambia: (Float) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(titolo, style = Caratteri.corpo(16), color = Colori.testo, modifier = Modifier.weight(1f))
            Text(valore, style = Caratteri.numeriEvidenti(13), color = Colori.testoChiaro)
        }
        Slider(
            value = attuale.coerceIn(intervallo.start, intervallo.endInclusive),
            onValueChange = cambia,
            valueRange = intervallo,
            steps = passi,
            colors = SliderDefaults.colors(thumbColor = Colori.accento, activeTrackColor = Colori.accento, inactiveTrackColor = Colori.linea),
            modifier = Modifier.semantics { contentDescription = titolo },
        )
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
