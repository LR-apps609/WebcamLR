# Materiale per gli store · WebcamLR 1.0

Testi, risposte ai questionari, screenshot, video e note per la revisione di **App Store** (iPhone) e **Google Play** (Android),
più le note di rilascio di Mac e Windows su GitHub. Scritto il 26 ottobre 2026 sul ramo `materiale-store` (da `round-2`).
Completa `Pubblicazione.md` (passi tecnici) e ne aggiorna la bozza «Testi della scheda»: **valgono i testi di questo documento**.

Regole seguite in tutto il documento:
- Solo funzioni che esistono nel codice di oggi (controllate una per una, sotto *Verifiche nel codice*). Niente funzioni del
  dopo-lancio (`Idee nuove funzioni.md`: Documento/Scrivania, verticale 9:16, webcam fissa, visualizzatore nel browser, effetti sul
  volto, telefono come monitor). Il profilo «Lingua dei segni» **non è ancora nel codice**: non è citato.
- Niente nomi di concorrenti né di app di terzi nei testi degli store; niente prezzi nei metadati (Apple 2.3.7 e regole delle
  anteprime): il prezzo lo mostra lo store, e così il prezzo di lancio 9,99 € e quello pieno 14,99 € compaiono da soli.
- Nei testi App Store niente «Android» né «Google Play» (Apple 2.3.10, *Altre piattaforme*); nei testi Play niente «iPhone».
- Segnaposto da riempire: **[NOME TITOLARE]**, **[EMAIL ASSISTENZA]**, **[TELEFONO]**, **[INDIRIZZO]**.
- Ogni campo con un limite ha sotto la riga «Conteggio»: il numero è calcolato da uno script (sezione 9), non a occhio. Le parole
  chiave di Apple si contano in **byte** (UTF-8), come dice Apple; tutto il resto in caratteri.

Indirizzi usati: sito https://lr-apps609.github.io/WebcamLR/ · aiuto https://lr-apps609.github.io/WebcamLR/aiuto.html ·
privacy https://lr-apps609.github.io/WebcamLR/privacy.html · download https://lr-apps609.github.io/WebcamLR/download.html.

---

## 0. Da sapere prima: cosa ho trovato controllando codice e regole

Bloccanti o quasi, in ordine di importanza. I dettagli sono nelle sezioni indicate.

| # | Problema | Dove | Effetto | Proposta |
| --- | --- | --- | --- | --- |
| A | **MediaPipe manda statistiche d'uso a Google.** La libreria `com.google.mediapipe:tasks-vision` (Android, effetti) dipende da `tasks-core`, che porta con sé il trasporto di log di Google (DataTransport/CCT); la documentazione di MediaPipe Tasks dice che le API «inviano a Google metriche sulle prestazioni e sull'uso» e che il consenso degli utenti è responsabilità di chi fa l'app. Nel sorgente libero c'è solo un registratore vuoto: la raccolta è attivata nei pacchetti pubblicati su Maven (`ENABLE_TASKS_USAGE_LOGGING`) | `Android/app/build.gradle.kts` | Con il codice di oggi **non** si può rispondere «Nessun dato raccolto» nel modulo Play, e la privacy del sito («nessuno strumento di tracciamento», «le app usano internet per una cosa sola») non è vera su Android | Decisione di Ledion (sezione 4.4): togliere la telemetria (consigliato) oppure dichiararla |
| B | **Livello API di destinazione**: dal 31 agosto 2026 Google Play accetta app nuove e aggiornamenti solo con `targetSdk` 36 (Android 16); proroga su richiesta fino al 1° novembre 2026. Il codice ha `compileSdk 35`, `targetSdk 35` | `Android/app/build.gradle.kts` | Play rifiuta il caricamento | Round Android: passare a 36 e riprovare (permessi e servizio in primo piano) |
| C | **Play Billing 7.1.1**: le versioni 7.x non si possono più usare per app nuove e aggiornamenti dopo il 31 agosto 2026 (proroga fino al 1° novembre) | idem | Play rifiuta il caricamento | Passare alla libreria 8 o successiva (cambia la firma di `queryProductDetailsAsync`) |
| D | **Pagine da 16 KB**: MediaPipe 0.10.14 ha librerie native a 4 KB; MediaPipe dichiara il supporto ai 16 KB dalla 0.10.26. Obbligatorio per chi punta ad Android 15+ (vedi fonti per le date) | idem | Avviso o rifiuto in Play Console | Aggiornare MediaPipe (già scritto come nota nel `build.gradle.kts`) |
| E | **Firma di rilascio Android**: la build `release` usa la chiave di debug (`signingConfig = debug`) e `versionName = "0.1"` | idem | Play non accetta un AAB firmato con la chiave di debug | Chiave di caricamento (Play App Signing) fuori dalla repository, `versionName 1.0` |
| F | **Pro su Android promette due cose che Android non ha**: la pagina Pro elenca «Volto + scrivania» e «Sul computer: gobbo», ma nel codice Android non ci sono (il sito stesso dice «per ora solo sull'iPhone») | `Android/app/src/main/res/values/strings.xml` (`pro_pro_3`, `pro_pro_11`) e `values-en` | Rischio di rimborsi e di segnalazione per «funzionalità ingannevole» | Togliere le due righe su Android (o scriverle «solo con iPhone») prima di Play. Il testo Play qui sotto non le cita |
| G | **L'app iPhone nomina Android e Google Play**: le domande frequenti comuni (`Stile/Sources/Stile/DomandeFrequenti.swift`, risposte «cavo» e «costo»; `SezioneApp.swift`, guida) parlano di «Android», «Tethering USB di Android» e «Google Play» | Stile | Apple 2.3.10 vieta nomi di altre piattaforme mobili nell'app «salvo funzionalità interattiva approvata»: possibile rifiuto | Su iPhone mostrare la versione senza Android (per esempio «con un telefono di un altro tipo» o nessuna frase), lasciando le risposte complete sul Mac e sul sito |
| H | **Prezzo scritto nell'app**: la risposta «costo» delle domande frequenti dice «14,99 €», mentre durante il lancio lo store mostra 9,99 € (e altre valute fuori dall'euro) | `DomandeFrequenti.swift` | Incoerenza visibile al revisore e agli utenti | Togliere la cifra («un acquisto unico, al prezzo che vedi nella pagina WebcamLR Pro») |
| I | **Limiti dell'acquisto in-app**: Apple oggi dà **30** caratteri al nome e **45** alla descrizione; `Pubblicazione.md` dice 35 e 55, e la descrizione proposta lì ne ha 55 | `Pubblicazione.md`, sezione 5 | App Store Connect non la accetta | Usare i testi della sezione 1.6 |
| L | **Permesso fotocamera**: il testo non dice che la fotocamera serve anche a leggere il QR code del computer | `iPhone/project.yml`, `*.lproj/InfoPlist.strings` | Apple 5.1.1 chiede testi completi | Proposta nella sezione 3.4 (non modificato) |
| M | **Segnaposto online**: la privacy del sito è una «bozza» con titolare ed email da scrivere, e la pagina download dice «in arrivo» | ramo `sito` | Apple 2.1(a): niente testi provvisori né siti vuoti alla revisione | Completare prima di inviare (sezione 8) |
| N | **Email di assistenza vuota nelle app** (`InfoApp.EMAIL_ASSISTENZA = ""` su Android, `emailAssistenza = ""` in Stile per iPhone e Mac) | Android `Contenuti.kt`, `Stile/Sources/Stile/SezioneApp.swift` | «Segnala un bug» apre la condivisione invece della mail | Scrivere [EMAIL ASSISTENZA] quando c'è |

Il resto (privacy iPhone, cifratura, prodotto `it.lrapps.webcamlr.pro`, limiti gratis) è coerente: vedi *Verifiche nel codice* in fondo.

---

## 1. App Store (iPhone)

Lingua principale **Italiano**; localizzazione **Inglese (Stati Uniti)** (Apple la mostra nei paesi senza una lingua propria).
L'app è solo per iPhone (`TARGETED_DEVICE_FAMILY: "1"`): niente screenshot iPad obbligatori.

### 1.1 Nome e sottotitolo

Il nome contiene «Mac e PC» perché dice in tre parole a cosa serve; se «WebcamLR» da solo è preferito, va bene anche quello
(le parole «webcam», «Mac», «PC» passano allora nelle parole chiave). Nel nome niente «iPhone» (marchio Apple: Apple non lo vuole nei
nomi delle app di terzi).

**Nome · italiano** <!-- campo as.nome.it max=30 -->
```text
WebcamLR: webcam per Mac e PC
```
Conteggio: 29/30 caratteri

**Name · English** <!-- campo as.nome.en max=30 -->
```text
WebcamLR: Webcam for Mac & PC
```
Conteggio: 29/30 caratteri

**Sottotitolo · italiano** <!-- campo as.sottotitolo.it max=30 -->
```text
Il telefono in videochiamata
```
Conteggio: 28/30 caratteri

**Subtitle · English** <!-- campo as.sottotitolo.en max=30 -->
```text
Use your phone in video calls
```
Conteggio: 29/30 caratteri

### 1.2 Testo promozionale

Si cambia senza una nuova versione (utile a fine lancio o quando arriva una novità). Niente prezzo.

**Italiano** <!-- campo as.promo.it max=170 -->
```text
Il video della fotocamera dell'iPhone arriva sul Mac o sul PC, con il cavo USB o il Wi-Fi. Anche nella versione gratuita: niente filigrana, niente account.
```
Conteggio: 155/170 caratteri

**English** <!-- campo as.promo.en max=170 -->
```text
Your iPhone camera's video on your Mac or PC, over USB cable or Wi-Fi. Even in the free version: no watermark, no account.
```
Conteggio: 122/170 caratteri

### 1.3 Descrizione

La webcam virtuale del Mac c'è solo nella versione firmata con l'account sviluppatore a pagamento: la descrizione presuppone che
il dmg pubblicato sia quello (vedi sezione 8). Se si pubblicasse l'iPhone prima, togliere dal punto 3 «e, tramite la webcam
virtuale…» per il Mac.

