# Cavo USB con Android (Qualità 17)

Punto 17 della lista qualità 1.0: «Cavo USB Android nativo, che i due concorrenti hanno. Oggi c'è solo il "Tethering USB".»
Questo documento sceglie la strada e descrive il primo giro (novembre 2026). Il protocollo è in `Documenti/Protocollo.md`,
«Cavo USB con Android: adb».

## Com'è oggi

- **iPhone** (dalla 1.6): l'iPhone ascolta su 127.0.0.1:52741; il computer arriva lì con **usbmux**, il servizio di Apple
  (socket Unix `/var/run/usbmuxd` sul Mac, TCP 127.0.0.1:27015 su Windows con «Dispositivi Apple»). Il client è nostro
  (`Mac/Sorgenti/ClienteUSB.swift`, `Windows/WebcamLR.Ricevitore/ClienteUsbmux.cs`): `Listen` per sapere quando un
  iPhone si collega, `Connect` verso la porta 52741 ogni secondo finché l'app risponde, l'attesa che raddoppia (2 → 30 s)
  quando il telefono chiude prima del `ciao`, la sospensione dopo «Scollega», la pausa per la strada scelta.
- **Android**: solo il **Tethering USB** (RNDIS o NCM). Il telefono crea una piccola rete sul cavo e WebcamLR la usa come
  il Wi-Fi (ricerca mDNS sul cavo in `Android/.../rete/RicercaCavo.kt`). Non serve la modalità sviluppatore, ma sul Mac
  funziona solo con i telefoni NCM (Pixel 6 e successivi, pochi altri), su Windows la rete nasce «Pubblica» e alcuni
  operatori o produttori nascondono il tethering.

## Le tre strade

| | **adb** (debug USB) | **AOA** (Android Open Accessory) | **Tethering USB** (NCM/RNDIS) |
|---|---|---|---|
| Cosa fa l'utente | Una volta: modalità sviluppatore (7 tocchi su «Numero build»), «Debug USB», «Consenti» sul telefono. Poi solo il cavo | Il cavo; alla prima volta Android chiede «Aprire WebcamLR per questo accessorio?» | Il cavo e l'interruttore «Tethering USB» ogni volta (alcuni telefoni lo ricordano) |
| Permessi sul telefono | Debug USB (opzioni sviluppatore) | Nessuno speciale (API `UsbAccessory`) | Nessuno |
| Sul computer | Il server di adb (adb.exe / adb) | Codice USB nostro: libusb o WinUSB su Windows, IOKit sul Mac | Niente: driver di rete del sistema |
| Driver su Windows | Interfaccia ADB: driver di Google o del produttore, o WinUSB da solo sui telefoni recenti (da verificare, vedi sotto). Nessun driver nostro da firmare | In modalità accessorio il telefono (18D1:2D00/2D01) non porta i descrittori per WinUSB: serve un pacchetto driver (INF) **firmato** da noi (attestazione Microsoft, certificato EV), oppure Zadig/libusb | RNDIS e NCM integrati in Windows 10/11 |
| Mac senza account a pagamento | Sì: client TCP verso 127.0.0.1:5037, basta `network.client` del sandbox. Avviare adb dal sandbox no | Sì in teoria (IOKit con `com.apple.security.device.usb`), ma è un trasporto USB intero da scrivere | Solo telefoni NCM |
| Licenze | Client nostro; adb è Apache 2.0 nel codice sorgente, i binari di Google sono sotto la licenza dell'Android SDK (vedi sotto) | libusb è **LGPL 2.1**, Zadig GPL: da evitare. WinUSB e IOKit sono di sistema | Niente |
| Latenza attesa | Come usbmux: un canale TCP incapsulato nel protocollo di adb su USB 2/3; qualche ms in più del Wi-Fi buono, molto più stabile | La più bassa (bulk USB diretto), ma da scrivere tutto: flussi, controllo di flusso, ripresa | Come una rete cablata |
| Lavoro | **Piccolo**: client da scrivere come quello di usbmux, il telefono ascolta come l'iPhone | **Grande**: trasporto USB su due sistemi, driver firmato su Windows | Già fatto |
| Chi lo usa | DroidCam, Iriun, scrcpy | Pochi (accessori hardware) | — |

