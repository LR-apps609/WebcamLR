package it.lrapps.webcamlr.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.material.icons.filled.Delete
import androidx.compose.runtime.mutableIntStateOf
import it.lrapps.webcamlr.protocollo.Filtri
import it.lrapps.webcamlr.protocollo.Regolazioni
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
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.protocollo.Comando
import it.lrapps.webcamlr.protocollo.ModiSfondo
import it.lrapps.webcamlr.protocollo.QualitaCollegamento
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
            RigaValore(
                stringResource(R.string.formato),
                formato?.let { "${SessioneTelefono.nomeQualita(it.larghezza, it.altezza)} · ${it.fps} fps · ${SessioneTelefono.nomeCodec(it)}" } ?: "—",
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
        Spacer(Modifier.size(16.dp))
        Gruppo {
            RigaLink(stringResource(R.string.registro), icona = Icons.AutoMirrored.Filled.ListAlt) { registro = true }
        }
    }
}

/** «Prestazioni»: come [RigaValore], ma il valore (lungo) va sotto il titolo e può andare a capo. */
@Composable
private fun RigaPrestazioni(valore: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 8.dp).semantics(mergeDescendants = true) {},
    ) {
        Text(stringResource(R.string.dettagli_prestazioni), style = Caratteri.corpo(16), color = Colori.testo)
        Text(valore, style = Caratteri.numeri(13), color = Colori.testoChiaro)
    }
}

// MARK: Effetti

/**
 * «Effetti» a metà schermo: sopra si vede l'anteprima con gli effetti, come la riceve il computer. Filtri e regolazioni,
 * sfondo (sfocato gratis, sostituito con Pro: l'immagine si sceglie sul computer), ritocco della pelle e logo. Quello che il
 * telefono non sa fare ([SessioneTelefono.funzioni]) non compare. Senza Pro i comandi Pro hanno il segno e aprono Pro.
 */
