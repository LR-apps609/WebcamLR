// WebcamLR · aiutante del microfono (P20).
// Un programma minuscolo con due modi, ognuno avviato dal suo LaunchDaemon:
//
// 1. Memoria (/Library/LaunchDaemons/it.lrapps.webcamlr.microfono.plist, utente «nobody»): crea la memoria
//    condivisa dell'audio e la consegna, con XPC, a chi la chiede sul servizio Mach «it.lrapps.webcamlr.microfono»:
//    l'app WebcamLR (che scrive) e il driver dentro coreaudiod (che legge). L'audio non passa da qui: dopo la
//    consegna l'app e il driver lavorano direttamente sulla stessa memoria.
// 2. Rimozione (argomento «rimozione», /Library/LaunchDaemons/it.lrapps.webcamlr.microfono.rimozione.plist, root):
//    su richiesta dell'app WebcamLR toglie driver, aiutante e i due LaunchDaemon, poi riavvia coreaudiod
//    (Impostazioni › Microfono del telefono › «Rimuovi il microfono…»). Root serve solo qui: il modo «memoria»,
//    che parla anche con coreaudiod, resta senza privilegi.
//
// Sicurezza: tutti e due i modi controllano la firma di chi si collega con
// xpc_connection_set_peer_code_signing_requirement (pubblica, macOS 12+): XPC consegna i messaggi solo
// se chi li manda soddisfa il requisito. Memoria: l'app WebcamLR con il Team ID dell'aiutante, oppure
// coreaudiod / il processo di Core Audio che ospita i driver. Rimozione: solo l'app WebcamLR.
// Gli altri vengono rifiutati e scritti nel registro di sistema (sottosistema it.lrapps.webcamlr.microfono).
//
// Perché serve un aiutante: il driver vive nel sandbox di coreaudiod, che non legge file fuori dal bundle e non
// apre memorie POSIX altrui; può solo cercare i servizi Mach scritti nel suo Info.plist. L'app è nel sandbox
// delle app e non può pubblicare un servizio visibile a coreaudiod. Un LaunchDaemon sì.
// Dettagli in Documenti/Microfono Mac.md.

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <libproc.h>
#include <os/log.h>
#include <removefile.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <xpc/xpc.h>

#include "../Comune/AnelloMicrofono.h"

// ——— Dove sta il microfono (le stesse righe di Strumenti/Installa microfono.command e Rimuovi microfono.command) ———

#define ETICHETTA_MEMORIA "it.lrapps.webcamlr.microfono"
#define ETICHETTA_RIMOZIONE "it.lrapps.webcamlr.microfono.rimozione"
#define PERCORSO_DRIVER "/Library/Audio/Plug-Ins/HAL/WebcamLR Microfono.driver"
#define CARTELLA_AIUTO "/Library/Application Support/WebcamLR"
#define PERCORSO_AIUTO CARTELLA_AIUTO "/webcamlr-microfono-aiuto"
#define PLIST_MEMORIA "/Library/LaunchDaemons/" ETICHETTA_MEMORIA ".plist"
#define PLIST_RIMOZIONE "/Library/LaunchDaemons/" ETICHETTA_RIMOZIONE ".plist"

// ——— Chi può collegarsi ———

/// coreaudiod e i processi con cui Core Audio ospita i driver di terzi (da macOS 14 un driver può girare in un
/// processo a parte, «Core Audio Driver (…)»). «anchor apple»: solo programmi firmati da Apple stessa, quindi
/// gli identificatori in più non aprono la porta a nessun altro. Se in un macOS nuovo il driver gira in un processo
/// con un altro nome, il registro dice «Rifiutato …» con il suo identificatore: va aggiunto qui.
#define REQUISITO_AUDIO \
    "anchor apple and (identifier \"com.apple.audio.coreaudiod\"" \
    " or identifier \"com.apple.audio.Core-Audio-Driver-Service\"" \
    " or identifier \"com.apple.audio.Core-Audio-Driver-Service.helper\"" \
    " or identifier \"com.apple.audio.DriverHelper\")"

static os_log_t registro;
/// Il Team ID della firma di questo programma («Apple Development» o «Developer ID»); vuoto con la firma locale («-»).
static char team[32] = "";
/// L'app WebcamLR firmata dallo stesso team. Vuoto con la firma locale.
static char requisitoApp[256] = "";
/// Chi può avere la memoria: l'app oppure Core Audio.
static char requisitoMemoria[768] = "";
/// La versione installata (CFBundleShortVersionString e CFBundleVersion dell'Info.plist dentro il programma).
static char versionePacchetto[64] = "";

