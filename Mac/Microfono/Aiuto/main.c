// WebcamLR · aiutante del microfono (P20).
// Un LaunchDaemon minuscolo (/Library/LaunchDaemons/it.lrapps.webcamlr.microfono.plist) che fa una cosa sola:
// crea la memoria condivisa dell'audio e la consegna, con XPC, a chi la chiede sul servizio Mach
// «it.lrapps.webcamlr.microfono»: l'app WebcamLR (che scrive) e il driver dentro coreaudiod (che legge).
// L'audio non passa da qui: dopo la consegna l'app e il driver lavorano direttamente sulla stessa memoria.
//
// Perché serve: il driver vive nel sandbox di coreaudiod, che non legge file fuori dal bundle e non apre
// memorie POSIX altrui; può solo cercare i servizi Mach scritti nel suo Info.plist. L'app è nel sandbox
// delle app e non può pubblicare un servizio visibile a coreaudiod. Un LaunchDaemon sì.
// Dettagli in Documenti/Microfono Mac.md.

#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xpc/xpc.h>

#include "../Comune/AnelloMicrofono.h"

static void *regione = NULL;
static size_t dimensione = 0;

/// Ogni messaggio riceve la stessa memoria. Il contenuto della richiesta non conta (per ora «memoria»).
static void rispondi(xpc_connection_t collegamento, xpc_object_t messaggio) {
    xpc_object_t risposta = xpc_dictionary_create_reply(messaggio);
    if (risposta == NULL) return;
    xpc_object_t memoria = xpc_shmem_create(regione, dimensione);
    if (memoria != NULL) {
        xpc_dictionary_set_value(risposta, "memoria", memoria);
        xpc_release(memoria);
    }
    xpc_dictionary_set_uint64(risposta, "versione", MICROFONO_VERSIONE);
    xpc_connection_send_message(collegamento, risposta);
    xpc_release(risposta);
}

static void nuovoCollegamento(xpc_connection_t collegamento) {
    xpc_connection_set_event_handler(collegamento, ^(xpc_object_t evento) {
        if (xpc_get_type(evento) == XPC_TYPE_DICTIONARY) {
            rispondi(collegamento, evento);
        }
        // Gli errori (chi chiede se ne va) non richiedono nulla: XPC chiude da solo.
    });
    xpc_connection_resume(collegamento);
}

int main(void) {
    // Pagine intere, condivise e anonime: così xpc_shmem_create le può passare agli altri processi
    // e le scritture dell'app si vedono subito nel driver.
    size_t pagina = (size_t)sysconf(_SC_PAGESIZE);
    dimensione = (sizeof(AnelloMicrofono) + pagina - 1) / pagina * pagina;
    regione = mmap(NULL, dimensione, PROT_READ | PROT_WRITE, MAP_ANON | MAP_SHARED, -1, 0);
    if (regione == MAP_FAILED) {
        fprintf(stderr, "webcamlr-microfono-aiuto: memoria non disponibile\n");
        return 1;
    }
    anello_prepara((AnelloMicrofono *)regione);

    xpc_connection_t ascolto = xpc_connection_create_mach_service(
        MICROFONO_SERVIZIO, dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (ascolto == NULL) {
        fprintf(stderr, "webcamlr-microfono-aiuto: servizio Mach non disponibile\n");
        return 1;
    }
    xpc_connection_set_event_handler(ascolto, ^(xpc_object_t evento) {
        if (xpc_get_type(evento) == XPC_TYPE_CONNECTION) {
            nuovoCollegamento((xpc_connection_t)evento);
        }
    });
    xpc_connection_resume(ascolto);
    dispatch_main();
}
