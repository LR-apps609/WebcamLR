package it.lrapps.webcamlr.android.ui

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Share
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.sistema.Permessi
import it.lrapps.webcamlr.android.logica.MotivoRiduzione
import it.lrapps.webcamlr.android.logica.PreferenzeCollegamento
import it.lrapps.webcamlr.android.logica.RegolaCollegamento
import it.lrapps.webcamlr.android.logica.Strada
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sessione.SessioneTelefono.Stato
import it.lrapps.webcamlr.android.sistema.RegistroCollegamento
import it.lrapps.webcamlr.protocollo.Comando

// MARK: Pezzi comuni delle schermate secondarie

/** Struttura comune delle schermate secondarie: barra con «Indietro» e titolo, contenuto che scorre. */
@Composable
fun SchermataSecondaria(titolo: String, indietro: () -> Unit, contenuto: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().background(Colori.sfondoSchermata).safeDrawingPadding()) {
        BarraTitolo(titolo, indietro = indietro)
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(), content = contenuto)
        }
    }
}

/** La barra in cima: «Indietro» (se c'è), il titolo e, nei fogli, «Fine». */
@Composable
fun BarraTitolo(titolo: String, indietro: (() -> Unit)? = null, fine: (() -> Unit)? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 6.dp)) {
        if (indietro != null) {
            val etichetta = stringResource(R.string.indietro)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.size(48.dp).clip(RoundedCornerShape(24.dp))
                    .clickable(role = Role.Button, onClickLabel = etichetta, onClick = indietro)
                    .semantics { contentDescription = etichetta },
            ) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = Colori.testo) }
        } else {
            Spacer(Modifier.size(12.dp))
        }
        Text(
            titolo, style = Caratteri.titolo(26), color = Colori.testo, maxLines = 2,
            modifier = Modifier.weight(1f).padding(start = 4.dp).semantics { heading() },
        )
        if (fine != null) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp))
                    .clickable(role = Role.Button, onClick = fine).padding(horizontal = 14.dp),
            ) { Text(stringResource(R.string.fine), style = Caratteri.corpoForte(17), color = Colori.accento) }
        }
    }
}

/** Un gruppo di righe su sfondo pannello, come le sezioni delle impostazioni di sistema. */
@Composable
fun Gruppo(contenuto: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Colori.pannello).border(1.dp, Colori.lineaTenue, RoundedCornerShape(14.dp)),
        content = contenuto,
    )
}

/**
 * Un interruttore. `soloPro`: fa parte di WebcamLR Pro; senza Pro si vede attenuato con il segno «PRO» e un tocco
 * apre la pagina Pro invece di cambiarlo.
 */
@Composable
fun RigaInterruttore(
    testo: String,
    valore: Boolean,
    icona: ImageVector? = null,
    soloPro: Boolean = false,
    apriPro: () -> Unit = {},
    cambia: (Boolean) -> Unit,
) {
    val bloccato = soloPro && !Pro.attivo()
    val descrizioneBloccato = stringResource(R.string.pro_funzione)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(
                if (bloccato) {
                    Modifier.clickable(role = Role.Button, onClickLabel = descrizioneBloccato, onClick = apriPro)
                } else {
                    Modifier.toggleable(value = valore, role = Role.Switch, onValueChange = cambia)
                },
            )
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        if (icona != null) Icon(icona, contentDescription = null, tint = Colori.accento, modifier = Modifier.alpha(if (bloccato) 0.5f else 1f))
        Row(Modifier.weight(1f).alpha(if (bloccato) 0.5f else 1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(testo, style = Caratteri.corpo(16), color = Colori.testo, modifier = Modifier.weight(1f, fill = false))
        }
        if (bloccato) SegnoPro()
        Switch(
            checked = valore,
            onCheckedChange = null,
            enabled = !bloccato,
            colors = SwitchDefaults.colors(
                checkedTrackColor = Colori.accento, checkedThumbColor = Colori.fondo, checkedBorderColor = Colori.accento,
                uncheckedTrackColor = Colori.pannelloScuro, uncheckedThumbColor = Colori.testoSecondario, uncheckedBorderColor = Colori.bordo,
            ),
        )
    }
}

