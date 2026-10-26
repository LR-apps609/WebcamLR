package it.lrapps.webcamlr.android.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.acquisti.StatoPro
import kotlinx.coroutines.delay

/** La pagina «WebcamLR Pro» dalla sezione App (e dalle Impostazioni della lista dei computer). */
@Composable
fun SchermataPro(indietro: () -> Unit) {
    SchermataSecondaria("WebcamLR Pro", indietro) {
        ContenutoPro()
    }
}

/** «WebcamLR Pro» in un foglio con «Fine»: si apre toccando un comando con il segno «PRO» durante la sessione. */
@Composable
fun FoglioPro(chiudi: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        BarraTitolo("WebcamLR Pro", fine = chiudi)
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
            ContenutoPro()
        }
    }
}

/**
 * La pagina Pro come in Stile (PaginaPro e ConfrontoPro): titolo, stato o invito, acquisto con il prezzo di Google
 * Play, «Ripristina acquisti» e il confronto Gratis/Pro. Il pulsante è nell'accento con il testo scuro, mai corallo.
 */
@Composable
fun ContenutoPro() {
    val context = LocalContext.current
    val stato = Pro.stato()
    val attivo = stato.attivo
    val prezzo = stato.prezzo
    val inAttesa = stato.inAttesa
    val occupato = stato.operazione != StatoPro.Operazione.NESSUNA

    Column(verticalArrangement = Arrangement.spacedBy(20.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
            SegnoPro(grande = true)
            Text("WebcamLR Pro", style = Caratteri.titolo(28), color = Colori.testo)
        }
        if (attivo) {
            StatoProAttivo()
            Text(stringResource(R.string.pro_attivo_vale), style = Caratteri.corpo(15), color = Colori.testoSecondario)
            PulsanteRipristina(stato.operazione == StatoPro.Operazione.RIPRISTINO)
        } else {
            Text(stringResource(R.string.pro_invito), style = Caratteri.corpo(16), color = Colori.testoChiaro)
            Column(verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when {
                    // Senza Google Play (Huawei senza servizi Google) non si compra: lo si dice, niente attesa infinita.
                    !stato.giocoDisponibile -> Text(stringResource(R.string.pro_senza_play), style = Caratteri.corpo(15), color = Colori.ambraTesto, modifier = Modifier.fillMaxWidth())
                    prezzo != null -> PulsantePieno(
                        stringResource(R.string.pro_sblocca, prezzo),
                        abilitato = !inAttesa && !occupato,
                        inCorso = stato.operazione == StatoPro.Operazione.ACQUISTO,
                    ) {
                        context.trovaActivity()?.let { Pro.acquista(it) }
                    }
                    stato.prodottoNonTrovato -> Column(verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(stringResource(R.string.pro_play_non_risponde), style = Caratteri.corpo(15), color = Colori.ambraTesto, modifier = Modifier.fillMaxWidth())
                        PulsanteSecondario(stringResource(R.string.riprova)) { Pro.riprovaProdotto() }
                    }
                    else -> Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                        modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp),
                    ) {
                        CircularProgressIndicator(color = Colori.accento, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                        Text(stringResource(R.string.pro_collegamento_play), style = Caratteri.corpo(15), color = Colori.testoSecondario)
                    }
                }
                Text(stringResource(R.string.pro_una_volta), style = Caratteri.corpo(15), color = Colori.testoChiaro, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                if (inAttesa) {
                    Text(stringResource(R.string.pro_in_attesa), style = Caratteri.corpo(14), color = Colori.ambraTesto, modifier = Modifier.fillMaxWidth())
                }
                // La frase del negozio dopo un acquisto o un ripristino non riusciti.
                stato.avviso?.let { Text(it, style = Caratteri.corpo(14), color = Colori.ambraTesto, modifier = Modifier.fillMaxWidth()) }
                PulsanteRipristina(stato.operazione == StatoPro.Operazione.RIPRISTINO)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ColonnaConfronto(stringResource(R.string.pro_gratis), stringResource(R.string.pro_gratis_nota), vociGratis(), pro = false)
            ColonnaConfronto(stringResource(R.string.pro_pro), stringResource(R.string.pro_pro_nota), vociPro(), pro = true)
        }
    }
}

@Composable
private fun StatoProAttivo() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Colori.accentoTenue).padding(14.dp).semantics(mergeDescendants = true) {},
    ) {
        Icon(Icons.Filled.Verified, contentDescription = null, tint = Colori.accento, modifier = Modifier.size(28.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.pro_attivo), style = Caratteri.titolo(20), color = Colori.accentoChiaro)
            Text(stringResource(R.string.pro_attivo_grazie), style = Caratteri.corpo(15), color = Colori.testoChiaro)
        }
    }
}

