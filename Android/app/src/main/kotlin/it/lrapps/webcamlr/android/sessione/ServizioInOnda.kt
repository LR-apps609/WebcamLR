package it.lrapps.webcamlr.android.sessione

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import it.lrapps.webcamlr.android.MainActivity
import it.lrapps.webcamlr.android.R
import it.lrapps.webcamlr.android.sistema.Testi

/**
 * Servizio in primo piano di tipo «fotocamera» e, con il permesso, «microfono» (Android 9+ lo richiede per usare
 * fotocamera e microfono a schermo spento o con l'app in sottofondo; da Android 14 ogni tipo vuole il suo permesso
 * FOREGROUND_SERVICE_* e il tipo «microfono» solo con RECORD_AUDIO già concesso): un avviso fisso
 * «WebcamLR · video al computer» con «Scollega». La sessione vive nel processo ([Sessioni]); il servizio serve a
 * tenerlo in vita e a mostrarlo. I tipi vanno chiesti mentre l'app è in primo piano: [aggiorna] dopo il permesso.
 */
class ServizioInOnda : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == AZIONE_SCOLLEGA) {
            Handler(Looper.getMainLooper()).post { Sessioni.attuale?.termina() }
            stopSelf()
            return START_NOT_STICKY
        }
        creaCanale(this)
        val apri = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val scollega = PendingIntent.getService(
            this, 1, Intent(this, ServizioInOnda::class.java).setAction(AZIONE_SCOLLEGA),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val nome = Sessioni.attuale?.computer?.nome
        val avviso: Notification = NotificationCompat.Builder(this, CANALE)
            .setSmallIcon(R.drawable.ic_launcher_monocromatica)
            .setContentTitle(Testi.testo(R.string.avviso_titolo))
            .setContentText(if (nome != null) Testi.testo(R.string.avviso_testo_collegato, nome) else Testi.testo(R.string.avviso_testo))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(apri)
            .addAction(0, Testi.testo(R.string.scollega), scollega)
            .build()
        try {
            ServiceCompat.startForeground(this, ID_AVVISO, avviso, tipi(this))
        } catch (e: Exception) {
            // Android 12+ non lo permette se l'app non è in primo piano: la sessione continua finché lo schermo è acceso.
            Log.w("WebcamLR", "Servizio in primo piano non avviato", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // L'app tolta dalle recenti: si chiude il collegamento in modo pulito, con `arrivederci`.
        Handler(Looper.getMainLooper()).post { Sessioni.attuale?.termina() }
        stopSelf()
    }

    companion object {
        private const val CANALE = "in-onda"
        private const val ID_AVVISO = 1
        private const val AZIONE_SCOLLEGA = "it.lrapps.webcamlr.android.SCOLLEGA"

        fun avvia(context: Context) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, ServizioInOnda::class.java))
            } catch (e: Exception) {
                Log.w("WebcamLR", "Servizio in primo piano non avviato", e)
            }
        }

        fun ferma(context: Context) {
            context.stopService(Intent(context, ServizioInOnda::class.java))
        }

        /** Il permesso del microfono è arrivato: si chiede di nuovo il servizio, ora anche di tipo «microfono». */
        fun aggiorna(context: Context) {
            if (Sessioni.attuale != null) avvia(context)
        }

        /** Fotocamera sempre; microfono solo se il permesso c'è (altrimenti Android 14 rifiuta tutto il servizio). */
        fun tipi(context: Context): Int {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return 0
            var tipi = ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                tipi = tipi or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            return tipi
        }

        fun creaCanale(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val gestore = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Nome e descrizione si rifanno a ogni avvio: seguono la lingua del telefono se cambia.
            val canale = NotificationChannel(CANALE, Testi.testo(R.string.canale_in_onda), NotificationManager.IMPORTANCE_LOW).apply {
                description = Testi.testo(R.string.canale_in_onda_descrizione)
                setShowBadge(false)
            }
            gestore.createNotificationChannel(canale)
        }
    }
}