**Scelta: adb**, accanto al Tethering USB che resta (non chiede la modalità sviluppatore). Perché:

1. È la strada dei concorrenti (DroidCam e Iriun chiedono il debug USB), quindi gli utenti Android che cercano «USB» la
   conoscono già, e chi ha Android Studio o scrcpy ha già tutto.
2. Riusa per intero il cavo dell'iPhone: il telefono ascolta su 127.0.0.1:52741 come l'iPhone, il computer apre il canale
   come con il `Connect` di usbmux, la sessione sicura e la fiducia sono le stesse. Su Windows la logica comune ora è una
   classe sola (`ClienteCavo`) per i due cavi; sul Mac lo stesso `ClienteUSB` segue usbmux e adb.
3. Nessun driver nostro da firmare su Windows, nessuna eccezione nuova del sandbox sul Mac, nessuna libreria GPL o LGPL:
   il client di adb è scritto da zero (C# e Swift), parla con il server di adb su loopback.
4. AOA darebbe la latenza più bassa senza modalità sviluppatore, ma su Windows richiede un driver firmato (o libusb, LGPL)
   e un trasporto USB tutto nostro: settimane di lavoro e un rischio di certificazione. Resta un'idea per dopo, magari solo
   sul Mac.

### Perché `host:transport` + `tcp:52741` e non `adb reverse` o `adb forward`

- `adb forward tcp:X tcp:52741` occupa una porta X sul computer e lascia una regola nel server di adb, da togliere; con due
  telefoni servono due porte. `host:transport:<seriale>` seguito da `tcp:52741` fa la stessa cosa su **una connessione**:
  niente porte, niente regole, il canale finisce quando lo chiudiamo. È quello che fa adb stesso dietro `adb forward`.
- `adb reverse` farebbe collegare il telefono al computer (127.0.0.1 sul telefono → porta del computer): il telefono
  dovrebbe provare di continuo, la regola resta nel telefono, e il computer non saprebbe che la connessione arriva dal cavo.
  Con il canale aperto dal computer tutto resta come per l'iPhone: è il computer che sa quale telefono è sul cavo e lo
  sospende dopo «Scollega».

## Licenze e distribuzione di adb

**Il nostro codice** (`ClienteAdb.cs`, `ProtocolloAdb.cs`, `Adb.swift`, `AscoltoCavoAdb.kt`): scritto da zero, nessuna
libreria. Il protocollo del server di adb (richieste con 4 cifre esadecimali, `OKAY`/`FAIL`) è documentato nel codice
sorgente di adb (AOSP, `packages/modules/adb`, file `SERVICES.TXT` / `docs/dev/services.md`).

**adb** non è nostro e **non è nella repository**. Due cose diverse:

- il **codice sorgente** di adb è nell'Android Open Source Project, con licenza **Apache 2.0**: compilarlo e distribuirlo
  si può, con la licenza e il file NOTICE. Le sue dipendenze vanno guardate una per una (BoringSSL ha la licenza di OpenSSL
  e ISC; su Linux, e in alcune build per macOS, adb usa **libusb, LGPL 2.1**; su Windows usa AdbWinApi, Apache 2.0);
- i **binari pronti di Google** («SDK Platform-Tools», `dl.google.com/android/repository/platform-tools-latest-<sistema>.zip`)
  sono sotto l'**Android Software Development Kit License Agreement**, che per quanto ricordo **non permette di
  ridistribuire** l'SDK, solo di usarlo. Qui la rete verso i siti di Google e di Debian era chiusa: il testo della licenza
  attuale **non è verificato** in questo giro. Alcune app (scrcpy per Windows) mettono adb nel loro pacchetto; non è una
  prova che sia permesso.

Come averlo, in ordine di preferenza:

1. **Già sul computer**: Android Studio (`%LOCALAPPDATA%\Android\Sdk\platform-tools`), scrcpy, Homebrew sul Mac
   (`brew install android-platform-tools`), o adb nel PATH. Su Windows `TrovaAdb` cerca nella cartella di WebcamLR, in
   `ANDROID_HOME`/`ANDROID_SDK_ROOT`, nell'SDK di Android Studio e nel PATH, e se il server non risponde lancia
   `adb start-server` (al massimo una volta al minuto). Un server già acceso si usa così com'è: WebcamLR non fa mai
   `adb kill-server` e non lancia un adb di un'altra versione contro un server acceso.
2. **Scaricato su richiesta dell'utente** (Windows, giro successivo): un pulsante «Scarica gli strumenti Android (Google,
   circa 7 MB)» mostra la licenza di Google, scarica lo zip ufficiale da `dl.google.com` e lo apre in
   `%LOCALAPPDATA%\WebcamLR\platform-tools`, dove `TrovaAdb` guarda per primo. È l'utente che accetta la licenza di Google,
   come quando installa Android Studio: noi non ridistribuiamo nulla.