/** Una riga che apre una pagina o un foglio. */
@Composable
fun RigaLink(testo: String, icona: ImageVector? = null, valore: String? = null, pro: Boolean = false, nota: String? = null, azione: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = azione).padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        if (icona != null) Icon(icona, contentDescription = null, tint = Colori.accento)
        if (nota == null) {
            Text(testo, style = Caratteri.corpo(16), color = Colori.testo, modifier = Modifier.weight(1f))
        } else {
            // Una riga in più sotto il nome, per dire cosa succede toccandola.
            Column(Modifier.weight(1f)) {
                Text(testo, style = Caratteri.corpo(16), color = Colori.testo)
                Text(nota, style = Caratteri.corpo(14), color = Colori.testoSecondario)
            }
        }
        if (pro) SegnoPro()
        if (valore != null) Text(valore, style = Caratteri.numeri(13), color = Colori.testoSecondario)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Colori.testoSecondario)
    }
}

/** Una riga che dice soltanto qualcosa, senza azione. */
@Composable
fun RigaInformazione(testo: String, icona: ImageVector? = null) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 14.dp, vertical = 6.dp).semantics(mergeDescendants = true) {},
    ) {
        if (icona != null) Icon(icona, contentDescription = null, tint = Colori.testoSecondario)
        Text(testo, style = Caratteri.corpo(16), color = Colori.testoSecondario, modifier = Modifier.weight(1f))
    }
}

/** Titolo e valore, come i numeri dei «Dettagli». */
@Composable
fun RigaValore(titolo: String, valore: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 6.dp).semantics(mergeDescendants = true) {},
    ) {
        Text(titolo, style = Caratteri.corpo(16), color = Colori.testo, modifier = Modifier.weight(1f))
        Text(valore, style = Caratteri.numeri(13), color = Colori.testoChiaro, textAlign = TextAlign.End)
    }
}

@Composable
fun NotaSotto(testo: String) {
    Text(testo, style = Caratteri.corpo(14), color = Colori.testoSecondario, modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 6.dp))
}

/** Una scelta tra pochi valori, a pastiglie. Una pastiglia `pro` mostra il segno. */
@Composable
fun RigaScelta(titolo: String?, opzioni: List<Opzione>, scelta: String, scegli: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (titolo != null) Text(titolo, style = Caratteri.corpo(16), color = Colori.testo, modifier = Modifier.semantics { heading() })
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            for (opzione in opzioni) {
                val scelto = opzione.valore == scelta
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                    modifier = Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp))
                        .background(if (scelto) Colori.accentoTenue else Colori.pannelloScuro)
                        .border(if (scelto) 1.5.dp else 1.dp, if (scelto) Colori.accento else Colori.linea, RoundedCornerShape(12.dp))
                        .clickable(role = Role.RadioButton) { scegli(opzione.valore) }
                        .semantics { selected = scelto }
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                ) {
                    Text(opzione.etichetta, style = Caratteri.numeriEvidenti(14), color = if (scelto) Colori.accentoChiaro else Colori.testo, maxLines = 1)
                    if (opzione.pro) SegnoPro()
                }
            }
        }
    }
}

data class Opzione(val valore: String, val etichetta: String, val pro: Boolean = false)

// MARK: Impostazioni

/** Le pagine delle Impostazioni. */
enum class PaginaImpostazioni { Principale, Registro }

/** Le voci di «Altro» che aprono una schermata dell'app (dalla lista dei computer o da «In onda»). */
enum class VoceAltro { Aiuto, Segnala, ComputerConosciuti, Informazioni }

/** Cosa possono aprire le Impostazioni fuori da sé: la pagina Pro, le schermate di «Altro» e una risposta (`id`). */
class AzioniImpostazioni(val apriPro: () -> Unit, val apriAltro: (VoceAltro) -> Unit, val apriDomanda: (String) -> Unit = {})

@Composable
fun titoloPagina(pagina: PaginaImpostazioni): String = stringResource(
    when (pagina) {
        PaginaImpostazioni.Principale -> R.string.impostazioni
        PaginaImpostazioni.Registro -> R.string.registro
    },
)