@Composable
fun FoglioEffetti(sessione: SessioneTelefono, chiudi: () -> Unit, apriPro: () -> Unit) {
    val pro = Pro.attivo()
    val effetti = sessione.effetti.ora()
    val funzioni = sessione.funzioni.ora()
    var giro by remember { mutableIntStateOf(0) }
    CorpoFoglio(stringResource(R.string.effetti), chiudi) {
        NotaSotto(stringResource(R.string.effetti_nota))

        if (funzioni.filtri) {
            EtichettaSezione(stringResource(R.string.filtri))
            Gruppo {
                val filtri = Filtri.TUTTI.map { Opzione(it, nomeFiltro(it), pro = !pro && it != Filtri.NATURALE) }
                for (riga in filtri.chunked(3)) {
                    RigaScelta(null, riga, effetti.filtro) { scelto ->
                        if (!pro && scelto != Filtri.NATURALE) apriPro() else sessione.applica(Comando(filtro = scelto))
                    }
                }
                if (pro) {
                    Cursore(stringResource(R.string.luminosita), effetti.luminosita.toFloat(), -1f..1f, valore = percento(effetti.luminosita)) {
                        sessione.applica(Comando(regolazioni = Regolazioni(luminosita = it.toDouble())))
                    }
                    Cursore(stringResource(R.string.contrasto), effetti.contrasto.toFloat(), -1f..1f, valore = percento(effetti.contrasto)) {
                        sessione.applica(Comando(regolazioni = Regolazioni(contrasto = it.toDouble())))
                    }
                    Cursore(stringResource(R.string.saturazione), effetti.saturazione.toFloat(), -1f..1f, valore = percento(effetti.saturazione)) {
                        sessione.applica(Comando(regolazioni = Regolazioni(saturazione = it.toDouble())))
                    }
                    Cursore(stringResource(R.string.nitidezza), effetti.nitidezza.toFloat(), -1f..1f, valore = percento(effetti.nitidezza)) {
                        sessione.applica(Comando(regolazioni = Regolazioni(nitidezza = it.toDouble())))
                    }
                }
            }
            if (!pro) NotaSotto(stringResource(R.string.filtri_nota_gratis))
        }

        EtichettaSezione(stringResource(R.string.sfondo))
        if (funzioni.sfondo) {
            Gruppo {
                RigaScelta(
                    null,
                    listOf(
                        Opzione(ModiSfondo.NESSUNO, stringResource(R.string.sfondo_nessuno)),
                        Opzione(ModiSfondo.SFOCATO, stringResource(R.string.sfondo_sfocato)),
                        Opzione(ModiSfondo.SOSTITUITO, stringResource(R.string.sfondo_sostituito), pro = !pro),
                    ),
                    effetti.sfondo,
                ) { scelto -> if (scelto == ModiSfondo.SOSTITUITO && !pro) apriPro() else sessione.scegliSfondo(scelto) }
                if (effetti.sfondo != ModiSfondo.NESSUNO) {
                    Cursore(
                        stringResource(if (effetti.sfondo == ModiSfondo.SFOCATO) R.string.intensita_sfocatura else R.string.bordo_sfondo),
                        effetti.intensitaSfondo.toFloat(), 0f..1f, valore = percento(effetti.intensitaSfondo),
                    ) { sessione.applica(Comando(intensitaSfondo = it.toDouble())) }
                }
            }
            NotaSotto(stringResource(if (pro) R.string.sfondo_nota else R.string.sfondo_nota_gratis))
        } else {
            Gruppo { RigaInformazione(stringResource(R.string.sfondo_non_disponibile)) }
        }

        if (funzioni.pelle) {
            EtichettaSezione(stringResource(R.string.ritocco_pelle))
            Gruppo {
                RigaInterruttore(stringResource(R.string.ritocco_pelle), effetti.pelle > 0.0, soloPro = true, apriPro = apriPro) { acceso ->
                    sessione.applica(Comando(pelle = if (acceso) effetti.ultimaPelle else 0.0))
                }
                if (pro && effetti.pelle > 0.0) {
                    Cursore(stringResource(R.string.intensita), effetti.pelle.toFloat(), 0.01f..1f, valore = percento(effetti.pelle)) {
                        sessione.applica(Comando(pelle = it.toDouble()))
                    }
                }
            }
            NotaSotto(stringResource(R.string.ritocco_nota))
        }

        if (funzioni.scritta) {
            EtichettaSezione(stringResource(R.string.logo))
            Gruppo {
                // `giro` cambia dopo una scelta: si rilegge `haLogo`, che non si osserva.
                val haLogo = remember(giro, effetti) { sessione.haLogo }
                if (haLogo) {
                    RigaInterruttore(stringResource(R.string.mostra_logo), effetti.mostraLogo, soloPro = true, apriPro = apriPro) { sessione.impostaMostraLogo(it) }
                    RigaLink(stringResource(R.string.togli_logo), icona = Icons.Filled.Delete) { sessione.togliLogo(); giro++ }
                } else {
                    RigaInformazione(stringResource(R.string.logo_dal_computer))
                }
            }
            NotaSotto(stringResource(R.string.logo_nota))
        }
    }
}

private fun percento(valore: Double): String = "${(valore * 100).roundToInt()}"

@Composable
private fun nomeFiltro(filtro: String): String = stringResource(
    when (filtro) {
        Filtri.CALDO -> R.string.filtro_caldo
        Filtri.FREDDO -> R.string.filtro_freddo
        Filtri.LUMINOSO -> R.string.filtro_luminoso
        Filtri.CINEMA -> R.string.filtro_cinema
        Filtri.VIVIDO -> R.string.filtro_vivido
        Filtri.TENUE -> R.string.filtro_tenue
        Filtri.BIANCO_NERO -> R.string.filtro_bianco_nero
        Filtri.SEPPIA -> R.string.filtro_seppia
        Filtri.NOTTE -> R.string.filtro_notte
        else -> R.string.filtro_naturale
    },
)

// MARK: Assistente

/**
 * Le funzioni del volto durante la sessione: inquadratura automatica (Pro), luce sul volto, postura, faccia in giù.
 * I valori veri sono quelli della sessione ([SessioneTelefono.effetti]), che li salva; senza rilevamento dei volti
 * restano solo la spiegazione e la pausa a faccia in giù.
 */
