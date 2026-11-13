package it.lrapps.webcamlr.android

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.rete.AscoltoCavoAdb
import it.lrapps.webcamlr.android.rete.ComputerTrovato
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sessione.Sessioni
import it.lrapps.webcamlr.android.sistema.Permessi
import it.lrapps.webcamlr.android.sistema.Testi
import it.lrapps.webcamlr.android.ui.AzioniImpostazioni
import it.lrapps.webcamlr.android.ui.Colori
import it.lrapps.webcamlr.android.ui.PaginaImpostazioni
import it.lrapps.webcamlr.android.ui.PreferenzeInterfaccia
import it.lrapps.webcamlr.android.ui.Presentazione
import it.lrapps.webcamlr.android.ui.PulsantePieno
import it.lrapps.webcamlr.android.ui.PulsanteSecondario
import it.lrapps.webcamlr.android.ui.SchermataApp
import it.lrapps.webcamlr.android.ui.SchermataComputer
import it.lrapps.webcamlr.android.ui.SchermataDomande
import it.lrapps.webcamlr.android.ui.SchermataGuida
import it.lrapps.webcamlr.android.ui.SchermataInOnda
import it.lrapps.webcamlr.android.ui.SchermataLettoreQR
import it.lrapps.webcamlr.android.ui.SchermataPaginaImpostazioni
import it.lrapps.webcamlr.android.ui.SchermataPro
import it.lrapps.webcamlr.android.ui.SchermataSegnala
import it.lrapps.webcamlr.android.ui.Stili
import it.lrapps.webcamlr.android.ui.TemaWebcamLR
import it.lrapps.webcamlr.android.ui.VoceAltro
import it.lrapps.webcamlr.protocollo.Associazione
import kotlinx.coroutines.flow.MutableStateFlow
import java.net.Socket

/** Nessuna sessione: nessun permesso del microfono da chiedere. */
private val nessunaRichiesta = MutableStateFlow(false)

/** Le schermate dell'app, in una pila semplice (niente libreria di navigazione). */
sealed interface Schermata {
    data object Computer : Schermata
    data object LettoreQR : Schermata
    data object InOnda : Schermata
    /** Impostazioni e la sua pagina Registro, aperte dalla lista dei computer. */
    data class Impostazioni(val pagina: PaginaImpostazioni = PaginaImpostazioni.Principale) : Schermata
    data object App : Schermata
    data object Pro : Schermata
    data class Domande(val aperta: String? = null) : Schermata
    data object Guida : Schermata
    data object Segnala : Schermata
}

/**
 * Collaudo 20 (t09 B9): la pila in parole, per salvarla quando Android ricrea l'attività (dimensione del carattere o
 * dello schermo cambiata nelle impostazioni di sistema, lingua): prima si tornava sempre alla lista dei computer.
 */
private fun Schermata.inTesto(): String = when (this) {
    Schermata.Computer -> "computer"
    Schermata.LettoreQR -> "lettore"
    Schermata.InOnda -> "in-onda"
    is Schermata.Impostazioni -> "impostazioni:" + pagina.name
    Schermata.App -> "app"
    Schermata.Pro -> "pro"
    is Schermata.Domande -> "domande:" + (aperta ?: "")
    Schermata.Guida -> "guida"
    Schermata.Segnala -> "segnala"
}

private fun schermataDaTesto(testo: String): Schermata? {
    val (nome, resto) = testo.split(":", limit = 2).let { it[0] to it.getOrNull(1) }
    return when (nome) {
        "computer" -> Schermata.Computer
        "lettore" -> Schermata.LettoreQR
        "in-onda" -> Schermata.InOnda
        "impostazioni" -> Schermata.Impostazioni(PaginaImpostazioni.entries.firstOrNull { it.name == resto } ?: PaginaImpostazioni.Principale)
        "app" -> Schermata.App
        "pro" -> Schermata.Pro
        "domande" -> Schermata.Domande(resto?.ifEmpty { null })
        "guida" -> Schermata.Guida
        "segnala" -> Schermata.Segnala
        else -> null
    }
}

class MainActivity : ComponentActivity() {
    private val pila = mutableStateListOf<Schermata>(Schermata.Computer)

