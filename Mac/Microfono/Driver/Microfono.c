// WebcamLR · «WebcamLR (microfono)», il microfono virtuale del Mac (P20).
//
// Un Audio Server Plug-in (driver HAL) caricato da coreaudiod da /Library/Audio/Plug-Ins/HAL.
// Scritto da noi in C sulla struttura dell'esempio Apple «NullAudio» (Creating an Audio Server Driver
// Plug-in): un plug-in, un dispositivo, un flusso d'ingresso. Nessun codice di BlackHole (GPL).
//
// Il dispositivo: un solo flusso d'ingresso, 48 kHz, mono, Float32. È anche la propria sorgente
// di orologio: il tempo del dispositivo è il tempo di sistema (mach_absolute_time) contato in campioni.
// L'audio arriva dall'app WebcamLR attraverso una memoria condivisa (AnelloMicrofono.h) che il driver
// chiede all'aiutante con XPC: il servizio è scritto nell'Info.plist (AudioServerPlugIn_MachServices),
// altrimenti il sandbox di coreaudiod non lo lascerebbe cercare.
//
// Oggetti: 1 = plug-in (kAudioObjectPlugInObject), 2 = dispositivo, 3 = flusso d'ingresso.

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <xpc/xpc.h>

#include "../Comune/AnelloMicrofono.h"

// MARK: - Costanti

enum {
    oggettoPlugIn = kAudioObjectPlugInObject,
    oggettoDispositivo = 2,
    oggettoFlusso = 3,
};

#define NOME_DISPOSITIVO CFSTR("WebcamLR (microfono)")
#define PRODUTTORE CFSTR("WebcamLR")
#define UID_DISPOSITIVO CFSTR(MICROFONO_UID_DISPOSITIVO)
#define UID_MODELLO CFSTR("it.lrapps.webcamlr.microfono.modello")
#define IDENTIFICATIVO_BUNDLE CFSTR("it.lrapps.webcamlr.mac.microfono")

/// Ogni quanti campioni il dispositivo dà a coreaudiod un nuovo punto d'appoggio dell'orologio.
#define PERIODO_OROLOGIO 16384u
/// Latenza e margine di sicurezza dichiarati (campioni). Il ritardo vero lo decide l'app.
#define LATENZA_DISPOSITIVO 0u
#define MARGINE_SICUREZZA 0u
/// Campioni per arrivare a zero o a pieno volume quando l'audio manca o torna: niente clic.
#define PASSI_DISSOLVENZA 64.0f

// MARK: - Stato

static pthread_mutex_t blocco = PTHREAD_MUTEX_INITIALIZER;
static AudioServerPlugInHostRef ospite = NULL;
static UInt32 contatoreRiferimenti = 0;

/// Clienti con StartIO in corso. Sotto `blocco`.
static UInt32 clientiAttivi = 0;
/// Orologio: tempo di sistema dell'avvio e numero di periodi passati. Sotto `blocco` (e letti solo da GetZeroTimeStamp).
static UInt64 tempoAncora = 0;
static UInt64 periodiPassati = 0;
static Float64 tickPerCampione = 0;
/// L'indice della linea del tempo comune che corrisponde al campione 0 del dispositivo (dopo StartIO).
/// Scritto sotto `blocco` in StartIO, letto dal ciclo dell'audio.
static _Atomic uint64_t indiceAncora = 0;

/// La memoria condivisa. Il ciclo dell'audio legge solo il puntatore atomico.
static _Atomic(AnelloMicrofono *) anello = NULL;
static size_t dimensioneAnello = 0;
static xpc_connection_t collegamento = NULL;
static _Atomic bool daRifare = false;

/// Dissolvenza del ciclo dell'audio (un solo thread di IO alla volta per questo dispositivo).
static float guadagno = 0.0f;
static float ultimoCampione = 0.0f;

static mach_timebase_info_data_t basetempi;

// MARK: - Memoria condivisa

/// Protegge il collegamento con l'aiutante (mai preso dal ciclo dell'audio).
static pthread_mutex_t bloccoMemoria = PTHREAD_MUTEX_INITIALIZER;
/// Cresce a ogni collegamento nuovo: l'errore di un collegamento già chiuso non conta.
static uint64_t generazione = 0;

static void collegaAnello(void);

