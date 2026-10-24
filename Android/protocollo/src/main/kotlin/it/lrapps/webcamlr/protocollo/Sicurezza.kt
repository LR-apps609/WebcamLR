package it.lrapps.webcamlr.protocollo

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Collegamento sicuro, versione 2 del protocollo (Documenti/Protocollo.md, «Collegamento sicuro»).
 * Solo crittografia della piattaforma (java.security, javax.crypto): ECDSA ed ECDH P-256, HKDF-SHA256
 * (scritto qui con HmacSHA256), AES-256-GCM. Gli stessi calcoli di Sicurezza.swift e Sicurezza.cs.
 */
object Sicurezza {
    const val VERSIONE_SICURA = 2
    const val LUNGHEZZA_CHIAVE_PUBBLICA = 65
    const val LUNGHEZZA_FIRMA = 64

    private val casuale = SecureRandom()

    /** I parametri della curva P-256, presi da una chiave generata: funziona uguale su JVM e su Android. */
    val curva: ECParameterSpec by lazy {
        val generatore = KeyPairGenerator.getInstance("EC")
        generatore.initialize(ECGenParameterSpec("secp256r1"))
        (generatore.generateKeyPair().public as ECPublicKey).params
    }

    fun sha256(vararg parti: ByteArray): ByteArray {
        val hash = MessageDigest.getInstance("SHA-256")
        for (parte in parti) hash.update(parte)
        return hash.digest()
    }

    /** I primi 16 byte di SHA-256 della chiave pubblica, in base64url senza «=». */
    fun impronta(chiavePubblica: ByteArray): String = base64URL(sha256(chiavePubblica).copyOf(16))

    /** 16 byte casuali per il QR code: chi li rimanda ha visto lo schermo del computer. */
    fun nuovoGettone(): String = base64URL(ByteArray(16).also { casuale.nextBytes(it) })

    /** T = SHA-256("WebcamLR v2" ‖ chiave telefono ‖ identità telefono ‖ chiave computer ‖ identità computer). */
    fun trascrizione(
        chiaveTelefono: ByteArray,
        identitaTelefono: ByteArray,
        chiaveComputer: ByteArray,
        identitaComputer: ByteArray,
    ): ByteArray = sha256("WebcamLR v2".toByteArray(Charsets.UTF_8), chiaveTelefono, identitaTelefono, chiaveComputer, identitaComputer)

    /** Le 4 cifre da confrontare sui due schermi alla prima volta. */
    fun codice(trascrizione: ByteArray): String {
        val hash = sha256("WebcamLR codice".toByteArray(Charsets.UTF_8), trascrizione)
        var numero = 0L
        for (i in 0 until 4) numero = (numero shl 8) or (hash[i].toLong() and 0xFF)
        return String.format("%04d", numero % 10000)
    }

    /** Le due chiavi AES della sessione: telefono → computer e computer → telefono. */
    fun chiaviSessione(segreto: ByteArray, trascrizione: ByteArray): Pair<ByteArray, ByteArray> = Pair(
        hkdf(segreto, trascrizione, "WebcamLR v2 telefono-computer".toByteArray(Charsets.UTF_8), 32),
        hkdf(segreto, trascrizione, "WebcamLR v2 computer-telefono".toByteArray(Charsets.UTF_8), 32),
    )

    /** HKDF-SHA256 (RFC 5869): estrazione con il sale, poi espansione con le info. */
    fun hkdf(materiale: ByteArray, sale: ByteArray, info: ByteArray, lunghezza: Int): ByteArray {
        val estrazione = Mac.getInstance("HmacSHA256")
        estrazione.init(SecretKeySpec(if (sale.isEmpty()) ByteArray(32) else sale, "HmacSHA256"))
        val prk = estrazione.doFinal(materiale)

        val espansione = Mac.getInstance("HmacSHA256")
        espansione.init(SecretKeySpec(prk, "HmacSHA256"))
        val uscita = ByteArrayOutputStream()
        var blocco = ByteArray(0)
        var contatore = 1
        while (uscita.size() < lunghezza) {
            espansione.update(blocco)
            espansione.update(info)
            espansione.update(contatore.toByte())
            blocco = espansione.doFinal()
            uscita.write(blocco)
            contatore++
        }
        return uscita.toByteArray().copyOf(lunghezza)
    }