    /** P5: «Scollega» nella notifica ha aperto l'app: «In onda» mostra la domanda della X invece di scollegare subito. */
    private var richiestaScollega by mutableStateOf(false)
    /** Collaudo 55: un `webcamlr://collega` di un altro computer arrivato durante una sessione, da confermare. */
    private var collegamentoDaConfermare by mutableStateOf<ComputerTrovato?>(null)

    /**
     * Qualità 17: il cavo USB con il debug USB. Il computer apre la connessione attraverso adb sulla porta 52741 del
     * telefono; l'ascolto è acceso con l'app in primo piano e senza una sessione, o con una sessione del cavo che aspetta
     * il computer (vedi [aggiornaAscoltoCavo]).
     */
    private val ascoltoCavo = AscoltoCavoAdb { socket -> arrivoDalCavo(socket) }
    private var inPrimoPiano = false
    /**
     * Dopo la fine di una sessione del cavo con adb («Scollega», «Torna ai computer») l'ascolto resta spento: il
     * computer riprova ogni secondo e riaprirebbe subito «In onda». Torna con «Usa il cavo USB» o riaprendo l'app.
     */
    private var cavoEscluso = false
    /** La sessione vista l'ultima volta da [aggiornaAscoltoCavo]: per accorgersi di quando una del cavo finisce. */
    private var ultimaSessione: SessioneTelefono? = null

    /** Cosa fare quando arriva il permesso della fotocamera. */
    private var dopoIlPermesso: (() -> Unit)? = null

    private val permessoFotocamera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { concesso ->
        val azione = dopoIlPermesso
        dopoIlPermesso = null
        // P3: niente più solo un Toast. Rifiutata, la schermata dei computer mostra una scheda con «Apri Impostazioni»
        // (dopo il secondo rifiuto Android non chiede più: resta solo la strada delle impostazioni).
        Permessi.fotocameraRisposta(concesso)
        if (concesso) azione?.invoke()
    }

    private val permessoNotifiche = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    /** La sessione che ha chiesto il microfono: la risposta va a lei, anche se intanto ne è nata un'altra. */
    private var sessioneMicrofono: SessioneTelefono? = null

    private val permessoMicrofono = registerForActivityResult(ActivityResultContracts.RequestPermission()) { concesso ->
        sessioneMicrofono?.permessoMicrofonoCambiato(concesso)
        sessioneMicrofono = null
    }