/// Collegamento caduto (aiutante ripartito o assente): se qualcuno sta usando il microfono si riprova
/// fra 2 secondi, su una coda qualsiasi, fuori dal ciclo dell'audio.
static void collegamentoCaduto(uint64_t diQuale) {
    pthread_mutex_lock(&bloccoMemoria);
    bool attuale = diQuale == generazione;
    if (attuale) atomic_store(&daRifare, true);
    pthread_mutex_unlock(&bloccoMemoria);
    if (!attuale) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        pthread_mutex_lock(&blocco);
        bool inUso = clientiAttivi > 0;
        pthread_mutex_unlock(&blocco);
        if (inUso) collegaAnello();
    });
}

/// Fuori dal ciclo dell'audio (StartIO, o il nuovo tentativo qui sopra): chiede la memoria all'aiutante,
/// se manca o se l'aiutante è ripartito. La memoria vecchia non si lascia mai: il ciclo dell'audio potrebbe
/// leggerla ancora, e sono 128 KB (un aiutante ripartito capita di rado).
static void collegaAnello(void) {
    pthread_mutex_lock(&bloccoMemoria);
    if (atomic_load(&daRifare)) {
        if (collegamento != NULL) {
            // Prima si cambia generazione: l'errore che arriva dalla chiusura qui sotto non conta.
            ++generazione;
            xpc_connection_cancel(collegamento);
            xpc_release(collegamento);
            collegamento = NULL;
        }
        atomic_store(&daRifare, false);
        // Il ciclo dell'audio continua con la memoria vecchia finché non arriva quella nuova.
        dimensioneAnello = 0;
    } else if (atomic_load(&anello) != NULL && dimensioneAnello > 0) {
        pthread_mutex_unlock(&bloccoMemoria);
        return;
    }

    if (collegamento == NULL) {
        collegamento = xpc_connection_create_mach_service(MICROFONO_SERVIZIO, NULL, 0);
        if (collegamento == NULL) {
            pthread_mutex_unlock(&bloccoMemoria);
            return;
        }
        uint64_t questo = ++generazione;
        xpc_connection_set_event_handler(collegamento, ^(xpc_object_t evento) {
            if (xpc_get_type(evento) == XPC_TYPE_ERROR) collegamentoCaduto(questo);
        });
        xpc_connection_resume(collegamento);
    }
    xpc_object_t richiesta = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(richiesta, "richiesta", "memoria");
    xpc_object_t risposta = xpc_connection_send_message_with_reply_sync(collegamento, richiesta);
    xpc_release(richiesta);
    if (xpc_get_type(risposta) == XPC_TYPE_DICTIONARY) {
        xpc_object_t memoria = xpc_dictionary_get_value(risposta, "memoria");
        if (memoria != NULL) {
            void *indirizzo = NULL;
            size_t dimensione = xpc_shmem_map(memoria, &indirizzo);
            if (indirizzo != NULL && dimensione >= sizeof(AnelloMicrofono) && anello_valido((AnelloMicrofono *)indirizzo)) {
                dimensioneAnello = dimensione;
                atomic_store_explicit(&anello, (AnelloMicrofono *)indirizzo, memory_order_release);
            } else if (indirizzo != NULL) {
                munmap(indirizzo, dimensione);
            }
        }
    }
    // Se l'aiutante non c'è, la risposta è un errore e il gestore qui sopra prepara un nuovo tentativo.
    xpc_release(risposta);
    pthread_mutex_unlock(&bloccoMemoria);
}

static uint64_t microsecondiDaTick(uint64_t tick) {
    // tick × numer / denom = nanosecondi; diviso in due per non traboccare.
    uint64_t nanosecondi = tick / basetempi.denom * basetempi.numer
        + tick % basetempi.denom * basetempi.numer / basetempi.denom;
    return nanosecondi / 1000u;
}

// MARK: - Interfaccia del driver (dichiarazioni)

