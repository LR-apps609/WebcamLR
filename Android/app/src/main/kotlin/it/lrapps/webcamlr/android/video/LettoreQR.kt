package it.lrapps.webcamlr.android.video

import android.graphics.ImageFormat
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import it.lrapps.webcamlr.protocollo.Associazione
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Legge il QR code del computer dai fotogrammi YUV della fotocamera con ZXing core (Apache 2.0): niente ML Kit
 * né servizi Google, quindi funziona anche sui Huawei senza Play Store. Il QR si legge in qualsiasi verso,
 * quindi non serve ruotare l'immagine; basta la luminanza (il piano Y).
 */
class LettoreQR(larghezza: Int, altezza: Int, private val suLetto: (Associazione) -> Unit, private val suAltroQR: () -> Unit) {
    private val thread = HandlerThread("webcamlr-qr").apply { start() }
    private val gestore = Handler(thread.looper)
    private val lettore = ImageReader.newInstance(larghezza, altezza, ImageFormat.YUV_420_888, 2)
    private val occupato = AtomicBoolean(false)
    private val trovato = AtomicBoolean(false)
    private val decodificatore = QRCodeReader()
    private val suggerimenti = mapOf(
        DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
        DecodeHintType.CHARACTER_SET to "UTF-8",
    )
    private var buffer = ByteArray(0)
    private var ultimoAvvisoAltroQR = 0L

    val superficie: Surface get() = lettore.surface

    init {
        lettore.setOnImageAvailableListener({ sorgente ->
            val immagine = try { sorgente.acquireLatestImage() } catch (e: IllegalStateException) { null } ?: return@setOnImageAvailableListener
            try {
                if (trovato.get() || !occupato.compareAndSet(false, true)) return@setOnImageAvailableListener
                val piano = immagine.planes[0]
                val l = immagine.width
                val a = immagine.height
                val passoRiga = piano.rowStride
                val dati = piano.buffer
                if (buffer.size != l * a) buffer = ByteArray(l * a)
                // Il piano Y può avere righe più lunghe dell'immagine: si copia riga per riga.
                for (riga in 0 until a) {
                    dati.position(riga * passoRiga)
                    dati.get(buffer, riga * l, minOf(l, dati.remaining()))
                }
                decodifica(l, a)
            } catch (e: Exception) {
                // fotogramma rovinato: si passa al prossimo
            } finally {
                occupato.set(false)
                immagine.close()
            }
        }, gestore)
    }

    private fun decodifica(larghezza: Int, altezza: Int) {
        val sorgente = PlanarYUVLuminanceSource(buffer, larghezza, altezza, 0, 0, larghezza, altezza, false)
        val testo = try {
            decodificatore.decode(BinaryBitmap(HybridBinarizer(sorgente)), suggerimenti).text
        } catch (e: NotFoundException) {
            return
        } catch (e: Exception) {
            return
        } finally {
            decodificatore.reset()
        }
        val associazione = Associazione.leggi(testo)
        if (associazione != null) {
            if (trovato.compareAndSet(false, true)) suLetto(associazione)
        } else if (System.currentTimeMillis() - ultimoAvvisoAltroQR > 3_000) {
            ultimoAvvisoAltroQR = System.currentTimeMillis()
            suAltroQR()
        }
    }

    fun chiudi() {
        gestore.post {
            lettore.close()
            thread.quitSafely()
        }
    }
}