    /**
     * Il microfono acceso senza permesso (dal pulsante di «In onda» o dal computer): la sessione lo segnala con
     * `permessoMicrofonoDaChiedere` e qui si chiede ad Android; la risposta torna con `permessoMicrofonoCambiato`.
     */
    private fun chiediMicrofono(sessione: SessioneTelefono) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            sessione.permessoMicrofonoCambiato(true)
            return
        }
        if (sessioneMicrofono != null) return
        sessioneMicrofono = sessione
        permessoMicrofono.launch(Manifest.permission.RECORD_AUDIO)
    }

    /**
     * Ogni lingua diversa dall'italiano mostra l'inglese, come su iPhone e Mac: i testi di base (values/) sono in
     * italiano, values-en/ in inglese.
     */
    override fun attachBaseContext(base: Context) {
        // La stessa regola dei testi della sessione e dell'avviso (sistema/Testi.kt).
        super.attachBaseContext(Testi.localizza(base))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        PreferenzeInterfaccia.prepara(this)
        // Ricreata da Android (carattere, schermo, lingua): le pagine aperte tornano com'erano. «In onda» solo se la
        // sessione c'è ancora (ci pensa la riga sotto).
        savedInstanceState?.getStringArrayList(CHIAVE_PILA)?.mapNotNull { schermataDaTesto(it) }
            ?.filter { it != Schermata.InOnda || Sessioni.attuale != null }
            ?.takeIf { it.firstOrNull() == Schermata.Computer }
            ?.let { salvata ->
                pila.clear()
                pila.addAll(salvata)
            }
        // Una sessione ancora viva (per esempio dopo aver riaperto l'app dall'avviso): si torna a «In onda».
        if (Sessioni.attuale != null && pila.lastOrNull() != Schermata.InOnda) pila.add(Schermata.InOnda)
        setContent {
            TemaWebcamLR {
                // Surface: il colore del testo predefinito è quello chiaro della famiglia LR Apps.
                Surface(Modifier.fillMaxSize(), color = Colori.fondo, contentColor = Colori.testo) {
                    Contenuto()
                }
            }
        }
        gestisciCollegamento(intent)
        // Solo all'apertura vera, non quando Android ricrea l'attività con lo stesso intento.
        if (savedInstanceState == null) gestisciScollega(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putStringArrayList(CHIAVE_PILA, ArrayList(pila.map { it.inTesto() }))
    }

    /**
     * Di nuovo in primo piano: se intanto il sistema ha chiuso la fotocamera o fermato il codificatore, la sessione
     * riparte pulita (senza ricollegarsi).
     */
    override fun onStart() {
        super.onStart()
        // Di ritorno nell'app: il cavo escluso dopo «Scollega» torna disponibile.
        if (!inPrimoPiano) cavoEscluso = false
        inPrimoPiano = true
        aggiornaAscoltoCavo()
        // P3 e P4: di ritorno da Impostazioni schede e righe dicono subito lo stato nuovo.
        Permessi.aggiorna(this)
        Sessioni.attuale?.tornataInPrimoPiano()
        // Collaudo 49: gli acquisti si rileggono al ritorno in primo piano (e Google Play si ricollega se non c'era),
        // per esempio dopo aver aggiunto l'account Google o aggiornato il Play Store.
        it.lrapps.webcamlr.android.acquisti.NegozioPro.aggiorna()
    }

    /**
     * Non più in primo piano (un'altra app, la schermata Home, lo schermo spento). Senza il servizio in primo piano
     * la sessione manda subito la pausa `sottofondo` al computer, prima che Android tolga la fotocamera.
     */
    override fun onStop() {
        super.onStop()
        inPrimoPiano = false
        aggiornaAscoltoCavo()
        if (!isChangingConfigurations) Sessioni.attuale?.andataInSottofondo()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        gestisciCollegamento(intent)
        gestisciScollega(intent)
    }

    /**
     * P5: «Scollega» nella notifica ([it.lrapps.webcamlr.android.sessione.ServizioInOnda]) apre l'app su «In onda»
     * con la domanda della X: niente scollegamento subito, anche in onda.
     */
    private fun gestisciScollega(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_CONFERMA_SCOLLEGA, false) != true) return
        intent.removeExtra(EXTRA_CONFERMA_SCOLLEGA)
        // Riaperta dalle app recenti: Android ripete l'intento con cui era partita (la notifica di allora), che non è
        // un «Scollega» toccato adesso.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (Sessioni.attuale == null) return
        // Le pagine aperte sopra «In onda» (Segnala un bug, domande) si chiudono: la domanda si vede subito.
        val indice = pila.indexOf(Schermata.InOnda)
        if (indice < 0) {
            pila.add(Schermata.InOnda)
        } else {
            while (pila.lastIndex > indice) pila.removeAt(pila.lastIndex)
        }
        richiestaScollega = true
    }

    /** `webcamlr://collega?…` aperto dalla fotocamera di sistema o da un altro lettore di QR code. */
    private fun gestisciCollegamento(intent: Intent?) {
        val testo = intent?.dataString ?: return
        val associazione = Associazione.leggi(testo) ?: return
        intent.data = null
        val nuovo = ComputerTrovato.da(associazione)
        val attuale = Sessioni.attuale
        if (attuale != null) {
            // Collaudo 55: prima il link si scartava in silenzio. Lo stesso computer: niente da fare; un altro: si
            // chiede, e con il sì ci si collega come con il lettore QR interno.
            val stesso = attuale.computer.let { (it.impronta != null && it.impronta == nuovo.impronta) || it.nome == nuovo.nome }
            android.util.Log.i("WebcamLR", "Link di collegamento a ${nuovo.nome} durante la sessione con ${attuale.computer.nome}" + if (stesso) ": è lo stesso, lo ignoro" else ": chiedo")
            if (!stesso) collegamentoDaConfermare = nuovo
            return
        }
        if (!Impostazioni.benvenutoVisto) Impostazioni.impostaBenvenutoVisto(true)
        apriSessione(nuovo)
    }

    /** La domanda per [collegamentoDaConfermare]: con il sì si chiude la sessione attuale e si apre quella nuova. */
    @Composable
    private fun DomandaAltroComputer() {
        val nuovo = collegamentoDaConfermare ?: return
        val attuale = Sessioni.attuale
        if (attuale == null) {
            // La sessione è finita nel frattempo: ci si collega e basta (fuori dalla composizione).
            LaunchedEffect(nuovo) {
                collegamentoDaConfermare = null
                apriSessione(nuovo)
            }
            return
        }
        AlertDialog(
            onDismissRequest = { collegamentoDaConfermare = null },
            title = { Text(stringResource(R.string.collega_altro_domanda, nuovo.nome)) },
            text = { Text(stringResource(R.string.collega_altro_spiegazione, attuale.computer.nome), style = Stili.corpo, color = Colori.testoChiaro) },
            confirmButton = {
                PulsantePieno(stringResource(R.string.collega)) {
                    collegamentoDaConfermare = null
                    apriSessione(nuovo)
                }
            },
            dismissButton = {
                PulsanteSecondario(stringResource(R.string.annulla), compatto = true) { collegamentoDaConfermare = null }
            },
        )
    }

    @Composable
    private fun Contenuto() {
        if (!Impostazioni.benvenutoVisto) {
            // La presentazione chiede da sé fotocamera, microfono e notifiche con «Inizia».
            Presentazione(fine = { Impostazioni.impostaBenvenutoVisto(true) })
            return
        }
        val attuale = pila.last()
        // P1: in «In onda» Indietro lo gestisce la schermata stessa (domanda della X, schermo oscurato).
        BackHandler(enabled = pila.size > 1 && attuale != Schermata.InOnda) { indietro() }
        // La sessione finita da fuori (per esempio l'app tolta dalle recenti): «In onda» si chiude.
        val sessione = Sessioni.attuale
        LaunchedEffect(sessione) {
            if (sessione == null && pila.contains(Schermata.InOnda)) pila.remove(Schermata.InOnda)
        }
        // Qualità 17: l'ascolto sul cavo segue la sessione (nuova, chiusa, in attesa del computer).
        LaunchedEffect(sessione, sessione?.stato) { aggiornaAscoltoCavo() }
        val chiedeMicrofono by (sessione?.permessoMicrofonoDaChiedere ?: nessunaRichiesta).collectAsState()
        LaunchedEffect(sessione, chiedeMicrofono) {
            if (sessione != null && chiedeMicrofono) chiediMicrofono(sessione)
        }
        when (attuale) {
            Schermata.Computer -> SchermataComputer(
                collega = { apriSessione(it) },
                apriLettore = { conPermessoFotocamera { pila.add(Schermata.LettoreQR) } },
                apriImpostazioni = { pila.add(Schermata.Impostazioni()) },
                apriPro = { pila.add(Schermata.Pro) },
                apriApp = { pila.add(Schermata.App) },
                apriDomanda = { pila.add(Schermata.Domande(it)) },
                inPrimoPiano = pila.size == 1,
                usaCavo = {
                    cavoEscluso = false
                    aggiornaAscoltoCavo()
                },
            )
            Schermata.LettoreQR -> SchermataLettoreQR(
                letto = { associazione ->
                    pila.remove(Schermata.LettoreQR)
                    apriSessione(ComputerTrovato.da(associazione))
                },
                chiudi = { indietro() },
            )
            Schermata.InOnda -> {
                if (sessione != null) {
                    SchermataInOnda(
                        sessione = sessione,
                        chiudi = {
                            ultimaLatenza = sessione.ultimaLatenzaMs
                            sessione.termina()
                            pila.remove(Schermata.InOnda)
                        },
                        // Sopra «In onda»: la sessione continua, «Indietro» ci riporta.
                        apriAltro = { pila.add(schermataAltro(it)) },
                        richiestaScollega = richiestaScollega,
                        richiestaVista = { richiestaScollega = false },
                    )
                }
            }
            is Schermata.Impostazioni -> SchermataPaginaImpostazioni(
                pagina = attuale.pagina,
                indietro = { indietro() },
                apri = { pila.add(Schermata.Impostazioni(it)) },
                azioni = AzioniImpostazioni(
                    apriPro = { pila.add(Schermata.Pro) },
                    apriAltro = { pila.add(schermataAltro(it)) },
                    apriDomanda = { pila.add(Schermata.Domande(it)) },
                ),
            )
            Schermata.App -> SchermataApp(
                indietro = { indietro() },
                apriPro = { pila.add(Schermata.Pro) },
                apriDomande = { pila.add(Schermata.Domande()) },
                apriGuida = { pila.add(Schermata.Guida) },
                apriSegnala = { pila.add(Schermata.Segnala) },
            )
            Schermata.Pro -> SchermataPro(indietro = { indietro() })
            is Schermata.Domande -> SchermataDomande(aperta = attuale.aperta, indietro = { indietro() })
            Schermata.Guida -> SchermataGuida(indietro = { indietro() })
            Schermata.Segnala -> SchermataSegnala(ultimaLatenzaMs = sessione?.ultimaLatenzaMs ?: ultimaLatenza, indietro = { indietro() })
        }
        DomandaAltroComputer()
    }

    private var ultimaLatenza: Int? = null

    /** Le voci di «Altro» delle Impostazioni: «App e assistenza» è la sezione App, la stessa dell'icona in cima. */
    private fun schermataAltro(voce: VoceAltro): Schermata = when (voce) {
        VoceAltro.AppEAssistenza -> Schermata.App
        VoceAltro.Segnala -> Schermata.Segnala
    }

    /** Indietro dalle pagine sopra la lista dei computer. «In onda» non passa di qui (P1): si scollega solo con la domanda. */
    private fun indietro() {
        val ultima = pila.lastOrNull() ?: return
        if (pila.size <= 1 || ultima == Schermata.InOnda) return
        pila.removeAt(pila.lastIndex)
    }

    private fun conPermessoFotocamera(azione: () -> Unit) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            azione()
        } else {
            dopoIlPermesso = azione
            permessoFotocamera.launch(Manifest.permission.CAMERA)
        }
    }

    /**
     * Qualità 17: acceso solo quando una connessione dal cavo si può usare: in primo piano senza sessione (si apre «In
     * onda», come sull'iPhone), oppure con una sessione del cavo che aspetta il computer (anche in sottofondo, con il
     * servizio «In onda»). Con una sessione Wi-Fi resta spento: adb risponde «FAIL» al computer, che riprova ogni secondo
     * senza allungare l'attesa, e il cavo arriva appena la sessione Wi-Fi finisce.
     */
    private fun aggiornaAscoltoCavo() {
        val sessione = Sessioni.attuale
        val finita = ultimaSessione
        if (finita != null && finita !== sessione && finita.computer.viaAdb) cavoEscluso = true
        ultimaSessione = sessione
        val serve = if (sessione != null) sessione.aspettaIlCavo else inPrimoPiano && !cavoEscluso && puoAprireDalCavo()
        if (serve) ascoltoCavo.avvia() else ascoltoCavo.ferma()
    }

    /** Senza la presentazione vista o senza il permesso della fotocamera una connessione dal cavo non può aprire «In onda». */
    private fun puoAprireDalCavo(): Boolean = Impostazioni.benvenutoVisto &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /** Una connessione dal cavo (thread principale): alla sessione che la aspetta, oppure una sessione nuova. */
    private fun arrivoDalCavo(socket: Socket) {
        val attuale = Sessioni.attuale
        if (attuale != null) {
            if (!attuale.accogliCavo(socket)) runCatching { socket.close() }
            aggiornaAscoltoCavo()
            return
        }
        if (!inPrimoPiano || !puoAprireDalCavo()) {
            runCatching { socket.close() }
            return
        }
        apriSessione(ComputerTrovato.dalCavoAdb(getString(R.string.computer_sul_cavo)), socket)
    }

    /** Collegamento e fotocamera partono subito, mentre «In onda» si apre. `socketCavo`: arrivata dal cavo con adb. */
    private fun apriSessione(computer: ComputerTrovato, socketCavo: Socket? = null) {
        conPermessoFotocamera {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                // L'avviso «Video al computer» con «Scollega» (che apre la domanda): utile, non indispensabile.
                permessoNotifiche.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
            Sessioni.attuale?.termina()
            SessioneTelefono(this, computer, socketCavoIniziale = socketCavo).avvia()
            pila.removeAll { it == Schermata.InOnda || it == Schermata.LettoreQR }
            pila.add(Schermata.InOnda)
        }
    }

    companion object {
        /** Nell'intento della notifica: «Scollega» apre la domanda della X (P5). */
        const val EXTRA_CONFERMA_SCOLLEGA = "it.lrapps.webcamlr.android.CONFERMA_SCOLLEGA"

        /** La pila delle schermate nello stato salvato dell'attività. */
        private const val CHIAVE_PILA = "pila"
    }
}