static HRESULT QueryInterface(void *driver, REFIID uuid, LPVOID *interfaccia);
static ULONG AddRef(void *driver);
static ULONG Release(void *driver);
static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host);
static OSStatus CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef descrizione, const AudioServerPlugInClientInfo *cliente, AudioObjectID *dispositivo);
static OSStatus DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo);
static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, const AudioServerPlugInClientInfo *cliente);
static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, const AudioServerPlugInClientInfo *cliente);
static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt64 azione, void *informazioni);
static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt64 azione, void *informazioni);
static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo);
static OSStatus IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, Boolean *modificabile);
static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, UInt32 dimensioneQualificatore, const void *qualificatore, UInt32 *dimensione);
static OSStatus GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, UInt32 dimensioneQualificatore, const void *qualificatore, UInt32 dimensioneDati, UInt32 *dimensioneScritta, void *dati);
static OSStatus SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, UInt32 dimensioneQualificatore, const void *qualificatore, UInt32 dimensioneDati, const void *dati);
static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente);
static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente);
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, Float64 *tempoCampione, UInt64 *tempoSistema, UInt64 *seme);
static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, UInt32 operazione, Boolean *loFara, Boolean *alPosto);
static OSStatus BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, UInt32 operazione, UInt32 campioni, const AudioServerPlugInIOCycleInfo *ciclo);
static OSStatus DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, AudioObjectID flusso, UInt32 cliente, UInt32 operazione, UInt32 campioni, const AudioServerPlugInIOCycleInfo *ciclo, void *bufferPrincipale, void *bufferSecondario);
static OSStatus EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, UInt32 operazione, UInt32 campioni, const AudioServerPlugInIOCycleInfo *ciclo);

static AudioServerPlugInDriverInterface interfaccia = {
    NULL,
    QueryInterface,
    AddRef,
    Release,
    Initialize,
    CreateDevice,
    DestroyDevice,
    AddDeviceClient,
    RemoveDeviceClient,
    PerformDeviceConfigurationChange,
    AbortDeviceConfigurationChange,
    HasProperty,
    IsPropertySettable,
    GetPropertyDataSize,
    GetPropertyData,
    SetPropertyData,
    StartIO,
    StopIO,
    GetZeroTimeStamp,
    WillDoIOOperation,
    BeginIOOperation,
    DoIOOperation,
    EndIOOperation,
};
static AudioServerPlugInDriverInterface *puntatoreInterfaccia = &interfaccia;
static AudioServerPlugInDriverRef riferimentoDriver = &puntatoreInterfaccia;

// MARK: - Fabbrica (CFPlugInFactories nell'Info.plist)

__attribute__((visibility("default"))) void *WebcamLRMicrofono_Crea(CFAllocatorRef allocatore, CFUUIDRef tipo);

void *WebcamLRMicrofono_Crea(CFAllocatorRef allocatore, CFUUIDRef tipo) {
    (void)allocatore;
    if (!CFEqual(tipo, kAudioServerPlugInTypeUUID)) return NULL;
    return riferimentoDriver;
}

// MARK: - IUnknown

static HRESULT QueryInterface(void *driver, REFIID uuid, LPVOID *uscita) {
    if (driver != riferimentoDriver || uscita == NULL) return kAudioHardwareBadObjectError;
    CFUUIDRef richiesto = CFUUIDCreateFromUUIDBytes(NULL, uuid);
    if (richiesto == NULL) return kAudioHardwareIllegalOperationError;
    HRESULT esito = E_NOINTERFACE;
    if (CFEqual(richiesto, IUnknownUUID) || CFEqual(richiesto, kAudioServerPlugInDriverInterfaceUUID)) {
        pthread_mutex_lock(&blocco);
        ++contatoreRiferimenti;
        pthread_mutex_unlock(&blocco);
        *uscita = riferimentoDriver;
        esito = S_OK;
    }
    CFRelease(richiesto);
    return esito;
}

static ULONG AddRef(void *driver) {
    if (driver != riferimentoDriver) return 0;
    pthread_mutex_lock(&blocco);
    if (contatoreRiferimenti < UINT32_MAX) ++contatoreRiferimenti;
    ULONG valore = contatoreRiferimenti;
    pthread_mutex_unlock(&blocco);
    return valore;
}

static ULONG Release(void *driver) {
    if (driver != riferimentoDriver) return 0;
    pthread_mutex_lock(&blocco);
    if (contatoreRiferimenti > 0) --contatoreRiferimenti;
    ULONG valore = contatoreRiferimenti;
    pthread_mutex_unlock(&blocco);
    // Il driver è statico: non c'è niente da liberare.
    return valore;
}

// MARK: - Ciclo di vita

static OSStatus Initialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    ospite = host;
    mach_timebase_info(&basetempi);
    if (basetempi.denom == 0) {
        basetempi.numer = 1;
        basetempi.denom = 1;
    }
    // Tick del tempo di sistema in un secondo, poi per campione.
    Float64 tickAlSecondo = 1.0e9 * (Float64)basetempi.denom / (Float64)basetempi.numer;
    tickPerCampione = tickAlSecondo / (Float64)MICROFONO_FREQUENZA;
    // La memoria si chiede al primo StartIO: qui l'aiutante potrebbe non essere ancora pronto.
    return kAudioHardwareNoError;
}

