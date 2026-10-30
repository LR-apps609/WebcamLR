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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Spazi.medio).padding(bottom = Spazi.largo),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(), content = contenuto)
        }
    }
}

/**
 * La barra in cima, la `TopAppBar` piccola di Material 3: un solo modo di chiudere. Nelle pagine la freccia
 * «Indietro» a sinistra; nei fogli di «In onda» «Fine» a destra (e la freccia solo per tornare alla pagina di prima
 * dentro il foglio, come il Registro). Fondo trasparente: sotto c'è il fondo della schermata o del foglio.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BarraTitolo(titolo: String, indietro: (() -> Unit)? = null, fine: (() -> Unit)? = null) {
    TopAppBar(
        title = {
            Text(titolo, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { heading() })
        },
        navigationIcon = {
            if (indietro != null) {
                IconButton(onClick = indietro) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.indietro))
                }
            }
        },
        actions = {
            if (fine != null) PulsanteLink(stringResource(R.string.fine), azione = fine)
        },
        // I margini di sistema li mette già chi contiene la barra (pagina o foglio).
        windowInsets = WindowInsets(0),
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = Color.Transparent,
            scrolledContainerColor = Color.Transparent,
            navigationIconContentColor = Colori.testo,
            titleContentColor = Colori.testo,
            actionIconContentColor = Colori.testo,
        ),
    )
}

// MARK: Impostazioni

/** Le pagine delle Impostazioni. */
enum class PaginaImpostazioni { Principale, Registro }

/**
 * Le voci di «Altro» che aprono una schermata dell'app (dalla lista dei computer o da «In onda»): «App e assistenza»
 * (la stessa schermata dell'icona in cima alla lista dei computer: domande frequenti, guida, computer conosciuti,
 * informazioni) e «Segnala un bug».
 */
enum class VoceAltro { AppEAssistenza, Segnala }

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
 * Le Impostazioni aperte dalla lista dei computer: una pagina per schermata, nella pila di MainActivity, con la
 * freccia «Indietro» come ogni pagina (la «Fine» resta ai fogli di «In onda»).
 */
@Composable
fun SchermataPaginaImpostazioni(pagina: PaginaImpostazioni, indietro: () -> Unit, apri: (PaginaImpostazioni) -> Unit, azioni: AzioniImpostazioni) {
    SchermataSecondaria(titoloPagina(pagina), indietro) {
        ContenutoPaginaImpostazioni(pagina, sessione = null, apri = apri, azioni = azioni)
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
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Spazi.medio).padding(bottom = Spazi.largo)) {
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
            horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo),
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = azioni.apriPro)
                .semantics(mergeDescendants = true) { stateDescription = stato }.padding(horizontal = Spazi.medio, vertical = Spazi.stretto),
        ) {
            SegnoPro()
            Text("WebcamLR Pro", style = Stili.comando, color = Colori.testo, modifier = Modifier.weight(1f))
            Text(stato, style = Stili.comando, color = if (pro) Colori.accentoChiaro else Colori.accento, maxLines = 1)
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
                Modifier.fillMaxWidth().padding(start = Spazi.medio, end = Spazi.medio, bottom = Spazi.piccolo),
                verticalArrangement = Arrangement.spacedBy(Spazi.stretto),
            ) {
                Text(stringResource(R.string.batteria_limitata), style = Stili.nota, color = Colori.ambraTesto)
                Row(horizontalArrangement = Arrangement.spacedBy(Spazi.stretto), verticalAlignment = Alignment.CenterVertically) {
                    PulsantePieno(stringResource(R.string.apri_impostazioni), piccolo = true) { Permessi.apriBatteria(context) }
                    // I consigli per marca (Samsung, Xiaomi, Huawei…) nella risposta «Il video si ferma quando spengo lo schermo».
                    PulsanteLink(stringResource(R.string.perche_succede)) { azioni.apriDomanda("schermo-spento") }
                }
            }
        }
    }
    NotaSotto(stringResource(R.string.durante_uso_nota))

    // 6. Altro.
    EtichettaSezione(stringResource(R.string.sezione_altro))
    Gruppo {
        // Una voce sola per la sezione App: lo stesso nome dell'ingresso in cima alla lista dei computer.
        RigaLink(stringResource(R.string.app_e_assistenza), nota = stringResource(R.string.app_e_assistenza_nota)) { azioni.apriAltro(VoceAltro.AppEAssistenza) }
        RigaLink(stringResource(R.string.segnala_bug)) { azioni.apriAltro(VoceAltro.Segnala) }
        // In diretta si esce dall'app: lo si dice (il video continua grazie al servizio in primo piano).
        RigaLink(
            stringResource(R.string.lingua), valore = stringResource(R.string.lingua_attuale),
            nota = if (sessione != null) stringResource(R.string.lingua_nota_in_onda) else null,
        ) { apriLingua(context) }
        // Solo sul telefono: il registro del collegamento visto da qui.
        RigaLink(stringResource(R.string.registro)) { apri(PaginaImpostazioni.Registro) }
    }
    Text(
        stringResource(R.string.versione_app, "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"),
        style = Stili.numeri, color = Colori.testoSecondario, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = Spazi.largo),
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
        RigaScelta(stringResource(R.string.collegamento_automatico), scelta == PreferenzeCollegamento.AUTOMATICO) { scegli(PreferenzeCollegamento.AUTOMATICO) }
        RigaScelta(stringResource(R.string.collegamento_wifi), scelta == PreferenzeCollegamento.WIFI) { scegli(PreferenzeCollegamento.WIFI) }
        RigaScelta(stringResource(R.string.collegamento_cavo_usb), scelta == PreferenzeCollegamento.CAVO) { scegli(PreferenzeCollegamento.CAVO) }
    }
    if (stato != null) {
        val misure = stato.strade.mapNotNull { strada -> strada.ms?.let { ms -> Strada.entries.firstOrNull { it.valore == strada.tipo }?.let { it to ms } } }.toMap()
        val veloce = if (stato.strade.size > 1) RegolaCollegamento.piuVeloce(misure) else null
        val inUso = stringResource(R.string.collegamento_in_uso)
        val piuVeloce = stringResource(R.string.piu_veloce_ora)
        Spacer(Modifier.size(Spazi.stretto))
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
                style = Stili.nota,
                color = Colori.testoSecondario,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth().padding(start = Spazi.medio, end = Spazi.medio, bottom = Spazi.piccolo),
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
    Spacer(Modifier.size(Spazi.stretto))
    if (righe.isEmpty()) {
        NotaSotto(stringResource(R.string.registro_vuoto))
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(Spazi.piccolo), modifier = Modifier.fillMaxWidth().padding(bottom = Spazi.piccolo)) {
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
                Column(Modifier.padding(vertical = Spazi.stretto)) {
                    for (riga in righe.asReversed()) {
                        Text(riga, style = Stili.numeri, color = Colori.testoChiaro, modifier = Modifier.padding(horizontal = Spazi.medio, vertical = Spazi.minimo))
                    }
                }
            }
        }
    }
}