    // MARK: chiavi e firme

    /** Chiave pubblica X9.63 non compressa: 04 ‖ X ‖ Y, 65 byte. */
    fun x963(chiave: ECPublicKey): ByteArray =
        byteArrayOf(4) + intero32(chiave.w.affineX) + intero32(chiave.w.affineY)

    /** Da 65 byte X9.63 a chiave pubblica, controllando che il punto stia davvero sulla curva. */
    fun chiavePubblica(x963: ByteArray): ECPublicKey {
        if (x963.size != LUNGHEZZA_CHIAVE_PUBBLICA || x963[0].toInt() != 4) throw ErroreProtocollo("Chiave pubblica non valida")
        val x = BigInteger(1, x963.copyOfRange(1, 33))
        val y = BigInteger(1, x963.copyOfRange(33, 65))
        if (!sullaCurva(x, y)) throw ErroreProtocollo("Chiave pubblica fuori dalla curva")
        val spec = ECPublicKeySpec(ECPoint(x, y), curva)
        return KeyFactory.getInstance("EC").generatePublic(spec) as ECPublicKey
    }

    /** y² = x³ + ax + b (mod p): una chiave fuori dalla curva potrebbe rivelare il segreto ECDH. */
    private fun sullaCurva(x: BigInteger, y: BigInteger): Boolean {
        val campo = curva.curve.field as java.security.spec.ECFieldFp
        val p = campo.p
        if (x.signum() < 0 || y.signum() < 0 || x >= p || y >= p) return false
        val sinistra = y.multiply(y).mod(p)
        val destra = x.multiply(x).multiply(x).add(curva.curve.a.multiply(x)).add(curva.curve.b).mod(p)
        return sinistra == destra
    }

    private fun intero32(valore: BigInteger): ByteArray {
        val byte = valore.toByteArray()
        return when {
            byte.size == 32 -> byte
            byte.size > 32 -> byte.copyOfRange(byte.size - 32, byte.size)
            else -> ByteArray(32 - byte.size) + byte
        }
    }

    /** Verifica una firma ECDSA P-256 / SHA-256 in formato r ‖ s; falso anche se la chiave non è valida. */
    fun verificaFirma(chiavePubblica: ByteArray, dati: ByteArray, firma: ByteArray): Boolean = try {
        if (firma.size != LUNGHEZZA_FIRMA) {
            false
        } else {
            val verifica = Signature.getInstance("SHA256withECDSA")
            verifica.initVerify(chiavePubblica(chiavePubblica))
            verifica.update(dati)
            verifica.verify(firmaDer(firma))
        }
    } catch (e: Exception) {
        false
    }

    /** Firma ECDSA SHA-256 con una chiave privata qualsiasi (anche del Keystore di Android), formato r ‖ s. */
    fun firma(chiave: PrivateKey, dati: ByteArray): ByteArray {
        val firmatario = Signature.getInstance("SHA256withECDSA")
        firmatario.initSign(chiave)
        firmatario.update(dati)
        return firmaGrezza(firmatario.sign())
    }

    /** Da DER (SEQUENCE di due INTEGER, come la producono Java e Android) a r ‖ s di 64 byte. */
    fun firmaGrezza(der: ByteArray): ByteArray {
        var posizione = 0
        fun byte(): Int {
            if (posizione >= der.size) throw ErroreProtocollo("Firma DER troppo corta")
            return der[posizione++].toInt() and 0xFF
        }
        fun lunghezza(): Int {
            val primo = byte()
            if (primo < 0x80) return primo
            var valore = 0
            repeat(primo and 0x7F) { valore = (valore shl 8) or byte() }
            return valore
        }
        fun intero(): ByteArray {
            if (byte() != 0x02) throw ErroreProtocollo("Firma DER non valida")
            val quanti = lunghezza()
            if (posizione + quanti > der.size) throw ErroreProtocollo("Firma DER troppo corta")
            val valore = der.copyOfRange(posizione, posizione + quanti)
            posizione += quanti
            return intero32(BigInteger(1, valore))
        }
        if (byte() != 0x30) throw ErroreProtocollo("Firma DER non valida")
        lunghezza()
        return intero() + intero()
    }