**Italiano** <!-- campo as.descrizione.it max=4000 -->
```text
WebcamLR trasforma l'iPhone nella webcam del Mac o del PC. Videochiamate, lezioni e dirette prendono il video dalla fotocamera dell'iPhone, con più dettaglio e meno grana della webcam del portatile.

COME FUNZIONA
1. Installa WebcamLR sul computer: è gratuita, dal sito lr-apps609.github.io/WebcamLR (Mac con macOS 14 o successivo, PC con Windows 10 o 11 a 64 bit).
2. Apri WebcamLR sull'iPhone. Sulla stessa rete il computer compare da solo; altrimenti inquadri il QR code del computer o colleghi il cavo.
3. Il video arriva nella finestra di WebcamLR e, tramite la webcam virtuale «WebcamLR», nelle app di videochiamata e di diretta.

COLLEGAMENTO
• Cavo USB, Wi-Fi o hotspot dell'iPhone; con il Mac anche Wi-Fi diretto, senza router.
• Se attacchi il cavo durante una chiamata, il video passa al cavo senza fermarsi; se lo stacchi, torna al Wi-Fi.
• Sempre visibile: la strada in uso, la latenza e la qualità in parole («Ottimo», «Buono», «Debole»).
• Quando qualcosa non va, l'app dice la causa probabile e cosa fare: permesso «Rete locale», reti diverse, rete che separa i dispositivi.

IL TUO VIDEO RESTA TUO
• Video, audio e comandi vanno dall'iPhone al tuo computer, sulla tua rete o sul cavo, cifrati con chiavi nuove a ogni collegamento. Non passano da nostri server.
• Un computer nuovo si abbina con il suo QR code o con un codice di 4 cifre da confermare.
• Nessun account, nessuna pubblicità, nessun dato raccolto.

GRATIS, PER SEMPRE
• Video fino a 720p a 30 fps, senza filigrana.
• Specchia, sfondo sfocato e luce sul volto.
• Zoom, obiettivi, torcia ed esposizione, anche dal computer.
• Microfono dell'iPhone sul computer: sul Mac compare come «WebcamLR (microphone)»; su Windows passa da un cavo audio virtuale gratuito, da installare a parte.
• Telefono a faccia in giù: il video va in pausa. Schermo che si oscura da solo e qualità che scende a gradini se il telefono scalda.

WEBCAMLR PRO: UN ACQUISTO, SENZA ABBONAMENTO
• 1080p, 4K a 30 fps (HEVC) e 60 fps, dove l'iPhone ci arriva.
• Effetti: filtri di colore e regolazioni, sfondo sostituito con un'immagine, ritocco leggero della pelle, scritta con nome e ruolo, il tuo logo.
• Inquadratura automatica, e «Volto + scrivania» con il grandangolo 0,5×.
• Controlli Pro: ISO, tempo, bilanciamento del bianco e messa a fuoco.
• Sul computer: profili Riunione, Lezione, Diretta e Colloquio (e i tuoi), foto e registrazione, gobbo, un secondo telefono come seconda inquadratura, schermata d'attesa personalizzata.
Si compra una volta nell'app, vale anche In famiglia e sblocca il computer collegato a questo iPhone: sul Mac e su Windows non c'è niente da comprare. «Ripristina acquisti» è nella pagina WebcamLR Pro.

COSA SERVE
• Un iPhone con iOS 17 o successivo.
• WebcamLR sul Mac o sul PC, gratuita dal sito.
• Per il cavo USB su Windows, l'app gratuita «Dispositivi Apple».

WebcamLR è in italiano e in inglese.
Aiuto: lr-apps609.github.io/WebcamLR/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/privacy.html
```
Conteggio: 2984/4000 caratteri

**English** <!-- campo as.descrizione.en max=4000 -->
```text
WebcamLR turns your iPhone into the webcam for your Mac or PC. Video calls, lessons and live streams take the video from the iPhone camera, with more detail and less grain than the laptop's webcam.

HOW IT WORKS
1. Install WebcamLR on the computer: it's free, from lr-apps609.github.io/WebcamLR (Mac with macOS 14 or later, PC with 64-bit Windows 10 or 11).
2. Open WebcamLR on the iPhone. On the same network the computer shows up by itself; otherwise scan the computer's QR code or plug in the cable.
3. The video arrives in the WebcamLR window and, through the "WebcamLR" virtual webcam, in your video call and streaming apps.

CONNECTION
• USB cable, Wi-Fi or the iPhone's hotspot; with a Mac also Wi-Fi Direct, without a router.
• Plug in the cable during a call and the video moves to the cable without stopping; unplug it and it goes back to Wi-Fi.
• Always in view: the connection in use, the latency and the quality in words ("Excellent", "Good", "Weak").
• When something's wrong, the app tells you the likely cause and what to do: "Local Network" permission, different networks, a network that keeps devices apart.

YOUR VIDEO STAYS YOURS
• Video, audio and controls go from the iPhone to your computer, over your network or the cable, encrypted with new keys for every connection. They don't pass through our servers.
• A new computer is paired with its QR code or with a 4-digit code you confirm.
• No account, no ads, no data collected.

FREE, FOREVER
• Video up to 720p at 30 fps, with no watermark.
• Mirror, background blur and face lighting.
• Zoom, lenses, flashlight and exposure, from the computer too.
• The iPhone's microphone on the computer: on the Mac it shows up as "WebcamLR (microphone)"; on Windows it goes through a free virtual audio cable, installed separately.
• Phone face down: the video pauses. The screen dims by itself, and quality steps down if the phone gets hot.

WEBCAMLR PRO: ONE PURCHASE, NO SUBSCRIPTION
• 1080p, 4K at 30 fps (HEVC) and 60 fps, where the iPhone supports it.
• Effects: colour filters and adjustments, background replaced with an image, light skin smoothing, a caption with your name and role, your logo.
• Auto framing, and "Face + desk" with the 0.5× Ultra Wide camera.
• Pro controls: ISO, shutter, white balance and focus.
• On the computer: Meeting, Lesson, Live stream and Interview profiles (and your own), photos and recording, teleprompter, a second phone as a second angle, a custom waiting screen.
Buy it once in the app; it works with Family Sharing and unlocks the computer connected to this iPhone: there's nothing to buy on the Mac or on Windows. "Restore Purchases" is on the WebcamLR Pro page.

WHAT YOU NEED
• An iPhone with iOS 17 or later.
• WebcamLR on your Mac or PC, free from the website.
• For the USB cable on Windows, the free "Apple Devices" app.

WebcamLR is in English and Italian.
Help: lr-apps609.github.io/WebcamLR/en/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/en/privacy.html
```
Conteggio: 2977/4000 caratteri

### 1.4 Parole chiave

Separate da virgole senza spazi. Nessuna parola del nome («webcamlr», «webcam», «mac», «pc») né del sottotitolo (Apple li indicizza
già), niente marchi di altri (né nomi di app di chiamata, né «windows»: il nome dice già «PC»), niente plurali doppi.

**Italiano** <!-- campo as.parole.it max=100 byte -->
```text
fotocamera,videocamera,riunione,lezione,diretta,streaming,usb,wifi,microfono,4k,1080p,cavo,hotspot
```
Conteggio: 98/100 byte

**English** <!-- campo as.parole.en max=100 byte -->
```text
camera,meeting,conference,lesson,stream,streaming,live,usb,wifi,microphone,4k,1080p,cable,hotspot
```
Conteggio: 97/100 byte

### 1.5 Novità della versione, categorie, età, indirizzi

- **Novità della versione**: per la **prima** versione App Store Connect non mostra il campo. Testo pronto per la 1.0.1 (adattarlo):

  **Italiano** <!-- campo as.novita.it max=4000 -->
  ```text
  Correzioni e piccoli miglioramenti al collegamento. Grazie a chi ha segnalato i problemi da «Segnala un bug».
  ```
  Conteggio: 109/4000 caratteri

  **English** <!-- campo as.novita.en max=4000 -->
  ```text
  Fixes and small improvements to the connection. Thanks to everyone who reported issues with "Report a bug".
  ```
  Conteggio: 107/4000 caratteri

- **Categoria primaria**: **Foto e video** (Photo & Video). **Secondaria**: **Produttività** (Productivity), per riunioni e lezioni.
  In alternativa Business come secondaria; Utility è meno cercata.
- **Classificazione per età** (questionario nuovo, con le fasce 4+, 9+, 13+, 16+, 18+): tutte le risposte **No / Nessuno**:
  - Controlli nell'app: Controllo parentale **No**; Verifica dell'età **No**.
  - Capacità: Accesso libero al web **No** (i link aprono Safari, non c'è un browser nell'app); Contenuti generati dagli utenti **No**
    (il video va solo al computer di chi lo riprende, non è diffuso); Social media **No**; Messaggi e chat **No**; Pubblicità **No**.
  - Temi per adulti, Medicina o benessere, Sessualità o nudità, Violenza, Attività basate sul caso (gioco d'azzardo, simulato,
    concorsi, loot box): tutto **Nessuno**.
  - «Made for Kids» (Creata per bambini): **No**.
  - Risultato atteso: **4+**.
- **URL di supporto**: `https://lr-apps609.github.io/WebcamLR/aiuto.html` (inglese: `…/en/aiuto.html`, se App Store Connect
  accetta URL per lingua; altrimenti quello italiano, che ha il selettore EN).
- **URL di marketing**: `https://lr-apps609.github.io/WebcamLR/`.
- **URL della privacy**: `https://lr-apps609.github.io/WebcamLR/privacy.html` (inglese `…/en/privacy.html`). Prima va tolta la
  parola «bozza» e scritti titolare ed email (problema M).
- **Copyright**: `© 2026 [NOME TITOLARE]`.
- **Diritti sui contenuti**: «No, non contiene, mostra o accede a contenuti di terzi».
- **Stato di operatore commerciale (DSA, Unione Europea)**: con un acquisto in-app Ledion è quasi certamente «operatore
  commerciale» (trader): Apple pubblica allora nella scheda indirizzo, telefono ed email. Va dichiarato in App Store Connect ›
  Business prima di distribuire nell'UE.

### 1.6 Acquisto in-app «WebcamLR Pro»

Limiti verificati sulla pagina di Apple: nome visualizzato da 2 a **30** caratteri, descrizione **45**, note per la revisione 4000.
Tipo **Non consumabile**, ID `it.lrapps.webcamlr.pro` (uguale in `Stile/Sources/Stile/Pro.swift`, `iPhone/WebcamLR.storekit` e in
`Android/…/acquisti/NegozioPro.kt`), nome di riferimento `WebcamLR Pro`, Condivisione in famiglia accesa.

**Nome visualizzato · italiano** <!-- campo iap.nome.it max=30 -->
```text
WebcamLR Pro
```
Conteggio: 12/30 caratteri