static OSStatus CreateDevice(AudioServerPlugInDriverRef driver, CFDictionaryRef descrizione, const AudioServerPlugInClientInfo *cliente, AudioObjectID *dispositivo) {
    (void)driver; (void)descrizione; (void)cliente; (void)dispositivo;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus DestroyDevice(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo) {
    (void)driver; (void)dispositivo;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus AddDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, const AudioServerPlugInClientInfo *cliente) {
    (void)cliente;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    return kAudioHardwareNoError;
}

static OSStatus RemoveDeviceClient(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, const AudioServerPlugInClientInfo *cliente) {
    (void)cliente;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    return kAudioHardwareNoError;
}

static OSStatus PerformDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt64 azione, void *informazioni) {
    (void)azione; (void)informazioni;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    // Il formato è uno solo: non ci sono cambiamenti da fare.
    return kAudioHardwareNoError;
}

static OSStatus AbortDeviceConfigurationChange(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt64 azione, void *informazioni) {
    (void)azione; (void)informazioni;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    return kAudioHardwareNoError;
}

// MARK: - Formato

static AudioStreamBasicDescription formatoFlusso(void) {
    AudioStreamBasicDescription formato;
    memset(&formato, 0, sizeof(formato));
    formato.mSampleRate = (Float64)MICROFONO_FREQUENZA;
    formato.mFormatID = kAudioFormatLinearPCM;
    formato.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
    formato.mBytesPerPacket = sizeof(Float32);
    formato.mFramesPerPacket = 1;
    formato.mBytesPerFrame = sizeof(Float32);
    formato.mChannelsPerFrame = 1;
    formato.mBitsPerChannel = 32;
    return formato;
}

// MARK: - Proprietà

/// Copia `valore` in `dati` se c'è posto; altrimenti kAudioHardwareBadPropertySizeError.
#define SCRIVI(tipo, valore) \
    do { \
        if (dimensioneDati < sizeof(tipo)) return kAudioHardwareBadPropertySizeError; \
        *((tipo *)dati) = (valore); \
        *dimensioneScritta = sizeof(tipo); \
        return kAudioHardwareNoError; \
    } while (0)

static Boolean HasProperty(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo) {
    (void)processo;
    if (driver != riferimentoDriver || indirizzo == NULL) return false;
    switch (oggetto) {
    case oggettoPlugIn:
        switch (indirizzo->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyBundleID:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyResourceBundle:
            return true;
        default:
            return false;
        }
    case oggettoDispositivo:
        switch (indirizzo->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyStreams:
        case kAudioDevicePropertyClockIsStable:
            return true;
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
            return indirizzo->mScope == kAudioObjectPropertyScopeInput
                || indirizzo->mScope == kAudioObjectPropertyScopeGlobal;
        default:
            return false;
        }
    case oggettoFlusso:
        switch (indirizzo->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            return true;
        default:
            return false;
        }
    default:
        return false;
    }
}

static OSStatus IsPropertySettable(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, Boolean *modificabile) {
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (indirizzo == NULL || modificabile == NULL) return kAudioHardwareIllegalOperationError;
    if (!HasProperty(driver, oggetto, processo, indirizzo)) return kAudioHardwareUnknownPropertyError;
    // Il formato è uno solo e la frequenza anche: le app possono «impostarli» allo stesso valore.
    switch (indirizzo->mSelector) {
    case kAudioDevicePropertyNominalSampleRate:
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        *modificabile = true;
        break;
    default:
        *modificabile = false;
        break;
    }
    return kAudioHardwareNoError;
}

