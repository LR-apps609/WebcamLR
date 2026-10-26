package it.lrapps.webcamlr.android

import android.app.Application
import it.lrapps.webcamlr.android.acquisti.NegozioPro
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.IdentitaTelefono
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.sessione.ServizioInOnda
import it.lrapps.webcamlr.android.sistema.Testi

class WebcamLRApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // I testi fuori dall'interfaccia (sessione, avviso, negozio) nella lingua dell'app, come MainActivity.
        Testi.prepara(this)
        Impostazioni.prepara(this)
        ComputerConosciuti.prepara(this)
        // Il Keystore si legge in sottofondo all'avvio, non al tocco su «Collega».
        IdentitaTelefono.prepara(this)
        ServizioInOnda.creaCanale(this)
        // WebcamLR Pro: lo stato salvato subito, poi Google Play in sottofondo.
        NegozioPro.avvia(this)
    }
}