**Display name · English** <!-- campo iap.nome.en max=30 -->
```text
WebcamLR Pro
```
Conteggio: 12/30 caratteri

**Descrizione · italiano** <!-- campo iap.descrizione.it max=45 -->
```text
4K, 60 fps, effetti e profili. Per sempre
```
Conteggio: 41/45 caratteri

**Description · English** <!-- campo iap.descrizione.en max=45 -->
```text
4K, 60 fps, effects and profiles. Forever
```
Conteggio: 41/45 caratteri

**Screenshot per la revisione** (non pubblico; una delle misure accettate per iPhone, per esempio 1320 × 2868): la pagina
**WebcamLR Pro** dell'iPhone (ⓘ in alto a destra › WebcamLR Pro) con il pulsante «Sblocca Pro · …» e il confronto Gratis/Pro. Qui il
prezzo può vedersi: questo screenshot non va sullo store.

**Note per la revisione dell'acquisto** (in inglese) <!-- campo iap.note.en max=4000 -->
```text
WebcamLR Pro (it.lrapps.webcamlr.pro) is a one-time, non-consumable purchase with Family Sharing. No account is needed.

Where: tap the (i) button at the top right of the first screen › WebcamLR Pro. The page shows "Unlock Pro" with the price from the App Store and "Restore Purchases". Every Pro-only control in the app shows a "PRO" badge; tapping it opens the same page.

What it unlocks: 1080p, 4K at 30 fps and 60 fps video; effects (filters, adjustments, background replacement, skin smoothing, caption and logo); auto framing; Face + desk; manual ISO, shutter, white balance and focus. It also unlocks the matching features of the free WebcamLR app for Mac and Windows (profiles, photos and recording, teleprompter, a second phone, custom waiting screen) while this iPhone is connected. The computer apps sell nothing: they only read from the connected iPhone whether Pro is active.

The free version is fully usable: 720p at 30 fps, no watermark, no time limit, no ads.

After a sandbox purchase the page shows "Pro active" and the PRO badges disappear. The attached demo video shows the purchase and the unlocked 1080p option on the computer.
```
Conteggio: 1151/4000 caratteri

---

## 2. Privacy dell'app su App Store Connect («etichette nutrizionali»)

**Risposta: «No, noi e i nostri partner terzi non raccogliamo dati da questa app».** Tracciamento: **No**. Nessun tipo di dato da
selezionare. È coerente con `iPhone/Privacy/PrivacyInfo.xcprivacy` (`NSPrivacyTracking` falso, nessun dominio,
`NSPrivacyCollectedDataTypes` vuoto) e con il codice di oggi:

| Cosa fa l'app | Perché non è «raccolta» per Apple | Controllato in |
| --- | --- | --- |
| Video, audio, comandi, nome del telefono, batteria e temperatura verso il computer | Vanno solo al computer dell'utente (rete locale o cavo), cifrati con CryptoKit; non arrivano a noi né a terzi. Apple chiama «raccolta» la trasmissione fuori dal dispositivo verso lo sviluppatore o terzi | `Collegamento.swift` (`NWConnection` verso l'indirizzo del computer), `SessioneTelefono.swift` |
| Foto scelta per sfondo o logo | `PhotosPicker` di sistema (nessun permesso Foto), immagine ridotta e salvata sul telefono; nel video solo come parte dell'immagine | `SchermataEffetti.swift`, `EffettiVisivi.swift` |
| Acquisto di WebcamLR Pro | Lo gestisce Apple (StoreKit 2); sul telefono resta solo l'`originalID` | `NegozioPro.swift` |
| «Segnala un bug» | Apre Mail o il foglio di condivisione; il testo lo manda l'utente se vuole (per Apple è divulgazione facoltativa, non raccolta) | `SchermataApp.swift` |
| Collegamenti al sito | Solo `URL` aperti in Safari; l'app iPhone non scarica nulla da internet (il controllo di `versione.json` è solo su Mac e Windows) | `SezioneApp.swift`, ricerca di `URLSession`: nessun risultato nell'iPhone |
| Analisi, crash, pubblicità | Nessuna libreria di terzi nell'app iPhone (solo i pacchetti nostri `Protocollo` e `Stile`); niente MediaPipe su iOS (gli effetti usano Vision e Core Image di Apple) | `iPhone/project.yml`, `Package.swift` |

Da ricontrollare a ogni versione: se entra una libreria di terzi o una richiesta in rete verso un nostro server, le risposte
cambiano.

---

## 3. Note per il revisore Apple (App Review Information)

### 3.1 Campi