static OSStatus GetPropertyDataSize(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, UInt32 dimensioneQualificatore, const void *qualificatore, UInt32 *dimensione) {
    (void)dimensioneQualificatore; (void)qualificatore;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (indirizzo == NULL || dimensione == NULL) return kAudioHardwareIllegalOperationError;
    if (!HasProperty(driver, oggetto, processo, indirizzo)) return kAudioHardwareUnknownPropertyError;
    bool ingressoOGlobale = indirizzo->mScope == kAudioObjectPropertyScopeInput
        || indirizzo->mScope == kAudioObjectPropertyScopeGlobal;

    switch (indirizzo->mSelector) {
    case kAudioObjectPropertyBaseClass:
    case kAudioObjectPropertyClass:
        *dimensione = sizeof(AudioClassID);
        return kAudioHardwareNoError;
    case kAudioObjectPropertyOwner:
        *dimensione = sizeof(AudioObjectID);
        return kAudioHardwareNoError;
    case kAudioObjectPropertyName:
    case kAudioObjectPropertyManufacturer:
    case kAudioPlugInPropertyBundleID:
    case kAudioPlugInPropertyResourceBundle:
    case kAudioDevicePropertyDeviceUID:
    case kAudioDevicePropertyModelUID:
        *dimensione = sizeof(CFStringRef);
        return kAudioHardwareNoError;
    case kAudioObjectPropertyOwnedObjects:
        if (oggetto == oggettoPlugIn) *dimensione = sizeof(AudioObjectID);
        else if (oggetto == oggettoDispositivo) *dimensione = ingressoOGlobale ? sizeof(AudioObjectID) : 0;
        else *dimensione = 0;
        return kAudioHardwareNoError;
    case kAudioPlugInPropertyDeviceList:
        *dimensione = sizeof(AudioObjectID);
        return kAudioHardwareNoError;
    case kAudioPlugInPropertyTranslateUIDToDevice:
        *dimensione = sizeof(AudioObjectID);
        return kAudioHardwareNoError;
    case kAudioDevicePropertyRelatedDevices:
        *dimensione = sizeof(AudioObjectID);
        return kAudioHardwareNoError;
    case kAudioDevicePropertyStreams:
        *dimensione = ingressoOGlobale ? sizeof(AudioObjectID) : 0;
        return kAudioHardwareNoError;
    case kAudioObjectPropertyControlList:
        *dimensione = 0;
        return kAudioHardwareNoError;
    case kAudioDevicePropertyNominalSampleRate:
        *dimensione = sizeof(Float64);
        return kAudioHardwareNoError;
    case kAudioDevicePropertyAvailableNominalSampleRates:
        *dimensione = sizeof(AudioValueRange);
        return kAudioHardwareNoError;
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        *dimensione = sizeof(AudioStreamBasicDescription);
        return kAudioHardwareNoError;
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats:
        *dimensione = sizeof(AudioStreamRangedDescription);
        return kAudioHardwareNoError;
    default:
        // Tutte le altre sono un UInt32.
        *dimensione = sizeof(UInt32);
        return kAudioHardwareNoError;
    }
}