    /** Da r ‖ s a DER, per `Signature.verify`. */
    fun firmaDer(grezza: ByteArray): ByteArray {
        fun intero(byte: ByteArray): ByteArray {
            var valore = BigInteger(1, byte).toByteArray() // con lo zero davanti se serve
            if (valore.isEmpty()) valore = byteArrayOf(0)
            return byteArrayOf(0x02, valore.size.toByte()) + valore
        }
        val corpo = intero(grezza.copyOfRange(0, 32)) + intero(grezza.copyOfRange(32, 64))
        return byteArrayOf(0x30, corpo.size.toByte()) + corpo
    }

    // MARK: base64

    fun base64(dati: ByteArray): String = Base64.getEncoder().encodeToString(dati)

    fun base64URL(dati: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(dati)

    fun daBase64(testo: String, lunghezza: Int): ByteArray {
        val dati = try {
            Base64.getDecoder().decode(testo)
        } catch (e: IllegalArgumentException) {
            throw ErroreProtocollo("Base64 non valido")
        }
        if (dati.size != lunghezza) throw ErroreProtocollo("Lunghezza non valida: ${dati.size} invece di $lunghezza")
        return dati
    }
}

/** Chi firma per il dispositivo: una chiave software ([IdentitaDispositivo]) o, sull'app, il Keystore di Android. */
interface Firmatario {
    /** Chiave pubblica di firma, 65 byte X9.63. */
    val pubblica: ByteArray

    /** Firma ECDSA SHA-256, formato r ‖ s di 64 byte. */
    fun firma(dati: ByteArray): ByteArray

    val impronta: String get() = Sicurezza.impronta(pubblica)
}

/** Una coppia di chiavi di firma P-256 in memoria, salvabile come byte. */
class IdentitaDispositivo private constructor(
    private val privata: ECPrivateKey,
    override val pubblica: ByteArray,
) : Firmatario {

    override fun firma(dati: ByteArray): ByteArray = Sicurezza.firma(privata, dati)

    /** Chiave pubblica (65 byte) seguita dalla privata in PKCS#8: da conservare in un posto protetto. */
    val datiDaSalvare: ByteArray get() = pubblica + privata.encoded

    companion object {
        fun nuova(): IdentitaDispositivo {
            val generatore = KeyPairGenerator.getInstance("EC")
            generatore.initialize(ECGenParameterSpec("secp256r1"))
            val coppia = generatore.generateKeyPair()
            return IdentitaDispositivo(coppia.private as ECPrivateKey, Sicurezza.x963(coppia.public as ECPublicKey))
        }

        /** Da `datiDaSalvare`; controlla che privata e pubblica vadano insieme. */
        fun daDatiSalvati(dati: ByteArray): IdentitaDispositivo {
            if (dati.size <= Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA) throw ErroreProtocollo("Identità salvata non valida")
            val pubblica = dati.copyOfRange(0, Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA)
            val spec = PKCS8EncodedKeySpec(dati.copyOfRange(Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA, dati.size))
            val privata = KeyFactory.getInstance("EC").generatePrivate(spec) as ECPrivateKey
            val identita = IdentitaDispositivo(privata, pubblica)
            val prova = byteArrayOf(1, 2, 3)
            if (!Sicurezza.verificaFirma(pubblica, prova, identita.firma(prova))) {
                throw ErroreProtocollo("Identità salvata rovinata")
            }
            return identita
        }
    }
}

/** Una coppia di chiavi ECDH P-256 effimera: nuova per ogni connessione, buttata alla fine. */
internal class ChiaveEffimera {
    private val coppia = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }
        .generateKeyPair()