- **Accesso richiesto (Sign-in required)**: **No** (non c'è login).
- **Contatto**: [NOME TITOLARE] · [TELEFONO] · [EMAIL ASSISTENZA].
- **Allegato**: il video dimostrativo (sezione 3.3), anche come link non in elenco su YouTube nelle note.
- **Note** (in inglese, così le legge qualsiasi revisore):

<!-- campo review.note.en max=4000 -->
```text
WebcamLR turns the iPhone into a webcam for a Mac or a Windows PC. The iPhone app captures and encodes the video; a free companion app on the computer receives it and shows it in its window and as a virtual camera for video call apps. Without the computer app the iPhone app cannot show its main feature, so we attached a demo video recorded on real devices (iPhone + Mac): https://[VIDEO LINK]

If you want to try it yourself:
1. On a Mac (macOS 14+), download the free app: https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR.dmg (signed and notarized). Open the dmg and drag WebcamLR to Applications. A Windows version is at https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR-Setup.exe
2. Put the iPhone and the Mac on the same Wi-Fi network and open WebcamLR on both. Allow "Local Network" and "Camera" on the iPhone.
3. The Mac appears in the list on the iPhone (or scan the QR code shown at the bottom left of the Mac window). The first time, confirm the 4-digit code on the Mac.
4. The iPhone shows "LIVE" and the video appears on the Mac. A USB cable also works (no setup needed on the Mac).

Without a computer you can still review: the first-launch tour, "Looking for your computer..." with the help that appears after 15 seconds, Settings, FAQ, Guide, "Report a bug" and the WebcamLR Pro page.

Why the permissions:
- Local Network: to find the user's own computer with Bonjour (_webcamlr._tcp) and send it the video directly. Nothing goes to the internet or to our servers.
- Camera: to capture the video sent to the computer, and to scan the computer's QR code for pairing.
- Microphone: asked only when the user turns on the phone microphone; the audio goes to the same computer.
Video, audio and controls are end-to-end encrypted with CryptoKit (ECDH P-256, AES-GCM). The app collects no data and has no account.

In-app purchase: WebcamLR Pro (it.lrapps.webcamlr.pro), non-consumable. Tap (i) at the top right › WebcamLR Pro › Unlock Pro; "Restore Purchases" is on the same page. The free version is fully usable (720p at 30 fps, no watermark). Pro also unlocks matching features in the free computer app while this iPhone is connected; nothing is sold on the computer.
```
Conteggio: 2228/4000 caratteri

Prima di inviare: sostituire `[VIDEO LINK]` e controllare che i due link di download scarichino davvero i file (problema M).

### 3.2 Motivi di rifiuto tipici e come li evitiamo

| Linea guida | Rischio per WebcamLR | Cosa fa il materiale |
| --- | --- | --- |
| **2.1 Completezza** | Il revisore non ha il programma sul computer e vede solo «Cerco il tuo computer…»; link di download o privacy non funzionanti; testi provvisori | Video dimostrativo allegato e link nelle note; dmg notarizzato già su GitHub Releases; elenco di ciò che si prova senza computer; privacy senza «bozza» e senza segnaposto prima dell'invio |
| **2.1(b) Acquisti visibili** | Il revisore non trova l'acquisto | Percorso esatto (ⓘ › WebcamLR Pro) nelle note dell'app e dell'acquisto; primo acquisto inviato **insieme** alla versione |
| **2.3.7 / 2.3.10 Metadati** | Prezzi negli screenshot o nell'anteprima; «Android» nei testi o nell'app; marchi di app di chiamata nelle parole chiave | Didascalie senza prezzi; la pagina Pro negli screenshot è mostrata con «Pro attivo» (senza prezzo); niente Android nei metadati; resta il problema G nell'app |
| **3.1.1 Acquisti in-app** | Sblocco di funzioni con un meccanismo nostro | Lo sblocco è solo StoreKit; il computer non vende nulla e non accetta codici: legge `capacita.pro` dal telefono. Vedere un acquisto iOS anche sul computer è ammesso (3.1.3(b), il contrario non c'è) |
| **4.2 Funzionalità minima** | «App che da sola non fa nulla» | L'app fa il lavoro vero (cattura, codifica hardware, effetti, cifratura, collegamento USB/Wi-Fi, diagnosi); il video lo mostra; le note spiegano il ruolo dell'app per computer, come per gli accessori |
| **5.1.1 Permessi** | Testi poco chiari; microfono chiesto senza motivo | Microfono chiesto solo quando lo si accende (`CodificatoreAudio.swift`, `MicrofonoPermesso.chiedi`); fotocamera al primo «In onda» o QR (`Cattura.chiediPermesso`); testi migliorati proposti qui sotto |
| **5.1.2 / Privacy** | Privacy policy che non corrisponde all'etichetta | Etichetta «Nessun dato raccolto» uguale a manifesto, codice e privacy del sito |

### 3.3 Video dimostrativo per il revisore (non è l'anteprima dello store)

Da 1 a 2 minuti, ripreso con un altro telefono (qui si possono vedere mani e computer), più una registrazione dello schermo
dell'iPhone se serve. Senza montaggio elaborato, con didascalie in inglese:
1. Mac con WebcamLR aperto (finestra con il QR in basso a sinistra).
2. iPhone: apertura di WebcamLR, richiesta «Rete locale» e «Fotocamera» con i testi visibili.
3. Il Mac compare sull'iPhone; tocco; sul Mac «Consentire…?» con le 4 cifre; video sul Mac, «IN ONDA» sull'iPhone.
4. FaceTime o Photo Booth sul Mac con la videocamera «WebcamLR».
5. Specchia e Sfoca sfondo dall'iPhone, che cambiano anche sul Mac.
6. Cavo USB attaccato: l'indicatore passa a «Cavo USB» senza che il video si fermi.
7. Sull'iPhone ⓘ › WebcamLR Pro › Sblocca Pro (sandbox) › «Pro attivo»; sul Mac la qualità 1080p non è più grigia.
8. «Ripristina acquisti».

### 3.4 Testi dei permessi: proposta (non modificati)

Oggi (`iPhone/project.yml` e `Risorse/*.lproj/InfoPlist.strings`):
- Fotocamera: «WebcamLR usa la fotocamera per inviare il video al tuo computer.» / «WebcamLR uses the camera to send video to your computer.»
- Microfono: «WebcamLR usa il microfono per inviare l'audio al tuo computer.» / «WebcamLR uses the microphone to send audio to your computer.»
- Rete locale: «WebcamLR cerca il tuo Mac o PC sulla stessa rete Wi-Fi.» / «WebcamLR looks for your Mac or PC on the same Wi-Fi network.»

Sono chiari, ma la fotocamera non cita il QR code e nessuno dice che il video non va su internet. Proposta (da cambiare in tutti e
tre i posti: `project.yml`, `it.lproj`, `en.lproj`):

| Chiave | Italiano | English |
| --- | --- | --- |
| `NSCameraUsageDescription` | La fotocamera riprende il video che WebcamLR manda al tuo Mac o PC, per usarlo come webcam, e legge il QR code del computer. | The camera captures the video WebcamLR sends to your Mac or PC to use as a webcam, and scans the computer's QR code. |
| `NSMicrophoneUsageDescription` | Il microfono si usa solo se lo accendi: la tua voce arriva al Mac o al PC, per esempio in una videochiamata. | The microphone is used only if you turn it on: your voice reaches your Mac or PC, for example in a video call. |
| `NSLocalNetworkUsageDescription` | WebcamLR cerca il tuo Mac o PC sulla stessa rete Wi-Fi e gli manda il video direttamente, senza passare da internet. | WebcamLR finds your Mac or PC on the same Wi-Fi network and sends it the video directly, without going over the internet. |

Su Android i permessi non hanno un testo di sistema; le spiegazioni prima della richiesta sono già nell'app.

---

## 4. Google Play

Nome del pacchetto `it.lrapps.webcamlr.android`. Lingua predefinita **Italiano (it-IT)**, traduzione **Inglese (en-US)**.

### 4.1 Scheda dello store

**Titolo · italiano** <!-- campo gp.titolo.it max=30 -->
```text
WebcamLR: webcam per Mac e PC
```
Conteggio: 29/30 caratteri

**Title · English** <!-- campo gp.titolo.en max=30 -->
```text
WebcamLR: Webcam for Mac & PC
```
Conteggio: 29/30 caratteri

**Descrizione breve · italiano** <!-- campo gp.breve.it max=80 -->
```text
Il telefono come webcam per Mac e PC, con cavo USB o Wi-Fi. Senza filigrana.
```
Conteggio: 76/80 caratteri

**Short description · English** <!-- campo gp.breve.en max=80 -->
```text
Your phone as a webcam for Mac and PC, over USB or Wi-Fi. No watermark.
```
Conteggio: 71/80 caratteri

**Descrizione completa · italiano** <!-- campo gp.descrizione.it max=4000 -->
```text
WebcamLR trasforma il telefono Android nella webcam del Mac o del PC. Videochiamate, lezioni e dirette prendono il video dalla fotocamera del telefono, con più dettaglio della webcam del portatile.

COME FUNZIONA
1. Installa WebcamLR sul computer: è gratuita, dal sito lr-apps609.github.io/WebcamLR (Mac con macOS 14 o successivo, PC con Windows 10 o 11 a 64 bit).
2. Apri WebcamLR sul telefono. Sulla stessa rete il computer compare da solo; altrimenti inquadri il QR code del computer.
3. Il video arriva nella finestra di WebcamLR e, tramite la webcam virtuale «WebcamLR», nelle app di videochiamata e di diretta.

COLLEGAMENTO
• Wi-Fi, hotspot del telefono o cavo USB con il «Tethering USB» del telefono (su Windows; sul Mac solo con alcuni telefoni). Non serve la modalità sviluppatore.
• Se il collegamento in uso si stacca, WebcamLR passa all'altro senza fermare il video.
• Sempre visibile: la strada in uso, la latenza e la qualità in parole («Ottimo», «Buono», «Debole»).
• Quando qualcosa non va, l'app dice la causa probabile e cosa fare.
• Il video continua anche a schermo spento: lo dice l'avviso fisso «WebcamLR · video al computer», con «Scollega».

IL TUO VIDEO RESTA TUO
• Video, audio e comandi vanno dal telefono al tuo computer, sulla tua rete o sul cavo, cifrati con chiavi nuove a ogni collegamento. Non passano da nostri server.
• Un computer nuovo si abbina con il suo QR code o con un codice di 4 cifre da confermare.
• Nessun account, nessuna pubblicità.

GRATIS, PER SEMPRE
• Video fino a 720p a 30 fps, senza filigrana.
• Specchia, sfondo sfocato e luce sul volto.
• Zoom, obiettivi, torcia ed esposizione, anche dal computer.
• Microfono del telefono sul computer: sul Mac compare come «WebcamLR (microphone)»; su Windows passa da un cavo audio virtuale gratuito, da installare a parte.
• Telefono a faccia in giù: il video va in pausa. Se il telefono scalda, la qualità scende a gradini.

WEBCAMLR PRO: UN ACQUISTO, SENZA ABBONAMENTO
• 1080p, 4K a 30 fps e 60 fps, dove il telefono ci arriva.
• Effetti: filtri di colore e regolazioni, sfondo sostituito con un'immagine, ritocco leggero della pelle, scritta con nome e ruolo, il tuo logo.
• Inquadratura automatica.
• Controlli Pro: ISO, tempo, bilanciamento del bianco e messa a fuoco.
• Sul computer: profili Riunione, Lezione, Diretta e Colloquio (e i tuoi), foto e registrazione, un secondo telefono come seconda inquadratura, schermata d'attesa personalizzata.
Si compra una volta con Google Play e sblocca anche il computer collegato a questo telefono: sul Mac e su Windows non c'è niente da comprare. «Ripristina acquisti» è nella pagina WebcamLR Pro.

COSA SERVE
• Un telefono con Android 8 o successivo.
• WebcamLR sul Mac o sul PC, gratuita dal sito.

WebcamLR è in italiano e in inglese.
Aiuto: lr-apps609.github.io/WebcamLR/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/privacy.html
```
Conteggio: 2879/4000 caratteri

**Full description · English** <!-- campo gp.descrizione.en max=4000 -->
```text
WebcamLR turns your Android phone into the webcam for your Mac or PC. Video calls, lessons and live streams take the video from the phone's camera, with more detail than the laptop's webcam.

HOW IT WORKS
1. Install WebcamLR on the computer: it's free, from lr-apps609.github.io/WebcamLR (Mac with macOS 14 or later, PC with 64-bit Windows 10 or 11).
2. Open WebcamLR on the phone. On the same network the computer shows up by itself; otherwise scan the computer's QR code.
3. The video arrives in the WebcamLR window and, through the "WebcamLR" virtual webcam, in your video call and streaming apps.

CONNECTION
• Wi-Fi, the phone's hotspot or a USB cable with the phone's "USB tethering" (on Windows; on the Mac only with some phones). No developer mode needed.
• If the connection in use drops, WebcamLR switches to the other one without stopping the video.
• Always in view: the connection in use, the latency and the quality in words ("Excellent", "Good", "Weak").
• When something's wrong, the app tells you the likely cause and what to do.
• The video keeps going with the screen off: the ongoing notification "WebcamLR · video to computer" says so, with "Disconnect".

YOUR VIDEO STAYS YOURS
• Video, audio and controls go from the phone to your computer, over your network or the cable, encrypted with new keys for every connection. They don't pass through our servers.
• A new computer is paired with its QR code or with a 4-digit code you confirm.
• No account, no ads.

FREE, FOREVER
• Video up to 720p at 30 fps, with no watermark.
• Mirror, background blur and face lighting.
• Zoom, lenses, flashlight and exposure, from the computer too.
• The phone's microphone on the computer: on the Mac it shows up as "WebcamLR (microphone)"; on Windows it goes through a free virtual audio cable, installed separately.
• Phone face down: the video pauses. If the phone gets hot, quality steps down gradually.

WEBCAMLR PRO: ONE PURCHASE, NO SUBSCRIPTION
• 1080p, 4K at 30 fps and 60 fps, where the phone supports it.
• Effects: colour filters and adjustments, background replaced with an image, light skin smoothing, a caption with your name and role, your logo.
• Auto framing.
• Pro controls: ISO, shutter, white balance and focus.
• On the computer: Meeting, Lesson, Live stream and Interview profiles (and your own), photos and recording, a second phone as a second angle, a custom waiting screen.
Buy it once with Google Play; it unlocks the computer connected to this phone too: there's nothing to buy on the Mac or on Windows. "Restore purchases" is on the WebcamLR Pro page.

WHAT YOU NEED
• A phone with Android 8 or later.
• WebcamLR on your Mac or PC, free from the website.

WebcamLR is in English and Italian.
Help: lr-apps609.github.io/WebcamLR/en/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/en/privacy.html
```
Conteggio: 2831/4000 caratteri

Nota: il testo inglese dell'avviso («WebcamLR · video to computer», «Disconnect») va controllato contro
`Android/app/src/main/res/values-en/strings.xml` (`avviso_titolo`, `scollega`) prima di pubblicare.

**Novità di questa versione · italiano** <!-- campo gp.novita.it max=500 -->
```text
Prima versione pubblica: il telefono come webcam per Mac e PC, con Wi-Fi, hotspot o cavo USB (tethering). Gratis fino a 720p a 30 fps senza filigrana; WebcamLR Pro con un acquisto unico.
```
Conteggio: 186/500 caratteri

**Release notes · English** <!-- campo gp.novita.en max=500 -->
```text
First public version: your phone as a webcam for Mac and PC, over Wi-Fi, hotspot or USB cable (tethering). Free up to 720p at 30 fps with no watermark; WebcamLR Pro with a one-time purchase.
```
Conteggio: 190/500 caratteri

- **Categoria**: tipo **App**, categoria **Fotografia** (Photography), come «Foto e video» su Apple. Alternativa: Strumenti.
- **Tag** (fino a 5, solo dall'elenco di Play Console › Presenza nello store › Tag): scegliere quelli più vicini a fotocamera,
  videochiamate, streaming video, riunioni e produttività, secondo i nomi esatti che Play Console propone.
- **Dettagli di contatto**: [EMAIL ASSISTENZA] (obbligatoria), sito `https://lr-apps609.github.io/WebcamLR/`; telefono facoltativo.
- **Norme sulla privacy**: `https://lr-apps609.github.io/WebcamLR/privacy.html` (da completare, problema M; e da allineare alla
  scelta su MediaPipe, sezione 4.4).

### 4.2 Classificazione dei contenuti (IARC)

Email per il certificato IARC: [EMAIL ASSISTENZA]. Categoria: **Tutte le altre tipologie di app** (utilità, produttività,
comunicazione o altro: non è un gioco).

| Domanda | Risposta |
| --- | --- |
| Violenza, paura, sessualità, linguaggio volgare, sostanze, umorismo crudo | **No** a tutto |
| Gioco d'azzardo con denaro reale o simulato | **No** |
| Gli utenti possono interagire o scambiarsi contenuti con altri utenti? | **No**: il video va solo al computer di chi lo riprende, abbinato con QR o codice; nessuno scambio tra persone |
| L'app condivide la posizione dell'utente con altri utenti? | **No** |
| Acquisti di beni digitali? | **Sì** (WebcamLR Pro) |
| Accesso libero a internet / browser nell'app? | **No** (i link aprono il browser di sistema) |
| L'app è un browser o un motore di ricerca? | **No** |

Risultato atteso: PEGI 3, ESRB Everyone (E), USK 0, con l'indicazione «Acquisti in-app».

### 4.3 Pubblico di destinazione e altri moduli di «Contenuti dell'app»

- **Fasce d'età**: **13–15, 16–17, 18 e oltre** (studenti e lavoratori). **Non** selezionare fasce sotto i 13 anni: farebbe
  entrare l'app nelle norme Famiglie, con requisiti su ogni libreria (MediaPipe compresa).
- **L'app potrebbe attirare involontariamente i bambini?** **No** (nessun personaggio, gioco o contenuto per bambini).
- **Annunci**: **No, la mia app non contiene annunci**.
- **Accesso all'app**: «Tutte le funzionalità sono disponibili senza restrizioni di accesso», con le istruzioni della sezione 4.7
  (non c'è login, ma serve l'app per computer).
- **App governativa, funzioni finanziarie, salute, notizie, VPN**: tutto **No**.
- **Eliminazione dell'account**: non applicabile (nessun account).

### 4.4 Sicurezza dei dati

Regole di Google usate: è «raccolta» la trasmissione di dati fuori dal dispositivo; contano anche i dati raccolti dalle librerie
incluse (SDK), anche se vanno direttamente a un server di terzi; **non** vanno dichiarati i dati cifrati end-to-end (leggibili solo
da mittente e destinatario) né quelli trattati solo sul dispositivo.

Cosa fa l'app Android, controllato nel codice:

| Dato | Dove va | Va dichiarato? |
| --- | --- | --- |
| Video, audio, comandi, modello e nome del telefono, batteria e temperatura | Solo al computer dell'utente, sulla rete locale o sul cavo, cifrati end-to-end (ECDH P-256, AES-GCM, chiavi solo sui due dispositivi; nessun nostro server) | **No** (eccezione end-to-end) |
| Foto per sfondo o logo | `GetContent` di sistema, nessun permesso di lettura dei file; resta sul telefono | **No** |
| Lettura del QR | ZXing sul telefono, senza rete | **No** |
| Acquisto di WebcamLR Pro | Lo gestisce Google Play; token e numero d'ordine restano sul telefono, l'app non li manda a nessuno | **No** dati raccolti dall'app (da ricontrollare con la pagina dati della Play Billing Library prima dell'invio: non sono riuscito ad aprirla da qui) |
| «Segnala un bug» | Prepara un testo (con modello del telefono, se l'utente lo lascia) e lo passa all'app di posta o di condivisione scelta dall'utente | **No** come raccolta automatica; se Ledion preferisce la prudenza: «Diagnostica», facoltativa, solo per «Assistenza» |
| **Statistiche di MediaPipe** | La libreria degli effetti (`tasks-vision`, con `tasks-core` e il trasporto di log di Google) manda a Google metriche su prestazioni e uso delle sue API | **Sì**, finché la libreria resta così (problema A) |

**Scelta di Ledion (problema A):**

**Scenario 1, consigliato: togliere la telemetria e rispondere «nessun dato».** In un round Android: provare a escludere il
trasporto dei log (`exclude(group = "com.google.android.datatransport")` sulla dipendenza di MediaPipe) e verificare sul telefono
che gli effetti funzionino ancora e che non ci siano connessioni verso server Google mentre gli effetti sono accesi (per esempio con
il registro di rete di Android Studio). Se l'esclusione rompe MediaPipe, l'alternativa è compilare l'AAR di MediaPipe dal sorgente
senza `ENABLE_TASKS_USAGE_LOGGING` (più lavoro). Risposte del modulo, poi:
- La tua app raccoglie o condivide uno dei tipi di dati utente richiesti? **No.**
- (Il resto del modulo non si apre.)

**Scenario 2: tenere MediaPipe com'è e dichiararlo.** Risposte:
- Raccoglie o condivide dati? **Sì.**
- Tutti i dati raccolti sono criptati in transito? **Sì** (da confermare: il trasporto di Google usa HTTPS).
- Fornite agli utenti un modo per richiedere l'eliminazione dei dati? **No** (non li riceviamo noi).
- Tipo di dati: **Informazioni e prestazioni dell'app › Diagnostica** (e, se Google lo indica per MediaPipe, **Altri dati sulle
  prestazioni dell'app**). Raccolti: **Sì**. Condivisi: **Sì** per prudenza (Google li usa anche per migliorare MediaPipe, non solo
  per nostro conto). Trattati in modo temporaneo: **No**. Obbligatori (non facoltativi). Finalità: **Analisi**.
- In più: correggere `privacy.html` e `en/privacy.html` (oggi dicono «nessuno strumento di tracciamento» e «le app usano internet
  per una cosa sola») con una frase su MediaPipe su Android, e chiedere il consenso se un consulente lo ritiene necessario (lo
  chiede la documentazione di MediaPipe).

In entrambi i casi: nessun dato condiviso per pubblicità, nessun ID pubblicitario (l'app non dichiara `AD_ID`: verificare che il
manifest unito dalla build non lo aggiunga), nessuna posizione, nessun contatto.

### 4.5 Servizio in primo piano (Contenuti dell'app › Autorizzazioni per i servizi in primo piano)

Nel codice: `ServizioInOnda`, `android:foregroundServiceType="camera|microphone"`, permessi `FOREGROUND_SERVICE_CAMERA` e
`FOREGROUND_SERVICE_MICROPHONE`. Si avvia solo con l'app in primo piano, quando parte il video; il tipo **microfono** si aggiunge solo
se il permesso del microfono è già concesso (`ServizioInOnda.tipi`). Avviso fisso «WebcamLR · video al computer» con «Scollega».
Va dichiarato **ogni tipo**: **Fotocamera** e **Microfono**.

**Descrizione della funzione (camera)**, in inglese:
```text
WebcamLR turns the phone into a webcam for the user's own computer (Mac or Windows). While the user is in a video call on the computer, the phone keeps capturing and sending the camera video to that computer. The user often turns the phone screen off or switches to another app on the phone during a long call; the camera foreground service keeps the video going and shows an ongoing notification "WebcamLR · video to computer" with a "Disconnect" button. It starts only after the user connects to a computer from the app, and stops when they disconnect.
```
**Impatto se il sistema interrompe o rimanda**: «The video in the user's ongoing call freezes or the call app shows no camera:
the task cannot be deferred, it is a live video stream.»

**Descrizione della funzione (microphone)**:
```text
When the user turns on the phone microphone in WebcamLR, the phone's audio is sent to the user's own computer together with the video, as the microphone for their video call. The microphone foreground service keeps the audio going with the screen off, under the same ongoing notification. It is added only after the user grants the microphone permission and turns the microphone on.
```

**Caso d'uso**: tra le opzioni di Play Console scegliere quella più vicina a videochiamata / streaming della fotocamera in tempo
reale verso un altro dispositivo; se non c'è, «Altro» con il testo sopra.

**Video** (link YouTube non in elenco, 30–60 s, uno solo per i due tipi va bene se li mostra entrambi):
1. Apertura di WebcamLR sul telefono, collegamento al PC, video nella finestra di WebcamLR sul PC.
2. Microfono acceso dal pulsante tondo; il livello dell'audio si muove sul PC.
3. Pulsante Home o blocco dello schermo: il video **continua** sul PC; tendina delle notifiche aperta con «WebcamLR · video al
   computer».
4. «Scollega» dall'avviso: il video si ferma sul PC e l'avviso sparisce.

### 4.6 Prodotto in-app

- Tipo: **prodotto a pagamento unico** (one-time product, non consumabile: l'app lo conferma con `acknowledgePurchase` e non lo
  consuma).
- **ID prodotto `it.lrapps.webcamlr.pro`**, verificato in `Android/app/src/main/kotlin/it/lrapps/webcamlr/android/acquisti/NegozioPro.kt`
  (`ID_PRODOTTO`), uguale all'iPhone. Non si cambia più dopo la creazione.
- Nome e descrizione: gli stessi della sezione 1.6 (stanno nei limiti di Play, che sono più larghi).
- Prezzo: **14,99 €**, Italia come riferimento; prezzo di lancio **9,99 €** con un'offerta a tempo sul prodotto (o un cambio di
  prezzo con data, secondo ciò che Play Console offre oggi per i prodotti a pagamento unico). Raccolta famiglia: attivabile.
- Serve il **profilo pagamenti** (account commerciante) collegato a Play Console, e l'acquisto si prova solo con un'app caricata
  almeno in un canale di test e con i **tester delle licenze** (Impostazioni › Test delle licenze).

### 4.7 Istruzioni di accesso per la revisione (Accesso all'app)

```text
No login or account. The app's main feature needs the free companion app on a computer on the same Wi-Fi network:
Windows 10/11: https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR-Setup.exe
macOS 14+: https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR.dmg
Open WebcamLR on both; the computer appears on the phone (or scan the QR code at the bottom left of the computer window) and the video shows on the computer. Without a computer you can review the tour, the help after 15 seconds of searching, settings, FAQ and the WebcamLR Pro page (Info button › WebcamLR Pro). Demo video: https://[VIDEO LINK]
```

### 4.8 Test chiuso: 12 tester per 14 giorni

- **Vale ancora** (ottobre 2026) per gli **account sviluppatore personali creati dopo il 13 novembre 2023**: prima della produzione
  serve un test chiuso con **almeno 12 tester** iscritti **per 14 giorni di fila**; la produzione si sblocca da Play Console ›
  Dashboard, dopo aver risposto a poche domande sul test. Gli account **organizzazione** ne sono esenti (ma richiedono il D-U-N-S).
  All'inizio erano 20 tester; Google li ha ridotti a 12. Fonti: articoli del 2026 (la pagina di aiuto di Google non era raggiungibile
  da qui): Ledion lo vede comunque nella Dashboard del suo account.
