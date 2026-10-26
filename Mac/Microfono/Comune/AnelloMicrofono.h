// WebcamLR · microfono del telefono sul Mac (P20).
// La memoria condivisa tra l'app (che scrive l'audio) e il driver «WebcamLR Microfono.driver»
// (che lo legge dentro coreaudiod). La crea l'aiutante (webcamlr-microfono-aiuto, un LaunchDaemon)
// e la passa a tutti e due con XPC: vedi Documenti/Microfono Mac.md per il perché.
//
// Linea del tempo comune: l'indice di ogni campione è il tempo di sistema dall'avvio
// (CLOCK_UPTIME_RAW = mach_absolute_time, lo stesso di Orologio nel protocollo) espresso
// in campioni a 48 kHz. L'app mette ogni campione nel punto in cui va ascoltato; il driver,
// che ha come orologio lo stesso tempo di sistema, legge il punto che corrisponde al suo ciclo.
// Così la sincronia con il video la decide solo l'app.
//
// Solo C11, senza dipendenze: lo includono il driver, l'aiutante e la parte C dell'app.

#ifndef WEBCAMLR_ANELLO_MICROFONO_H
#define WEBCAMLR_ANELLO_MICROFONO_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

/// Il servizio Mach dell'aiutante. Deve essere uguale in: Info.plist del driver
/// (AudioServerPlugIn_MachServices), plist del LaunchDaemon, permessi dell'app (base.yml).
#define MICROFONO_SERVIZIO "it.lrapps.webcamlr.microfono"

/// Il servizio Mach della rimozione: lo stesso programma dell'aiutante, avviato da un secondo LaunchDaemon
/// (it.lrapps.webcamlr.microfono.rimozione.plist) che gira come root e risponde solo all'app WebcamLR
/// firmata dallo stesso team. Deve essere uguale nel plist e nei permessi dell'app (base.yml).
#define MICROFONO_SERVIZIO_RIMOZIONE "it.lrapps.webcamlr.microfono.rimozione"

/// L'identificatore di firma dell'app WebcamLR per Mac (PRODUCT_BUNDLE_IDENTIFIER in base.yml):
/// l'aiutante accetta solo lei (con il suo Team ID) e coreaudiod.
#define MICROFONO_ID_APP "it.lrapps.webcamlr.mac"

/// «WLRM» e la versione della disposizione: se cambiano, chi legge non si fida della memoria.
#define MICROFONO_MAGIA 0x574C524Du
#define MICROFONO_VERSIONE 1u

#define MICROFONO_FREQUENZA 48000u
/// Potenza di 2: 32768 campioni = 683 ms a 48 kHz. Basta per il ritardo massimo (300 ms) più il margine.
#define MICROFONO_CAPACITA 32768u
#define MICROFONO_MASCHERA (MICROFONO_CAPACITA - 1u)

/// L'UID del dispositivo: l'app lo cerca con kAudioHardwarePropertyTranslateUIDToDevice
/// per sapere se il driver è installato (MicrofonoTelefono.swift).
#define MICROFONO_UID_DISPOSITIVO "it.lrapps.webcamlr.microfono.dispositivo"

typedef struct {
    uint32_t magia;
    uint32_t versione;
    uint32_t frequenza;
    uint32_t capacita;
    /// Indice (nella linea del tempo comune) dopo l'ultimo campione scritto dall'app.
    /// Validi sono gli indici in [fine - capacita, fine). Scritto con «release» dopo i campioni.
    _Atomic uint64_t fine;
    /// Ultima scrittura dell'app, in microsecondi di sistema: per la diagnosi.
    _Atomic uint64_t ultimaScrittura;
    /// Il driver ha letto la memoria almeno una volta (microsecondi di sistema): per la diagnosi.
    _Atomic uint64_t ultimaLettura;
    float campioni[MICROFONO_CAPACITA];
} AnelloMicrofono;

/// Prepara una memoria appena creata (solo l'aiutante).
static inline void anello_prepara(AnelloMicrofono *anello) {
    memset(anello, 0, sizeof(*anello));
    anello->magia = MICROFONO_MAGIA;
    anello->versione = MICROFONO_VERSIONE;
    anello->frequenza = MICROFONO_FREQUENZA;
    anello->capacita = MICROFONO_CAPACITA;
    atomic_store_explicit(&anello->fine, 0, memory_order_release);
}

static inline bool anello_valido(const AnelloMicrofono *anello) {
    return anello != NULL && anello->magia == MICROFONO_MAGIA && anello->versione == MICROFONO_VERSIONE
        && anello->capacita == MICROFONO_CAPACITA;
}

/// Microsecondi di sistema → indice nella linea del tempo comune (48 campioni ogni millisecondo).
static inline uint64_t anello_indice_da_microsecondi(uint64_t microsecondi) {
    return microsecondi / 1000u * 48u + (microsecondi % 1000u) * 48u / 1000u;
}

#endif