/**
 * Le Impostazioni aperte dalla lista dei computer: una pagina per schermata, nella pila di MainActivity. La pagina
 * principale come il foglio di «In onda», con «Fine» in alto a destra.
 */
@Composable
fun SchermataPaginaImpostazioni(pagina: PaginaImpostazioni, indietro: () -> Unit, apri: (PaginaImpostazioni) -> Unit, azioni: AzioniImpostazioni) {
    if (pagina == PaginaImpostazioni.Principale) {
        Column(Modifier.fillMaxSize().background(Colori.sfondoSchermata).safeDrawingPadding()) {
            BarraTitolo(titoloPagina(pagina), fine = indietro)
            Column(
                Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(Modifier.widthIn(max = 640.dp).fillMaxWidth()) {
                    ContenutoPaginaImpostazioni(pagina, sessione = null, apri = apri, azioni = azioni)
                }
            }
        }
    } else {
        SchermataSecondaria(titoloPagina(pagina), indietro) {
            ContenutoPaginaImpostazioni(pagina, sessione = null, apri = apri, azioni = azioni)
        }
    }
}

/** Le stesse Impostazioni aperte da «In onda», in un foglio con «Fine»; il Registro si apre dentro il foglio. */
@Composable
fun FoglioImpostazioni(sessione: SessioneTelefono, chiudi: () -> Unit, azioni: AzioniImpostazioni) {
    val pagine = remember { mutableStateListOf(PaginaImpostazioni.Principale) }
    val attuale = pagine.last()
    BackHandler(enabled = pagine.size > 1) { pagine.removeAt(pagine.lastIndex) }
    Column(Modifier.fillMaxWidth()) {
        BarraTitolo(
            titoloPagina(attuale),
            indietro = if (pagine.size > 1) ({ pagine.removeAt(pagine.lastIndex) }) else null,
            fine = chiudi,
        )
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 24.dp)) {
            ContenutoPaginaImpostazioni(attuale, sessione = sessione, apri = { pagine.add(it) }, azioni = azioni)
        }
    }
}

@Composable
private fun ColumnScope.ContenutoPaginaImpostazioni(
    pagina: PaginaImpostazioni,
    sessione: SessioneTelefono?,
    apri: (PaginaImpostazioni) -> Unit,
    azioni: AzioniImpostazioni,
) {
    when (pagina) {
        PaginaImpostazioni.Principale -> ContenutoImpostazioni(sessione, apri, azioni)
        PaginaImpostazioni.Registro -> ContenutoRegistro()
    }
}

/**
 * Le Impostazioni del telefono: una lista sola e semplice, solo ciò che riguarda il telefono. Nell'ordine:
 * WebcamLR Pro · Video · Fotocamera · Collegamento · Schermo e batteria · Altro. Effetti, inquadratura automatica,
 * assistente e controlli Pro si comandano dal computer.
 */
