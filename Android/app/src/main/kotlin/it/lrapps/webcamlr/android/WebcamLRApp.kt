package it.lrapps.webcamlr.android

import android.app.Application
import it.lrapps.webcamlr.android.dati.ComputerConosciuti
import it.lrapps.webcamlr.android.dati.IdentitaTelefono
import it.lrapps.webcamlr.android.dati.Impostazioni
import it.lrapps.webcamlr.android.sessione.ServizioInOnda

class WebcamLRApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Impostazioni.prepara(this)
        ComputerConosciuti.prepara(this)
        // Il Keystore si legge in sottofondo all'avvio, non al tocco su «Collega».
        IdentitaTelefono.prepara(this)
        ServizioInOnda.creaCanale(this)
    }
}
