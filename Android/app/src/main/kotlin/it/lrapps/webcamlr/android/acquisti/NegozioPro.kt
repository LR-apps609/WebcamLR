package it.lrapps.webcamlr.android.acquisti

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import it.lrapps.webcamlr.android.BuildConfig
import it.lrapps.webcamlr.android.sistema.RegistroCollegamento
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Lo stato di WebcamLR Pro per l'interfaccia (come le proprietà osservate di NegozioPro.swift). */
data class StatoPro(
    /** WebcamLR Pro è sbloccato su questo telefono. */
    val attivo: Boolean = false,
    /** Il prezzo nella valuta dell'utente, da Google Play (mai scritto nel codice); `null` finché non arriva. */
    val prezzo: String? = null,
    val caricamentoProdotto: Boolean = false,
    /** Google Play non ha risposto o non conosce il prodotto: «Riprova». */
    val prodottoNonTrovato: Boolean = false,
    val operazione: Operazione = Operazione.NESSUNA,
    /** Acquisto in attesa (pagamento da completare, per esempio in contanti o con l'approvazione di un genitore). */
    val inAttesa: Boolean = false,
    /** Una frase per l'utente dopo un acquisto o un ripristino non riusciti. */
    val avviso: String? = null,
    /** Google Play ha già detto almeno una volta quali acquisti ci sono. */
    val dirittiLetti: Boolean = false,
    /** Google Play c'è su questo telefono (falso sui Huawei senza servizi Google: lì si compra più avanti con un account). */
    val giocoDisponibile: Boolean = true,
) {
    enum class Operazione { NESSUNA, ACQUISTO, RIPRISTINO }
}

/**
 * WebcamLR Pro con Google Play Billing (libreria 7): un prodotto in-app non consumabile `it.lrapps.webcamlr.pro`,
 * acquistato una volta sola, senza account (Documenti/Protocollo.md, «WebcamLR Pro»). Il telefono è l'unica fonte di
 * verità: la sessione lo dice al computer con `capacita.pro` e la rimanda a ogni cambiamento di [stato].
 *
 * - Diritti: `queryPurchasesAsync` (anche «Ripristina acquisti»), solo gli acquisti `PURCHASED`; quelli in attesa
 *   (`PENDING`) non sbloccano nulla finché non sono pagati. Ogni acquisto si conferma (`acknowledgePurchase`), altrimenti
 *   Google lo rimborsa dopo tre giorni. Un rimborso fa sparire l'acquisto alla lettura successiva (all'avvio dell'app e
 *   a ogni sessione).
 * - L'ultimo stato resta salvato per partire subito con quello giusto (niente 720p per un attimo a chi ha Pro): appena
 *   Google Play risponde vale la sua lettura.
 * - Il token e il numero d'ordine restano salvati: serviranno per collegare il Pro a un account facoltativo più avanti
 *   (come `originalTransactionID` sull'iPhone).
 * - Raccolta famiglia: si attiva in Play Console per il prodotto; gli acquisti condivisi arrivano come gli altri.
 *
 * Tutto sul thread principale.
 */
object NegozioPro {
    const val ID_PRODOTTO = "it.lrapps.webcamlr.pro"

    private val principale = Handler(Looper.getMainLooper())
    private val interno = MutableStateFlow(StatoPro())
    val stato: StateFlow<StatoPro> = interno.asStateFlow()

    // Gli stessi valori uno per uno, per l'interfaccia (ui/Ponte.kt).
    private val proInterno = MutableStateFlow(false)
    private val prezzoInterno = MutableStateFlow<String?>(null)
    private val inAttesaInterno = MutableStateFlow(false)
    /** WebcamLR Pro è sbloccato su questo telefono. */
    val pro: StateFlow<Boolean> = proInterno.asStateFlow()
    /** Il prezzo da Google Play, nella valuta dell'utente; `null` finché non arriva. */
    val prodottoPrezzo: StateFlow<String?> = prezzoInterno.asStateFlow()
    /** Un acquisto aspetta il pagamento. */
    val inAttesa: StateFlow<Boolean> = inAttesaInterno.asStateFlow()

    private fun cambia(modifica: (StatoPro) -> StatoPro) {
        interno.update(modifica)
        val attuale = interno.value
        proInterno.value = attuale.attivo
        prezzoInterno.value = attuale.prezzo
        inAttesaInterno.value = attuale.inAttesa
    }

    private var preferenze: SharedPreferences? = null
    private var cliente: BillingClient? = null
    private var prodotto: ProductDetails? = null
    private var tentativiConnessione = 0
    private var simulato: Boolean? = null