@Composable
private fun ColumnScope.ContenutoImpostazioni(
    sessione: SessioneTelefono?,
    apri: (PaginaImpostazioni) -> Unit,
    azioni: AzioniImpostazioni,
) {
    val context = LocalContext.current
    val pro = Pro.attivo()

    // 1. WebcamLR Pro, sempre in cima: «Sblocca» o «Attivo ✓», apre la pagina Pro.
    EtichettaSezione("WebcamLR Pro")
    Gruppo {
        val stato = stringResource(if (pro) R.string.pro_riga_attivo else R.string.pro_riga_sblocca)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = azioni.apriPro)
                .semantics(mergeDescendants = true) { stateDescription = stato }.padding(horizontal = 14.dp, vertical = 6.dp),
        ) {
            SegnoPro()
            Text("WebcamLR Pro", style = Caratteri.corpoForte(16), color = Colori.testo, modifier = Modifier.weight(1f))
            Text(stato, style = Caratteri.corpoForte(15), color = if (pro) Colori.accentoChiaro else Colori.accento, maxLines = 1)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Colori.testoSecondario)
        }
    }

    // 2. Video: quello che il telefono manda, in sola lettura (la qualità si sceglie sul computer).
    SezioneVideo(sessione)

    // 3. Fotocamera: aiuti solo sul telefono, non nel video.
    EtichettaSezione(stringResource(R.string.sezione_fotocamera))
    Gruppo {
        RigaInterruttore(stringResource(R.string.griglia), Impostazioni.griglia) { Impostazioni.impostaGriglia(it) }
        RigaInterruttore(stringResource(R.string.livella), PreferenzeInterfaccia.livella) { PreferenzeInterfaccia.impostaLivella(it) }
        // La torcia: durante la sessione e solo con un obiettivo che ce l'ha (si comanda anche dal computer).
        if (sessione != null && sessione.obiettivo != null && sessione.haTorcia) {
            RigaInterruttore(stringResource(R.string.torcia), sessione.torciaAccesa) { sessione.cambiaTorcia() }
        }
    }
    NotaSotto(stringResource(R.string.inquadratura_nota))

    // 4. Collegamento.
    SezioneCollegamento(sessione)

    // 5. Schermo e batteria.
    EtichettaSezione(stringResource(R.string.sezione_schermo_batteria))
    Gruppo {
        RigaInterruttore(stringResource(R.string.oscura_da_solo), Impostazioni.oscuraDaSolo) { Impostazioni.impostaOscuraDaSolo(it) }
        RigaInterruttore(stringResource(R.string.pausa_faccia_in_giu), PreferenzeInterfaccia.facciaInGiu) { PreferenzeInterfaccia.impostaFacciaInGiu(it) }
        // Durante la sessione il valore vero è quello della sessione; prima si salva e la sessione lo legge.
        if (sessione != null) {
            RigaInterruttore(stringResource(R.string.promemoria_postura), sessione.effetti.ora().postura) { sessione.applica(Comando(postura = it)) }
        } else {
            RigaInterruttore(stringResource(R.string.promemoria_postura), PreferenzeInterfaccia.postura) { PreferenzeInterfaccia.impostaPostura(it) }
        }
        RigaInterruttore(stringResource(R.string.riduci_se_caldo), Impostazioni.riduciSeCaldo) { Impostazioni.impostaRiduciSeCaldo(it) }
        RigaInterruttore(stringResource(R.string.risparmio_batteria), Impostazioni.risparmioBatteria) { Impostazioni.impostaRisparmioBatteria(it) }
        // P4: il risparmio energetico di Android può fermare il video a schermo spento. Si rilegge a ogni ritorno
        // nell'app (MainActivity.onStart), quindi dopo «Apri Impostazioni» il valore cambia da solo.
        val senzaLimiti = Permessi.senzaLimitiBatteria
        RigaValore(stringResource(R.string.senza_limiti_batteria), stringResource(if (senzaLimiti) R.string.si else R.string.no))
        if (!senzaLimiti) {
            Column(
                Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(stringResource(R.string.batteria_limitata), style = Caratteri.corpo(14), color = Colori.ambraTesto)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    PillolaAzione(stringResource(R.string.apri_impostazioni)) { Permessi.apriBatteria(context) }
                    // I consigli per marca (Samsung, Xiaomi, Huawei…) nella risposta «Il video si ferma quando spengo lo schermo».
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier.heightIn(min = 44.dp).clickable(role = Role.Button) { azioni.apriDomanda("schermo-spento") }
                            .padding(horizontal = 8.dp),
                    ) { Text(stringResource(R.string.perche_succede), style = Caratteri.corpoForte(15), color = Colori.accentoChiaro) }
                }
            }
        }
    }
    NotaSotto(stringResource(R.string.durante_uso_nota))

    // 6. Altro.
    EtichettaSezione(stringResource(R.string.sezione_altro))
    Gruppo {
        RigaLink(stringResource(R.string.aiuto)) { azioni.apriAltro(VoceAltro.Aiuto) }
        RigaLink(stringResource(R.string.segnala_bug)) { azioni.apriAltro(VoceAltro.Segnala) }
        RigaLink(stringResource(R.string.computer_conosciuti)) { azioni.apriAltro(VoceAltro.ComputerConosciuti) }
        // In diretta si esce dall'app: lo si dice (il video continua grazie al servizio in primo piano).
        RigaLink(
            stringResource(R.string.lingua), valore = stringResource(R.string.lingua_attuale),
            nota = if (sessione != null) stringResource(R.string.lingua_nota_in_onda) else null,
        ) { apriLingua(context) }
        RigaLink(stringResource(R.string.informazioni)) { azioni.apriAltro(VoceAltro.Informazioni) }
        // Solo sul telefono: il registro del collegamento visto da qui.
        RigaLink(stringResource(R.string.registro)) { apri(PaginaImpostazioni.Registro) }
    }
    Text(
        stringResource(R.string.versione_app, "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"),
        style = Caratteri.numeri(12), color = Colori.testoSecondario, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
    )
}