    val pubblica: ByteArray = Sicurezza.x963(coppia.public as ECPublicKey)

    /** La coordinata x del punto condiviso, 32 byte. */
    fun segreto(altra: ByteArray): ByteArray {
        val accordo = KeyAgreement.getInstance("ECDH")
        accordo.init(coppia.private)
        accordo.doPhase(Sicurezza.chiavePubblica(altra), true)
        val segreto = accordo.generateSecret()
        return when {
            segreto.size == 32 -> segreto
            segreto.size < 32 -> ByteArray(32 - segreto.size) + segreto
            else -> throw ErroreProtocollo("Segreto ECDH di lunghezza inattesa")
        }
    }
}

/**
 * Cifra e decifra i pacchetti dopo la stretta di mano: AES-256-GCM, un contatore per direzione.
 * Chi usa `cifra` deve scrivere i pacchetti nello stesso ordine in cui li cifra.
 */
class CanaleCifrato(chiaveInvio: ByteArray, chiaveRicezione: ByteArray) {
    private val chiaveInvio = SecretKeySpec(chiaveInvio, "AES")
    private val chiaveRicezione = SecretKeySpec(chiaveRicezione, "AES")
    private val bloccoInvio = Any()
    private val bloccoRicezione = Any()
    private var contatoreInvio = 0uL
    private var contatoreRicezione = 0uL

    fun cifra(chiaro: Pacchetto): Pacchetto = synchronized(bloccoInvio) {
        val flag = chiaro.flag or FLAG_CIFRATO
        val cifrario = Cipher.getInstance("AES/GCM/NoPadding")
        cifrario.init(Cipher.ENCRYPT_MODE, chiaveInvio, GCMParameterSpec(LUNGHEZZA_ETICHETTA * 8, nonce(contatoreInvio)))
        cifrario.updateAAD(byteArrayOf(chiaro.tipo.valore.toByte(), flag.toByte()))
        val cifrato = cifrario.doFinal(chiaro.contenuto) // testo cifrato ‖ etichetta
        contatoreInvio++
        Pacchetto(chiaro.tipo, flag, cifrato)
    }

    /** Un pacchetto ripetuto, mancante o alterato è un errore: la connessione va chiusa. */
    fun decifra(cifrato: Pacchetto): Pacchetto = synchronized(bloccoRicezione) {
        if (cifrato.flag and FLAG_CIFRATO == 0 || cifrato.contenuto.size < LUNGHEZZA_ETICHETTA) {
            throw ErroreProtocollo("Pacchetto non cifrato")
        }
        val chiaro = try {
            val cifrario = Cipher.getInstance("AES/GCM/NoPadding")
            cifrario.init(Cipher.DECRYPT_MODE, chiaveRicezione, GCMParameterSpec(LUNGHEZZA_ETICHETTA * 8, nonce(contatoreRicezione)))
            cifrario.updateAAD(byteArrayOf(cifrato.tipo.valore.toByte(), cifrato.flag.toByte()))
            cifrario.doFinal(cifrato.contenuto)
        } catch (e: java.security.GeneralSecurityException) {
            throw ErroreProtocollo("Pacchetto cifrato non valido")
        }
        contatoreRicezione++
        Pacchetto(cifrato.tipo, cifrato.flag and FLAG_CIFRATO.inv(), chiaro)
    }

    companion object {
        const val FLAG_CIFRATO = 0x80
        const val LUNGHEZZA_ETICHETTA = 16

        /** 4 byte a zero ‖ contatore a 64 bit big-endian. */
        fun nonce(contatore: ULong): ByteArray = ByteArray(4) + Pacchetto.intero64(contatore)
    }
}

/** Cosa resta della stretta di mano: il canale e chi c'è dall'altra parte. */
class SessioneSicura(
    val canale: CanaleCifrato,
    /** La chiave pubblica di firma dell'altro dispositivo. */
    val identitaAltro: ByteArray,
    val trascrizione: ByteArray,
    /** Le 4 cifre da confrontare alla prima volta. */
    val codice: String,
) {
    val improntaAltro: String get() = Sicurezza.impronta(identitaAltro)
}