static OSStatus GetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, UInt32 dimensioneQualificatore, const void *qualificatore, UInt32 dimensioneDati, UInt32 *dimensioneScritta, void *dati) {
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (indirizzo == NULL || dimensioneScritta == NULL || dati == NULL) return kAudioHardwareIllegalOperationError;
    if (!HasProperty(driver, oggetto, processo, indirizzo)) return kAudioHardwareUnknownPropertyError;
    bool ingressoOGlobale = indirizzo->mScope == kAudioObjectPropertyScopeInput
        || indirizzo->mScope == kAudioObjectPropertyScopeGlobal;

    switch (oggetto) {
    case oggettoPlugIn:
        switch (indirizzo->mSelector) {
        case kAudioObjectPropertyBaseClass: SCRIVI(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: SCRIVI(AudioClassID, kAudioPlugInClassID);
        case kAudioObjectPropertyOwner: SCRIVI(AudioObjectID, kAudioObjectUnknown);
        case kAudioObjectPropertyManufacturer: SCRIVI(CFStringRef, PRODUTTORE);
        case kAudioPlugInPropertyBundleID: SCRIVI(CFStringRef, IDENTIFICATIVO_BUNDLE);
        case kAudioPlugInPropertyResourceBundle: SCRIVI(CFStringRef, CFSTR(""));
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            if (dimensioneDati < sizeof(AudioObjectID)) {
                *dimensioneScritta = 0;
                return kAudioHardwareNoError;
            }
            SCRIVI(AudioObjectID, oggettoDispositivo);
        case kAudioPlugInPropertyTranslateUIDToDevice: {
            AudioObjectID trovato = kAudioObjectUnknown;
            if (dimensioneQualificatore == sizeof(CFStringRef) && qualificatore != NULL) {
                CFStringRef uid = *((const CFStringRef *)qualificatore);
                if (uid != NULL && CFStringCompare(uid, UID_DISPOSITIVO, 0) == kCFCompareEqualTo) trovato = oggettoDispositivo;
            }
            SCRIVI(AudioObjectID, trovato);
        }
        default:
            return kAudioHardwareUnknownPropertyError;
        }

    case oggettoDispositivo:
        switch (indirizzo->mSelector) {
        case kAudioObjectPropertyBaseClass: SCRIVI(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: SCRIVI(AudioClassID, kAudioDeviceClassID);
        case kAudioObjectPropertyOwner: SCRIVI(AudioObjectID, oggettoPlugIn);
        case kAudioObjectPropertyName: SCRIVI(CFStringRef, NOME_DISPOSITIVO);
        case kAudioObjectPropertyManufacturer: SCRIVI(CFStringRef, PRODUTTORE);
        case kAudioDevicePropertyDeviceUID: SCRIVI(CFStringRef, UID_DISPOSITIVO);
        case kAudioDevicePropertyModelUID: SCRIVI(CFStringRef, UID_MODELLO);
        case kAudioDevicePropertyTransportType: SCRIVI(UInt32, kAudioDeviceTransportTypeVirtual);
        case kAudioDevicePropertyRelatedDevices: SCRIVI(AudioObjectID, oggettoDispositivo);
        case kAudioDevicePropertyClockDomain: SCRIVI(UInt32, 0);
        case kAudioDevicePropertyDeviceIsAlive: SCRIVI(UInt32, 1);
        case kAudioDevicePropertyDeviceIsRunning: {
            pthread_mutex_lock(&blocco);
            UInt32 inCorso = clientiAttivi > 0 ? 1 : 0;
            pthread_mutex_unlock(&blocco);
            SCRIVI(UInt32, inCorso);
        }
        // Un microfono che si può scegliere come predefinito; mai come uscita degli avvisi.
        case kAudioDevicePropertyDeviceCanBeDefaultDevice: SCRIVI(UInt32, 1);
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice: SCRIVI(UInt32, 0);
        case kAudioDevicePropertyLatency: SCRIVI(UInt32, LATENZA_DISPOSITIVO);
        case kAudioDevicePropertySafetyOffset: SCRIVI(UInt32, MARGINE_SICUREZZA);
        case kAudioDevicePropertyIsHidden: SCRIVI(UInt32, 0);
        case kAudioDevicePropertyClockIsStable: SCRIVI(UInt32, 1);
        case kAudioDevicePropertyZeroTimeStampPeriod: SCRIVI(UInt32, PERIODO_OROLOGIO);
        case kAudioDevicePropertyNominalSampleRate: SCRIVI(Float64, (Float64)MICROFONO_FREQUENZA);
        case kAudioDevicePropertyAvailableNominalSampleRates: {
            AudioValueRange intervallo;
            intervallo.mMinimum = (Float64)MICROFONO_FREQUENZA;
            intervallo.mMaximum = (Float64)MICROFONO_FREQUENZA;
            SCRIVI(AudioValueRange, intervallo);
        }
        case kAudioObjectPropertyOwnedObjects:
        case kAudioDevicePropertyStreams:
            if (!ingressoOGlobale || dimensioneDati < sizeof(AudioObjectID)) {
                *dimensioneScritta = 0;
                return kAudioHardwareNoError;
            }
            SCRIVI(AudioObjectID, oggettoFlusso);
        case kAudioObjectPropertyControlList:
            *dimensioneScritta = 0;
            return kAudioHardwareNoError;
        default:
            return kAudioHardwareUnknownPropertyError;
        }

    case oggettoFlusso:
        switch (indirizzo->mSelector) {
        case kAudioObjectPropertyBaseClass: SCRIVI(AudioClassID, kAudioObjectClassID);
        case kAudioObjectPropertyClass: SCRIVI(AudioClassID, kAudioStreamClassID);
        case kAudioObjectPropertyOwner: SCRIVI(AudioObjectID, oggettoDispositivo);
        case kAudioObjectPropertyOwnedObjects:
            *dimensioneScritta = 0;
            return kAudioHardwareNoError;
        case kAudioStreamPropertyIsActive: SCRIVI(UInt32, 1);
        // 1 = ingresso.
        case kAudioStreamPropertyDirection: SCRIVI(UInt32, 1);
        case kAudioStreamPropertyTerminalType: SCRIVI(UInt32, kAudioStreamTerminalTypeMicrophone);
        case kAudioStreamPropertyStartingChannel: SCRIVI(UInt32, 1);
        case kAudioStreamPropertyLatency: SCRIVI(UInt32, 0);
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            SCRIVI(AudioStreamBasicDescription, formatoFlusso());
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription disponibile;
            memset(&disponibile, 0, sizeof(disponibile));
            disponibile.mFormat = formatoFlusso();
            disponibile.mSampleRateRange.mMinimum = (Float64)MICROFONO_FREQUENZA;
            disponibile.mSampleRateRange.mMaximum = (Float64)MICROFONO_FREQUENZA;
            SCRIVI(AudioStreamRangedDescription, disponibile);
        }
        default:
            return kAudioHardwareUnknownPropertyError;
        }

    default:
        return kAudioHardwareBadObjectError;
    }
}

static OSStatus SetPropertyData(AudioServerPlugInDriverRef driver, AudioObjectID oggetto, pid_t processo, const AudioObjectPropertyAddress *indirizzo, UInt32 dimensioneQualificatore, const void *qualificatore, UInt32 dimensioneDati, const void *dati) {
    (void)dimensioneQualificatore; (void)qualificatore;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (indirizzo == NULL || dati == NULL) return kAudioHardwareIllegalOperationError;
    if (!HasProperty(driver, oggetto, processo, indirizzo)) return kAudioHardwareUnknownPropertyError;
    switch (indirizzo->mSelector) {
    case kAudioDevicePropertyNominalSampleRate:
        if (dimensioneDati < sizeof(Float64)) return kAudioHardwareBadPropertySizeError;
        // Solo 48 kHz: lo stesso valore va bene, un altro no.
        return *((const Float64 *)dati) == (Float64)MICROFONO_FREQUENZA
            ? kAudioHardwareNoError : kAudioHardwareIllegalOperationError;
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat: {
        if (dimensioneDati < sizeof(AudioStreamBasicDescription)) return kAudioHardwareBadPropertySizeError;
        const AudioStreamBasicDescription *chiesto = (const AudioStreamBasicDescription *)dati;
        AudioStreamBasicDescription nostro = formatoFlusso();
        bool uguale = chiesto->mSampleRate == nostro.mSampleRate && chiesto->mFormatID == nostro.mFormatID
            && chiesto->mChannelsPerFrame == nostro.mChannelsPerFrame && chiesto->mBitsPerChannel == nostro.mBitsPerChannel;
        return uguale ? kAudioHardwareNoError : kAudioDeviceUnsupportedFormatError;
    }
    default:
        return kAudioHardwareUnknownPropertyError;
    }
}

// MARK: - IO

static OSStatus StartIO(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente) {
    (void)cliente;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    // La memoria prima di tutto, fuori da `blocco`: la richiesta all'aiutante può durare qualche millisecondo.
    collegaAnello();
    pthread_mutex_lock(&blocco);
    if (clientiAttivi == 0) {
        // Primo cliente: il punto d'appoggio dell'orologio.
        tempoAncora = mach_absolute_time();
        periodiPassati = 0;
        atomic_store(&indiceAncora, anello_indice_da_microsecondi(microsecondiDaTick(tempoAncora)));
        guadagno = 0.0f;
        ultimoCampione = 0.0f;
    }
    ++clientiAttivi;
    pthread_mutex_unlock(&blocco);
    if (ospite != NULL) {
        AudioObjectPropertyAddress inCorso = { kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        ospite->PropertiesChanged(ospite, oggettoDispositivo, 1, &inCorso);
    }
    return kAudioHardwareNoError;
}

static OSStatus StopIO(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente) {
    (void)cliente;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&blocco);
    if (clientiAttivi > 0) --clientiAttivi;
    pthread_mutex_unlock(&blocco);
    if (ospite != NULL) {
        AudioObjectPropertyAddress inCorso = { kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        ospite->PropertiesChanged(ospite, oggettoDispositivo, 1, &inCorso);
    }
    return kAudioHardwareNoError;
}

/// Come in NullAudio: un nuovo punto d'appoggio ogni PERIODO_OROLOGIO campioni, sul tempo di sistema.
/// Il dispositivo va esattamente alla velocità del tempo di sistema: è il suo orologio.
static OSStatus GetZeroTimeStamp(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, Float64 *tempoCampione, UInt64 *tempoSistema, UInt64 *seme) {
    (void)cliente;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    pthread_mutex_lock(&blocco);
    UInt64 adesso = mach_absolute_time();
    Float64 tickPerPeriodo = tickPerCampione * (Float64)PERIODO_OROLOGIO;
    UInt64 prossimo = tempoAncora + (UInt64)((Float64)(periodiPassati + 1) * tickPerPeriodo);
    if (prossimo <= adesso) ++periodiPassati;
    *tempoCampione = (Float64)(periodiPassati * PERIODO_OROLOGIO);
    *tempoSistema = tempoAncora + (UInt64)((Float64)periodiPassati * tickPerPeriodo);
    *seme = 1;
    pthread_mutex_unlock(&blocco);
    return kAudioHardwareNoError;
}

static OSStatus WillDoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, UInt32 operazione, Boolean *loFara, Boolean *alPosto) {
    (void)cliente;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    if (loFara == NULL || alPosto == NULL) return kAudioHardwareIllegalOperationError;
    *loFara = operazione == kAudioServerPlugInIOOperationReadInput;
    *alPosto = true;
    return kAudioHardwareNoError;
}

static OSStatus BeginIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, UInt32 operazione, UInt32 campioni, const AudioServerPlugInIOCycleInfo *ciclo) {
    (void)cliente; (void)operazione; (void)campioni; (void)ciclo;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    return kAudioHardwareNoError;
}

