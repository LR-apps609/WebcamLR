// WebcamLR · lato app del microfono del telefono (P20).
// Funzioni C semplici, senza tipi atomici in vista: Swift le chiama dal ponte (Ponte.h).
// Tutte, tranne microfono_ultima_lettura, solo dalla coda di MicrofonoTelefono.

#ifndef WEBCAMLR_COLLEGAMENTO_MICROFONO_H
#define WEBCAMLR_COLLEGAMENTO_MICROFONO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// Chiede all'aiutante la memoria condivisa, se non c'è già. Vero se l'app può scrivere l'audio.
/// Senza aiutante (microfono non installato) risponde falso in pochi millisecondi.
bool microfono_collega(void);

/// Lascia la memoria (telefono scollegato a lungo o app in chiusura).
void microfono_scollega(void);

bool microfono_collegato(void);

/// Mette `quanti` campioni (48 kHz, mono, da -1 a 1) a partire dall'indice `posizione` della linea del tempo
/// comune (AnelloMicrofono.h). Un buco prima di `posizione` diventa silenzio con le dissolvenze, una
/// sovrapposizione diventa una dissolvenza incrociata: niente clic.
void microfono_scrivi(uint64_t posizione, const float *campioni, uint32_t quanti);

/// Dopo l'ultimo campione scritto; 0 se niente ancora.
uint64_t microfono_fine(void);

/// L'ultima volta che il driver ha letto (microsecondi di sistema); 0 se mai o non collegati.
uint64_t microfono_ultima_lettura(void);

// ——— Impostazioni › Microfono del telefono (da qualsiasi coda, ma non dalla principale: aspettano la risposta) ———

/// Chiede all'aiutante la versione installata («1.0 (2)»), senza prendere la memoria. Vero se l'aiutante ha risposto;
/// `versione` resta vuota se l'aiutante è di una versione che non la dice. Falso se l'aiutante non c'è o ci rifiuta.
bool microfono_leggi_versione(char *versione, size_t dimensione);

/// Esiti di microfono_disinstalla.
typedef enum {
    /// Driver, aiutante e LaunchDaemon tolti, coreaudiod riavviato.
    MicrofonoRimozioneRiuscita = 0,
    /// Il servizio di rimozione non c'è (microfono installato da una versione di prima, o già tolto): serve lo script.
    MicrofonoRimozioneServizioAssente = 1,
    /// L'aiutante ha la firma locale: non può sapere chi chiede, quindi non toglie niente da root. Serve lo script.
    MicrofonoRimozioneFirmaLocale = 2,
    /// Qualcosa non si è potuto togliere: `errore` dice cosa.
    MicrofonoRimozioneNonRiuscita = 3
} MicrofonoRimozione;

/// Chiede al LaunchDaemon di rimozione (root) di togliere il microfono. Aspetta la risposta (qualche secondo:
/// coreaudiod si riavvia). La memoria dell'app non va chiusa prima: quando l'aiutante si ferma, il collegamento
/// cade da solo e MicrofonoTelefono smette di scrivere.
MicrofonoRimozione microfono_disinstalla(char *errore, size_t dimensione);

#endif