/// Un CFString in un buffer C; falso se manca o non ci sta.
static bool testoDa(CFTypeRef valore, char *uscita, size_t dimensione) {
    if (valore == NULL || CFGetTypeID(valore) != CFStringGetTypeID()) return false;
    return CFStringGetCString((CFStringRef)valore, uscita, (CFIndex)dimensione, kCFStringEncodingUTF8);
}

/// Un Team ID è fatto di lettere maiuscole e cifre (10 caratteri): niente virgolette che cambino il requisito.
static bool teamValido(const char *testo) {
    size_t lunghezza = strlen(testo);
    if (lunghezza == 0 || lunghezza > 20) return false;
    for (size_t i = 0; i < lunghezza; i++) {
        char c = testo[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) return false;
    }
    return true;
}

/// Legge il Team ID dalla firma di questo stesso programma. Con «Apple Development» (anche con l'Apple ID gratuito,
/// che ha un team personale) e con «Developer ID» c'è; con la firma locale no.
static void leggiTeam(void) {
    SecCodeRef io = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &io) != errSecSuccess || io == NULL) return;
    SecStaticCodeRef statico = NULL;
    OSStatus esito = SecCodeCopyStaticCode(io, kSecCSDefaultFlags, &statico);
    CFRelease(io);
    if (esito != errSecSuccess || statico == NULL) return;
    CFDictionaryRef informazioni = NULL;
    esito = SecCodeCopySigningInformation(statico, kSecCSSigningInformation, &informazioni);
    CFRelease(statico);
    if (esito != errSecSuccess || informazioni == NULL) return;
    char letto[sizeof(team)] = "";
    if (testoDa(CFDictionaryGetValue(informazioni, kSecCodeInfoTeamIdentifier), letto, sizeof(letto)) && teamValido(letto)) {
        strlcpy(team, letto, sizeof(team));
    }
    CFRelease(informazioni);
}

static void leggiVersione(void) {
    CFBundleRef bundle = CFBundleGetMainBundle();
    if (bundle == NULL) return;
    char breve[32] = "", build[32] = "";
    testoDa(CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("CFBundleShortVersionString")), breve, sizeof(breve));
    testoDa(CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("CFBundleVersion")), build, sizeof(build));
    if (breve[0] != '\0' && build[0] != '\0') {
        snprintf(versionePacchetto, sizeof(versionePacchetto), "%s (%s)", breve, build);
    } else if (breve[0] != '\0') {
        strlcpy(versionePacchetto, breve, sizeof(versionePacchetto));
    }
}

/// Un requisito scritto male rifiuterebbe tutti in silenzio: si prova a compilarlo e si scrive nel registro.
static bool requisitoValido(const char *testo) {
    CFStringRef stringa = CFStringCreateWithCString(kCFAllocatorDefault, testo, kCFStringEncodingUTF8);
    if (stringa == NULL) return false;
    SecRequirementRef requisito = NULL;
    OSStatus esito = SecRequirementCreateWithString(stringa, kSecCSDefaultFlags, &requisito);
    CFRelease(stringa);
    if (requisito != NULL) CFRelease(requisito);
    if (esito != errSecSuccess) {
        os_log_error(registro, "Requisito di firma non valido (%d): %{public}s", (int)esito, testo);
        return false;
    }
    return true;
}

static void preparaRequisiti(void) {
    leggiTeam();
    if (team[0] != '\0') {
        snprintf(requisitoApp, sizeof(requisitoApp),
                 "identifier \"" MICROFONO_ID_APP "\" and anchor apple generic and certificate leaf[subject.OU] = \"%s\"", team);
        snprintf(requisitoMemoria, sizeof(requisitoMemoria), "(%s) or (%s)", requisitoApp, REQUISITO_AUDIO);
        os_log(registro, "Team ID dell'aiutante: %{public}s", team);
    } else {
        // Firma locale («-», per esempio «Crea dmg» in modo locale): non c'è un team da confrontare. La memoria resta
        // per l'app con il nostro identificatore (controllo debole: chiunque può firmarsi così) e per Core Audio;
        // la rimozione è spenta (vedi gestisciRimozione).
        snprintf(requisitoMemoria, sizeof(requisitoMemoria), "(identifier \"" MICROFONO_ID_APP "\") or (%s)", REQUISITO_AUDIO);
        os_log_error(registro, "Aiutante con la firma locale: nessun Team ID, controllo dell'app solo sull'identificatore");
    }
    if (requisitoApp[0] != '\0') requisitoValido(requisitoApp);
    requisitoValido(requisitoMemoria);
}