3. **Compilato da noi dal codice AOSP** (Apache 2.0) e messo nel pacchetto: solo se la 2 non basta. Serve una build
   riproducibile per Windows e Mac, il file NOTICE, e controllare che nella build non entri libusb.

**Mac**: il sandbox non lascia avviare adb (e un adb avviato da noi avrebbe la sua chiave nel contenitore dell'app, quindi
il telefono chiederebbe di nuovo «Consenti»). In questo giro il Mac usa un server di adb già acceso: Android Studio aperto,
oppure `adb start-server` nel Terminale (resta acceso fino al riavvio). Per avviarlo da soli servirà un piccolo programma
di supporto fuori dal sandbox, la stessa decisione in sospeso per usbmux e il Mac App Store (`Studio USB.md`).

**Driver su Windows**: per l'interfaccia ADB Windows vuole un driver. Pixel: «Google USB Driver»; Samsung: «Samsung USB
Driver»; molti produttori lo installano con Windows Update. Da Android 11 in poi adbd dichiara i descrittori Microsoft OS
per WinUSB e Windows dovrebbe usarlo da solo: **da verificare** sui telefoni veri. Non distribuiamo driver, quindi niente
firma da fare.

## Cosa c'è in questo giro

| App | Cosa c'è | Provato |
|---|---|---|
| **Windows** (`WebcamLR.Ricevitore`) | `ClienteCavo` (logica comune dei cavi, presa da `ClienteUsbmux`), `ClienteAdb` (server di adb, `host:track-devices`, canale con `host:transport` + `tcp:52741`, avvio di adb se trovato), `ProtocolloAdb` e `TrovaAdb` (pura logica), `RigaCavo` (la riga «Cavo USB» con i due cavi), diagnosi «Consenti il debug USB sul telefono» e «Telefono Android collegato con il cavo», domanda frequente `cavo-android` | Test C#: adb finto su loopback, sessione sicura completa da un telefono Android finto |
| **Windows** (app WinUI) | Secondo cavo accanto a quello dell'iPhone: stessa accettazione, «Scollega», pausa per scelta e risveglio per tutti e due; riga «Cavo USB» con «In uso · Android», «Consenti sul telefono», «Nessun telefono»; stato di adb in «Segnala un bug» | Non compilata qui |
| **Mac** | `Adb.swift` (client del server di adb) e `ClienteUSB` che segue anche adb su un secondo filo; riga «Cavo USB» e diagnosi come su Windows; risposta «cavo» con il debug USB | Non compilato qui (niente Swift) |
| **Android** (protocollo) | `Collegamento` accetta una connessione già aperta (`socketPronto`) | Test Kotlin |
| **Android** (app) | `AscoltoCavoAdb` su 127.0.0.1:52741; la connessione apre «In onda» con la stessa stretta di mano; controllo del codice di sicurezza al `benvenuto`; «Cavo USB scollegato» dopo 30 s senza il computer, poi riparte da solo; ascolto spento dopo «Scollega» fino a «Usa il cavo USB»; domanda frequente e link nel foglio del cavo | Non compilata qui (niente Android SDK) |

Il protocollo dei messaggi non cambia: i tre test «CiaoComeNelDocumento» restano gli stessi.

## Cosa manca per chiudere il punto 17

1. **Prova sui telefoni veri** (checklist qui sotto): soprattutto che adb risponda `FAIL` quando l'app non ascolta (se
   invece desse `OKAY` e chiudesse, il computer allungherebbe l'attesa fino a 30 secondi) e i driver su Windows.
