# WebcamLR per Android

Il telefono Android come webcam per Mac e Windows, con lo stesso protocollo dell'iPhone (`Documenti/Protocollo.md`, versione 2: collegamento cifrato, codice di conferma, QR code). Kotlin, Jetpack Compose con Material 3 nei colori LR Apps, Camera2, MediaCodec. **Nessun servizio Google**: funziona anche sui Huawei senza Play Store.

## Cartelle

```
Android/
├── protocollo/   protocollo WebcamLR in Kotlin puro (JVM), con i test: si prova su qualsiasi computer
│   ├── Pacchetto, Messaggi, Json   pacchetti e messaggi (stesso JSON di Swift, scritto a mano)
│   ├── Sicurezza                   ECDH/ECDSA P-256, HKDF-SHA256, AES-256-GCM, codice, impronta
│   ├── Associazione                QR code e indirizzo scritto
│   ├── Collegamento                il collegamento del telefono: stretta di mano, attese, ping, video
│   └── Qualita                     qualità in parole, bitrate che segue la rete, tipo di collegamento
└── app/          l'app (serve l'Android SDK)
    ├── sessione/  SessioneTelefono (come SessioneTelefono.swift), ServizioInOnda (servizio in primo piano)
    ├── video/     Cattura (Camera2), Renderizzatore (OpenGL: rotazione e specchio), Codificatore (MediaCodec), LettoreQR (ZXing)
    ├── rete/      CercaComputer (NsdManager, `_webcamlr._tcp`)
    ├── dati/      impostazioni, computer conosciuti, identità nel Keystore di Android
    ├── ui/        le schermate in Compose
    └── contenuti/ domande frequenti e guida, scritte per Android
```

## Costruire e provare (Ledion)

1. Installa **Android Studio** (gratuito, developer.android.com/studio). Va bene qualsiasi versione del 2025 o successiva.
2. In Android Studio: **Open** e scegli la cartella `Android/` della repository (non la cartella principale).
3. Al primo avvio Android Studio scarica da solo l'Android SDK 35 e Gradle: aspetta che in basso finisca «Gradle sync». Se propone di aggiornare il plugin Android, puoi rispondere «Non ora».
4. Sul telefono attiva le **Opzioni sviluppatore**: Impostazioni › Info sul telefono › tocca 7 volte «Numero build» (su Xiaomi «Versione MIUI/HyperOS», su Huawei «Numero build» in Info sul telefono). Poi Opzioni sviluppatore › **Debug USB** attivo.
5. Collega il telefono con il cavo, accetta «Consentire il debug USB?» sul telefono, scegli il telefono in alto in Android Studio e premi **▶ Run**.

Senza cavo: Opzioni sviluppatore › Debug wireless, poi in Android Studio «Pair devices using Wi-Fi».

APK da installare a mano (per esempio su un secondo telefono): Build › Build App Bundle(s) / APK(s) › Build APK(s); il file è in `app/build/outputs/apk/debug/`. Da riga di comando: `./gradlew :app:assembleDebug`.