/// Scrive nel registro chi è stato rifiutato: processo, percorso, identificatore e team della sua firma.
/// Il pid serve solo al registro (la decisione l'ha già presa XPC sulla firma vera del collegamento).
static void registraRifiutato(xpc_connection_t collegamento, const char *servizio) {
    pid_t pid = xpc_connection_get_pid(collegamento);
    char percorso[PROC_PIDPATHINFO_MAXSIZE] = "?";
    if (pid > 0 && proc_pidpath(pid, percorso, sizeof(percorso)) <= 0) strlcpy(percorso, "?", sizeof(percorso));
    char identificatore[256] = "?", suoTeam[32] = "-";
    CFNumberRef numero = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &pid);
    if (numero != NULL) {
        const void *chiavi[] = { kSecGuestAttributePid };
        const void *valori[] = { numero };
        CFDictionaryRef attributi = CFDictionaryCreate(kCFAllocatorDefault, chiavi, valori, 1,
                                                       &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(numero);
        SecCodeRef codice = NULL;
        if (attributi != NULL && SecCodeCopyGuestWithAttributes(NULL, attributi, kSecCSDefaultFlags, &codice) == errSecSuccess && codice != NULL) {
            CFDictionaryRef informazioni = NULL;
            if (SecCodeCopySigningInformation((SecStaticCodeRef)codice, kSecCSSigningInformation, &informazioni) == errSecSuccess
                && informazioni != NULL) {
                testoDa(CFDictionaryGetValue(informazioni, kSecCodeInfoIdentifier), identificatore, sizeof(identificatore));
                testoDa(CFDictionaryGetValue(informazioni, kSecCodeInfoTeamIdentifier), suoTeam, sizeof(suoTeam));
                CFRelease(informazioni);
            }
            CFRelease(codice);
        }
        if (attributi != NULL) CFRelease(attributi);
    }
    os_log_error(registro, "Rifiutato su %{public}s: pid %d, %{public}s, firma «%{public}s», team %{public}s",
                 servizio, (int)pid, percorso, identificatore, suoTeam);
}

/// Vero se l'errore è «chi si collega non soddisfa il requisito di firma».
static bool erroreDiFirma(xpc_object_t evento) {
#ifdef XPC_ERROR_PEER_CODE_SIGNING_REQUIREMENT
    return evento == XPC_ERROR_PEER_CODE_SIGNING_REQUIREMENT;
#else
    (void)evento;
    return false;
#endif
}

/// Mette il requisito sul collegamento nuovo (prima di resume, come chiede XPC). Se non si può mettere,
/// il collegamento si chiude: meglio nessuno che chiunque.
static bool proteggi(xpc_connection_t collegamento, const char *requisito, const char *servizio) {
    int esito = xpc_connection_set_peer_code_signing_requirement(collegamento, requisito);
    if (esito == 0) return true;
    os_log_error(registro, "Requisito di firma non applicato su %{public}s (errore %d): collegamento chiuso", servizio, esito);
    xpc_connection_set_event_handler(collegamento, ^(xpc_object_t evento) { (void)evento; });
    xpc_connection_resume(collegamento);
    xpc_connection_cancel(collegamento);
    return false;
}

// ——— Modo «memoria» ———

static void *regione = NULL;
static size_t dimensione = 0;

/// «memoria» (o una richiesta senza nome, come facevano le versioni prima): la memoria condivisa.
/// «versione»: solo le versioni, per le Impostazioni dell'app (senza consegnare la memoria).
static void rispondiMemoria(xpc_connection_t collegamento, xpc_object_t messaggio) {
    xpc_object_t risposta = xpc_dictionary_create_reply(messaggio);
    if (risposta == NULL) return;
    const char *richiesta = xpc_dictionary_get_string(messaggio, "richiesta");
    bool soloVersione = richiesta != NULL && strcmp(richiesta, "versione") == 0;
    if (!soloVersione) {
        xpc_object_t memoria = xpc_shmem_create(regione, dimensione);
        if (memoria != NULL) {
            xpc_dictionary_set_value(risposta, "memoria", memoria);
            xpc_release(memoria);
        }
    }
    xpc_dictionary_set_uint64(risposta, "versione", MICROFONO_VERSIONE);
    if (versionePacchetto[0] != '\0') xpc_dictionary_set_string(risposta, "versionePacchetto", versionePacchetto);
    xpc_connection_send_message(collegamento, risposta);
    xpc_release(risposta);
}

