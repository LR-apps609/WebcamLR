// WebcamLR · lato app del microfono del telefono (P20).
// Funzioni C semplici, senza tipi atomici in vista: Swift le chiama dal ponte (Ponte.h).
// Tutte, tranne microfono_ultima_lettura, solo dalla coda di MicrofonoTelefono.

#ifndef WEBCAMLR_COLLEGAMENTO_MICROFONO_H
#define WEBCAMLR_COLLEGAMENTO_MICROFONO_H

#include <stdbool.h>
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

#endif
