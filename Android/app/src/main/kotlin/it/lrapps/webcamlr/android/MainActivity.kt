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
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import it.lrapps.webcamlr.android.dati.Impostazioni
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
import it.lrapps.webcamlr.android.ui.SchermataApp
import it.lrapps.webcamlr.android.ui.SchermataComputer
import it.lrapps.webcamlr.android.ui.SchermataDomande
import it.lrapps.webcamlr.android.ui.SchermataGuida
import it.lrapps.webcamlr.android.ui.SchermataInOnda
import it.lrapps.webcamlr.android.ui.SchermataLettoreQR
import it.lrapps.webcamlr.android.ui.SchermataPaginaImpostazioni
import it.lrapps.webcamlr.android.ui.SchermataPro
import it.lrapps.webcamlr.android.ui.SchermataSegnala
import it.lrapps.webcamlr.android.ui.TemaWebcamLR
import it.lrapps.webcamlr.android.ui.VoceAltro
import it.lrapps.webcamlr.protocollo.Associazione
import kotlinx.coroutines.flow.MutableStateFlow

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

class MainActivity : ComponentActivity() {
    private val pila = mutableStateListOf<Schermata>(Schermata.Computer)

    /** P5: «Scollega» nella notifica ha aperto l'app: «In onda» mostra la domanda della X invece di scollegare subito. */
    private var richiestaScollega by mutableStateOf(false)

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

    /**
     * Di nuovo in primo piano: se intanto il sistema ha chiuso la fotocamera o fermato il codificatore, la sessione
     * riparte pulita (senza ricollegarsi).
     */
    override fun onStart() {
        super.onStart()
        // P3 e P4: di ritorno da Impostazioni schede e righe dicono subito lo stato nuovo.
        Permessi.aggiorna(this)
        Sessioni.attuale?.tornataInPrimoPiano()
    }

    /**
     * Non più in primo piano (un'altra app, la schermata Home, lo schermo spento). Senza il servizio in primo piano
     * la sessione manda subito la pausa `sottofondo` al computer, prima che Android tolga la fotocamera.
     */
    override fun onStop() {
        super.onStop()
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
        if (Sessioni.attuale != null) return
        if (!Impostazioni.benvenutoVisto) Impostazioni.impostaBenvenutoVisto(true)
        apriSessione(ComputerTrovato.da(associazione))
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

    /** Collegamento e fotocamera partono subito, mentre «In onda» si apre. */
    private fun apriSessione(computer: ComputerTrovato) {
        conPermessoFotocamera {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                // L'avviso «Video al computer» con «Scollega» (che apre la domanda): utile, non indispensabile.
                permessoNotifiche.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
            Sessioni.attuale?.termina()
            SessioneTelefono(this, computer).avvia()
            pila.removeAll { it == Schermata.InOnda || it == Schermata.LettoreQR }
            pila.add(Schermata.InOnda)
        }
    }

    companion object {
        /** Nell'intento della notifica: «Scollega» apre la domanda della X (P5). */
        const val EXTRA_CONFERMA_SCOLLEGA = "it.lrapps.webcamlr.android.CONFERMA_SCOLLEGA"
    }
}