@Composable
fun FoglioAssistente(sessione: SessioneTelefono, chiudi: () -> Unit, apriPro: () -> Unit) {
    val effetti = sessione.effetti.ora()
    val volti = sessione.funzioni.ora().volti
    CorpoFoglio(stringResource(R.string.assistente), chiudi) {
        EtichettaSezione(stringResource(R.string.volto))
        if (volti) {
            Gruppo {
                RigaInterruttore(stringResource(R.string.inquadratura_automatica), effetti.inquadratura, soloPro = true, apriPro = apriPro) {
                    sessione.applica(Comando(inquadratura = it))
                }
                RigaInterruttore(stringResource(R.string.luce_volto), effetti.luceVolto) { sessione.applica(Comando(luceVolto = it)) }
            }
            NotaSotto(stringResource(R.string.volto_nota))
        } else {
            Gruppo { RigaInformazione(stringResource(R.string.volti_non_disponibili)) }
        }
        Spacer(Modifier.size(8.dp))
        Gruppo {
            if (volti) {
                RigaInterruttore(stringResource(R.string.promemoria_postura), effetti.postura) { sessione.applica(Comando(postura = it)) }
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
 * automatica con WebcamLR Pro. Passano per [SessioneTelefono.applica], la stessa strada dei comandi del computer,
 * con gli stessi limiti; i valori mostrati sono quelli usati ([SessioneTelefono.controlli]).
 */
@Composable
fun FoglioControlliPro(sessione: SessioneTelefono, chiudi: () -> Unit, apriPro: () -> Unit) {
    val pro = Pro.attivo()
    val controlli = sessione.controlli.ora()
    var isoScelto by remember { mutableFloatStateOf(controlli.iso.toFloat().takeIf { it > 0f } ?: 400f) }
    val fps = sessione.formato?.fps ?: 30
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
            val esposizione = controlli.esposizione.toFloat()
            Cursore(
                stringResource(R.string.compensazione), esposizione, -2f..2f, passi = 39,
                valore = if (kotlin.math.abs(esposizione) < 0.05f) "0" else String.format(Testi.locale, "%+.1f", esposizione),
            ) { sessione.impostaEsposizione(it.toDouble()) }
            RigaInterruttore(stringResource(R.string.iso_automatico), controlli.iso <= 0.0, soloPro = true, apriPro = apriPro) { automatico ->
                sessione.applica(Comando(iso = if (automatico) 0.0 else isoScelto.toDouble()))
            }
            if (pro && controlli.iso > 0) {
                Cursore("ISO", isoScelto, 50f..3200f, valore = isoScelto.roundToInt().toString()) { nuovo ->
                    isoScelto = nuovo
                    sessione.applica(Comando(iso = nuovo.roundToInt().toDouble()))
                }
            }
            RigaInterruttore(stringResource(R.string.tempo_automatico), controlli.tempo <= 0, soloPro = true, apriPro = apriPro) { automatico ->
                sessione.applica(Comando(tempo = if (automatico) 0 else maxOf(fps, 60)))
            }
            if (pro && controlli.tempo > 0) {
                RigaScelta(
                    stringResource(R.string.tempo_di_posa),
                    TEMPI.filter { it >= fps }.take(4).map { Opzione(it.toString(), "1/$it") },
                    controlli.tempo.toString(),
                ) { sessione.applica(Comando(tempo = it.toInt())) }
            }
        }
        NotaSotto(stringResource(if (pro) R.string.controlli_nota else R.string.controlli_nota_gratis))

        EtichettaSezione(stringResource(R.string.bianco))
        Gruppo {
            val bianco = controlli.bianco
            RigaInterruttore(stringResource(R.string.bianco_automatico), bianco == 0, soloPro = true, apriPro = apriPro) { automatico ->
                sessione.applica(Comando(bianco = if (automatico) 0 else 5000))
            }
            if (pro && bianco > 0) {
                Cursore(stringResource(R.string.temperatura_colore), bianco.toFloat(), 2500f..7500f, valore = "$bianco K") { nuovo ->
                    sessione.applica(Comando(bianco = (nuovo / 100).roundToInt() * 100))
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
                    .clickable(role = Role.Button) { if (bloccato) apriPro() else sessione.applica(Comando(fuoco = "continuo")) }
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