2. **adb su Windows senza Android Studio**: il download su richiesta (punto 2 della distribuzione), con la licenza di Google
   mostrata prima. Oggi senza adb la riga dice «Non disponibile» se manca anche «Dispositivi Apple».
3. **Mac**: avviare adb da soli (programma di supporto fuori dal sandbox) o almeno un pulsante che spiega il comando.
4. **Passaggio Wi-Fi ↔ cavo con adb durante una sessione** (come l'iPhone dalla 1.9): oggi con una sessione Wi-Fi
   l'ascolto del cavo è spento e il cavo entra solo dopo. Serve il «candidato» sul cavo in `SessioneTelefono.kt`.
5. **Guida al primo collegamento** sul computer (pagina con i passi per la modalità sviluppatore, con immagini per
   Samsung, Xiaomi, Pixel), oggi solo nelle domande frequenti e nella diagnosi.
6. Misura della latenza sul cavo con adb (`Documenti/Prestazioni.md`), da confrontare con usbmux e con il Tethering USB.

## Checklist sui dispositivi veri

Telefono Android con il debug USB acceso, cavo dati (non solo di ricarica).

- [ ] **Windows, adb già installato** (Android Studio o platform-tools nel PATH), server spento: WebcamLR lo avvia da sola
      entro qualche secondo; nel registro «Server di adb trovato (cavo USB di Android)».
- [ ] **Prima volta**: il telefono chiede «Consentire il debug USB?»; sul PC la riga «Cavo USB» dice «Consenti sul
      telefono» e la diagnosi spiega cosa fare. Dopo «Consenti» e con WebcamLR aperta sul telefono: «In onda» si apre da
      solo, il PC chiede il codice a 4 cifre come in Wi-Fi.
- [ ] Riga «Cavo USB» sul PC: «In uso · Android»; sul telefono in alto «Cavo USB». Video, comandi e audio come in Wi-Fi.
- [ ] **App chiusa sul telefono** con il cavo collegato: la riga dice «Apri l'app»; riaprendo l'app il video torna in 1–2
      secondi (non dopo 30). Se torna tardi, mandare il registro del PC: vuol dire che adb non risponde «FAIL».
- [ ] **Cavo staccato** durante il video: il telefono dice «Ricollego…», dopo 30 s «Cavo USB scollegato»; riattaccando il
      cavo riparte da solo.
- [ ] **«Scollega» sul PC**: il cavo resta fermo finché non lo si stacca e riattacca. **«Scollega» sul telefono**: non si
      riapre da solo; «Usa il cavo USB» nella lista dei computer lo riaccende.
- [ ] **Driver**: su un PC senza driver del produttore, il telefono compare in `adb devices`? (Se no: Google USB Driver o
      quello del produttore, e scriverlo nella guida.)
- [ ] **Mac** (Apple ID gratuito): con `adb start-server` nel Terminale (o Android Studio aperto) il telefono si collega
      come su Windows; senza server la riga dice «Nessun telefono» o «Non disponibile».
- [ ] **Con un iPhone sul cavo nello stesso momento**: tutti e due arrivano (con Pro), ognuno con il suo cavo.
- [ ] **Debug wireless** acceso: il telefono in Wi-Fi via adb non deve comparire come cavo.
- [ ] Latenza nei numeri del PC: annotare cavo adb, Tethering USB e Wi-Fi con lo stesso telefono.

## Decisioni per Ledion

1. **Distribuzione di adb su Windows**: download su richiesta da Google (proposta) o adb compilato da noi nel pacchetto?
   Prima di tutto far leggere a chi si occupa delle licenze l'«Android SDK License Agreement» attuale.
2. **Mac**: programma di supporto fuori dal sandbox per avviare adb (come per usbmux e lo store) o basta la guida?
3. **Testo per l'utente**: «debug USB» va bene, o preferisci «modalità sviluppatore» nei titoli?
4. **Store**: nelle schede e nel materiale («Non serve la modalità sviluppatore») va aggiunta la seconda strada, dopo la
   prova sui telefoni veri.