/** La stretta di mano dal lato del telefono. */
class StrettaTelefono(private val identita: Firmatario) {
    private val effimera = ChiaveEffimera()

    val apertura: Stretta
        get() = Stretta(Sicurezza.VERSIONE_SICURA, Sicurezza.base64(effimera.pubblica), Sicurezza.base64(identita.pubblica))

    /** Verifica la risposta del computer; poi va mandata la [Prova], già cifrata. */
    fun completa(risposta: Stretta, gettone: String? = null): Pair<SessioneSicura, Prova> {
        val firmaTesto = risposta.firma
        if (risposta.versione != Sicurezza.VERSIONE_SICURA || firmaTesto == null) throw ErroreProtocollo("Stretta di mano non valida")
        val chiaveComputer = Sicurezza.daBase64(risposta.chiave, Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA)
        val identitaComputer = Sicurezza.daBase64(risposta.identita, Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA)
        val firma = Sicurezza.daBase64(firmaTesto, Sicurezza.LUNGHEZZA_FIRMA)

        val trascrizione = Sicurezza.trascrizione(effimera.pubblica, identita.pubblica, chiaveComputer, identitaComputer)
        if (!Sicurezza.verificaFirma(identitaComputer, trascrizione, firma)) throw ErroreProtocollo("Firma del computer non valida")
        val (telefonoComputer, computerTelefono) = Sicurezza.chiaviSessione(effimera.segreto(chiaveComputer), trascrizione)
        val sessione = SessioneSicura(
            CanaleCifrato(chiaveInvio = telefonoComputer, chiaveRicezione = computerTelefono),
            identitaComputer, trascrizione, Sicurezza.codice(trascrizione),
        )
        return Pair(sessione, Prova(Sicurezza.base64(identita.firma(trascrizione)), gettone))
    }
}

/** La stretta di mano dal lato del computer: qui serve ai test e al computer simulato. */
class StrettaComputer(private val identita: Firmatario) {
    private val effimera = ChiaveEffimera()

    fun rispondi(apertura: Stretta): Pair<Stretta, SessioneSicura> {
        if (apertura.versione != Sicurezza.VERSIONE_SICURA) throw ErroreProtocollo("Versione della stretta di mano non valida")
        val chiaveTelefono = Sicurezza.daBase64(apertura.chiave, Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA)
        val identitaTelefono = Sicurezza.daBase64(apertura.identita, Sicurezza.LUNGHEZZA_CHIAVE_PUBBLICA)
        // Un'identità che non è un punto valido della curva non potrà mai firmare la prova.
        Sicurezza.chiavePubblica(identitaTelefono)

        val trascrizione = Sicurezza.trascrizione(chiaveTelefono, identitaTelefono, effimera.pubblica, identita.pubblica)
        val (telefonoComputer, computerTelefono) = Sicurezza.chiaviSessione(effimera.segreto(chiaveTelefono), trascrizione)
        val risposta = Stretta(
            Sicurezza.VERSIONE_SICURA, Sicurezza.base64(effimera.pubblica), Sicurezza.base64(identita.pubblica),
            Sicurezza.base64(identita.firma(trascrizione)),
        )
        val sessione = SessioneSicura(
            CanaleCifrato(chiaveInvio = computerTelefono, chiaveRicezione = telefonoComputer),
            identitaTelefono, trascrizione, Sicurezza.codice(trascrizione),
        )
        return Pair(risposta, sessione)
    }

    companion object {
        /** Il telefono possiede davvero la chiave che ha dichiarato. */
        fun provaValida(prova: Prova, sessione: SessioneSicura): Boolean {
            val firma = try {
                Sicurezza.daBase64(prova.firma, Sicurezza.LUNGHEZZA_FIRMA)
            } catch (e: ErroreProtocollo) {
                return false
            }
            return Sicurezza.verificaFirma(sessione.identitaAltro, sessione.trascrizione, firma)
        }
    }
}
