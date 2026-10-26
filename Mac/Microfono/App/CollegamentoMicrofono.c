// WebcamLR · lato app del microfono del telefono (P20). Vedi CollegamentoMicrofono.h.

#include "CollegamentoMicrofono.h"

#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <xpc/xpc.h>

#include "../Comune/AnelloMicrofono.h"

/// Campioni delle dissolvenze: 128 = 2,7 ms, abbastanza per non sentire un clic, troppo poco per sentire un buco.
#define DISSOLVENZA 128u

static AnelloMicrofono *anello = NULL;
static size_t dimensioneAnello = 0;
static xpc_connection_t collegamento = NULL;
/// L'aiutante è uscito o il collegamento è caduto: la memoria va lasciata e richiesta di nuovo
/// (un aiutante ripartito ne crea una nuova). Scritto dalla coda di XPC, letto dalla coda dell'app.
static _Atomic bool daRifare = false;
/// Cresce a ogni collegamento nuovo: l'errore di un collegamento già chiuso da noi non conta.
static _Atomic uint64_t generazione = 0;

static uint64_t adessoMicrosecondi(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000u;
}

void microfono_scollega(void) {
    if (anello != NULL) {
        munmap(anello, dimensioneAnello);
        anello = NULL;
        dimensioneAnello = 0;
    }
    if (collegamento != NULL) {
        // Prima si cambia generazione: l'errore che arriva dalla chiusura qui sotto non conta.
        atomic_fetch_add(&generazione, 1);
        xpc_connection_cancel(collegamento);
        xpc_release(collegamento);
        collegamento = NULL;
    }
    atomic_store(&daRifare, false);
}

bool microfono_collegato(void) {
    return anello != NULL && !atomic_load(&daRifare);
}

bool microfono_collega(void) {
    if (atomic_load(&daRifare)) microfono_scollega();
    if (anello != NULL) return true;

    if (collegamento == NULL) {
        collegamento = xpc_connection_create_mach_service(MICROFONO_SERVIZIO, NULL, 0);
        if (collegamento == NULL) return false;
        uint64_t questo = atomic_fetch_add(&generazione, 1) + 1;
        xpc_connection_set_event_handler(collegamento, ^(xpc_object_t evento) {
            if (xpc_get_type(evento) == XPC_TYPE_ERROR && atomic_load(&generazione) == questo) {
                atomic_store(&daRifare, true);
            }
        });
        xpc_connection_resume(collegamento);
    }

    xpc_object_t richiesta = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(richiesta, "richiesta", "memoria");
    xpc_object_t risposta = xpc_connection_send_message_with_reply_sync(collegamento, richiesta);
    xpc_release(richiesta);

    bool riuscito = false;
    if (xpc_get_type(risposta) == XPC_TYPE_DICTIONARY) {
        xpc_object_t memoria = xpc_dictionary_get_value(risposta, "memoria");
        if (memoria != NULL) {
            void *indirizzo = NULL;
            size_t dimensione = xpc_shmem_map(memoria, &indirizzo);
            if (indirizzo != NULL && dimensione >= sizeof(AnelloMicrofono) && anello_valido((AnelloMicrofono *)indirizzo)) {
                anello = (AnelloMicrofono *)indirizzo;
                dimensioneAnello = dimensione;
                riuscito = true;
            } else if (indirizzo != NULL) {
                // Un aiutante di un'altra versione: meglio niente che una memoria con un'altra forma.
                munmap(indirizzo, dimensione);
            }
        }
    }
    xpc_release(risposta);
    if (!riuscito) {
        // Senza aiutante la risposta è un errore: si riprova più tardi con un collegamento nuovo.
        microfono_scollega();
    }
    return riuscito;
}

uint64_t microfono_fine(void) {
    if (anello == NULL) return 0;
    return atomic_load_explicit(&anello->fine, memory_order_relaxed);
}

uint64_t microfono_ultima_lettura(void) {
    AnelloMicrofono *attuale = anello;
    if (attuale == NULL) return 0;
    return atomic_load_explicit(&attuale->ultimaLettura, memory_order_relaxed);
}