/**
 * «Lingua»: la lingua di WebcamLR nelle impostazioni di sistema (da Android 13), prima la lingua del telefono.
 * L'app parla italiano se la lingua è l'italiano, inglese in tutte le altre.
 */
private fun apriLingua(context: Context) {
    val perApp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.fromParts("package", context.packageName, null))
    } else {
        null
    }
    for (intento in listOfNotNull(perApp, Intent(Settings.ACTION_LOCALE_SETTINGS))) {
        try {
            context.startActivity(intento)
            return
        } catch (e: ActivityNotFoundException) {
            // si prova la successiva
        }
    }
}

/**
 * «Collegamento al computer»: Automatico, Wi-Fi o Cavo USB (Documenti/Interfaccia finale.md). Durante la sessione
 * vale subito e mostra le strade con la latenza e «più veloce ora» (solo un'informazione: Automatico non cambia per
 * la latenza). La stessa scelta arriva anche dal computer.
 */
@Composable
private fun ColumnScope.SezioneCollegamento(sessione: SessioneTelefono?) {
    val stato = sessione?.statoCollegamento
    val scelta = stato?.preferenza ?: Impostazioni.collegamento
    val scegli = { valore: String -> if (sessione != null) sessione.impostaPreferenzaCollegamento(valore) else Impostazioni.impostaCollegamento(valore) }
    EtichettaSezione(stringResource(R.string.collegamento_sezione))
    Gruppo {
        RigaOpzione(stringResource(R.string.collegamento_automatico), scelta == PreferenzeCollegamento.AUTOMATICO) { scegli(PreferenzeCollegamento.AUTOMATICO) }
        RigaOpzione(stringResource(R.string.collegamento_wifi), scelta == PreferenzeCollegamento.WIFI) { scegli(PreferenzeCollegamento.WIFI) }
        RigaOpzione(stringResource(R.string.collegamento_cavo_usb), scelta == PreferenzeCollegamento.CAVO) { scegli(PreferenzeCollegamento.CAVO) }
    }
    if (stato != null) {
        val misure = stato.strade.mapNotNull { strada -> strada.ms?.let { ms -> Strada.entries.firstOrNull { it.valore == strada.tipo }?.let { it to ms } } }.toMap()
        val veloce = if (stato.strade.size > 1) RegolaCollegamento.piuVeloce(misure) else null
        val inUso = stringResource(R.string.collegamento_in_uso)
        val piuVeloce = stringResource(R.string.piu_veloce_ora)
        Spacer(Modifier.size(8.dp))
        Gruppo {
            for (strada in stato.strade) {
                val tipo = Strada.entries.firstOrNull { it.valore == strada.tipo } ?: continue
                val attiva = SessioneTelefono.stradaDi(sessione?.tipoCollegamento ?: continue) == tipo
                val valore = listOfNotNull(
                    if (attiva) inUso else null,
                    strada.ms?.let { "$it ms" },
                    if (tipo == veloce) piuVeloce else null,
                ).joinToString(" · ").ifEmpty { "—" }
                RigaValore(stringResource(if (tipo == Strada.CAVO) R.string.collegamento_cavo_usb else R.string.collegamento_wifi), valore)
            }
        }
    }
    NotaSotto(stringResource(R.string.collegamento_nota))
}

/** Una scelta tra poche voci, una per riga, con il segno di spunta su quella scelta. */
@Composable
private fun RigaOpzione(testo: String, scelta: Boolean, scegli: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
            .clickable(role = Role.RadioButton, onClick = scegli)
            .semantics { selected = scelta }
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        Text(testo, style = Caratteri.corpo(16), color = if (scelta) Colori.accentoChiaro else Colori.testo, modifier = Modifier.weight(1f))
        if (scelta) Icon(Icons.Filled.Check, contentDescription = null, tint = Colori.accento)
    }
}