    /** All'apertura dell'app (`WebcamLRApp`): stato salvato, poi Google Play. */
    fun avvia(context: Context) {
        if (cliente != null) return
        val app = context.applicationContext
        val salvate = app.getSharedPreferences("pro", Context.MODE_PRIVATE)
        preferenze = salvate
        cambia { it.copy(attivo = salvate.getBoolean("attivo", false)) }
        cliente = try {
            BillingClient.newBuilder(app)
                .setListener(ascoltoAcquisti)
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                .build()
        } catch (e: Exception) {
            Log.w(TAG, "Google Play Billing non disponibile", e)
            cambia { it.copy(giocoDisponibile = false) }
            null
        }
        connetti()
    }

    /** Rilegge gli acquisti (all'inizio di una sessione e al ritorno in primo piano): così un rimborso si vede. */
    fun aggiorna() {
        if (cliente?.isReady == true) leggiAcquisti(ripristino = false) else connetti()
    }

    /** «Sblocca Pro»: il foglio di acquisto di Google Play, sopra l'attività. Non sospende: l'esito arriva in [stato]. */
    fun acquista(attivita: Activity) = compra(attivita)

    fun compra(attivita: Activity) {
        val attuale = stato.value
        if (attuale.operazione != StatoPro.Operazione.NESSUNA) return
        val dettagli = prodotto
        val c = cliente
        if (dettagli == null || c == null || !c.isReady) {
            cambia { it.copy(avviso = "Google Play non risponde: controlla la connessione e riprova.") }
            caricaProdotto()
            return
        }
        cambia { it.copy(operazione = StatoPro.Operazione.ACQUISTO, avviso = null) }
        val parametri = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(dettagli).build()))
            .build()
        val esito = c.launchBillingFlow(attivita, parametri)
        if (esito.responseCode != BillingClient.BillingResponseCode.OK) {
            cambia {
                it.copy(
                    operazione = StatoPro.Operazione.NESSUNA,
                    avviso = if (esito.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) null else "Acquisto non riuscito. Controlla la connessione e riprova.",
                )
            }
            if (esito.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) leggiAcquisti(ripristino = false)
        }
    }

    /** «Ripristina acquisti»: chiede a Google Play gli acquisti di questo account. Non sospende: l'esito arriva in [stato]. */
    fun ripristina() {
        if (stato.value.operazione != StatoPro.Operazione.NESSUNA) return
        cambia { it.copy(operazione = StatoPro.Operazione.RIPRISTINO, avviso = null) }
        if (cliente?.isReady == true) {
            leggiAcquisti(ripristino = true)
        } else {
            connetti()
            principale.postDelayed({
                if (stato.value.operazione == StatoPro.Operazione.RIPRISTINO && cliente?.isReady != true) {
                    cambia { it.copy(operazione = StatoPro.Operazione.NESSUNA, avviso = "Ripristino non riuscito. Controlla la connessione e riprova.") }
                }
            }, 8_000)
        }
    }

    /** Il prezzo non è arrivato: «Riprova». */
    fun riprovaProdotto() = caricaProdotto()

    /** Solo nelle versioni di prova (Android Studio): Pro acceso o spento senza comprare, per provare i limiti. */
    fun simula(attivo: Boolean?) {
        if (!BuildConfig.DEBUG) return
        simulato = attivo
        imposta(attivo ?: (preferenze?.getBoolean("acquistato", false) ?: false))
    }

    // Interni

    private fun connetti() {
        val c = cliente ?: return
        if (c.isReady) return
        try {
            c.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(esito: BillingResult) {
                    principale.post {
                        if (esito.responseCode == BillingClient.BillingResponseCode.OK) {
                            tentativiConnessione = 0
                            cambia { it.copy(giocoDisponibile = true) }
                            leggiAcquisti(ripristino = stato.value.operazione == StatoPro.Operazione.RIPRISTINO)
                            caricaProdotto()
                        } else {
                            Log.w(TAG, "Google Play Billing: ${esito.responseCode} ${esito.debugMessage}")
                            val assente = esito.responseCode == BillingClient.BillingResponseCode.BILLING_UNAVAILABLE
                            cambia { it.copy(giocoDisponibile = !assente, prodottoNonTrovato = true, caricamentoProdotto = false) }
                            if (!assente) riprovaPiuTardi()
                        }
                    }
                }

                override fun onBillingServiceDisconnected() {
                    principale.post { riprovaPiuTardi() }
                }
            })
        } catch (e: Exception) {
            Log.w(TAG, "Google Play Billing non raggiungibile", e)
        }
    }

    /** Di nuovo dopo 1, 2, 4… secondi (al massimo un minuto): Google Play si sta aggiornando, o manca la rete. */
    private fun riprovaPiuTardi() {
        val ritardo = minOf(60_000L, 1_000L shl minOf(tentativiConnessione, 6))
        tentativiConnessione++
        principale.postDelayed({ connetti() }, ritardo)
    }

    private fun caricaProdotto() {
        val c = cliente ?: return
        if (!c.isReady || stato.value.caricamentoProdotto || prodotto != null) return
        cambia { it.copy(caricamentoProdotto = true, prodottoNonTrovato = false) }
        val parametri = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(ID_PRODOTTO)
                        .setProductType(BillingClient.ProductType.INAPP)
                        .build(),
                ),
            )
            .build()
        c.queryProductDetailsAsync(parametri) { esito, elenco ->
            principale.post {
                val trovato = if (esito.responseCode == BillingClient.BillingResponseCode.OK) elenco.firstOrNull { it.productId == ID_PRODOTTO } else null
                prodotto = trovato
                cambia {
                    it.copy(
                        caricamentoProdotto = false,
                        prodottoNonTrovato = trovato == null,
                        prezzo = trovato?.oneTimePurchaseOfferDetails?.formattedPrice,
                    )
                }
            }
        }
    }

    private fun leggiAcquisti(ripristino: Boolean) {
        val c = cliente ?: return
        val parametri = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        c.queryPurchasesAsync(parametri) { esito, acquisti ->
            principale.post {
                if (esito.responseCode != BillingClient.BillingResponseCode.OK) {
                    if (ripristino) {
                        cambia { it.copy(operazione = StatoPro.Operazione.NESSUNA, avviso = "Ripristino non riuscito. Controlla la connessione e riprova.") }
                    }
                    return@post
                }
                gestisci(acquisti)
                cambia { it.copy(dirittiLetti = true) }
                if (ripristino) {
                    cambia {
                        it.copy(
                            operazione = StatoPro.Operazione.NESSUNA,
                            avviso = if (!it.attivo && !it.inAttesa) "Nessun acquisto di WebcamLR Pro per questo account Google." else null,
                        )
                    }
                }
            }
        }
    }

    private val ascoltoAcquisti = PurchasesUpdatedListener { esito, acquisti ->
        principale.post {
            when (esito.responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    gestisci(acquisti.orEmpty(), soloAggiunte = true)
                    cambia { it.copy(operazione = StatoPro.Operazione.NESSUNA) }
                }
                BillingClient.BillingResponseCode.USER_CANCELED -> cambia { it.copy(operazione = StatoPro.Operazione.NESSUNA) }
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                    cambia { it.copy(operazione = StatoPro.Operazione.NESSUNA) }
                    leggiAcquisti(ripristino = false)
                }
                else -> cambia {
                    it.copy(operazione = StatoPro.Operazione.NESSUNA, avviso = "Acquisto non riuscito. Controlla la connessione e riprova.")
                }
            }
        }
    }

    /**
     * Gli acquisti di WebcamLR Pro: pagati = Pro (e si confermano), in attesa = «in attesa». `soloAggiunte`: arrivano da
     * un acquisto appena fatto (l'elenco non è completo: non toglie il Pro).
     */
    private fun gestisci(acquisti: List<Purchase>, soloAggiunte: Boolean = false) {
        val nostri = acquisti.filter { ID_PRODOTTO in it.products }
        val pagato = nostri.firstOrNull { it.purchaseState == Purchase.PurchaseState.PURCHASED }
        val inAttesa = pagato == null && nostri.any { it.purchaseState == Purchase.PurchaseState.PENDING }
        if (pagato != null) {
            preferenze?.edit()?.putString("token", pagato.purchaseToken)?.putString("ordine", pagato.orderId)?.apply()
            if (!pagato.isAcknowledged) conferma(pagato)
        }
        cambia { it.copy(inAttesa = inAttesa) }
        if (pagato != null || !soloAggiunte) {
            preferenze?.edit()?.putBoolean("acquistato", pagato != null)?.apply()
            imposta(simulato ?: (pagato != null))
        }
    }

    /** Senza conferma entro tre giorni Google rimborsa l'acquisto: si riprova a ogni lettura finché non riesce. */
    private fun conferma(acquisto: Purchase) {
        val c = cliente ?: return
        val parametri = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(acquisto.purchaseToken).build()
        c.acknowledgePurchase(parametri) { esito ->
            if (esito.responseCode != BillingClient.BillingResponseCode.OK) {
                Log.w(TAG, "Acquisto non confermato: ${esito.responseCode}")
            }
        }
    }

    private fun imposta(nuovo: Boolean) {
        if (preferenze?.getBoolean("attivo", false) != nuovo) preferenze?.edit()?.putBoolean("attivo", nuovo)?.apply()
        if (stato.value.attivo == nuovo) return
        cambia { it.copy(attivo = nuovo) }
        RegistroCollegamento.aggiungi(if (nuovo) "WebcamLR Pro attivo" else "WebcamLR Pro non attivo")
    }

    /** Il token dell'acquisto, per un account futuro. */
    val tokenAcquisto: String? get() = preferenze?.getString("token", null)

    private const val TAG = "WebcamLR"
}