- Cosa fare: aprire il test chiuso **appena** l'AAB è caricabile (problemi B–E risolti), con un gruppo Google o un elenco di email;
  chiedere ai tester di installare **dal link di Play** e di usare l'app davvero nei 14 giorni (Google chiede che cosa è stato
  provato). Se i tester scendono sotto 12, il conteggio può ripartire.

---

## 5. Screenshot

Regola comune: immagini vere delle app (dopo le prove), didascalia breve **sopra** l'immagine nel carattere Barlow Condensed su
fondo verde scuro (`#30453E → #0D1B18`), testo quasi bianco, niente prezzi, niente «gratis» in grande, niente «n. 1» o inviti
«Scarica ora», niente loghi di app di terzi nello schermo del computer (in una chiamata di prova usare la finestra di WebcamLR o
FaceTime/Photo Booth sul Mac). Nome del telefono finto («iPhone di Anna»), nessun dato personale.

### 5.1 App Store (iPhone)

Formati (pagina *Screenshot specifications* di Apple, letta oggi):
- **Obbligatorio**: almeno uno per **iPhone con Dynamic Island, schermo medio**: **1206 × 2622** (iPhone 17, 17 Pro) o 1179 × 2556.
- **Consigliato insieme**: **iPhone con Dynamic Island, schermo grande** («6,9"»): **1320 × 2868** (iPhone 17 Pro Max), o 1290 × 2796 /
  1260 × 2736. Gli altri formati Apple li ricava riducendo.
- Da 1 a 10 per formato, PNG o JPEG, **senza trasparenza**. Verticale.
- Si possono fare dal Simulatore di Xcode (iPhone 17 Pro Max e iPhone 17) o da un iPhone vero.

| # | Schermata dell'app | Cosa inquadra | Didascalia IT | Caption EN |
| --- | --- | --- | --- | --- |
| 1 | «In onda», verticale | Video della fotocamera, «IN ONDA», colonna di pulsanti tondi (Specchia, Sfoca sfondo, Microfono, Pausa, Luce), riga «Wi-Fi · Ottimo» | Il telefono diventa la webcam del computer | Your phone becomes your computer's webcam |
| 2 | Ricerca del computer | «Cerco il tuo computer…» → elenco con «MacBook di Anna» e il pulsante per il QR | Si collega da solo, o con il QR code | Connects by itself, or with a QR code |
| 3 | «In onda» con il cavo | Indicatore «Cavo USB · 9 ms» nella riga di stato | Cavo USB o Wi-Fi, senza fermare il video | USB cable or Wi-Fi, without stopping the video |
| 4 | Effetti | Sfondo sfocato acceso, filtri con il segno «PRO» | Sfondo sfocato, filtri e ritocco | Background blur, filters and retouch |
| 5 | Volto + scrivania | Vista doppia (volto e scrivania raddrizzata) | Volto e scrivania nello stesso video | Your face and your desk in one video |
| 6 | Prova la webcam | Il controllo con luce, volto al centro, distanza, telefono dritto | Luce e inquadratura giuste in cinque secondi | Light and framing checked in five seconds |
| 7 | Aiuto dopo 15 secondi | I tre controlli (app aperta, stessa rete, «Rete locale») e «Prova con il cavo USB» | Se qualcosa non va, ti dice cosa fare | If something's wrong, it tells you what to do |
| 8 | Pagina WebcamLR Pro, **con «Pro attivo»** (così non si vede il prezzo) | Segno PRO e confronto Gratis/Pro | Pro: un acquisto, senza abbonamento | Pro: one purchase, no subscription |

Facoltativo, con un po' di rischio: uno screenshot «composto» con la finestra del Mac accanto al telefono. Apple vuole che gli
screenshot mostrino l'app in uso; il computer come sfondo è comune nelle app compagne, ma tenerlo piccolo e mai al posto dell'app.

### 5.2 Google Play (telefono)

Formati: PNG o JPEG a 24 bit, **da 2 a 8** per tipo di dispositivo, lato tra 320 e 3840 px, il lato lungo **non più del doppio**
del corto (attenzione: lo screenshot grezzo di un telefono moderno, 1080 × 2400, supera il rapporto 2:1 e va ritagliato o
composto). Usare **1080 × 1920** (9:16); almeno 4 a 1080 px o più per poter comparire nei consigli di Play.

| # | Schermata | Cosa inquadra | Didascalia IT | Caption EN |
| --- | --- | --- | --- | --- |
| 1 | «In onda», verticale | Come iPhone n. 1 | Il telefono diventa la webcam del computer | Your phone becomes your computer's webcam |
| 2 | Ricerca del computer / lettore QR | Computer trovato o QR inquadrato | Si collega da solo, o con il QR code | Connects by itself, or with a QR code |
| 3 | «In onda» con «Tethering USB» | Indicatore del collegamento via cavo | Wi-Fi, hotspot o cavo USB | Wi-Fi, hotspot or USB cable |
| 4 | Tendina delle notifiche | Avviso «WebcamLR · video al computer» con «Scollega» | Il video continua a schermo spento | The video keeps going with the screen off |
| 5 | Effetti | Sfondo sfocato, filtri con «PRO» | Sfondo sfocato, filtri e ritocco | Background blur, filters and retouch |
| 6 | Aiuto dopo 15 secondi | I tre controlli e il cavo | Se qualcosa non va, ti dice cosa fare | If something's wrong, it tells you what to do |
| 7 | Pagina WebcamLR Pro con «Pro attivo» | Confronto Gratis/Pro **senza** le righe del problema F | Pro: un acquisto, senza abbonamento | Pro: one purchase, no subscription |
| 8 | (facoltativo) Finestra di WebcamLR su Windows con il video del telefono | QR in basso a sinistra, barra Specchia · Sfoca · Foto · Registra | Il video arriva su Mac e Windows | The video arrives on Mac and Windows |

**Grafica in primo piano** (obbligatoria): **1024 × 500**, JPEG o PNG a 24 bit senza trasparenza. Fondo con la sfumatura del logo,
a sinistra il logo LR e «WebcamLR» in Barlow Condensed, sotto «Il telefono come webcam» (EN: «Your phone as a webcam»); a destra il
disegno di un telefono su un supporto rivolto verso un portatile, nello stile dei disegni del sito. Testo importante lontano dai
bordi (Play può ritagliarla), niente prezzi, niente inviti all'azione. Serve anche come copertina del video.

**Icona Play**: 512 × 512 PNG a 32 bit, dall'icona dell'app (`Strumenti/genera_icone.py`).

---

## 6. Video

### 6.1 Anteprima App Store (15–30 s)

Requisiti (pagine *App preview specifications* e *App previews* di Apple, lette oggi):
- **Durata da 15 a 30 secondi**; fino a 3 anteprime per formato e lingua.
- Verticale **886 × 1920** (accettata per gli iPhone con Dynamic Island grandi e medi e Face ID grandi); massimo **30 fps**.
- H.264 (.mov, .m4v, .mp4) fino a High Profile 4.0, 10–12 Mbit/s, oppure ProRes 422 HQ; al massimo 500 MB.
- Audio stereo AAC 256 kbit/s, 44,1 o 48 kHz (anche solo musica); di base l'anteprima parte **senza audio**, quindi conta il testo.
- **Solo contenuto dell'app**: registrazione dello schermo dell'iPhone. **Niente persone che toccano lo schermo, niente riprese da
  sopra la spalla**, niente cornici di dispositivi (servono solo a imitare ciò che non è l'app), **niente prezzi**, niente date o
  riferimenti stagionali. Va detto se serve un acquisto: frase finale. Il **computer non può comparire** (non è l'app iPhone): il
  passaggio verso il computer si racconta con il testo.
- Fotogramma di copertina scelto a mano (schermata 1).

| Scena | Tempo | Cosa si vede (registrazione dello schermo, «Mostra tocchi» spento) | Testo a schermo IT | EN |
| --- | --- | --- | --- | --- |
| 1 | 0–4 s | Prima pagina della presentazione dell'app (iPhone sul supporto, videochiamata) | Il telefono diventa la webcam del computer | Your phone becomes your computer's webcam |
| 2 | 4–9 s | «Cerco il tuo computer…» → «MacBook di Anna» → tocco → «IN ONDA» | Si collega da solo | Connects by itself |
| 3 | 9–14 s | «In onda»: Specchia e Sfoca sfondo si accendono | Specchia e sfondo sfocato con un tocco | Mirror and background blur in one tap |
| 4 | 14–19 s | La riga di stato passa da «Wi-Fi» a «Cavo USB · 9 ms», il video non si ferma | Cavo o Wi-Fi, il video non si ferma | Cable or Wi-Fi, the video doesn't stop |
| 5 | 19–25 s | Effetti con filtri e «Volto + scrivania» (segno PRO visibile) | Effetti e 4K con WebcamLR Pro | Effects and 4K with WebcamLR Pro |
| 6 | 25–30 s | Ritorno a «In onda» pulito | Serve WebcamLR sul Mac o sul PC, gratis dal sito. Pro: acquisto in-app | Needs WebcamLR on your Mac or PC, free from the website. Pro: in-app purchase |

Una versione per lingua (le schermate dell'app in italiano per l'anteprima italiana, in inglese per quella inglese). Musica solo se
con licenza valida per l'uso commerciale in tutti i paesi.

### 6.2 Google Play (YouTube, fino a 60 s)

Requisiti di Play (da ricontrollare in Play Console, le pagine di Google non erano raggiungibili da qui): link YouTube **pubblico o
non in elenco**, **senza annunci** (monetizzazione spenta), senza limite d'età, incorporamento permesso; la grafica in primo piano fa
da copertina. Orizzontale 16:9, 1920 × 1080. Qui si possono mostrare telefono **e** computer, ripresi dal vero.

| Scena | Tempo | Cosa si vede | Testo IT | EN |
| --- | --- | --- | --- | --- |
| 1 | 0–6 s | Portatile con la webcam integrata, immagine scura; accanto un telefono Android su un supporto | La webcam migliore che hai è già in tasca | The best webcam you own is already in your pocket |
| 2 | 6–14 s | Sul PC Windows si apre WebcamLR (QR in basso a sinistra); sul telefono si apre WebcamLR e trova il PC | Si collega da solo, o con il QR code | Connects by itself, or with a QR code |
| 3 | 14–22 s | Il video del telefono nella finestra di WebcamLR; poi in una chiamata di prova (webcam «WebcamLR» scelta nelle impostazioni video, logo dell'app di chiamata non in primo piano) | Nelle tue videochiamate, come una webcam | In your video calls, like a webcam |
| 4 | 22–30 s | Tocchi su Specchia e Sfoca sfondo dal telefono, cambiano sul PC; poi dal PC | Comandi dal telefono o dal computer | Control it from the phone or the computer |
| 5 | 30–38 s | Cavo USB collegato, «Tethering USB»; l'indicatore cambia senza fermare il video | Wi-Fi, hotspot o cavo USB | Wi-Fi, hotspot or USB cable |
| 6 | 38–46 s | Schermo del telefono spento, il video continua; avviso fisso nella tendina | Il video continua a schermo spento | The video keeps going with the screen off |
| 7 | 46–54 s | Effetti e qualità 1080p/4K dal menu sul video (segno PRO) | Effetti, 1080p e 4K con WebcamLR Pro | Effects, 1080p and 4K with WebcamLR Pro |
| 8 | 54–60 s | Logo e indirizzo del sito | Gratis sul computer: lr-apps609.github.io/WebcamLR | Free on your computer: lr-apps609.github.io/WebcamLR |

Lo stesso montaggio, con il Mac al posto del PC e un iPhone, serve per il sito e per YouTube (non per l'anteprima App Store).

---

## 7. Pagina download e GitHub Releases: note di rilascio 1.0

Da incollare nella release `v1.0` (titolo «WebcamLR 1.0»). I file: `WebcamLR.dmg` (Mac, con «WebcamLR Microfono.pkg» dentro) e
`WebcamLR-Setup.exe` (Windows), con questi nomi fissi (link `releases/latest/download/…`, `Pubblicazione.md` sezioni 6 e 7).

**Italiano**

```markdown
## WebcamLR 1.0

La prima versione pubblica. WebcamLR trasforma il telefono (iPhone o Android) nella webcam del Mac o del PC, con il cavo USB,
il Wi-Fi o l'hotspot. L'app per computer è gratuita; l'app per il telefono è su App Store e Google Play.

### Mac · `WebcamLR.dmg`
- macOS 14 Sonoma o successivo.
- Apri il dmg e trascina WebcamLR in Applicazioni. Per usare il microfono del telefono apri anche «WebcamLR Microfono.pkg»
  (chiede la password del Mac): compare l'ingresso «WebcamLR (microphone)».
- Webcam virtuale: in WebcamLR premi «Attiva la webcam virtuale» e approvala in Impostazioni di Sistema (macOS 15 e successivi:
  Generali › Elementi di login ed estensioni › Estensioni videocamera; macOS 14: Privacy e sicurezza › Consenti). Poi chiudi e
  riapri le app di chiamata e scegli «WebcamLR».
- L'app è firmata e notarizzata da Apple: si apre senza avvisi (al massimo «scaricata da Internet, vuoi aprirla?» › Apri).

### Windows · `WebcamLR-Setup.exe`
- Windows 10 o 11 a 64 bit. L'installatore mette WebcamLR per il tuo utente e chiede **una volta** il permesso
  dell'amministratore per la webcam virtuale e per la regola del firewall (solo reti private). Se manca, scarica .NET 8 da Microsoft.
- Se Windows mostra «PC protetto da Windows»: **Ulteriori informazioni** › **Esegui comunque**. Nel browser, se Edge dice che il file
  «non viene scaricato comunemente»: **…** › **Mantieni** › **Mostra altro** › **Mantieni comunque**.
- Con l'iPhone e il cavo USB serve l'app gratuita «Dispositivi Apple» di Microsoft Store.
- Microfono del telefono: WebcamLR manda la voce a un cavo audio virtuale gratuito come VB-CABLE, da installare a parte;
  nell'app di chiamata scegli «CABLE Output» come microfono. Non c'è ancora un microfono «WebcamLR» nativo su Windows.

### Gratis e Pro
Gratis per sempre fino a 720p a 30 fps, senza filigrana. WebcamLR Pro (1080p, 4K, 60 fps, effetti, profili, registrazione, gobbo,
secondo telefono, schermata d'attesa personalizzata) si compra una volta sul telefono e sblocca anche il computer collegato:
sul computer non c'è niente da comprare.

Aiuto: https://lr-apps609.github.io/WebcamLR/aiuto.html · Privacy: https://lr-apps609.github.io/WebcamLR/privacy.html
```

**English**

```markdown
## WebcamLR 1.0

The first public version. WebcamLR turns your phone (iPhone or Android) into the webcam for your Mac or PC, over USB cable,
Wi-Fi or hotspot. The computer app is free; the phone app is on the App Store and Google Play.

### Mac · `WebcamLR.dmg`
- macOS 14 Sonoma or later.
- Open the dmg and drag WebcamLR to Applications. To use the phone's microphone, also open "WebcamLR Microfono.pkg" (it asks for
  your Mac password): the "WebcamLR (microphone)" input appears.
- Virtual webcam: in WebcamLR click "Turn on the virtual webcam" and approve it in System Settings (macOS 15 and later: General ›
  Login Items & Extensions › Camera Extensions; macOS 14: Privacy & Security › Allow). Then quit and reopen your call apps and
  choose "WebcamLR".
- The app is signed and notarized by Apple: it opens without warnings (at most "downloaded from the Internet, open it?" › Open).

### Windows · `WebcamLR-Setup.exe`
- 64-bit Windows 10 or 11. The installer sets up WebcamLR for your user and asks **once** for administrator permission for the
  virtual webcam and the firewall rule (private networks only). If .NET 8 is missing, it downloads it from Microsoft.
- If Windows shows "Windows protected your PC": **More info** › **Run anyway**. In the browser, if Edge says the file "isn't
  commonly downloaded": **…** › **Keep** › **Show more** › **Keep anyway**.
- With an iPhone and the USB cable you need the free "Apple Devices" app from the Microsoft Store.
- Phone microphone: WebcamLR sends your voice to a free virtual audio cable such as VB-CABLE, installed separately; in your call
  app choose "CABLE Output" as the microphone. There is no native "WebcamLR" microphone on Windows yet.

### Free and Pro
Free forever up to 720p at 30 fps, with no watermark. WebcamLR Pro (1080p, 4K, 60 fps, effects, profiles, recording,
teleprompter, second phone, custom waiting screen) is bought once on the phone and unlocks the connected computer too: there's
nothing to buy on the computer.

Help: https://lr-apps609.github.io/WebcamLR/en/aiuto.html · Privacy: https://lr-apps609.github.io/WebcamLR/en/privacy.html
```

Note per Ledion:
- Le etichette inglesi dei pulsanti e delle Impostazioni di Sistema vanno confrontate con l'app Mac inglese prima di pubblicare
  (per esempio il nome esatto di «Attiva la webcam virtuale»).
- **Se il dmg non fosse notarizzato** (solo per tester, mai per il pubblico), sostituire la riga sulla firma con: «Al primo avvio
  macOS lo blocca: premi Fine, poi Impostazioni di Sistema › Privacy e sicurezza › **Apri comunque** e conferma con la password. Su
  macOS 15 e successivi il clic destro › Apri non basta più.» Con l'Apple ID gratuito, comunque, la webcam virtuale non c'è:
  **per pubblicare il Mac serve l'account sviluppatore a pagamento** (Developer ID, notarizzazione, Camera Extension).
- **Windows non firmato**: le istruzioni SmartScreen sopra servono finché l'installatore non è firmato. Su alcuni Windows 11
  installati da zero **Smart App Control** blocca le app non firmate senza nessun pulsante per proseguire: va detto nella pagina di
  aiuto, e la firma (Azure Trusted Signing o certificato OV, `Pubblicazione.md` sezione 7) va avviata prima del lancio pubblico.
- `Sito/versione.json` (ramo `sito`) si aggiorna **dopo** aver pubblicato i file.

---

## 8. Lista di controllo «prima di premere Invia»

Legenda: **[pronto]** = è in questo documento o nella repository; **[Ledion]** = lo fa Ledion; **[round]** = serve un round di codice.

### Comuni
- [ ] **[Ledion]** Decidere titolare (persona o ditta), [EMAIL ASSISTENZA], telefono e indirizzo; dichiarazione di operatore
  commerciale UE su App Store Connect e indirizzo per Play (le app con acquisti mostrano l'indirizzo).
- [ ] **[Ledion]** Sito (ramo `sito`): privacy senza «bozza» e con titolare, email e data; link veri in `download.js` e
  `download.html`; frase «Non ancora pubblicata» aggiornata; repository o release **pubbliche**.
- [ ] **[Ledion]** GitHub Release `v1.0` con `WebcamLR.dmg` (notarizzato) e `WebcamLR-Setup.exe` e le note della sezione 7
  **[pronto]**; provare i due link `releases/latest/download/…` da un browser non collegato a GitHub.
- [ ] **[Ledion]** Screenshot (sezione 5) e i tre video (anteprima App Store, YouTube Play, video per i revisori) **[copioni pronti]**.
- [ ] **[round]** Problema H (prezzo nelle domande frequenti) e N (email nell'app).

### App Store
- [ ] **[Ledion]** Account sviluppatore a pagamento, contratti app gratuite e a pagamento, dati bancari e fiscali.
- [ ] **[round]** Problema G (Android e Google Play nell'app iPhone); facoltativo: testi dei permessi della sezione 3.4.
- [ ] **[Ledion]** Build provata in TestFlight, compresi acquisto, «Ripristina acquisti» e sblocco del Mac in sandbox.
- [ ] **[Ledion]** Riga 03 (Privacy Report) e sezione L2 di `Checklist iPhone e Mac.md` (`Pubblicazione.md`, «Obbligatori»).
- [ ] **[pronto]** Nome, sottotitolo, testo promozionale, descrizione, parole chiave IT/EN (sezione 1).
- [ ] **[pronto]** Categoria, età (4+), URL, copyright (sezione 1.5). **[Ledion]** inserirli.
- [ ] **[pronto]** Privacy dell'app: «Nessun dato raccolto» (sezione 2). **[Ledion]** inserirla.
- [ ] **[pronto]** Acquisto in-app: nome e descrizione nei limiti 30/45, note (sezione 1.6). **[Ledion]** crearlo, prezzo 14,99 € e
  cambio a tempo 9,99 €, In famiglia, screenshot della pagina Pro, e **selezionarlo nella versione** prima di «Aggiungi per la
  revisione».
- [ ] **[pronto]** Note per la revisione (sezione 3.1). **[Ledion]** link del video, contatti, allegato.
- [ ] **[Ledion]** Screenshot 1206 × 2622 (obbligatori) e 1320 × 2868; anteprima 886 × 1920.
- [ ] **[Ledion]** `ITSAppUsesNonExemptEncryption = NO` già nella build **[pronto]**: se App Store Connect chiede la cifratura,
  rispondere come in `Pubblicazione.md`.

### Google Play
- [ ] **[Ledion]** Account sviluppatore (personale o organizzazione), verifica dell'identità, profilo pagamenti.
- [ ] **[round]** Problemi B, C, D, E (target 36, Billing 8+, MediaPipe ≥ 0.10.26, chiave di caricamento e `versionName 1.0`) e F
  (righe Pro inesistenti su Android).
- [ ] **[Ledion]** Decisione su MediaPipe (problema A, sezione 4.4) e, con lo scenario 1, verifica sul telefono che non ci siano
  connessioni a Google.
- [ ] **[Ledion]** Test chiuso con 12 tester per 14 giorni (se l'account è personale e nuovo), poi richiesta di accesso alla produzione.
- [ ] **[pronto]** Titolo, descrizione breve e completa, novità IT/EN (sezione 4.1); categoria e tag.
- [ ] **[pronto]** IARC, pubblico di destinazione, annunci, accesso all'app (sezioni 4.2, 4.3, 4.7). **[Ledion]** compilarli.
- [ ] **[pronto]** Sicurezza dei dati, nei due scenari (sezione 4.4). **[Ledion]** compilare quello scelto.
- [ ] **[pronto]** Servizio in primo piano: testi (sezione 4.5). **[Ledion]** video su YouTube non in elenco.
- [ ] **[pronto]** Prodotto `it.lrapps.webcamlr.pro` (sezione 4.6). **[Ledion]** crearlo, prezzo, tester delle licenze.
- [ ] **[Ledion]** Grafica in primo piano 1024 × 500, icona 512 × 512, 4–8 screenshot 1080 × 1920, video YouTube.

---

## 9. Come sono stati contati i caratteri

Ogni campo con limite ha accanto un commento HTML invisibile con il suo nome e il limite (con `byte` per le parole chiave di Apple,
che Apple misura in byte). Lo script qui sotto legge il documento, prende il blocco di testo che segue ogni commento, conta i
caratteri (`len` del testo, a capo compresi) o i byte UTF-8, controlla il limite e riscrive la riga «Conteggio». Esce con errore se
un campo è troppo lungo. Al primo giro ha trovato tre campi oltre il limite (parole chiave IT 103 byte ed EN 101, descrizione
dell'acquisto IT 48 caratteri), poi accorciati. Dopo ogni modifica ai testi: salvarlo come `conta.py` fuori dalla repository e
lanciare `python3 conta.py "Documenti/Materiale store.md"`.

```python
import re, sys
p = sys.argv[1]
righe = open(p, encoding="utf-8").read().split("\n")
marcatore = re.compile(r"<!-- " + "campo" + r" (\S+) max=(\d+)( byte)? -->")
errori = 0
i = 0
while i < len(righe):
    m = marcatore.search(righe[i])
    if not m:
        i += 1
        continue
    nome, limite, byte = m.group(1), int(m.group(2)), bool(m.group(3))
    j = i + 1
    while not righe[j].lstrip().startswith("```"):
        j += 1
    rientro = len(righe[j]) - len(righe[j].lstrip())
    k = j + 1
    while not righe[k].lstrip().startswith("```"):
        k += 1
    testo = "\n".join(r[rientro:] for r in righe[j + 1:k])
    n = len(testo.encode("utf-8")) if byte else len(testo)
    unita = "byte" if byte else "caratteri"
    ok = n <= limite
    if not ok:
        errori += 1
    c = k + 1
    assert righe[c].lstrip().startswith("Conteggio:"), (nome, righe[c])
    righe[c] = " " * rientro + f"Conteggio: {n}/{limite} {unita}" + ("" if ok else " · TROPPO LUNGO")
    print(f"{nome:24} {n:5}/{limite} {unita} {'ok' if ok else 'TROPPO LUNGO'}")
    i = c + 1
open(p, "w", encoding="utf-8").write("\n".join(righe))
sys.exit(1 if errori else 0)
```

## Verifiche nel codice (26 ottobre, ramo `round-2`)

| Affermazione | Dove l'ho controllata |
| --- | --- |
| Gratis 720p a 30 fps senza filigrana; Pro sblocca 1080p, 4K, 60 fps, filtri, regolazioni, sfondo sostituito, ritocco, inquadratura, scritta, volto + scrivania, ISO, tempo, bianco | `iPhone/Sorgenti/NegozioPro.swift` (`LimitiGratis`), `Android/…/logica/LimitiGratis.kt`, `Stile/Sources/Stile/Pro.swift` (`ConfrontoPro.gratis`/`.pro`) |
| Sfondo sfocato, luce sul volto e microfono gratis | `ConfrontoPro.gratis`, `strings.xml` `pro_gratis_*` |
| 4K solo a 30 fps in HEVC, 60 fps fino a 1080p | `iPhone/Sorgenti/Cattura.swift` (`fpsMassimo4K`), `Codificatore.swift`, `Registro lavori.md` 25 ottobre |
| Webcam virtuale fino a 4K30 e 1080p60 su Mac e Windows | `Mac/FotocameraVirtuale/Fotocamera.swift`, `Windows/WebcamLR.Webcam.Logica/FormatiWebcam.cs` |
| Prodotto `it.lrapps.webcamlr.pro`, non consumabile, In famiglia, «Ripristina acquisti» | `Stile/…/Pro.swift`, `NegozioPro.swift`, `NegozioPro.kt`, `SchermataPro.swift` |
| Pagina Pro: ⓘ in alto a destra › WebcamLR Pro | `SchermataConnessione.swift` (pulsante `info.circle`), `SchermataApp.swift` |
| Permessi iPhone e momento della richiesta | `iPhone/project.yml`, `Risorse/*.lproj/InfoPlist.strings`, `Cattura.chiediPermesso`, `MicrofonoPermesso.chiedi` |
| Nessun dato raccolto su iPhone | `iPhone/Privacy/PrivacyInfo.xcprivacy`; nessun `URLSession` nell'app iPhone; foto con `PhotosPicker` |
| Servizio in primo piano camera + microfono | `AndroidManifest.xml`, `sessione/ServizioInOnda.kt` |
| Dipendenze Android: MediaPipe 0.10.14, Billing 7.1.1, ZXing; target 35 | `Android/app/build.gradle.kts` |
| Gobbo e volto + scrivania assenti su Android | nessun riferimento nel codice Kotlin (solo il campo `doppiaVista` filtrato in `LimitiGratis.kt`) |
| Profilo «Lingua dei segni» | **non** presente nel codice: non citato |
| Requisiti: iOS 17, macOS 14, Android 8 (minSdk 26), Windows 10/11 64 bit | `iPhone/project.yml`, `Mac/base.yml`, `Android/app/build.gradle.kts`, sito |

## Fonti (consultate il 26 ottobre 2026)

Apple:
- App Store Connect, *Screenshot specifications*: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/
- *App preview specifications*: https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/
- *App previews* (regole sul contenuto): https://developer.apple.com/app-store/app-previews/
- *Platform version information* (testo promozionale 170, descrizione 4000, parole chiave 100 byte, novità 4000): https://developer.apple.com/help/app-store-connect/reference/platform-version-information/
- *App information* (nome e sottotitolo 30, età, privacy): https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- *In-App Purchase information* (nome 30, descrizione 45, note 4000, screenshot): https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-information/
- *Age ratings*: https://developer.apple.com/help/app-store-connect/reference/age-ratings
- *App Review Guidelines* (2.1, 2.3.7, 2.3.10, 3.1.1, 3.1.3(b), 4.2, 5.1.1): https://developer.apple.com/app-store/review/guidelines/

Google (le pagine `support.google.com`, `developers.google.com` e `dl.google.com` non erano raggiungibili da questo ambiente: dati presi
da ricerche e da pagine che le citano; **da ricontrollare in Play Console**):
- Livello API 36 dal 31 agosto 2026, proroga al 1° novembre: https://developer.android.com/google/play/requirements/target-sdk
- Play Billing Library 7 non accettata dopo il 31 agosto 2026: https://developer.android.com/google/play/billing/deprecation-faq · https://www.revenuecat.com/blog/engineering/play-billing-8-migration
- Pagine da 16 KB: https://developer.android.com/guide/practices/page-sizes · MediaPipe e 16 KB: https://discuss.ai.google.dev/t/tflite-vision-task-library-is-not-16kb-compatible/102973
- Telemetria di MediaPipe Tasks: https://developers.google.com/edge/mediapipe/solutions/tasks (sezione sui dati inviati a Google) · dipendenze del pacchetto `tasks-core` (trasporto DataTransport CCT): https://www.nuget.org/packages/MediaPipeTasksCore.Android · sorgente con il registratore vuoto e l'opzione `ENABLE_TASKS_USAGE_LOGGING`: https://github.com/google-ai-edge/mediapipe/blob/master/mediapipe/tasks/java/com/google/mediapipe/tasks/core/BUILD
- Sicurezza dei dati, eccezione end-to-end e definizioni: https://support.google.com/googleplay/android-developer/answer/10787469 · https://support.google.com/googleplay/answer/11416267
- Servizi in primo piano e dichiarazione in Play Console: https://support.google.com/googleplay/android-developer/answer/13392821 · tipi di servizio: https://developer.android.com/develop/background-work/services/fgs/service-types
- Test chiuso 12 tester × 14 giorni: https://www.testerscommunity.com/blog/google-play-closed-testing-requirements-2026 · https://www.choicely.com/blog/google-play-12-tester-rule (pagina ufficiale: https://support.google.com/googleplay/android-developer/answer/14151465)
- Scheda dello store (descrizione breve 80, grafica 1024 × 500, screenshot): https://support.google.com/googleplay/android-developer/answer/9866151 · https://appradar.com/blog/android-app-screenshot-sizes-and-guidelines-for-google-play