void microfono_scrivi(uint64_t posizione, const float *campioni, uint32_t quanti) {
    if (anello == NULL || campioni == NULL || quanti == 0 || quanti > MICROFONO_CAPACITA / 2) return;
    float *s = anello->campioni;
    // Solo l'app scrive `fine`: la lettura rilassata basta.
    uint64_t fine = atomic_load_explicit(&anello->fine, memory_order_relaxed);
    // Molto prima della fine: ormai fuori dalla memoria, non serve a niente.
    if (posizione + MICROFONO_CAPACITA < fine) return;

    if (posizione > fine) {
        uint64_t buco = posizione - fine;
        // La coda già scritta (di solito non ancora letta: l'app scrive in anticipo) scende a zero.
        if (fine > 0 && buco < MICROFONO_CAPACITA) {
            uint64_t passi = fine < DISSOLVENZA ? fine : DISSOLVENZA;
            for (uint64_t k = 0; k < passi; k++) {
                uint64_t indice = fine - passi + k;
                float peso = 1.0f - (float)(k + 1) / (float)passi;
                s[indice & MICROFONO_MASCHERA] *= peso;
            }
        }
        // Il buco diventa silenzio (al massimo tutta la memoria: niente resti di prima).
        uint64_t daAzzerare = buco < MICROFONO_CAPACITA ? buco : MICROFONO_CAPACITA;
        for (uint64_t i = posizione - daAzzerare; i < posizione; i++) {
            s[i & MICROFONO_MASCHERA] = 0.0f;
        }
        // Il blocco nuovo entra con una dissolvenza.
        for (uint32_t k = 0; k < quanti; k++) {
            float valore = campioni[k];
            if (k < DISSOLVENZA) valore *= (float)(k + 1) / (float)DISSOLVENZA;
            s[(posizione + k) & MICROFONO_MASCHERA] = valore;
        }
    } else {
        // Sovrapposizione (o il caso normale, posizione == fine, senza nessuna dissolvenza):
        // sui campioni già scritti si passa dal vecchio al nuovo in DISSOLVENZA campioni.
        for (uint32_t k = 0; k < quanti; k++) {
            uint64_t indice = posizione + k;
            float valore = campioni[k];
            if (indice < fine && k < DISSOLVENZA) {
                float peso = (float)(k + 1) / (float)DISSOLVENZA;
                valore = s[indice & MICROFONO_MASCHERA] * (1.0f - peso) + valore * peso;
            }
            s[indice & MICROFONO_MASCHERA] = valore;
        }
    }
    // La fine è sempre dopo il blocco nuovo, anche se prima era più avanti: quello che c'era dopo
    // apparteneva alla linea del tempo vecchia. Release: il driver vede i campioni prima della fine.
    atomic_store_explicit(&anello->ultimaScrittura, adessoMicrosecondi(), memory_order_relaxed);
    atomic_store_explicit(&anello->fine, posizione + quanti, memory_order_release);
}

// ——— Impostazioni › Microfono del telefono ———

/// Una richiesta sola su un collegamento nuovo, chiuso subito dopo (non tocca quello della memoria).
/// La risposta (da rilasciare) o l'errore di XPC: XPC_ERROR_CONNECTION_INVALID se il servizio non c'è,
/// XPC_ERROR_CONNECTION_INTERRUPTED se l'aiutante ci ha rifiutati o è caduto.
static xpc_object_t richiestaSingola(const char *servizio, const char *richiesta) {
    xpc_connection_t singolo = xpc_connection_create_mach_service(servizio, NULL, 0);
    if (singolo == NULL) return NULL;
    xpc_connection_set_event_handler(singolo, ^(xpc_object_t evento) { (void)evento; });
    xpc_connection_resume(singolo);
    xpc_object_t messaggio = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(messaggio, "richiesta", richiesta);
    xpc_object_t risposta = xpc_connection_send_message_with_reply_sync(singolo, messaggio);
    xpc_release(messaggio);
    xpc_connection_cancel(singolo);
    xpc_release(singolo);
    return risposta;
}

static void copiaTesto(char *destinazione, size_t dimensione, const char *origine) {
    if (destinazione == NULL || dimensione == 0) return;
    strlcpy(destinazione, origine != NULL ? origine : "", dimensione);
}

bool microfono_leggi_versione(char *versione, size_t dimensione) {
    copiaTesto(versione, dimensione, "");
    xpc_object_t risposta = richiestaSingola(MICROFONO_SERVIZIO, "versione");
    if (risposta == NULL) return false;
    bool riuscito = xpc_get_type(risposta) == XPC_TYPE_DICTIONARY;
    if (riuscito) copiaTesto(versione, dimensione, xpc_dictionary_get_string(risposta, "versionePacchetto"));
    xpc_release(risposta);
    return riuscito;
}

MicrofonoRimozione microfono_disinstalla(char *errore, size_t dimensione) {
    copiaTesto(errore, dimensione, "");
    xpc_object_t risposta = richiestaSingola(MICROFONO_SERVIZIO_RIMOZIONE, "disinstalla");
    if (risposta == NULL) return MicrofonoRimozioneServizioAssente;
    MicrofonoRimozione esito;
    if (xpc_get_type(risposta) == XPC_TYPE_DICTIONARY) {
        const char *motivo = xpc_dictionary_get_string(risposta, "errore");
        if (xpc_dictionary_get_bool(risposta, "esito")) {
            esito = MicrofonoRimozioneRiuscita;
        } else if (motivo != NULL && strcmp(motivo, "firma-locale") == 0) {
            esito = MicrofonoRimozioneFirmaLocale;
        } else {
            esito = MicrofonoRimozioneNonRiuscita;
            copiaTesto(errore, dimensione, motivo);
        }
    } else if (risposta == XPC_ERROR_CONNECTION_INVALID) {
        esito = MicrofonoRimozioneServizioAssente;
    } else {
        // Di solito: l'app non ha la firma del team dell'aiutante (per esempio una build con la firma locale).
        esito = MicrofonoRimozioneNonRiuscita;
        copiaTesto(errore, dimensione, "rifiutato");
    }
    xpc_release(risposta);
    return esito;
}