@Composable
private fun PulsanteRipristina(inCorso: Boolean) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).clickable(enabled = !inCorso, role = Role.Button) { Pro.ripristina() }.padding(horizontal = 16.dp),
    ) {
        if (inCorso) CircularProgressIndicator(color = Colori.accento, strokeWidth = 2.dp, modifier = Modifier.size(16.dp))
        Text(stringResource(R.string.pro_ripristina), style = Caratteri.corpoForte(15), color = Colori.accento)
    }
}

@Composable
private fun ColonnaConfronto(titolo: String, nota: String, voci: List<String>, pro: Boolean) {
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(if (pro) Colori.pannelloChiaro else Colori.pannello)
            .border(1.dp, if (pro) Colori.accento.copy(alpha = 0.55f) else Colori.lineaTenue, RoundedCornerShape(14.dp)).padding(16.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = "$titolo, $nota"; heading() },
        ) {
            if (pro) SegnoPro() else Text(titolo, style = Caratteri.titolo(20), color = Colori.testo)
            Text(nota, style = Caratteri.corpo(14), color = Colori.testoSecondario)
        }
        for (voce in voci) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                Icon(
                    if (pro) Icons.Filled.Add else Icons.Filled.Check, contentDescription = null,
                    tint = if (pro) Colori.accento else Colori.testoSecondario, modifier = Modifier.padding(top = 2.dp).width(16.dp),
                )
                Text(voce, style = Caratteri.corpo(15), color = Colori.testoChiaro)
            }
        }
    }
}

/** Ciò che resta gratis, per sempre e senza filigrana (come ConfrontoPro.gratis in Stile, per Android). */
@Composable
private fun vociGratis() = listOf(
    stringResource(R.string.pro_gratis_1), stringResource(R.string.pro_gratis_2), stringResource(R.string.pro_gratis_3),
    stringResource(R.string.pro_gratis_4), stringResource(R.string.pro_gratis_5), stringResource(R.string.pro_gratis_6),
    stringResource(R.string.pro_gratis_7), stringResource(R.string.pro_gratis_8),
)

/** Ciò che aggiunge Pro, sul telefono e sul computer (come ConfrontoPro.pro in Stile). */
@Composable
private fun vociPro() = listOf(
    stringResource(R.string.pro_pro_1), stringResource(R.string.pro_pro_2),
    stringResource(R.string.pro_pro_4), stringResource(R.string.pro_pro_5), stringResource(R.string.pro_pro_6),
    stringResource(R.string.pro_pro_7), stringResource(R.string.pro_pro_8), stringResource(R.string.pro_pro_9),
    stringResource(R.string.pro_pro_10), stringResource(R.string.pro_pro_12),
    stringResource(R.string.pro_pro_13),
)

/** L'Activity dietro un contesto di Compose (serve a Google Play per mostrare l'acquisto). */
fun Context.trovaActivity(): Activity? {
    var attuale: Context? = this
    while (attuale is ContextWrapper) {
        if (attuale is Activity) return attuale
        attuale = attuale.baseContext
    }
    return null
}
