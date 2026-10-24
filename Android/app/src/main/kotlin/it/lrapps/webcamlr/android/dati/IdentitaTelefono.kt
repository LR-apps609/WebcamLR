package it.lrapps.webcamlr.android.dati

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import it.lrapps.webcamlr.protocollo.Firmatario
import it.lrapps.webcamlr.protocollo.IdentitaDispositivo
import it.lrapps.webcamlr.protocollo.Sicurezza
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

/**
 * L'identità permanente del telefono (protocollo 2, «Identità»): una chiave di firma ECDSA P-256 creata una volta.
 * Di preferenza nel Keystore di Android (la chiave privata non esce mai dal telefono, spesso nemmeno dal chip
 * di sicurezza); se il Keystore non funziona (capita su qualche telefono vecchio) una chiave software salvata
 * nei dati privati dell'app. I computer la riconoscono tra i telefoni fidati.
 */
object IdentitaTelefono {
    private const val ALIAS = "webcamlr-identita"
    private const val TAG = "WebcamLR"

    @Volatile
    private var caricata: Firmatario? = null

    /** Vero se nessun salvataggio ha funzionato: l'identità vale solo fino alla chiusura dell'app. */
    @Volatile
    var soloPerQuestaVolta = false
        private set

    /** Da chiamare all'avvio, fuori dal thread principale: il Keystore può metterci qualche decina di millisecondi. */
    fun prepara(context: Context) {
        Thread({ condivisa(context) }, "webcamlr-identita").start()
    }

    @Synchronized
    fun condivisa(context: Context): Firmatario {
        caricata?.let { return it }
        val nuova = daKeystore() ?: daFile(context) ?: IdentitaDispositivo.nuova().also { soloPerQuestaVolta = true }
        caricata = nuova
        return nuova
    }

    private class FirmatarioKeystore(private val privata: PrivateKey, override val pubblica: ByteArray) : Firmatario {
        override fun firma(dati: ByteArray): ByteArray = Sicurezza.firma(privata, dati)
    }

    private fun daKeystore(): Firmatario? = try {
        val archivio = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!archivio.containsAlias(ALIAS)) {
            val generatore = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
            generatore.initialize(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generatore.generateKeyPair()
        }
        val privata = archivio.getKey(ALIAS, null) as PrivateKey
        val pubblica = Sicurezza.x963(archivio.getCertificate(ALIAS).publicKey as ECPublicKey)
        val firmatario = FirmatarioKeystore(privata, pubblica)
        // Una prova: alcuni Keystore creano la chiave ma poi non firmano.
        val prova = byteArrayOf(1, 2, 3)
        if (Sicurezza.verificaFirma(pubblica, prova, firmatario.firma(prova))) firmatario else null
    } catch (e: Exception) {
        Log.w(TAG, "Keystore non disponibile, uso una chiave software", e)
        null
    }

    private fun daFile(context: Context): Firmatario? = try {
        val preferenze = context.getSharedPreferences("identita", Context.MODE_PRIVATE)
        val salvata = preferenze.getString("chiave", null)?.let {
            runCatching { IdentitaDispositivo.daDatiSalvati(Base64.decode(it, Base64.NO_WRAP)) }.getOrNull()
        }
        salvata ?: IdentitaDispositivo.nuova().also { nuova ->
            val scritta = preferenze.edit().putString("chiave", Base64.encodeToString(nuova.datiDaSalvare, Base64.NO_WRAP)).commit()
            if (!scritta) soloPerQuestaVolta = true
        }
    } catch (e: Exception) {
        Log.w(TAG, "Identità software non salvata", e)
        null
    }
}