/**
 * «Video»: la qualità che il telefono manda adesso, in sola lettura. Dal 27 ottobre (decisione di Ledion) qualità,
 * fotogrammi e formato si scelgono solo sul computer, sopra il video: qui niente scelte che il computer poi
 * cambierebbe. Se il telefono ha abbassato la qualità chiesta (calore, batteria, versione gratuita, obiettivo) la riga
 * dice perché, così i numeri tornano.
 */
@Composable
private fun ColumnScope.SezioneVideo(sessione: SessioneTelefono?) {
    val formato = sessione?.takeIf { it.stato == Stato.Collegato }?.formato
    EtichettaSezione(stringResource(R.string.video))
    Gruppo {
        RigaValore(
            stringResource(R.string.qualita_video),
            formato?.let { "${SessioneTelefono.nomeQualita(it.larghezza, it.altezza)} · ${it.fps} fps · ${SessioneTelefono.nomeCodec(it)}" } ?: "—",
        )
        val motivi = if (formato != null) sessione?.motiviRiduzioneMostrati else null
        if (motivi != null) {
            Text(
                testoMotiviRiduzione(motivi),
                style = Caratteri.corpo(14),
                color = Colori.testoSecondario,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 10.dp),
            )
        }
    }
    NotaSotto(stringResource(if (formato != null) R.string.qualita_dal_computer else R.string.qualita_dal_computer_scollegato))
}

/** I motivi della qualità ridotta in breve, «ridotta per il calore, 24 fps per risparmiare batteria». */
@Composable
fun testoMotiviRiduzione(motivi: List<MotivoRiduzione>): String = motivi.map {
    stringResource(
        when (it) {
            MotivoRiduzione.CALORE -> R.string.riduzione_calore
            MotivoRiduzione.BATTERIA -> R.string.riduzione_batteria
            MotivoRiduzione.GRATIS -> R.string.riduzione_gratis
            MotivoRiduzione.OBIETTIVO -> R.string.riduzione_obiettivo
        },
    )
}.joinToString(", ")

/**
 * Il registro del collegamento, per chi vuole capire cosa è successo. Si aggiorna mentre è aperto; in cima «Copia» e
 * «Condividi», e le righe si possono selezionare (passo 9, P7).
 */
@Composable
fun ColumnScope.ContenutoRegistro() {
    val context = LocalContext.current
    val righe by RegistroCollegamento.righe.collectAsState()
    var copiato by remember { mutableStateOf(false) }
    LaunchedEffect(copiato) {
        if (copiato) {
            delay(2_000)
            copiato = false
        }
    }
    val titolo = stringResource(R.string.registro)
    val condividi = stringResource(R.string.condividi_registro)
    Spacer(Modifier.size(8.dp))
    if (righe.isEmpty()) {
        NotaSotto(stringResource(R.string.registro_vuoto))
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
            PulsanteSecondario(stringResource(if (copiato) R.string.copiato else R.string.copia), Modifier.weight(1f), icona = Icons.Filled.ContentCopy) {
                val appunti = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                appunti?.setPrimaryClip(ClipData.newPlainText(titolo, RegistroCollegamento.testo()))
                copiato = true
            }
            PulsanteSecondario(condividi, Modifier.weight(1f), icona = Icons.Filled.Share) {
                val invio = Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, titolo).putExtra(Intent.EXTRA_TEXT, RegistroCollegamento.testo())
                try {
                    context.startActivity(Intent.createChooser(invio, condividi))
                } catch (e: ActivityNotFoundException) {
                    // Nessuna app per condividere: resta «Copia».
                }
            }
        }
        Gruppo {
            SelectionContainer {
                Column(Modifier.padding(vertical = 8.dp)) {
                    for (riga in righe.asReversed()) {
                        Text(riga, style = Caratteri.numeri(12), color = Colori.testoChiaro, modifier = Modifier.padding(horizontal = 14.dp, vertical = 3.dp))
                    }
                }
            }
        }
    }
}
