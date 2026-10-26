package it.lrapps.webcamlr.android.rete

import it.lrapps.webcamlr.android.logica.Sottoreti
import it.lrapps.webcamlr.android.logica.Strada
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Da quale strada si raggiunge un indirizzo del computer: il cavo (Tethering USB, `rndis`/`ncm`/`usb`) o la rete
 * (Wi-Fi, hotspot, Wi-Fi diretto), guardando le sottoreti IPv4 delle interfacce accese del telefono.
 */
object StradeRete {
    /** Un'interfaccia accesa del telefono con un indirizzo IPv4. */
    data class Interfaccia(val nome: String, val cavo: Boolean, val indirizzo: Int, val prefisso: Int)

    /** Le interfacce accese con IPv4, senza quella interna (`lo`). Lista vuota se Android non le dà. */
    fun interfacce(): List<Interfaccia> = try {
        NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().filter { it.isUp && !it.isLoopback }.flatMap { interfaccia ->
            val nome = interfaccia.name
            val cavo = nome.lowercase().let { it.startsWith("rndis") || it.startsWith("ncm") || it.startsWith("usb") }
            interfaccia.interfaceAddresses.mapNotNull { indirizzo ->
                val ip = indirizzo.address as? Inet4Address ?: return@mapNotNull null
                val numero = ip.hostAddress?.let { Sottoreti.numero(it) } ?: return@mapNotNull null
                Interfaccia(nome, cavo, numero, indirizzo.networkPrefixLength.toInt())
            }
        }
    } catch (e: Exception) {
        emptyList()
    }

    /** La strada che raggiunge questo indirizzo adesso; null se nessuna interfaccia accesa è sulla sua sottorete. */
    fun strada(indirizzo: String, interfacce: List<Interfaccia>): Strada? {
        val numero = Sottoreti.numero(indirizzo) ?: return null
        val trovata = interfacce.firstOrNull { Sottoreti.stessa(it.indirizzo, numero, it.prefisso) } ?: return null
        return if (trovata.cavo) Strada.CAVO else Strada.WIFI
    }

    /** Vero se l'interfaccia con questo nome è ancora accesa con un indirizzo IPv4. */
    fun accesa(nome: String, interfacce: List<Interfaccia>): Boolean = interfacce.any { it.nome == nome }
}
