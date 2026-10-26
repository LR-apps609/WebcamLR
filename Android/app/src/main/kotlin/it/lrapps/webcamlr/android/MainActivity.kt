package it.lrapps.webcamlr.android

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
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
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.rete.ComputerTrovato
import it.lrapps.webcamlr.android.sessione.SessioneTelefono
import it.lrapps.webcamlr.android.sessione.Sessioni
import it.lrapps.webcamlr.android.sistema.Testi
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
import it.lrapps.webcamlr.protocollo.Associazione
import kotlinx.coroutines.flow.MutableStateFlow

/** Nessuna sessione: nessun permesso del microfono da chiedere. */
private val nessunaRichiesta = MutableStateFlow(false)

/** Le schermate dell'app, in una pila semplice (niente libreria di navigazione). */
sealed interface Schermata {
    data object Computer : Schermata
    data object LettoreQR : Schermata
    data object InOnda : Schermata
    /** Impostazioni e le sue pagine (Video avanzato, Registro), aperte dalla lista dei computer. */
    data class Impostazioni(val pagina: PaginaImpostazioni = PaginaImpostazioni.Principale) : Schermata
    data object App : Schermata
    data object Pro : Schermata
    data class Domande(val aperta: String? = null) : Schermata
    data object Guida : Schermata
    data object Segnala : Schermata
}

class MainActivity : ComponentActivity() {
    private val pila = mutableStateListOf<Schermata>(Schermata.Computer)

    /** Cosa fare quando arriva il permesso della fotocamera. */
    private var dopoIlPermesso: (() -> Unit)? = null

    private val permessoFotocamera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { concesso ->
        val azione = dopoIlPermesso
        dopoIlPermesso = null
        if (concesso) {
            azione?.invoke()
        } else {
            Toast.makeText(this, getString(R.string.permesso_fotocamera_negato), Toast.LENGTH_LONG).show()
        }
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        gestisciCollegamento(intent)
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
        BackHandler(enabled = pila.size > 1) { indietro() }
        // La sessione finita da fuori («Scollega» nell'avviso): «In onda» si chiude.
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
                            sessione.termina()
                            pila.remove(Schermata.InOnda)
                        },
                    )
                }
            }
            is Schermata.Impostazioni -> SchermataPaginaImpostazioni(
                pagina = attuale.pagina,
                indietro = { indietro() },
                apri = { pila.add(Schermata.Impostazioni(it)) },
                apriPro = { pila.add(Schermata.Pro) },
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

    private fun indietro() {
        val ultima = pila.lastOrNull() ?: return
        if (pila.size <= 1) return
        if (ultima == Schermata.InOnda) {
            // Tornare indietro da «In onda» vuol dire scollegare, come sull'iPhone.
            Sessioni.attuale?.let {
                ultimaLatenza = it.ultimaLatenzaMs
                it.termina()
            }
        }
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
                // L'avviso «Video al computer» con «Scollega»: utile, non indispensabile.
                permessoNotifiche.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
            Sessioni.attuale?.termina()
            SessioneTelefono(this, computer).avvia()
            pila.removeAll { it == Schermata.InOnda || it == Schermata.LettoreQR }
            pila.add(Schermata.InOnda)
        }
    }
}