Se il «Gradle sync» si ferma con un errore sulla versione di Java («Unsupported Java», «incompatible Gradle JVM»): Settings › Build, Execution, Deployment › Build Tools › Gradle › **Gradle JDK** › scegli una JDK 21 (se non c'è: «Download JDK…», versione 21), poi «Sync Project with Gradle Files». Il progetto usa Gradle 8.14.3, che gira con Java da 17 a 24.

**Test del protocollo**, anche senza Android SDK: `./gradlew -PsoloProtocollo :protocollo:test` (o `gradle -PsoloProtocollo :protocollo:test`, oppure con la variabile `WEBCAMLR_SOLO_PROTOCOLLO=1`). Con `-PsoloProtocollo` la build include solo `:protocollo` e non scarica il plugin Android; senza, include sempre anche `:app` (serve l'Android SDK: in Android Studio c'è da sé).

Prova con il ricevitore Windows vero (senza interfaccia, anche su Mac o Linux): avvia un piccolo programma che usa `WebcamLR.Ricevitore` in ascolto su 127.0.0.1, poi
`WEBCAMLR_RICEVITORE="<porta> <impronta> <gettone o ->" ./gradlew -PsoloProtocollo :protocollo:test --tests '*Interoperabilita*'`. Fatto il 24 ottobre 2026: passato sia con il QR code sia con il codice di conferma.

## Telefoni: cosa sapere

**Tutti.** Al primo collegamento Android chiede la fotocamera e le notifiche. Mentre manda il video WebcamLR mostra l'avviso fisso «WebcamLR · video al computer» con «Scollega»: è il servizio in primo piano che tiene viva la fotocamera a schermo spento (Android lo richiede). Lo schermo resta acceso e dopo 30 secondi si oscura al minimo, come sull'iPhone.

**Xiaomi, Redmi, POCO (MIUI e HyperOS).** Il risparmio energetico è aggressivo e può fermare il video a schermo spento:
- Impostazioni › App › Gestisci app › WebcamLR › **Avvio automatico** attivo;
- stessa pagina › Risparmio batteria › **Nessuna restrizione**;
- nelle app recenti tieni premuto WebcamLR › lucchetto («Blocca»), così non viene chiusa quando pulisci le recenti.
Per installare dal computer con il cavo serve anche Opzioni sviluppatore › **Installa tramite USB** (chiede l'accesso all'account Xiaomi e, a volte, una SIM).

**Huawei e Honor (EMUI, HarmonyOS fino alla 4).** Senza servizi Google WebcamLR funziona uguale: ricerca del computer (NsdManager), QR code (ZXing dentro l'app), video e sicurezza sono tutti di sistema. Per il video a schermo spento: Impostazioni › Batteria › Avvio app › WebcamLR › **Gestisci manualmente** e attiva avvio automatico, avvio secondario ed esecuzione in background. Distribuzione: APK dal sito oppure **AppGallery** (serve un account sviluppatore Huawei, gratuito; l'APK va firmato con la chiave di pubblicazione). HarmonyOS NEXT (5 e successivi) non esegue più le app Android: lì WebcamLR non va.

**Samsung (One UI).** Impostazioni › App › WebcamLR › Batteria › **Senza limitazioni**; controlla che WebcamLR non sia tra le «App in sospensione» (Assistenza dispositivo › Batteria › Limiti utilizzo in background).

**Oppo, Realme, OnePlus, Vivo.** Come Xiaomi: avvio automatico consentito e nessuna ottimizzazione della batteria per WebcamLR.

## Come funziona il video

Camera2 → SurfaceTexture → OpenGL ES 2 (`Renderizzatore`) → Surface d'ingresso del codificatore hardware (MediaCodec). Nessuna copia dei fotogrammi in memoria: rotazione e specchio li fa la GPU. Il codificatore usa solo l'hardware del telefono (H.264 di serie, HEVC a scelta, ripiego su H.264 se manca), con priorità tempo reale, latenza minima, niente fotogrammi B, un fotogramma chiave ogni 2 secondi o su richiesta, e il bitrate che scende e risale con la rete (come l'iPhone). SPS/PPS (e VPS per HEVC) davanti a ogni fotogramma chiave.

**Rotazione.** Il video inviato è sempre orizzontale e dritto rispetto a come è tenuto il telefono (sensore di orientamento); l'anteprima è dritta rispetto allo schermo. Convenzione: la matrice della SurfaceTexture dà l'immagine dritta nell'orientamento naturale del telefono, già specchiata per la frontale; il video inviato si ruota di quanto è girato il telefono (in senso orario) e la frontale si «smonta» dallo specchio, salvo «Specchia l'immagine inviata». È la parte più delicata da provare (checklist): se su un telefono il video arriva capovolto o specchiato, mandami marca, modello e come era tenuto.

**Orologio.** I timestamp sono quelli della fotocamera; al primo fotogramma l'app sceglie l'orologio di sistema corrispondente (`elapsedRealtime` o monotono), così la latenza misurata dal computer è giusta su tutti i telefoni.

**Rete.** Il socket chiede la priorità video del Wi-Fi (DSCP CS5), il Wi-Fi resta in modalità bassa latenza e il processore sveglio finché si manda il video.

## Cavo USB: le possibilità (non ancora nell'app)

Sull'iPhone il cavo passa da usbmux; su Android ci sono tre strade:

1. **Tethering USB** (consigliato per la 1.x). Sul telefono: Impostazioni › Rete › Hotspot e tethering › Tethering USB. Il telefono crea una piccola rete sul cavo (RNDIS, o NCM sui telefoni più recenti) e il computer riceve un indirizzo: il protocollo resta identico, si collega come in Wi-Fi e l'app mostra «Cavo USB» (interfaccia `rndis`/`ncm`). Non serve installare nulla sul computer: Windows ha il driver RNDIS; il Mac ha NCM ma non RNDIS, quindi sul Mac funziona solo con i telefoni che usano NCM. Lato computer servono: ascolto su tutte le interfacce (già così), annuncio mDNS anche sulla rete del cavo, QR code con anche l'indirizzo del cavo, e su Windows il firewall: la nuova rete nasce «pubblica» e va consentita. La ricerca automatica sul cavo dipende dalla versione di Android: il QR code funziona sempre.
2. **ADB reverse** (`adb reverse tcp:52740 tcp:52740`): il telefono si collega a 127.0.0.1 e ADB porta tutto al computer. Serve adb sul computer (platform-tools di Google) e il Debug USB attivo sul telefono: troppo tecnico per tutti, utile come opzione avanzata più avanti.
3. **Android Open Accessory** (il computer parla direttamente con il telefono via USB): niente rete né debug, ma su Windows richiede un driver USB e le librerie pronte (libusb) sono LGPL. Da valutare solo dopo.

## Non ancora

Audio (microfono), il cavo USB «nativo», i controlli Pro sul telefono, il blocco AE/AF preciso su ogni telefono (il tocco usa la posizione approssimata sul sensore), il passaggio automatico Wi-Fi ↔ cavo (1.9), le diagnosi automatiche complete (1.3). Da Android 16/17 potrebbe servire il nuovo permesso «rete locale» quando si alzerà il targetSdk.