static void nuovoCollegamentoMemoria(xpc_connection_t collegamento) {
    if (!proteggi(collegamento, requisitoMemoria, MICROFONO_SERVIZIO)) return;
    xpc_connection_set_event_handler(collegamento, ^(xpc_object_t evento) {
        if (xpc_get_type(evento) == XPC_TYPE_DICTIONARY) {
            rispondiMemoria(collegamento, evento);
        } else if (erroreDiFirma(evento)) {
            registraRifiutato(collegamento, MICROFONO_SERVIZIO);
        }
        // Gli altri errori (chi chiede se ne va) non richiedono nulla: XPC chiude da solo.
    });
    xpc_connection_resume(collegamento);
}

static int avviaMemoria(void) {
    // Pagine intere, condivise e anonime: così xpc_shmem_create le può passare agli altri processi
    // e le scritture dell'app si vedono subito nel driver.
    size_t pagina = (size_t)sysconf(_SC_PAGESIZE);
    dimensione = (sizeof(AnelloMicrofono) + pagina - 1) / pagina * pagina;
    regione = mmap(NULL, dimensione, PROT_READ | PROT_WRITE, MAP_ANON | MAP_SHARED, -1, 0);
    if (regione == MAP_FAILED) {
        os_log_error(registro, "Memoria non disponibile");
        return 1;
    }
    anello_prepara((AnelloMicrofono *)regione);

    xpc_connection_t ascolto = xpc_connection_create_mach_service(
        MICROFONO_SERVIZIO, dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (ascolto == NULL) {
        os_log_error(registro, "Servizio Mach non disponibile");
        return 1;
    }
    xpc_connection_set_event_handler(ascolto, ^(xpc_object_t evento) {
        if (xpc_get_type(evento) == XPC_TYPE_CONNECTION) {
            nuovoCollegamentoMemoria((xpc_connection_t)evento);
        }
    });
    xpc_connection_resume(ascolto);
    dispatch_main();
}

// ——— Modo «rimozione» (root) ———

/// Avvia un programma di sistema con argomenti fissi (niente shell). Con `aspetta`, il suo codice di uscita.
static int esegui(char *const argomenti[], bool aspetta) {
    static char *const ambiente[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL };
    pid_t pid = 0;
    if (posix_spawn(&pid, argomenti[0], NULL, NULL, argomenti, ambiente) != 0) return -1;
    if (!aspetta) return 0;
    int stato = 0;
    while (waitpid(pid, &stato, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    return WIFEXITED(stato) ? WEXITSTATUS(stato) : -1;
}

/// Toglie un file o una cartella (con tutto il contenuto). Vero anche se non c'era.
static bool rimuovi(const char *percorso, char *errore, size_t dimensioneErrore) {
    struct stat informazioni;
    if (lstat(percorso, &informazioni) != 0) {
        if (errno == ENOENT) return true;
    } else if (S_ISDIR(informazioni.st_mode) ? removefile(percorso, NULL, REMOVEFILE_RECURSIVE) == 0 : unlink(percorso) == 0) {
        return true;
    }
    int codice = errno;
    os_log_error(registro, "Non riesco a togliere %{public}s: %{public}s", percorso, strerror(codice));
    if (errore[0] == '\0') snprintf(errore, dimensioneErrore, "%s: %s", percorso, strerror(codice));
    return false;
}

/// Le stesse righe di Strumenti/Rimuovi microfono.command. I percorsi sono fissi: la richiesta non ne porta.
static bool disinstalla(char *errore, size_t dimensioneErrore) {
    os_log(registro, "Disinstallo il microfono di WebcamLR");
    // L'aiutante della memoria si ferma prima (se non era caricato, va bene lo stesso).
    char *fermaMemoria[] = { "/bin/launchctl", "bootout", "system/" ETICHETTA_MEMORIA, NULL };
    esegui(fermaMemoria, true);

    bool riuscito = true;
    riuscito &= rimuovi(PERCORSO_DRIVER, errore, dimensioneErrore);
    riuscito &= rimuovi(PLIST_MEMORIA, errore, dimensioneErrore);
    riuscito &= rimuovi(PLIST_RIMOZIONE, errore, dimensioneErrore);
    // Questo stesso programma: macOS lo lascia girare anche dopo che il file non c'è più.
    riuscito &= rimuovi(PERCORSO_AIUTO, errore, dimensioneErrore);
    rmdir(CARTELLA_AIUTO);  // Solo se è vuota: se ci fosse altro, resta.

    // coreaudiod carica e scarica i driver solo all'avvio. launchd lo fa ripartire da solo.
    char *fermaAudio[] = { "/usr/bin/killall", "coreaudiod", NULL };
    if (esegui(fermaAudio, true) != 0) {
        char *riavviaAudio[] = { "/bin/launchctl", "kickstart", "-k", "system/com.apple.audio.coreaudiod", NULL };
        esegui(riavviaAudio, true);
    }
    if (riuscito) os_log(registro, "Microfono di WebcamLR disinstallato");
    return riuscito;
}

static uint64_t ultimaAttivita = 0;
static bool chiusuraProgrammata = false;

static uint64_t secondiDiSistema(void) {
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000000u;
}

static void gestisciRimozione(xpc_connection_t collegamento, xpc_object_t messaggio) {
    ultimaAttivita = secondiDiSistema();
    xpc_object_t risposta = xpc_dictionary_create_reply(messaggio);
    if (risposta == NULL) return;
    const char *richiesta = xpc_dictionary_get_string(messaggio, "richiesta");
    bool riuscito = false;
    char errore[512] = "";
    if (team[0] == '\0') {
        // Con la firma locale non si può sapere chi chiede: niente rimozione da root, resta lo script.
        strlcpy(errore, "firma-locale", sizeof(errore));
    } else if (richiesta == NULL || strcmp(richiesta, "disinstalla") != 0) {
        strlcpy(errore, "richiesta-sconosciuta", sizeof(errore));
    } else {
        os_log(registro, "Rimozione chiesta dall'app WebcamLR (pid %d)", (int)xpc_connection_get_pid(collegamento));
        riuscito = disinstalla(errore, sizeof(errore));
    }
    xpc_dictionary_set_bool(risposta, "esito", riuscito);
    if (!riuscito) xpc_dictionary_set_string(risposta, "errore", errore);
    xpc_connection_send_message(collegamento, risposta);
    xpc_release(risposta);

    if (riuscito && !chiusuraProgrammata) {
        chiusuraProgrammata = true;
        // Dopo la risposta: launchd dimentica questo servizio (il plist non c'è già più) e il programma esce.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            char *dimentica[] = { "/bin/launchctl", "bootout", "system/" ETICHETTA_RIMOZIONE, NULL };
            esegui(dimentica, false);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            exit(0);
        });
    }
}

static void nuovoCollegamentoRimozione(xpc_connection_t collegamento) {
    // Con la firma locale non c'è un requisito vero: si risponde solo «firma-locale» (gestisciRimozione).
    if (requisitoApp[0] != '\0' && !proteggi(collegamento, requisitoApp, MICROFONO_SERVIZIO_RIMOZIONE)) return;
    xpc_connection_set_event_handler(collegamento, ^(xpc_object_t evento) {
        if (xpc_get_type(evento) == XPC_TYPE_DICTIONARY) {
            gestisciRimozione(collegamento, evento);
        } else if (erroreDiFirma(evento)) {
            registraRifiutato(collegamento, MICROFONO_SERVIZIO_RIMOZIONE);
        }
    });
    xpc_connection_resume(collegamento);
}

static int avviaRimozione(void) {
    xpc_connection_t ascolto = xpc_connection_create_mach_service(
        MICROFONO_SERVIZIO_RIMOZIONE, dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (ascolto == NULL) {
        os_log_error(registro, "Servizio Mach della rimozione non disponibile");
        return 1;
    }
    ultimaAttivita = secondiDiSistema();
    xpc_connection_set_event_handler(ascolto, ^(xpc_object_t evento) {
        if (xpc_get_type(evento) == XPC_TYPE_CONNECTION) {
            ultimaAttivita = secondiDiSistema();
            nuovoCollegamentoRimozione((xpc_connection_t)evento);
        }
    });
    xpc_connection_resume(ascolto);

    // Un processo root non resta acceso per niente: dopo un minuto senza richieste esce,
    // e launchd lo riavvia alla prossima (i messaggi intanto aspettano sulla porta del servizio).
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), 30 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        if (!chiusuraProgrammata && secondiDiSistema() - ultimaAttivita >= 60) exit(0);
    });
    dispatch_resume(timer);
    dispatch_main();
}

int main(int argc, char *argv[]) {
    registro = os_log_create("it.lrapps.webcamlr.microfono", argc > 1 ? "rimozione" : "memoria");
    leggiVersione();
    preparaRequisiti();
    if (argc > 1 && strcmp(argv[1], "rimozione") == 0) return avviaRimozione();
    return avviaMemoria();
}
