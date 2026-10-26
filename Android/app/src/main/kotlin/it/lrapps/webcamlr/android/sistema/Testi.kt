package it.lrapps.webcamlr.android.sistema

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * La lingua dell'app e i testi fuori dall'interfaccia (sessione, registro del collegamento, avviso del servizio,
 * WebcamLR Pro). La regola è una sola, come su iPhone e Mac: italiano se il telefono è in italiano, inglese in ogni
 * altra lingua (values/ è l'italiano, values-en/ l'inglese). MainActivity la usa per l'interfaccia ([localizza]);
 * il resto dell'app chiede i testi a [testo], con un contesto localizzato creato una volta e rifatto solo se la
 * lingua del telefono cambia.
 */
object Testi {
    @Volatile private var app: Context? = null
    @Volatile private var memoria: Pair<Locale, Context>? = null

    /** Da WebcamLRApp, prima di tutto il resto. */
    fun prepara(context: Context) {
        app = context.applicationContext
    }

    /** La lingua dell'app per una configurazione: quella del telefono se è italiano o inglese, altrimenti l'inglese. */
    fun lingua(configurazione: Configuration): Locale {
        val telefono = configurazione.locales[0]
        return if (telefono.language == "it" || telefono.language == "en") telefono else Locale.ENGLISH
    }

    /** `base` con la lingua dell'app (lo stesso contesto se è già quella giusta). */
    fun localizza(base: Context): Context {
        val configurazione = base.resources.configuration
        val voluta = lingua(configurazione)
        if (voluta == configurazione.locales[0]) return base
        val nuova = Configuration(configurazione)
        nuova.setLocale(voluta)
        return base.createConfigurationContext(nuova)
    }

    private fun contesto(): Context {
        val base = app ?: error("Testi.prepara non chiamato")
        val telefono = base.resources.configuration.locales[0]
        memoria?.let { (lingua, contesto) -> if (lingua == telefono) return contesto }
        val contesto = localizza(base)
        memoria = telefono to contesto
        return contesto
    }

    /** Un testo delle risorse nella lingua dell'app, da qualsiasi thread. */
    fun testo(id: Int, vararg argomenti: Any): String = contesto().getString(id, *argomenti)

    /** La lingua dell'app, per i numeri: «1,4 s» in italiano, «1.4 s» in inglese. */
    val locale: Locale get() = contesto().resources.configuration.locales[0]

    /** Vero se l'app è in inglese. */
    val inglese: Boolean get() = locale.language != "it"
}