/// Sul thread dell'audio in tempo reale: niente blocchi, niente memoria nuova, niente XPC.
/// Legge dalla linea del tempo comune il tratto che corrisponde a questo ciclo; dove l'app non ha scritto
/// (telefono spento, buco di rete) esce silenzio, con una breve dissolvenza in chiusura e in apertura.
static OSStatus DoIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, AudioObjectID flusso, UInt32 cliente, UInt32 operazione, UInt32 campioni, const AudioServerPlugInIOCycleInfo *ciclo, void *bufferPrincipale, void *bufferSecondario) {
    (void)cliente; (void)bufferSecondario;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo || flusso != oggettoFlusso) return kAudioHardwareBadObjectError;
    if (operazione != kAudioServerPlugInIOOperationReadInput || bufferPrincipale == NULL || ciclo == NULL) return kAudioHardwareNoError;

    Float32 *uscita = (Float32 *)bufferPrincipale;
    AnelloMicrofono *memoria = atomic_load_explicit(&anello, memory_order_acquire);
    uint64_t fine = 0;
    uint64_t inizio = 0;
    if (memoria != NULL) {
        fine = atomic_load_explicit(&memoria->fine, memory_order_acquire);
        inizio = fine > MICROFONO_CAPACITA ? fine - MICROFONO_CAPACITA : 0;
    }
    Float64 tempo = ciclo->mInputTime.mSampleTime;
    uint64_t primo = atomic_load_explicit(&indiceAncora, memory_order_relaxed) + (tempo > 0 ? (uint64_t)tempo : 0);
    float passo = 1.0f / PASSI_DISSOLVENZA;

    for (UInt32 k = 0; k < campioni; k++) {
        uint64_t indice = primo + k;
        bool valido = memoria != NULL && indice >= inizio && indice < fine;
        if (valido) {
            ultimoCampione = memoria->campioni[indice & MICROFONO_MASCHERA];
            if (guadagno < 1.0f) guadagno = guadagno + passo > 1.0f ? 1.0f : guadagno + passo;
        } else {
            // Si tiene l'ultimo valore e lo si porta a zero: niente scalino.
            if (guadagno > 0.0f) guadagno = guadagno - passo < 0.0f ? 0.0f : guadagno - passo;
        }
        uscita[k] = ultimoCampione * guadagno;
    }
    if (memoria != NULL) {
        atomic_store_explicit(&memoria->ultimaLettura, microsecondiDaTick(mach_absolute_time()), memory_order_relaxed);
    }
    return kAudioHardwareNoError;
}

static OSStatus EndIOOperation(AudioServerPlugInDriverRef driver, AudioObjectID dispositivo, UInt32 cliente, UInt32 operazione, UInt32 campioni, const AudioServerPlugInIOCycleInfo *ciclo) {
    (void)cliente; (void)operazione; (void)campioni; (void)ciclo;
    if (driver != riferimentoDriver) return kAudioHardwareBadObjectError;
    if (dispositivo != oggettoDispositivo) return kAudioHardwareBadObjectError;
    return kAudioHardwareNoError;
}
