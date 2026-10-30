# Store · WebcamLR 1.0 RC

Materiale per gli store della **1.0 RC «Sito e store»** (Fase 6 della `Roadmap 1.0 beta.md`), scritto il 30 ottobre 2026 sul
ramo `store-rc` (da `beta4`, 842615b). Una sezione per ogni store: **App Store** (iPhone), **Mac** (Mac App Store o fuori
store), **Google Play** (Android), **Microsoft Store** o installatore dal sito (Windows).

Prende il posto dei testi di `Materiale store.md` (26 ottobre, prima delle beta 2–4): per i testi, i questionari e gli
screenshot **vale questo documento**. Restano validi in `Materiale store.md` i copioni dei video (sezione 6), le note di
rilascio di GitHub (sezione 7) e la lista «prima di premere Invia» (sezione 8); in `Pubblicazione.md` i passi tecnici.

**Regole seguite**
- Solo funzioni che il codice di `beta4` fa (controllate una per una: *Verifiche nel codice*, in fondo). Niente funzioni
  tolte (la «Prova la webcam» dell'iPhone è stata tolta in 49f78ea) né da fare (profilo «Lingua dei segni», audio nelle
  registrazioni, microfono «WebcamLR» nativo su Windows).
- Parole del `Glossario.md`: **telefono** (mai «smartphone»), **Frontale** (mai «Selfie»), **Collega / Scollega**, **In onda**,
  **codice di conferma**, **Hotspot personale**, **Rete locale**, **Segnala un bug**; la registrazione è sempre detta
  **senza audio**.
- Niente superlativi né confronti che non possiamo dimostrare («la migliore», «zero ritardo», «più nitida di…»), niente nomi
  di concorrenti né di app di terzi nei testi pubblici, niente prezzi nei testi (lo store mostra il prezzo da solo, anche
  quello di lancio). Nei testi Apple niente «Android» né «Google Play» (2.3.10); nei testi Play niente «iPhone».
- WebcamLR Pro è un **acquisto unico, non consumabile, senza abbonamento** (`it.lrapps.webcamlr.pro`). Nel Glossario la riga
  «Abbonamento → WebcamLR Pro» è fuorviante: vedi le incoerenze (I10).
- Ogni campo con un limite ha sotto la riga **Conteggio**, scritta dallo script `controlla_store.py` (sezione 5), che controlla
  anche le parole vietate. Le parole chiave di Apple si contano in **byte** UTF-8, tutto il resto in caratteri.
- Segnaposto da riempire: **[NOME TITOLARE]**, **[EMAIL ASSISTENZA]**, **[TELEFONO]**, **[INDIRIZZO]**, **[LINK VIDEO]**.

Indirizzi: sito `https://lr-apps609.github.io/WebcamLR/` · aiuto `…/aiuto.html` · privacy `…/privacy.html` (inglese
`…/en/privacy.html`) · download `…/download.html`.

---

## 0. Incoerenze trovate (codice, privacy, testi)

Controllate il 30 ottobre su `beta4` e su `main:Sito/privacy.html`. «Stato» dice se il problema c'era già il 26 ottobre in
`Materiale store.md` (lettere A–N) e se oggi è risolto.

| # | Cosa | Dove | Stato | Cosa fare |
| --- | --- | --- | --- | --- |
| I1 | **Android manda statistiche d'uso a Google tramite MediaPipe** (`tasks-vision` 0.10.14 con `tasks-core` e il trasporto di log di Google). La privacy del sito dice «nessuno strumento di tracciamento» e «le app usano internet per una cosa sola» | `Android/app/build.gradle.kts` riga 82; `privacy.html` «In breve» e «Cosa usano le app» | come A, **aperto** | Decisione di Ledion (sezione 3.9): togliere la telemetria (consigliato) o dichiararla nel modulo Play e nella privacy |
| I2 | **Windows: ONNX Runtime** (`Microsoft.ML.OnnxRuntime.DirectML` 1.24.4, effetti). Le build ufficiali per Windows hanno eventi di telemetria (TraceLogging) che seguono le impostazioni di diagnostica di Windows; nel codice non c'è `DisableTelemetryEvents()` | `Windows/WebcamLR.Effetti/*.csproj` | **nuovo**, da verificare | Un round Windows: chiamare `OrtEnv…DisableTelemetryEvents()` all'avvio degli effetti (una riga), poi la privacy resta vera |
| I3 | **Le immagini personali (sfondo e logo) non si scelgono più sul telefono**: arrivano dal computer (pacchetto di tipo 4) e restano nell'Application Support del telefono. La privacy dice «Foto (telefono): … solo se la scegli tu · Resta sul telefono»; `Materiale store.md` cita `PhotosPicker` e `GetContent`, che nel codice non ci sono più | `iPhone/Sorgenti/EffettiVisivi.swift` righe 15–16, 100–103; `privacy.html` tabella | **nuovo** | Privacy: riga «Immagine per sfondo o logo (computer → telefono): la scegli sul computer, va cifrata al telefono e resta lì». Nessun permesso Foto da chiedere (giusto così) |
| I4 | **«Segnala un bug» allega il registro del collegamento di serie** («Includi il registro…», acceso), e il registro contiene i **nomi dei computer** («Collegato a MacBook di Anna», «Trovato …»). La privacy dice «senza nomi di persone o computer»; i dati tecnici, invece, il nome lo tolgono davvero | `iPhone/Sorgenti/SessioneTelefono.swift` 1030, 1625; `CercaComputer.swift` 139; `Stile/…/VisteSezioneApp.swift` 64 | **nuovo** | O il registro sostituisce i nomi con «computer 1», o la privacy dice «il registro può contenere il nome dei tuoi computer». Per gli store non cambia nulla: lo manda l'utente, se vuole |
| I5 | **Permesso della fotocamera dell'iPhone**: non dice che serve anche a leggere il QR code del computer | `iPhone/project.yml` 74, `iPhone/Risorse/*.lproj/InfoPlist.strings` | come L, **aperto** | Testo nuovo nella sezione 1.11 (tre posti: `project.yml`, `it.lproj`, `en.lproj`) |
| I6 | **Permesso della fotocamera del Mac** (solo con l'account a pagamento): «WebcamLR passa il video **dell'iPhone** alla propria webcam virtuale», ma anche i telefoni Android si collegano al Mac | `Mac/project.yml` 15, `Mac/Risorse/*.lproj/InfoPlist.strings` | **nuovo** | «… il video **del telefono** …» / «… passes the **phone's** video …» (sezione 2.11) |
| I7 | **Il nome del microfono**: le app Mac dicono «WebcamLR (microphone)» anche in italiano; la privacy dice «WebcamLR (microfono)» | `Mac/Sorgenti/Impostazioni.swift`; `privacy.html` | già nell'audit, **aperto** | Privacy: «WebcamLR (microphone)», com'è il dispositivo |
| I8 | **L'app iPhone nomina Android e Google Play** (domande frequenti «cavo», «firewall», «costo»; guida «Se non si collega»; parola di ricerca «android») | `Stile/Sources/Stile/DomandeFrequenti.swift` 31, 45, 90, 110; `SezioneApp.swift` 69 | come G, **aperto** | Apple 2.3.10: rischio di rifiuto. Su iPhone mostrare le risposte senza la parte Android (filtro per piattaforma in Stile) |
| I9 | **Email di assistenza vuota** in tutte le app: «Segnala un bug» apre la condivisione invece della mail | `Stile/…/SezioneApp.swift` 7, Android `Contenuti.kt` 321 | come N, **aperto** | Scrivere [EMAIL ASSISTENZA] prima dell'invio (serve anche negli store) |
| I10 | **Glossario: «Abbonamento → WebcamLR Pro»**, mentre Pro è un acquisto unico e tutte le app dicono «senza abbonamento» | `Documenti/Glossario.md` | **nuovo** | Riga del Glossario: «Acquisto unico (non abbonamento) → WebcamLR Pro» |
| I11 | **Privacy ancora «bozza»**, senza titolare né email; «Le app usano internet per una cosa sola» dimentica che l'installatore Windows scarica .NET 8 da Microsoft se manca | `main:Sito/privacy.html` | come M, **aperto** | Titolare, email, data; frase sull'installatore; poi togliere «bozza» (Apple 2.1 e Play rifiutano testi provvisori) |
| I12 | **Android non pubblicabile così su Play**: `targetSdk 35` (serve 36), Play Billing 7.1.1 (serve 8+), MediaPipe senza pagine da 16 KB, build `release` firmata con la chiave di debug | `Android/app/build.gradle.kts` 19, 30, 82, 86 | come B–E, **aperti** (`versionName` è ora «1.0», risolto) | Un round Android prima del test chiuso |
| I13 | **Notifiche del Mac**: il Mac chiede il permesso delle notifiche (`UNUserNotificationCenter.requestAuthorization`), la privacy non lo elenca | `Mac/Sorgenti/Notifiche.swift` 110, 134 | **nuovo**, minore | Una riga in privacy: «Notifiche (Mac): telefono collegato o perso, registrazione salvata; restano sul Mac» |
| I14 | **4K su Windows**: arriva in HEVC e richiede le «Estensioni video HEVC» di Microsoft Store (a pagamento); va detto dove si promette il 4K | `Windows/WebcamLR.Ricevitore/Risorse/Testi.resx` | **nuovo** nei testi store | Detto nelle descrizioni qui sotto |
| I15 | **Mac App Store**: le eccezioni del sandbox per il cavo USB (`usbmuxd`) e per il microfono (servizi Mach dell'aiutante) non sono accettate; il controllo di `versione.json` non è permesso a un'app dello store | `Mac/base.yml` entitlements; `ControlloAggiornamenti.swift` | noto (`Pubblicazione.md`), **aperto** | Sezione 2.1: per la 1.0 Mac fuori store |

Risolti dal 26 ottobre: **F** (la pagina Pro di Android non promette più «Volto + scrivania» né il gobbo) e **H** (nessun prezzo
nelle domande frequenti: «il prezzo è quello indicato dallo store del tuo paese»).

## 0.1 Decisioni che spettano a Ledion

1. **Account sviluppatore Apple** (99 USD l'anno): senza, non si pubblica né l'iPhone né il Mac (sezione 2.1). Lo stesso account
   copre App Store, Developer ID e notarizzazione. Con l'Apple ID gratuito si può solo provare sui propri dispositivi.
2. **Mac App Store sì o no**. Consiglio: **no per la 1.0**; Mac dal sito, firmato Developer ID e notarizzato, con tutte le
   funzioni (sezione 2.1). Un'eventuale versione store in seguito, ridotta (niente cavo USB né microfono del telefono).
3. **Prezzo di WebcamLR Pro**: oggi deciso **14,99 €**, **9,99 € al lancio** (Registro, 25 ottobre; `Pubblicazione.md`). Da
   confermare: durata del lancio, fasce di prezzo per paese (Apple e Google le propongono da sole partendo dall'euro),
   In famiglia / Raccolta famiglia accese.
4. **Google Play**: account personale (25 USD una volta, poi test chiuso con 12 tester per 14 giorni) oppure organizzazione
   (D-U-N-S, niente test obbligatorio). E la scelta su MediaPipe (I1).
5. **Windows**: firma dell'installatore (Azure Trusted Signing, circa 10 USD al mese, se disponibile in Italia; o certificato OV,
   100–400 € l'anno) e **Microsoft Store sì o no** (sezione 4.1). Consiglio: installatore firmato dal sito per la 1.0; lo Store
   più avanti come scheda che rimanda al nostro installatore (serve comunque la firma).
6. **Titolare** (persona o ditta), email, telefono e indirizzo: servono alla privacy, ad Apple (operatore commerciale UE, DSA)
   e a Play (indirizzo pubblico per le app con acquisti).
7. **Nome negli store**: «WebcamLR: webcam per Mac e PC» (consigliato, dice a cosa serve) oppure solo «WebcamLR».

---

## 1. App Store (iPhone)

Bundle `it.lrapps.webcamlr.iphone`, solo iPhone (`TARGETED_DEVICE_FAMILY 1`), iOS 17 o successivo. Lingua principale
**Italiano**, localizzazione **Inglese (Stati Uniti)**.

### 1.1 Nome

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

### 1.2 Sottotitolo

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

**Testo promozionale · italiano** (si cambia senza nuova versione) <!-- campo as.promo.it max=170 -->
```text
Il video della fotocamera dell'iPhone arriva sul Mac o sul PC, con il cavo USB o il Wi-Fi. Anche nella versione gratuita: niente filigrana, niente account.
```
Conteggio: 155/170 caratteri

**Promotional text · English** <!-- campo as.promo.en max=170 -->
```text
Your iPhone camera's video on your Mac or PC, over USB cable or Wi-Fi. Even in the free version: no watermark, no account.
```
Conteggio: 122/170 caratteri

### 1.3 Parole chiave (100 byte)

Separate da virgole senza spazi; nessuna parola già nel nome o nel sottotitolo, nessun marchio di altri.

**Italiano** <!-- campo as.parole.it max=100 byte -->
```text
fotocamera,videocamera,riunione,lezione,diretta,streaming,usb,wifi,microfono,4k,1080p,cavo,hotspot
```
Conteggio: 98/100 byte

**English** <!-- campo as.parole.en max=100 byte -->
```text
camera,meeting,conference,lesson,live,streaming,usb,wifi,microphone,4k,1080p,cable,hotspot,teacher
```
Conteggio: 98/100 byte

### 1.4 Descrizione

**Italiano** <!-- campo as.descrizione.it max=4000 -->
```text
WebcamLR trasforma l'iPhone nella webcam del Mac o del PC. Videochiamate, lezioni e dirette prendono il video dalla fotocamera dell'iPhone invece che dalla webcam del computer.

COME FUNZIONA
1. Installa WebcamLR sul computer: è gratuita, dal sito lr-apps609.github.io/WebcamLR (Mac con macOS 14 o successivo, PC con Windows 10 o 11 a 64 bit).
2. Apri WebcamLR sull'iPhone. Sulla stessa rete Wi-Fi il computer compare da solo; altrimenti inquadri il QR code del computer o colleghi il cavo USB.
3. La prima volta confermi sul computer il codice di 4 cifre. Il video arriva nella finestra di WebcamLR e, tramite la webcam virtuale «WebcamLR», nelle app di videochiamata e di diretta.

COLLEGAMENTO
• Cavo USB, Wi-Fi o Hotspot personale; con il Mac anche Wi-Fi diretto, senza router.
• Se attacchi il cavo durante una chiamata, il video passa al cavo senza fermarsi; se lo stacchi, torna al Wi-Fi.
• Sempre in vista: il collegamento in uso e la sua qualità in parole («Ottimo», «Buono», «Debole»).
• Quando qualcosa non va, l'app dice la causa probabile e cosa fare: permesso «Rete locale», reti diverse, rete che tiene separati i dispositivi.
• Se il collegamento cade, WebcamLR si ricollega da sola.

IL TUO VIDEO RESTA TUO
• Video, audio e comandi vanno dall'iPhone al tuo computer, sulla tua rete o sul cavo, cifrati con chiavi nuove a ogni collegamento. Non passano da nostri server.
• Un computer nuovo si abbina con il suo QR code o con il codice di conferma di 4 cifre.
• Nessun account, nessuna pubblicità, nessun dato raccolto.

GRATIS
• Video fino a 720p a 30 fps, senza filigrana e senza limiti di tempo.
• Specchia, sfondo sfocato e luce sul volto.
• Zoom, obiettivi (Frontale, Principale 1×, Grandangolo 0,5×, Tele dove c'è), torcia ed esposizione, anche dal computer.
• Microfono dell'iPhone sul computer: sul Mac compare come «WebcamLR (microphone)»; su Windows passa da un cavo audio virtuale gratuito, da installare a parte.
• Telefono a faccia in giù: il video va in pausa senza scollegarsi. Lo schermo si oscura da solo e, se il telefono scalda, la qualità scende a gradini e lo dice.

WEBCAMLR PRO: UN ACQUISTO, SENZA ABBONAMENTO
• 1080p e 4K, fino a 60 fps (il 4K a 30), dove l'iPhone ci arriva. Su Windows il 4K richiede le «Estensioni video HEVC» di Microsoft Store.
• Effetti: filtri e regolazioni, sfondo sostituito con un'immagine, ritocco della pelle, scritta con nome e ruolo, il tuo logo.
• Inquadratura automatica, e «Volto + scrivania» con il Grandangolo 0,5×.
• Controlli Pro: ISO, tempo, bilanciamento del bianco e messa a fuoco.
• Sul computer: profili Riunione, Lezione, Diretta e Colloquio (e i tuoi), foto e registrazione senza audio, gobbo che scorre sull'iPhone vicino all'obiettivo, due telefoni insieme, schermata d'attesa personalizzata.
Si compra una volta nell'app, vale anche In famiglia e sblocca il computer collegato a questo iPhone: sul Mac e su Windows non c'è niente da comprare. «Ripristina acquisti» è nella pagina WebcamLR Pro.

COSA SERVE
• Un iPhone con iOS 17 o successivo.
• WebcamLR sul Mac o sul PC, gratuita dal sito.
• Per il cavo USB su Windows, l'app gratuita «Dispositivi Apple».

WebcamLR è in italiano e in inglese.
Aiuto: lr-apps609.github.io/WebcamLR/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/privacy.html
```
Conteggio: 3281/4000 caratteri

**English** <!-- campo as.descrizione.en max=4000 -->
```text
WebcamLR turns your iPhone into the webcam for your Mac or PC. Video calls, lessons and live streams take the video from the iPhone camera instead of the computer's webcam.

HOW IT WORKS
1. Install WebcamLR on the computer: it's free, from lr-apps609.github.io/WebcamLR (Mac with macOS 14 or later, PC with 64-bit Windows 10 or 11).
2. Open WebcamLR on the iPhone. On the same Wi-Fi network the computer shows up by itself; otherwise scan the computer's QR code or plug in the USB cable.
3. The first time, confirm the 4-digit code on the computer. The video arrives in the WebcamLR window and, through the "WebcamLR" virtual webcam, in your video call and streaming apps.

CONNECTION
• USB cable, Wi-Fi or Personal Hotspot; with a Mac also Wi-Fi Direct, without a router.
• Plug in the cable during a call and the video moves to the cable without stopping; unplug it and it goes back to Wi-Fi.
• Always in view: the connection in use and its quality in words ("Excellent", "Good", "Weak").
• When something's wrong, the app tells you the likely cause and what to do: "Local Network" permission, different networks, a network that keeps devices apart.
• If the connection drops, WebcamLR reconnects by itself.

YOUR VIDEO STAYS YOURS
• Video, audio and controls go from the iPhone to your computer, over your network or the cable, encrypted with new keys for every connection. They don't pass through our servers.
• A new computer is paired with its QR code or with the 4-digit confirmation code.
• No account, no ads, no data collected.

FREE
• Video up to 720p at 30 fps, with no watermark and no time limit.
• Mirror, background blur and face lighting.
• Zoom, lenses (Front, Main 1×, Ultra Wide 0.5×, Telephoto where available), flashlight and exposure, from the computer too.
• The iPhone's microphone on the computer: on the Mac it shows up as "WebcamLR (microphone)"; on Windows it goes through a free virtual audio cable, installed separately.
• Phone face down: the video pauses without disconnecting. The screen dims by itself and, if the phone gets hot, quality steps down and the app says so.

WEBCAMLR PRO: ONE PURCHASE, NO SUBSCRIPTION
• 1080p and 4K, up to 60 fps (4K at 30), where the iPhone supports it. On Windows, 4K needs "HEVC Video Extensions" from the Microsoft Store.
• Effects: filters and adjustments, background replaced with an image, skin smoothing, a caption with your name and role, your logo.
• Auto framing, and "Face + desk" with the Ultra Wide 0.5× camera.
• Pro controls: ISO, shutter, white balance and focus.
• On the computer: Meeting, Lesson, Live stream and Interview profiles (and your own), photos and recording without audio, a teleprompter that scrolls on the iPhone next to the lens, two phones at once, a custom waiting screen.
Buy it once in the app; it works with Family Sharing and unlocks the computer connected to this iPhone: there's nothing to buy on the Mac or on Windows. "Restore Purchases" is on the WebcamLR Pro page.

WHAT YOU NEED
• An iPhone with iOS 17 or later.
• WebcamLR on your Mac or PC, free from the website.
• For the USB cable on Windows, the free "Apple Devices" app.

WebcamLR is in English and Italian.
Help: lr-apps609.github.io/WebcamLR/en/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/en/privacy.html
```
Conteggio: 3282/4000 caratteri

### 1.5 Novità della versione

Per la **prima** versione App Store Connect non mostra il campo. Testo pronto per la prima correzione (1.0.1), da adattare.

**Italiano** <!-- campo as.novita.it max=4000 -->
```text
Correzioni e piccoli miglioramenti al collegamento. Grazie a chi ha segnalato i problemi con «Segnala un bug».
```
Conteggio: 110/4000 caratteri

**English** <!-- campo as.novita.en max=4000 -->
```text
Fixes and small improvements to the connection. Thanks to everyone who reported issues with "Report a bug".
```
Conteggio: 107/4000 caratteri

### 1.6 Categoria, età, indirizzi

- **Categoria primaria**: **Foto e video** (Photo & Video). **Secondaria**: **Produttività** (Productivity).
- **Classificazione per età** (questionario con le fasce 4+, 9+, 13+, 16+, 18+): tutto **No / Nessuno**. Controllo parentale No;
  verifica dell'età No; accesso libero al web **No** (i link aprono Safari); contenuti generati dagli utenti **No** (il video
  va solo al computer di chi lo riprende); social, messaggi e chat **No**; pubblicità **No**; temi per adulti, medicina,
  sessualità, violenza, gioco d'azzardo, loot box **Nessuno**. «Creata per bambini» **No**. Risultato atteso: **4+**.
- **URL di supporto** `https://lr-apps609.github.io/WebcamLR/aiuto.html` · **marketing** `https://lr-apps609.github.io/WebcamLR/`
  · **privacy** `https://lr-apps609.github.io/WebcamLR/privacy.html` (dopo I11).
- **Copyright** `© 2026 [NOME TITOLARE]`. **Diritti sui contenuti**: non contiene contenuti di terzi.
- **Operatore commerciale (DSA, UE)**: con un acquisto in-app quasi certamente sì; indirizzo, telefono ed email diventano
  pubblici nella scheda.

### 1.7 Acquisto in-app «WebcamLR Pro»

Tipo **Non consumabile**, ID `it.lrapps.webcamlr.pro` (come in `Stile/Sources/Stile/Pro.swift`, `iPhone/WebcamLR.storekit`,
`Android/…/acquisti/NegozioPro.kt`), Condivisione in famiglia **accesa**. Prezzo: decisione 3.

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
4K, 60 fps, effetti e profili. Una volta sola
```
Conteggio: 45/45 caratteri

**Description · English** <!-- campo iap.descrizione.en max=45 -->
```text
4K, 60 fps, effects and profiles. Pay once
```
Conteggio: 42/45 caratteri

**Screenshot per la revisione dell'acquisto** (non pubblico, 1320 × 2868): pagina **WebcamLR Pro** con «Sblocca Pro · …» e il
confronto Gratis/Pro. Qui il prezzo può vedersi.

### 1.8 Screenshot

Misure (pagina *Screenshot specifications* di Apple, letta il 26 ottobre): **1320 × 2868** (iPhone con Dynamic Island grande,
6,9″) e **1206 × 2622** (Dynamic Island media, 6,3″); fare entrambe le serie, così ogni misura richiesta è coperta e Apple
ricava le altre. Da 1 a 10 per misura, PNG o JPEG senza trasparenza, verticali. Didascalia breve sopra l'immagine in
Barlow Condensed su fondo `#30453E → #0D1B18`; niente prezzi; computer «MacBook di Anna», nessun dato personale. Una serie
con l'app in italiano, una in inglese.

| # | Schermata | Stato da preparare | Didascalia IT | Caption EN |
| --- | --- | --- | --- | --- |
| 1 | In onda, verticale | Collegato in Wi-Fi a «MacBook di Anna», pillola **IN ONDA** corallo, colonna di tondi (Specchia, Sfoca sfondo, Luce sul volto, Microfono al computer, Pausa), obiettivi in basso con **Frontale** scelto, Sfoca sfondo acceso | Il telefono diventa la webcam del computer | Your phone becomes your computer's webcam |
| 2 | Lista dei computer | «MacBook di Anna» e «PC dello studio» trovati, sotto «Inquadra il QR code del computer» e «Usa il cavo USB» | Trova il computer da solo, o con il QR code | Finds the computer by itself, or with a QR code |
| 3 | Codice di conferma | Primo collegamento: le 4 cifre sull'iPhone, «Conferma sul computer» | Un computer nuovo si conferma con 4 cifre | A new computer is confirmed with 4 digits |
| 4 | In onda, orizzontale, sul cavo | Riga di stato «Cavo USB», collegamento «Ottimo» | Cavo USB o Wi-Fi, senza fermare il video | USB cable or Wi-Fi, without stopping the video |
| 5 | In onda con Volto + scrivania | Vista doppia (volto e scrivania), segno **PRO**, Pro attivo | Volto e scrivania nello stesso video | Your face and your desk in one video |
| 6 | In onda con effetti | Sfondo sostituito con uno degli sfondi inclusi, scritta con nome e ruolo («Anna Rossi · Docente»), Pro attivo | Sfondo, filtri e scritta, dal computer | Background, filters and caption, from the computer |
| 7 | Gobbo | Testo che scorre in alto vicino all'obiettivo, In onda | Il gobbo scorre vicino all'obiettivo | The teleprompter scrolls next to the lens |
| 8 | «Non trovo nessun computer» | Dopo 15 secondi senza computer: le cose da controllare e «Usa il cavo USB» | Se qualcosa non va, ti dice cosa fare | If something's wrong, it tells you what to do |
| 9 | Pagina WebcamLR Pro, **Pro attivo** (niente prezzo) | Segno PRO, confronto Gratis/Pro, «Pro attivo» | Pro: un acquisto, senza abbonamento | Pro: one purchase, no subscription |

### 1.9 Privacy dell'app (etichetta di App Store Connect)

**Risposta: «No, noi e i nostri partner non raccogliamo dati da questa app».** Tracciamento **No**. Coerente con
`iPhone/Privacy/PrivacyInfo.xcprivacy` e con il codice:

| Cosa fa l'app | Perché non è «raccolta» | Dove l'ho controllato |
| --- | --- | --- |
| Video, audio, comandi, nome e stato del telefono (batteria, temperatura) verso il computer | Vanno solo al computer dell'utente, in rete locale o sul cavo, cifrati (CryptoKit, AES-GCM, chiavi nuove a ogni collegamento); non arrivano a noi né a terzi | `Collegamento.swift`, `SessioneTelefono.swift` |
| Immagine per sfondo o logo | Arriva dal computer dell'utente e resta nel telefono (I3) | `EffettiVisivi.swift` |
| Acquisto di Pro | Lo gestisce Apple (StoreKit 2) | `NegozioPro.swift` |
| «Segnala un bug» | Prepara un testo che l'utente manda, se vuole, con Mail o la condivisione (divulgazione facoltativa, non raccolta) | `Stile/…/VisteSezioneApp.swift` |
| Internet | L'app iPhone non fa richieste in rete: nessun `URLSession`; i link si aprono in Safari | ricerca nel codice |
| Analisi, crash, pubblicità | Nessuna libreria di terzi (solo i pacchetti `Protocollo` e `Stile`); effetti con Vision e Core Image di Apple | `iPhone/project.yml` |

### 1.10 Cifratura

`ITSAppUsesNonExemptEncryption = NO` è già nell'Info.plist (solo CryptoKit del sistema: esente). App Store Connect non chiede il
questionario.

### 1.11 Motivi d'uso dei permessi

| Chiave | Testo di oggi (IT / EN) | Cosa fa il codice | Giudizio | Proposta (IT / EN) |
| --- | --- | --- | --- | --- |
| `NSCameraUsageDescription` | «WebcamLR usa la fotocamera per inviare il video al tuo computer.» / «WebcamLR uses the camera to send video to your computer.» | Video (`Cattura.chiediPermesso`, al primo In onda) **e** lettura del QR (`LettoreQR.swift`) | **incompleto** (I5) | «La fotocamera riprende il video che WebcamLR manda al tuo Mac o PC e legge il QR code del computer.» / «The camera captures the video WebcamLR sends to your Mac or PC and scans the computer's QR code.» |
| `NSMicrophoneUsageDescription` | «WebcamLR usa il microfono per inviare l'audio al tuo computer.» / «… to send audio to your computer.» | Chiesto solo quando si accende «Microfono al computer» (`CodificatoreAudio.swift`) | coincide | facoltativo: «Il microfono si usa solo se lo accendi: la tua voce arriva al Mac o al PC.» / «The microphone is used only if you turn it on: your voice reaches your Mac or PC.» |
| `NSLocalNetworkUsageDescription` + `NSBonjourServices` `_webcamlr._tcp` | «WebcamLR cerca il tuo Mac o PC sulla stessa rete Wi-Fi.» / «… looks for your Mac or PC on the same Wi-Fi network.» | Bonjour e collegamento diretto (`CercaComputer.swift`, `Collegamento.swift`) | coincide | facoltativo: aggiungere «e gli manda il video direttamente, senza passare da internet» |
| Foto, posizione, Bluetooth, contatti, tracciamento | nessuna chiave | Nessun uso nel codice (le immagini arrivano dal computer) | giusto | — |

Nessun permesso chiesto senza motivo; nessun uso senza chiave.

### 1.12 Note per la revisione di Apple

- **Accesso richiesto**: No (nessun login). **Contatto**: [NOME TITOLARE] · [TELEFONO] · [EMAIL ASSISTENZA].
- **Allegato**: video dimostrativo da 1–2 minuti (copione in `Materiale store.md` 3.3, con il percorso nuovo verso la pagina Pro).
- Inviare **insieme** alla versione l'acquisto in-app (selezionato nella pagina della versione).

<!-- campo as.revisione.en max=4000 -->
```text
WebcamLR turns the iPhone into a webcam for a Mac or a Windows PC. The iPhone app captures and encodes the video; a free companion app on the computer receives it and shows it in its window and as a virtual camera for video call apps. The iPhone app needs that computer app for its main feature, so we attached a demo video recorded on real devices (iPhone + Mac): [LINK VIDEO]

To try it with a computer:
1. Mac (macOS 14+): https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR.dmg (signed and notarized). Windows 10/11: https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR-Setup.exe
2. Put the iPhone and the computer on the same Wi-Fi network and open WebcamLR on both. On the iPhone allow "Local Network" and "Camera".
3. The computer appears in the list on the iPhone (or tap "Scan the computer's QR code" and scan the QR code in the computer window). The first time, confirm the 4-digit code on the computer.
4. The iPhone shows "LIVE" and the video appears on the computer. A USB cable also works, with no setup on the Mac.

Without a computer you can still review: the first-launch tour, the computer search with the help that appears after 15 seconds ("Use the USB cable", "Send me the link for the computer"), Settings (gear at the top right), App and support (Guide, FAQ, Report a bug) and the WebcamLR Pro page.

Permissions:
- Local Network: to find the user's own computer with Bonjour (_webcamlr._tcp) and send it the video directly. Nothing goes to the internet or to our servers.
- Camera: to capture the video sent to the computer, and to scan the computer's QR code.
- Microphone: asked only when the user turns on "Microphone to computer"; the audio goes to the same computer.
Video, audio and controls are encrypted with CryptoKit (ECDH P-256, AES-GCM, new keys for every connection). The app collects no data and has no account.

In-app purchase: WebcamLR Pro (it.lrapps.webcamlr.pro) is a one-time, non-consumable purchase with Family Sharing (no subscription). Where: the "PRO Unlock" button at the top of the first screen, or Settings (gear) › WebcamLR Pro. The page shows "Unlock Pro" with the App Store price and "Restore Purchases". Every Pro control shows a "PRO" badge that opens the same page. The free version is fully usable: 720p at 30 fps, no watermark, no time limit, no ads. Pro also unlocks the matching features of the free computer app while this iPhone is connected (profiles, photos and recording without audio, teleprompter, two phones, custom waiting screen); the computer app sells nothing and accepts no codes: it only reads from the connected iPhone whether Pro is active.
```
Conteggio: 2659/4000 caratteri

**Note dell'acquisto in-app** <!-- campo iap.revisione.en max=4000 -->
```text
WebcamLR Pro (it.lrapps.webcamlr.pro): one-time, non-consumable purchase with Family Sharing (no subscription). No account needed. Open it from the "PRO Unlock" button at the top of the first screen or from Settings (gear) › WebcamLR Pro. It unlocks 1080p and 4K (up to 60 fps, 4K at 30), effects (filters, adjustments, background replacement, skin smoothing, caption and logo), auto framing, Face + desk and manual ISO, shutter, white balance and focus; and, while this iPhone is connected, the matching features of the free computer app. After a sandbox purchase the page shows "Pro active" and the PRO badges disappear. "Restore Purchases" is on the same page.
```
Conteggio: 663/4000 caratteri

---

## 2. Mac

### 2.1 Mac App Store o fuori store: cosa si può e cosa no

| | Fuori store (Developer ID + notarizzazione, dmg dal sito) | Mac App Store | Apple ID gratuito |
| --- | --- | --- | --- |
| Account | a pagamento (99 USD/anno, lo stesso dell'iPhone) | a pagamento | gratuito |
| Webcam virtuale (Camera Extension) | **sì** | sì (le Camera Extension sono ammesse nello store) | **no**: richiede l'account a pagamento (`Mac/project-senza-account.yml`) |
| Cavo USB dell'iPhone (`usbmuxd`) | sì | **no**: eccezione del sandbox non accettata | sì, solo sul proprio Mac |
| Microfono del telefono («WebcamLR (microphone)», driver audio e aiutante installati con `.pkg`) | sì | **no**: niente driver né LaunchDaemon dallo store | sì, solo sul proprio Mac |
| Wi-Fi, Hotspot personale, Wi-Fi diretto, Tethering USB di Android | sì | sì | sì |
| «Aggiornamento disponibile» (`versione.json`) | sì | **no**: gli aggiornamenti passano dallo store; va spento nella versione store | sì |
| Pro letto dal telefono collegato | sì | **a rischio**: per Apple 3.1.1 e 3.1.3(b) un'app dello store che sblocca funzioni comprate altrove (anche su Google Play) deve offrire lo stesso acquisto in-app; l'acquisto dell'iPhone non vale per un'app Mac con un altro bundle | sì |
| Distribuire ad altri | sì, si apre senza avvisi | sì | **no**: senza Developer ID macOS blocca l'app sugli altri Mac (Impostazioni › Privacy e sicurezza › «Apri comunque», e niente webcam virtuale) |

**Conclusione.** Con l'Apple ID gratuito il Mac **non si può pubblicare**: va bene per Ledion e per gli amici che provano, ma
senza webcam virtuale non serve alle videochiamate. Con l'account a pagamento la strada per la 1.0 è **fuori store**: dmg
firmato Developer ID e notarizzato, con tutte le funzioni (cavo, microfono, webcam virtuale, aggiornamenti). Una versione per il
Mac App Store è possibile solo **ridotta** (solo reti, niente microfono del telefono, controllo aggiornamenti spento, acquisto
Pro anche nell'app Mac): un lavoro a parte, da decidere dopo il lancio (decisione 2). I testi qui sotto servono già al sito, alla
pagina di download e alle note di rilascio; i campi con «solo Mac App Store» servono solo se un giorno si sceglie lo store.

### 2.2 Nome (solo Mac App Store; fuori store il nome è «WebcamLR»)

**Nome · italiano** <!-- campo mac.nome.it max=30 -->
```text
WebcamLR: webcam dal telefono
```
Conteggio: 29/30 caratteri

**Name · English** <!-- campo mac.nome.en max=30 -->
```text
WebcamLR: Phone as Webcam
```
Conteggio: 25/30 caratteri

### 2.3 Sottotitolo (solo Mac App Store; fuori store è la riga sotto il titolo della pagina di download)

**Sottotitolo · italiano** <!-- campo mac.sottotitolo.it max=30 -->
```text
Il video del telefono sul Mac
```
Conteggio: 29/30 caratteri

**Subtitle · English** <!-- campo mac.sottotitolo.en max=30 -->
```text
Your phone's video on your Mac
```
Conteggio: 30/30 caratteri

### 2.4 Parole chiave (solo Mac App Store)

**Italiano** <!-- campo mac.parole.it max=100 byte -->
```text
fotocamera,videocamera,iphone,webcam virtuale,riunione,lezione,diretta,streaming,4k,cavo,microfono
```
Conteggio: 98/100 byte

**English** <!-- campo mac.parole.en max=100 byte -->
```text
camera,virtual camera,iphone,meeting,conference,lesson,live,streaming,4k,cable,microphone,teacher
```
Conteggio: 97/100 byte

### 2.5 Descrizione (pagina di download e, se un giorno, Mac App Store)

Scritta per la versione **fuori store** (con cavo e microfono). Per lo store togliere le righe del cavo USB dell'iPhone e del
microfono.

**Italiano** <!-- campo mac.descrizione.it max=4000 -->
```text
WebcamLR porta sul Mac il video della fotocamera del telefono. Lo vedi nella finestra di WebcamLR e lo usi nelle app di videochiamata e di diretta tramite la webcam virtuale «WebcamLR».

COME FUNZIONA
1. Apri WebcamLR sul Mac: al centro della finestra c'è il QR code «Collega il tuo telefono».
2. Sul telefono apri WebcamLR (iPhone o Android, dagli store). Sulla stessa rete Wi-Fi il Mac compare da solo; altrimenti inquadri il QR code.
3. La prima volta confermi sul Mac il codice di 4 cifre: il telefono diventa un telefono fidato e la volta dopo si ricollega da solo.
4. Nell'app di chiamata scegli «WebcamLR» come videocamera.

COLLEGAMENTO
• iPhone: cavo USB, Wi-Fi, Hotspot personale o Wi-Fi diretto, senza router. Se attacchi il cavo durante una chiamata, il video passa al cavo senza fermarsi.
• Telefono Android: Wi-Fi, hotspot o Tethering USB (con alcuni telefoni).
• Il collegamento in uso e la sua qualità sono sempre scritti («Ottimo», «Buono», «Debole»); se qualcosa non va, WebcamLR dice la causa probabile e cosa fare.
• Video, audio e comandi viaggiano cifrati, con chiavi nuove a ogni collegamento, e non passano da nostri server.

REGIA DAL MAC
• Specchia, Sfondo, Foto, Registra e Schermo in una barra, con lo stato scritto sotto ogni comando.
• Zoom, obiettivi, torcia, esposizione e messa a fuoco del telefono comandati dal Mac.
• Pillola «IN ONDA» quando un'app usa il video, «In pausa» quando il telefono è a faccia in giù o WebcamLR è in sottofondo, con la schermata «Webcam in pausa» per le app di chiamata.
• Icona nella barra dei menu con lo stato, finestra mini sempre in primo piano, schermo intero.
• Microfono del telefono come ingresso «WebcamLR (microphone)» in tutte le app del Mac (si installa una volta, con la password del Mac).

GRATIS
• Video fino a 720p a 30 fps, senza filigrana e senza limiti di tempo; specchia, sfondo sfocato, luce sul volto, microfono.

CON WEBCAMLR PRO, COMPRATO SUL TELEFONO
• 1080p e 4K, fino a 60 fps (il 4K a 30), effetti, inquadratura automatica.
• Profili Riunione, Lezione, Diretta e Colloquio, e i tuoi.
• Foto e registrazione senza audio, in Immagini e Filmati › WebcamLR.
• Gobbo (con l'iPhone), due telefoni insieme, schermata d'attesa personalizzata.
Sul Mac non c'è niente da comprare: le funzioni Pro si accendono quando è collegato un telefono con Pro.

COSA SERVE
• macOS 14 Sonoma o successivo.
• WebcamLR sul telefono: iPhone con iOS 17 o successivo, oppure Android 8 o successivo.

Aiuto: lr-apps609.github.io/WebcamLR/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/privacy.html
```
Conteggio: 2564/4000 caratteri

**English** <!-- campo mac.descrizione.en max=4000 -->
```text
WebcamLR brings your phone camera's video to your Mac. You see it in the WebcamLR window and use it in video call and streaming apps through the "WebcamLR" virtual webcam.

HOW IT WORKS
1. Open WebcamLR on the Mac: the "Connect your phone" QR code is in the middle of the window.
2. On the phone open WebcamLR (iPhone or Android, from the stores). On the same Wi-Fi network the Mac shows up by itself; otherwise scan the QR code.
3. The first time, confirm the 4-digit code on the Mac: the phone becomes a trusted phone and reconnects by itself next time.
4. In your call app choose "WebcamLR" as the camera.

CONNECTION
• iPhone: USB cable, Wi-Fi, Personal Hotspot or Wi-Fi Direct, without a router. Plug in the cable during a call and the video moves to the cable without stopping.
• Android phone: Wi-Fi, hotspot or USB tethering (with some phones).
• The connection in use and its quality are always written ("Excellent", "Good", "Weak"); if something's wrong, WebcamLR tells you the likely cause and what to do.
• Video, audio and controls are encrypted with new keys for every connection and don't pass through our servers.

CONTROL ROOM ON THE MAC
• Mirror, Background, Photo, Record and Screen in one bar, with the state written under each control.
• Zoom, lenses, flashlight, exposure and focus of the phone, controlled from the Mac.
• A "LIVE" pill when an app uses the video, "Paused" when the phone is face down or WebcamLR is in the background, with a "Webcam paused" screen for call apps.
• Menu bar icon with the status, an always-on-top mini window, full screen.
• The phone's microphone as the "WebcamLR (microphone)" input in every Mac app (installed once, with your Mac password).

FREE
• Video up to 720p at 30 fps, with no watermark and no time limit; mirror, background blur, face lighting, microphone.

WITH WEBCAMLR PRO, BOUGHT ON THE PHONE
• 1080p and 4K, up to 60 fps (4K at 30), effects, auto framing.
• Meeting, Lesson, Live stream and Interview profiles, and your own.
• Photos and recording without audio, in Pictures and Movies › WebcamLR.
• Teleprompter (with an iPhone), two phones at once, a custom waiting screen.
There's nothing to buy on the Mac: Pro features turn on when a phone with Pro is connected.

WHAT YOU NEED
• macOS 14 Sonoma or later.
• WebcamLR on the phone: iPhone with iOS 17 or later, or Android 8 or later.

Help: lr-apps609.github.io/WebcamLR/en/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/en/privacy.html
```
Conteggio: 2466/4000 caratteri

### 2.6 Novità della versione (note di rilascio della 1.0 su GitHub; nello store dalla 1.0.1)

**Italiano** <!-- campo mac.novita.it max=4000 -->
```text
Prima versione pubblica. Webcam virtuale «WebcamLR», collegamento con il cavo USB o il Wi-Fi, microfono del telefono, icona nella barra dei menu e un pannello Impostazioni unico (⌘,).
```
Conteggio: 183/4000 caratteri

**English** <!-- campo mac.novita.en max=4000 -->
```text
First public version. "WebcamLR" virtual webcam, connection over USB cable or Wi-Fi, the phone's microphone, a menu bar icon and a single Settings panel (⌘,).
```
Conteggio: 158/4000 caratteri

### 2.7 Categoria ed età

- **Categoria**: **Video** (coerente con `LSApplicationCategoryType public.app-category.video` in `Mac/base.yml`);
  secondaria **Produttività**.
- **Età**: stesso questionario dell'iPhone, tutto No/Nessuno → **4+**.

### 2.8 Screenshot

Mac App Store: 16:10, una di **2880 × 1800**, 2560 × 1600, 1440 × 900 o 1280 × 800; da 1 a 10. Per la pagina di download le stesse
immagini a 2880 × 1800 ridotte. Scrivania pulita, sfondo scuro, nessun'altra app nel quadro; la finestra in tema scuro.

| # | Schermata | Stato da preparare | Didascalia IT | Caption EN |
| --- | --- | --- | --- | --- |
| 1 | Finestra principale, In onda | Video del telefono, pillola **IN ONDA**, barra Specchia · Sfondo · Foto · Registra · Schermo con «Acceso» sotto Sfondo, colonna Telefoni con «iPhone di Anna», riga in fondo «In uso da un'altra app» | Il video del telefono, pronto per le chiamate | Your phone's video, ready for calls |
| 2 | Primo avvio | QR grande «Collega il tuo telefono» al centro | Si collega con un QR code | Connects with a QR code |
| 3 | Conferma del telefono | Foglio con il codice di conferma di 4 cifre | Un telefono nuovo si conferma con 4 cifre | A new phone is confirmed with 4 digits |
| 4 | Profili | Colonna di destra con Riunione scelto e «Torna a «Riunione»» dopo una modifica, Pro attivo | Profili per riunioni, lezioni e dirette | Profiles for meetings, lessons and live streams |
| 5 | Effetti | Pannello Effetti con un filtro e lo sfondo sostituito, Pro attivo | Effetti comandati dal Mac | Effects controlled from the Mac |
| 6 | Due telefoni | Video principale con il secondo telefono in piccolo («CAM 2») | Due telefoni, due inquadrature | Two phones, two angles |
| 7 | Barra dei menu | Menu dell'icona aperto con lo stato e «Esci da WebcamLR» | Lo stato anche a finestra chiusa | Status even with the window closed |
| 8 | Sezione Connessione (colonna di sinistra) | Cavo USB in uso, qualità «Ottimo» | Cavo USB, Wi-Fi o Wi-Fi diretto | USB cable, Wi-Fi or Wi-Fi Direct |

### 2.9 Privacy (etichetta, solo Mac App Store; fuori store vale la privacy del sito)

**«Nessun dato raccolto»**, tracciamento **No**. L'unica richiesta in rete dell'app Mac è la lettura del file pubblico
`versione.json` (`ControlloAggiornamenti.swift`, all'avvio e ogni 6 ore), senza dati né identificativi (solo `Accept`): non è
raccolta. Nella versione store va comunque spenta (sezione 2.1). Foto e registrazioni restano nel Mac; le notifiche restano
nel Mac (I13). Manifesti: `Mac/Privacy/App` e `Mac/Privacy/FotocameraVirtuale`.

### 2.10 Note per la revisione (solo Mac App Store)

Senza telefono il revisore vede la finestra con il QR, le Impostazioni, «App e assistenza» e la webcam virtuale con la
schermata d'attesa in un'app di chiamata. Testo da adattare alla versione ridotta:

<!-- campo mac.revisione.en max=4000 -->
```text
WebcamLR for Mac receives the video of the user's own phone (iPhone or Android, free apps on the stores) and shows it in its window and as the "WebcamLR" virtual camera (Camera Extension) for video call apps. Without a phone you can review the window with the "Connect your phone" QR code, Settings (Command-comma), App and support, and the virtual camera: choose "WebcamLR" in FaceTime or Photo Booth to see the "Webcam paused" screen. With an iPhone: install WebcamLR from the App Store, put both devices on the same Wi-Fi network, open WebcamLR on both and confirm the 4-digit code on the Mac. A demo video is attached: [LINK VIDEO]. The app collects no data; video and controls are encrypted end to end between the user's own devices.
```
Conteggio: 738/4000 caratteri

### 2.11 Motivi d'uso dei permessi

| Chiave | Testo di oggi (IT / EN) | Cosa fa il codice | Giudizio | Proposta |
| --- | --- | --- | --- | --- |
| `NSLocalNetworkUsageDescription` + `_webcamlr._tcp` | «WebcamLR si fa trovare dai telefoni sulla stessa rete Wi-Fi.» / «WebcamLR lets phones on the same Wi-Fi network find this Mac.» | Bonjour e ascolto (`Ricevitore.swift`) | coincide | — |
| `NSCameraUsageDescription` (solo `project.yml`, account a pagamento) | «WebcamLR passa il video dell'iPhone alla propria webcam virtuale.» / «WebcamLR passes the iPhone video to its own virtual webcam.» | Permesso chiesto all'avvio solo se c'è la webcam virtuale (`WebcamLRMacApp.swift` 63, 122) | **non coincide** (I6: anche Android) | «WebcamLR passa il video del telefono alla propria webcam virtuale.» / «WebcamLR passes the phone's video to its own virtual webcam.» |
| `NSSystemExtensionUsageDescription` | «Serve per far vedere WebcamLR come una webcam nelle altre app.» / «Needed so other apps can see WebcamLR as a webcam.» | Attivazione della Camera Extension | coincide | — |
| Notifiche | nessuna chiave (non serve) | `Notifiche.swift` chiede il permesso | giusto; manca nella privacy (I13) | — |
| Immagini e Filmati, file scelti | entitlement del sandbox, nessun testo | Foto in Immagini › WebcamLR, registrazioni in Filmati › WebcamLR, immagine d'attesa dal pannello «Apri» | giusto | — |

Senza account (`project-senza-account.yml`) non c'è la chiave della fotocamera e l'app non la chiede: giusto.

---

## 3. Google Play (Android)

Pacchetto `it.lrapps.webcamlr.android`, Android 8 o successivo (`minSdk 26`). Lingua predefinita **it-IT**, traduzione **en-US**.
Prima dell'invio: I1 e I12.

### 3.1 Titolo

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

### 3.2 Descrizione breve

**Italiano** <!-- campo gp.breve.it max=80 -->
```text
Il telefono come webcam per Mac e PC, con Wi-Fi o cavo USB. Senza filigrana.
```
Conteggio: 76/80 caratteri

**English** <!-- campo gp.breve.en max=80 -->
```text
Your phone as a webcam for Mac and PC, over Wi-Fi or USB. No watermark.
```
Conteggio: 71/80 caratteri

### 3.3 Parole chiave

Google Play non ha un campo per le parole chiave: contano titolo, descrizione breve e descrizione. Al loro posto, fino a **5 tag**
dall'elenco di Play Console (quelli più vicini a fotocamera, videochiamate, streaming video, riunioni, produttività).

### 3.4 Descrizione completa

**Italiano** <!-- campo gp.descrizione.it max=4000 -->
```text
WebcamLR trasforma il telefono Android nella webcam del Mac o del PC. Videochiamate, lezioni e dirette prendono il video dalla fotocamera del telefono invece che dalla webcam del computer.

COME FUNZIONA
1. Installa WebcamLR sul computer: è gratuita, dal sito lr-apps609.github.io/WebcamLR (Mac con macOS 14 o successivo, PC con Windows 10 o 11 a 64 bit).
2. Apri WebcamLR sul telefono. Sulla stessa rete Wi-Fi il computer compare da solo; altrimenti inquadri il QR code del computer.
3. La prima volta confermi sul computer il codice di 4 cifre. Il video arriva nella finestra di WebcamLR e, tramite la webcam virtuale «WebcamLR», nelle app di videochiamata e di diretta.

COLLEGAMENTO
• Wi-Fi, hotspot del telefono o cavo USB con il «Tethering USB» del telefono (su Windows; sul Mac con alcuni telefoni). Non serve la modalità sviluppatore.
• Se il collegamento in uso cade, WebcamLR passa all'altro o si ricollega da sola.
• Sempre in vista: il collegamento in uso e la sua qualità in parole («Ottimo», «Buono», «Debole»).
• Quando qualcosa non va, l'app dice la causa probabile e cosa fare.
• Il video continua anche a schermo spento: lo dice l'avviso fisso «WebcamLR · video al computer», con «Scollega».

IL TUO VIDEO RESTA TUO
• Video, audio e comandi vanno dal telefono al tuo computer, sulla tua rete o sul cavo, cifrati con chiavi nuove a ogni collegamento. Non passano da nostri server.
• Un computer nuovo si abbina con il suo QR code o con il codice di conferma di 4 cifre.
• Nessun account, nessuna pubblicità.

GRATIS
• Video fino a 720p a 30 fps, senza filigrana e senza limiti di tempo.
• Specchia, sfondo sfocato e luce sul volto.
• Zoom, obiettivi, torcia ed esposizione, anche dal computer.
• Microfono del telefono sul computer: sul Mac compare come «WebcamLR (microphone)»; su Windows passa da un cavo audio virtuale gratuito, da installare a parte.
• Telefono a faccia in giù: il video va in pausa senza scollegarsi. Se il telefono scalda o la batteria scende, la qualità si abbassa e l'app lo dice.

WEBCAMLR PRO: UN ACQUISTO, SENZA ABBONAMENTO
• 1080p e 4K, fino a 60 fps (il 4K a 30), dove il telefono ci arriva. Su Windows il 4K richiede le «Estensioni video HEVC» di Microsoft Store.
• Effetti: filtri e regolazioni, sfondo sostituito con un'immagine, ritocco della pelle, scritta e logo nel video.
• Inquadratura automatica.
• Controlli Pro: ISO, tempo, bilanciamento del bianco e messa a fuoco.
• Sul computer: profili Riunione, Lezione, Diretta e Colloquio, foto e registrazione senza audio, due telefoni insieme, schermata d'attesa personalizzata.
Si compra una volta con Google Play, vale su ogni telefono Android con il tuo account Google e sblocca anche il computer collegato: sul Mac e su Windows non c'è niente da comprare. «Ripristina acquisti» è nella pagina WebcamLR Pro.

COSA SERVE
• Un telefono con Android 8 o successivo.
• WebcamLR sul Mac o sul PC, gratuita dal sito.

WebcamLR è in italiano e in inglese.
Aiuto: lr-apps609.github.io/WebcamLR/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/privacy.html
```
Conteggio: 3051/4000 caratteri

**English** <!-- campo gp.descrizione.en max=4000 -->
```text
WebcamLR turns your Android phone into the webcam for your Mac or PC. Video calls, lessons and live streams take the video from the phone's camera instead of the computer's webcam.

HOW IT WORKS
1. Install WebcamLR on the computer: it's free, from lr-apps609.github.io/WebcamLR (Mac with macOS 14 or later, PC with 64-bit Windows 10 or 11).
2. Open WebcamLR on the phone. On the same Wi-Fi network the computer shows up by itself; otherwise scan the computer's QR code.
3. The first time, confirm the 4-digit code on the computer. The video arrives in the WebcamLR window and, through the "WebcamLR" virtual webcam, in your video call and streaming apps.

CONNECTION
• Wi-Fi, the phone's hotspot or a USB cable with the phone's "USB tethering" (on Windows; on the Mac with some phones). No developer mode needed.
• If the connection in use drops, WebcamLR switches to the other one or reconnects by itself.
• Always in view: the connection in use and its quality in words ("Excellent", "Good", "Weak").
• When something's wrong, the app tells you the likely cause and what to do.
• The video keeps going with the screen off: the ongoing notification "WebcamLR · video to computer" says so, with "Disconnect".

YOUR VIDEO STAYS YOURS
• Video, audio and controls go from the phone to your computer, over your network or the cable, encrypted with new keys for every connection. They don't pass through our servers.
• A new computer is paired with its QR code or with the 4-digit confirmation code.
• No account, no ads.

FREE
• Video up to 720p at 30 fps, with no watermark and no time limit.
• Mirror, background blur and face lighting.
• Zoom, lenses, flashlight and exposure, from the computer too.
• The phone's microphone on the computer: on the Mac it shows up as "WebcamLR (microphone)"; on Windows it goes through a free virtual audio cable, installed separately.
• Phone face down: the video pauses without disconnecting. If the phone gets hot or the battery runs low, quality goes down and the app says so.

WEBCAMLR PRO: ONE PURCHASE, NO SUBSCRIPTION
• 1080p and 4K, up to 60 fps (4K at 30), where the phone supports it. On Windows, 4K needs "HEVC Video Extensions" from the Microsoft Store.
• Effects: filters and adjustments, background replaced with an image, skin smoothing, caption and logo in the video.
• Auto framing.
• Pro controls: ISO, shutter, white balance and focus.
• On the computer: Meeting, Lesson, Live stream and Interview profiles, photos and recording without audio, two phones at once, a custom waiting screen.
Buy it once with Google Play; it works on every Android phone with your Google account and unlocks the connected computer too: there's nothing to buy on the Mac or on Windows. "Restore purchases" is on the WebcamLR Pro page.

WHAT YOU NEED
• A phone with Android 8 or later.
• WebcamLR on your Mac or PC, free from the website.

WebcamLR is in English and Italian.
Help: lr-apps609.github.io/WebcamLR/en/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/en/privacy.html
```
Conteggio: 3011/4000 caratteri

### 3.5 Novità di questa versione

**Italiano** <!-- campo gp.novita.it max=500 -->
```text
Prima versione pubblica: il telefono come webcam per Mac e PC, con Wi-Fi, hotspot o cavo USB (tethering). Gratis fino a 720p a 30 fps senza filigrana; WebcamLR Pro con un acquisto unico.
```
Conteggio: 186/500 caratteri

**English** <!-- campo gp.novita.en max=500 -->
```text
First public version: your phone as a webcam for Mac and PC, over Wi-Fi, hotspot or USB cable (tethering). Free up to 720p at 30 fps with no watermark; WebcamLR Pro with a one-time purchase.
```
Conteggio: 190/500 caratteri

### 3.6 Categoria ed età

- Tipo **App**, categoria **Fotografia** (Photography); alternativa Strumenti.
- **Classificazione IARC** (categoria «Tutte le altre tipologie di app»): violenza, paura, sessualità, linguaggio, sostanze,
  gioco d'azzardo **No**; interazione o scambio di contenuti tra utenti **No** (il video va solo al computer di chi lo
  riprende); posizione condivisa **No**; acquisti digitali **Sì** (WebcamLR Pro); browser o accesso libero a internet **No**.
  Risultato atteso: **PEGI 3**, ESRB **E**, USK 0, con «Acquisti in-app».
- **Pubblico di destinazione**: 13–15, 16–17, 18+ (non sotto i 13: farebbe entrare l'app nelle norme Famiglie). Attira i
  bambini **No**. Annunci **No**. App governativa, finanza, salute, notizie, VPN **No**. Eliminazione dell'account: non c'è
  un account.

### 3.7 Screenshot e grafica

Telefono: PNG o JPEG a 24 bit, **da 2 a 8**, lato tra 320 e 3840 px, lato lungo al massimo il doppio del corto. Usare
**1080 × 1920** (lo screenshot grezzo 1080 × 2400 supera il 2:1: va ritagliato o composto). Grafica in primo piano
**1024 × 500**, icona **512 × 512**. Stesse regole di stile dell'iPhone; telefono finto «Pixel di Anna», computer «PC dello studio».

| # | Schermata | Stato da preparare | Didascalia IT | Caption EN |
| --- | --- | --- | --- | --- |
| 1 | In onda, verticale | Pillola **IN ONDA**, tondi (Specchia, Sfoca sfondo, Luce sul volto, Microfono al computer, Pausa), **Frontale** scelta, Sfoca sfondo acceso | Il telefono diventa la webcam del computer | Your phone becomes your computer's webcam |
| 2 | Lista dei computer | «PC dello studio» trovato, sotto «Inquadra il QR code del computer» e «Usa il cavo USB» | Trova il computer da solo, o con il QR code | Finds the computer by itself, or with a QR code |
| 3 | In onda con Tethering USB | Riga di stato del cavo, qualità «Ottimo» | Wi-Fi, hotspot o cavo USB | Wi-Fi, hotspot or USB cable |
| 4 | Tendina delle notifiche | Avviso «WebcamLR · video al computer» con «Scollega» | Il video continua a schermo spento | The video keeps going with the screen off |
| 5 | In onda con effetti | Sfondo sostituito e scritta con nome e ruolo, Pro attivo | Sfondo, filtri e scritta, dal computer | Background, filters and caption, from the computer |
| 6 | «Non trovo nessun computer» | Le cose da controllare dopo 15 secondi | Se qualcosa non va, ti dice cosa fare | If something's wrong, it tells you what to do |
| 7 | Pagina WebcamLR Pro, **Pro attivo** | Confronto Gratis/Pro (righe Android, senza Volto + scrivania né gobbo) | Pro: un acquisto, senza abbonamento | Pro: one purchase, no subscription |
| 8 | Finestra di WebcamLR su Windows (facoltativo) | Video del telefono, pillola IN ONDA, barra dei comandi | Il video arriva su Mac e Windows | The video arrives on Mac and Windows |

**Grafica in primo piano**: sfumatura del logo, logo LR e «WebcamLR» in Barlow Condensed, «Il telefono come webcam» / «Your
phone as a webcam»; a destra il disegno di un telefono su un supporto verso un portatile. Niente prezzi né inviti all'azione.

### 3.8 Permessi e motivi

Su Android i permessi non hanno un testo di sistema: le spiegazioni sono nell'ultima pagina della presentazione
(`presentazione_permessi_*`) e nei messaggi di permesso negato.

| Permesso (manifest) | Spiegazione nell'app | Cosa fa il codice | Giudizio |
| --- | --- | --- | --- |
| `CAMERA` | «Per mandare il video al computer. Senza, WebcamLR non può funzionare.» | Video e lettore QR (`LettoreQR.kt`, ZXing sul telefono) | coincide; si può aggiungere «e per leggere il QR code del computer» (come I5) |
| `RECORD_AUDIO` | «Per usare il telefono anche come microfono del computer, se lo accendi.» | Solo quando il microfono è acceso | coincide |
| `POST_NOTIFICATIONS` | «Per l'avviso «Video al computer» con «Scollega»…» | Avviso fisso del servizio in primo piano | coincide (il titolo vero è «WebcamLR · video al computer», il canale si chiama «Video al computer») |
| `FOREGROUND_SERVICE_CAMERA`, `_MICROPHONE` | avviso fisso | `ServizioInOnda`, tipo microfono solo con il permesso già dato | coincide; va dichiarato in Play Console (testi e video in `Materiale store.md` 4.5, ancora validi) |
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` | commento nel manifest: «Niente di tutto questo va su Internet» | mDNS e collegamento al computer; **ma** MediaPipe usa internet per le sue statistiche (I1) | il commento è vero per il nostro codice, non per la libreria |
| `WAKE_LOCK`, `VIBRATE` | nessuna (permessi normali) | video a schermo spento; vibrazione a faccia in giù | giusto |
| `com.android.vending.BILLING` | aggiunto dalla libreria Play Billing | acquisto di Pro | giusto |

Nessun permesso di posizione, contatti, file o `AD_ID` (da ricontrollare nel manifest unito della build di rilascio).

### 3.9 Sicurezza dei dati

Regole di Google: è raccolta la trasmissione fuori dal dispositivo, anche da parte delle librerie incluse; **non** si dichiarano i
dati cifrati end-to-end né quelli trattati solo sul dispositivo.

| Dato | Dove va | Da dichiarare? |
| --- | --- | --- |
| Video, audio, comandi, nome e modello del telefono, batteria, temperatura | Solo al computer dell'utente, cifrati end-to-end (ECDH P-256, AES-GCM) | **No** (eccezione end-to-end) |
| Immagine di sfondo o logo | Dal computer al telefono, cifrata; resta sul telefono (I3) | **No** |
| QR code | Letto sul telefono con ZXing, senza rete | **No** |
| Acquisto di Pro | Gestito da Google Play; token e ordine restano sul telefono | **No** dall'app (ricontrollare la pagina dati della Play Billing Library prima dell'invio) |
| «Segnala un bug» | Testo con il modello del telefono, se l'utente lo lascia, passato all'app di posta o condivisione scelta | **No** (lo manda l'utente) |
| **Statistiche di MediaPipe** | A Google, dalla libreria degli effetti | **Sì**, finché la libreria resta così (I1) |

**Scenario 1, consigliato** (telemetria di MediaPipe tolta e verificata sul telefono, `Materiale store.md` 4.4): «La tua app
raccoglie o condivide dati utente?» **No**.

**Scenario 2** (MediaPipe com'è): Raccoglie o condivide **Sì**; cifrati in transito **Sì**; richiesta di eliminazione **No**;
tipo **Informazioni e prestazioni dell'app › Diagnostica**, raccolti **Sì**, condivisi **Sì** (per prudenza), obbligatori,
finalità **Analisi**. E la privacy del sito va corretta con una frase su MediaPipe.

In entrambi: niente pubblicità, niente ID pubblicitario, niente posizione né contatti.

### 3.10 Istruzioni di accesso per la revisione

<!-- campo gp.revisione.en max=4000 -->
```text
No login or account. The app's main feature needs the free companion app on a computer on the same Wi-Fi network:
Windows 10/11: https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR-Setup.exe
macOS 14+: https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR.dmg
Open WebcamLR on both; the computer appears on the phone (or tap "Scan the computer's QR code" and scan the QR code in the computer window), confirm the 4-digit code on the computer and the video shows there. Without a computer you can review the tour, the help after 15 seconds of searching, Settings, App and support (guide, FAQ, Report a bug) and the WebcamLR Pro page. WebcamLR Pro is a one-time product (it.lrapps.webcamlr.pro), with no subscription. Demo video: [LINK VIDEO]
```
Conteggio: 780/4000 caratteri

---

## 4. Windows: Microsoft Store o installatore dal sito

### 4.1 Cosa è possibile

| | Installatore dal sito (`WebcamLR-Setup.exe`, oggi) | Microsoft Store con il nostro EXE | Microsoft Store con un pacchetto MSIX |
| --- | --- | --- | --- |
| Webcam virtuale Windows 11 (Media Foundation) | sì (amministratore una volta) | sì, è il nostro installatore | da provare: registrazione COM del pacchetto per Frame Server |
| Webcam virtuale Windows 10 (filtro DirectShow) | sì | sì | **no**: un MSIX non installa filtri DirectShow |
| Regola del firewall (reti private) | sì | sì | no come oggi (servirebbe un'altra strada) |
| Firma | **da fare** (oggi SmartScreen e Smart App Control bloccano o avvisano) | **obbligatoria** con un certificato riconosciuto (lo Store non firma un EXE) | la fa lo Store |
| Costo | firma: circa 10 USD/mese o 100–400 €/anno | firma + account Partner Center (singoli: gratuito, da verificare) | lavoro di qualche giorno |
| Note | aggiornamenti con «Aggiornamento disponibile» | l'installatore deve installare senza domande con un parametro e non scaricare altro (oggi scarica .NET 8 se manca: da verificare con le regole dello Store, o includere .NET) | |

**Consiglio per la 1.0**: installatore **firmato** dal sito. Lo Store dopo, come scheda che scarica il nostro EXE firmato
(serve a farsi trovare, non toglie la firma). I testi qui sotto valgono per la pagina di download e per la scheda dello Store.

Limiti dello Store (Partner Center, scheda di un'app MSI/EXE; `learn.microsoft.com` non era raggiungibile da qui, dati da
ricerca: **ricontrollarli in Partner Center**): descrizione 10 000 caratteri, descrizione breve 1000, novità 1500, fino a 20
funzionalità di 200 caratteri, fino a 7 termini di ricerca di 30 caratteri (21 parole in tutto), screenshot da 1 a 10.

### 4.2 Nome

«**WebcamLR**» (nome riservato in Partner Center; lo Store non ha un campo sottotitolo).

### 4.3 Descrizione breve

**Italiano** <!-- campo ms.breve.it max=1000 -->
```text
Usa la fotocamera del telefono (iPhone o Android) come webcam del PC, con il Wi-Fi o il cavo USB. Gratis fino a 720p a 30 fps, senza filigrana e senza account.
```
Conteggio: 159/1000 caratteri

**English** <!-- campo ms.breve.en max=1000 -->
```text
Use your phone's camera (iPhone or Android) as your PC's webcam, over Wi-Fi or USB cable. Free up to 720p at 30 fps, with no watermark and no account.
```
Conteggio: 150/1000 caratteri

### 4.4 Termini di ricerca (al posto delle parole chiave)

**Italiano** <!-- campo ms.ricerca.it max=30 righe=7 -->
```text
webcam
webcam virtuale
iphone come webcam
android come webcam
videocamera
videochiamate
fotocamera del telefono
```
Conteggio: 7/7 righe, la più lunga 23/30 caratteri, 14/21 parole

**English** <!-- campo ms.ricerca.en max=30 righe=7 -->
```text
webcam
virtual webcam
iphone webcam
android webcam
phone camera
video calls
streaming
```
Conteggio: 7/7 righe, la più lunga 14/30 caratteri, 12/21 parole

### 4.5 Descrizione

**Italiano** <!-- campo ms.descrizione.it max=10000 -->
```text
WebcamLR porta sul PC il video della fotocamera del telefono. Lo vedi nella finestra di WebcamLR e lo usi nelle app di videochiamata e di diretta tramite la webcam virtuale «WebcamLR».

COME FUNZIONA
1. Installa WebcamLR sul PC. L'installatore chiede una volta il permesso dell'amministratore per la webcam virtuale e per la regola del firewall (solo reti private).
2. Sul telefono apri WebcamLR (iPhone o Android, dagli store). Sulla stessa rete Wi-Fi il PC compare da solo; altrimenti inquadri il QR code «Collega il tuo telefono».
3. La prima volta confermi sul PC il codice di 4 cifre: il telefono diventa un telefono fidato e la volta dopo si ricollega da solo.
4. Nell'app di chiamata scegli «WebcamLR» come videocamera.

COLLEGAMENTO
• iPhone: Wi-Fi, Hotspot personale o cavo USB (serve l'app gratuita «Dispositivi Apple»). Se attacchi il cavo durante una chiamata, il video passa al cavo senza fermarsi.
• Telefono Android: Wi-Fi, hotspot o Tethering USB.
• Anche con il cavo di rete del PC.
• Il collegamento in uso e la sua qualità sono sempre scritti («Ottimo», «Buono», «Debole»); se qualcosa non va, WebcamLR dice la causa probabile e cosa fare.
• Video, audio e comandi viaggiano cifrati, con chiavi nuove a ogni collegamento, e non passano da nostri server.

REGIA DAL PC
• Specchia, Sfondo, Foto, Registra e Schermo in una barra, con lo stato scritto sotto ogni comando.
• Zoom, obiettivi, torcia, esposizione e messa a fuoco del telefono comandati dal PC.
• Pillola «IN ONDA» quando un'app usa il video, «In pausa» quando il telefono è a faccia in giù o WebcamLR è in sottofondo, con la schermata «Webcam in pausa» per le app di chiamata.
• Icona accanto all'orologio con lo stato, finestra mini sempre in primo piano, schermo intero (F11), Contrasto elevato.
• Microfono del telefono: WebcamLR manda la voce a un cavo audio virtuale gratuito, da installare a parte, che le app di chiamata vedono come microfono.

GRATIS
• Video fino a 720p a 30 fps, senza filigrana e senza limiti di tempo; specchia, sfondo sfocato, luce sul volto, microfono.

CON WEBCAMLR PRO, COMPRATO SUL TELEFONO
• 1080p e 4K, fino a 60 fps (il 4K a 30), effetti, inquadratura automatica. Il 4K arriva in HEVC e richiede le «Estensioni video HEVC» di Microsoft Store.
• Profili Riunione, Lezione, Diretta e Colloquio, e i tuoi.
• Foto e registrazione senza audio, nelle cartelle Immagini e Video › WebcamLR.
• Gobbo (con l'iPhone), due telefoni insieme, schermata d'attesa personalizzata.
Sul PC non c'è niente da comprare: le funzioni Pro si accendono quando è collegato un telefono con Pro.

COSA SERVE
• Windows 10 o 11 a 64 bit. Su Windows 11 la webcam virtuale è quella di sistema e la vedono tutte le app; su Windows 10 è un filtro DirectShow, che la maggior parte delle app di chiamata e dei browser vede, ma non l'app Fotocamera di Windows.
• WebcamLR sul telefono: iPhone con iOS 17 o successivo, oppure Android 8 o successivo.

Aiuto: lr-apps609.github.io/WebcamLR/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/privacy.html
```
Conteggio: 3027/10000 caratteri

**English** <!-- campo ms.descrizione.en max=10000 -->
```text
WebcamLR brings your phone camera's video to your PC. You see it in the WebcamLR window and use it in video call and streaming apps through the "WebcamLR" virtual webcam.

HOW IT WORKS
1. Install WebcamLR on the PC. The installer asks once for administrator permission for the virtual webcam and the firewall rule (private networks only).
2. On the phone open WebcamLR (iPhone or Android, from the stores). On the same Wi-Fi network the PC shows up by itself; otherwise scan the "Connect your phone" QR code.
3. The first time, confirm the 4-digit code on the PC: the phone becomes a trusted phone and reconnects by itself next time.
4. In your call app choose "WebcamLR" as the camera.

CONNECTION
• iPhone: Wi-Fi, Personal Hotspot or USB cable (you need the free "Apple Devices" app). Plug in the cable during a call and the video moves to the cable without stopping.
• Android phone: Wi-Fi, hotspot or USB tethering.
• Also with the PC's Ethernet cable.
• The connection in use and its quality are always written ("Excellent", "Good", "Weak"); if something's wrong, WebcamLR tells you the likely cause and what to do.
• Video, audio and controls are encrypted with new keys for every connection and don't pass through our servers.

CONTROL ROOM ON THE PC
• Mirror, Background, Photo, Record and Screen in one bar, with the state written under each control.
• Zoom, lenses, flashlight, exposure and focus of the phone, controlled from the PC.
• A "LIVE" pill when an app uses the video, "Paused" when the phone is face down or WebcamLR is in the background, with a "Webcam paused" screen for call apps.
• Icon next to the clock with the status, an always-on-top mini window, full screen (F11), High contrast.
• The phone's microphone: WebcamLR sends your voice to a free virtual audio cable, installed separately, that call apps see as a microphone.

FREE
• Video up to 720p at 30 fps, with no watermark and no time limit; mirror, background blur, face lighting, microphone.

WITH WEBCAMLR PRO, BOUGHT ON THE PHONE
• 1080p and 4K, up to 60 fps (4K at 30), effects, auto framing. 4K arrives in HEVC and needs "HEVC Video Extensions" from the Microsoft Store.
• Meeting, Lesson, Live stream and Interview profiles, and your own.
• Photos and recording without audio, in the Pictures and Videos › WebcamLR folders.
• Teleprompter (with an iPhone), two phones at once, a custom waiting screen.
There's nothing to buy on the PC: Pro features turn on when a phone with Pro is connected.

WHAT YOU NEED
• 64-bit Windows 10 or 11. On Windows 11 the virtual webcam is the system one and every app sees it; on Windows 10 it is a DirectShow filter that most call apps and browsers see, but not the Windows Camera app.
• WebcamLR on the phone: iPhone with iOS 17 or later, or Android 8 or later.

Help: lr-apps609.github.io/WebcamLR/en/aiuto.html
Privacy: lr-apps609.github.io/WebcamLR/en/privacy.html
```
Conteggio: 2891/10000 caratteri

### 4.6 Funzionalità (elenco dello Store)

**Italiano** <!-- campo ms.funzioni.it max=200 righe=20 -->
```text
Webcam virtuale «WebcamLR» per le app di videochiamata e di diretta
Collegamento con Wi-Fi, hotspot, cavo USB o cavo di rete
Video cifrato con chiavi nuove a ogni collegamento, senza nostri server
Gratis fino a 720p a 30 fps, senza filigrana e senza account
Comandi del telefono dal PC: zoom, obiettivi, torcia, esposizione
Icona accanto all'orologio, finestra mini e schermo intero
Con WebcamLR Pro: 1080p, 4K, 60 fps, effetti, profili
Con WebcamLR Pro: foto e registrazione senza audio, due telefoni insieme
```
Conteggio: 8/20 righe, la più lunga 72/200 caratteri

**English** <!-- campo ms.funzioni.en max=200 righe=20 -->
```text
"WebcamLR" virtual webcam for video call and streaming apps
Connection over Wi-Fi, hotspot, USB cable or Ethernet cable
Video encrypted with new keys for every connection, no servers of ours
Free up to 720p at 30 fps, with no watermark and no account
Phone controls from the PC: zoom, lenses, flashlight, exposure
Icon next to the clock, mini window and full screen
With WebcamLR Pro: 1080p, 4K, 60 fps, effects, profiles
With WebcamLR Pro: photos and recording without audio, two phones at once
```
Conteggio: 8/20 righe, la più lunga 73/200 caratteri

### 4.7 Novità della versione

**Italiano** <!-- campo ms.novita.it max=1500 -->
```text
Prima versione pubblica. Webcam virtuale «WebcamLR» su Windows 11 e 10, collegamento con Wi-Fi o cavo USB, finestra con la Mica e una sola barra del titolo, icona accanto all'orologio, Contrasto elevato.
```
Conteggio: 203/1500 caratteri

**English** <!-- campo ms.novita.en max=1500 -->
```text
First public version. "WebcamLR" virtual webcam on Windows 11 and 10, connection over Wi-Fi or USB cable, a window with Mica and a single title bar, an icon next to the clock, High contrast.
```
Conteggio: 190/1500 caratteri

### 4.8 Categoria ed età

- **Categoria**: **Foto e video** (Photo & video); sottocategoria, se proposta, quella più vicina a «Video».
- **Età**: questionario IARC in Partner Center, come Play: tutto No, nessun acquisto **nell'app Windows** (Pro si compra sul
  telefono). Atteso **PEGI 3 / ESRB E**.

### 4.9 Screenshot

Desktop: PNG, **1920 × 1080** (sopra il minimo di 1366 × 768; da ricontrollare in Partner Center), da 1 a 10, didascalia fino a
200 caratteri. Finestra in tema scuro con la Mica su uno sfondo scuro neutro; per la pagina di download le stesse immagini.

| # | Schermata | Stato da preparare | Didascalia IT | Caption EN |
| --- | --- | --- | --- | --- |
| 1 | Finestra principale, In onda | Video del telefono, pillola **IN ONDA**, barra dei comandi con «Acceso» sotto Sfondo, colonna Telefoni con «iPhone di Anna» | Il video del telefono, pronto per le chiamate | Your phone's video, ready for calls |
| 2 | Primo avvio | QR «Collega il tuo telefono» al centro | Si collega con un QR code | Connects with a QR code |
| 3 | Conferma del telefono | Codice di conferma di 4 cifre | Un telefono nuovo si conferma con 4 cifre | A new phone is confirmed with 4 digits |
| 4 | Profili | Riunione scelto, Pro attivo | Profili per riunioni, lezioni e dirette | Profiles for meetings, lessons and live streams |
| 5 | Finestra mini | Finestra mini sopra un documento | Finestra mini sempre in primo piano | Always-on-top mini window |
| 6 | Icona accanto all'orologio | Menu dell'icona aperto, stato «In onda» | Lo stato anche a finestra chiusa | Status even with the window closed |
| 7 | Contrasto elevato | Stessa finestra con un tema a contrasto elevato di Windows | Leggibile anche con il Contrasto elevato | Readable with High contrast too |

### 4.10 Privacy e permessi

- Partner Center chiede se l'app accede, raccoglie o trasmette dati personali: **No** (con I2 risolto) e l'URL della privacy
  comunque. L'app legge solo `versione.json` (`Aggiornamenti.cs`); l'installatore scarica .NET 8 da Microsoft se manca (I11).
- Windows non ha testi di permesso per le app desktop: l'unica domanda è quella dell'amministratore (webcam e firewall), detta
  prima dall'installatore (due Task Dialog, 06cde7f). Il firewall chiede solo le reti private.
- Un eventuale MSIX dichiarerebbe `internetClient`, `privateNetworkClientServer` e `runFullTrust`; non serve la capacità webcam
  (WebcamLR la fornisce, non la usa).

---

## 5. Come si controllano i testi

Script: `controlla_store.py`, nella scratchpad della sessione (fuori dalla repository, come chiesto). Legge questo documento,
prende il blocco che segue ogni commento `campo`, conta caratteri (o byte UTF-8 per le parole chiave di Apple, o righe per
termini di ricerca e funzionalità), riscrive la riga «Conteggio» e cerca:
- le parole vietate dal Glossario e dalle decisioni: «smartphone», «Selfie», superlativi («migliore», «best», «n. 1»…),
  promesse non dimostrabili («zero latenza», «no lag»), nomi di concorrenti, funzioni tolte o assenti («Prova la webcam»,
  «Lingua dei segni»), «connetti/disconnetti», prezzi;
- nei testi pubblici: nomi di app di terzi (Teams, FaceTime, OBS…); nei testi italiani: parole inglesi da evitare (stream,
  device, background…);
- per store: «Android»/«Google Play» nei campi Apple; «iPhone», «App Store», «Volto + scrivania», «gobbo», «Wi-Fi diretto» nei
  campi Play;
- «abbonamento» / «subscription» solo come «senza abbonamento» / «no subscription»;
- registrazione sempre con «senza audio» / «without audio».

Uso: `python3 controlla_store.py Documenti/Store.md` (esce con errore se un campo non va). Al primo giro ha trovato quattro
problemi, tutti nelle note per i revisori (tre «not a subscription», da scrivere «no subscription»; una registrazione senza
«without audio»), poi corretti: 48 campi, 0 problemi.

---

## Verifiche nel codice (30 ottobre, `beta4` 842615b)

| Affermazione | Dove |
| --- | --- |
| Gratis: 720p30 senza filigrana, Wi-Fi e cavo, Specchia, Sfoca lo sfondo, Luce sul volto, microfono, zoom/torcia/esposizione, collegamento sicuro | `Stile/Sources/Stile/Pro.swift` (`ConfrontoPro.gratis`), Android `strings.xml` `pro_gratis_1…8` |
| Pro iPhone: 1080p e 4K fino a 60 fps (il 4K a 30), inquadratura, Volto + scrivania, filtri, sfondo, ritocco, scritta e logo, controlli Pro; sul computer profili, foto e registrazione, gobbo, due telefoni, schermata d'attesa | `ConfrontoPro.pro` |
| Pro Android: come sopra senza Volto + scrivania e senza gobbo; «vale su ogni telefono Android con il tuo account Google» | `strings.xml` `pro_pro_*`, `pro_attivo_vale` |
| Acquisto unico, «senza abbonamento», In famiglia, «Ripristina acquisti» | `pro_invito`, `SchermataPro.swift`, `NegozioPro.swift`/`.kt` |
| Pagina Pro dall'iPhone: pulsante «PRO Sblocca» in alto o Impostazioni › WebcamLR Pro | `SchermataConnessione.swift` 398, `SchermataImpostazioni.swift` 16 |
| Ingranaggio come unico ingresso in alto; «App e assistenza» dentro le Impostazioni | `SchermataConnessione.swift` 374–390 |
| Aiuto dopo 15 secondi | `SchermataConnessione.swift` 33 |
| Gobbo sul telefono, vicino all'obiettivo, fuori dal video | `iPhone/Sorgenti/GobboTelefono.swift` |
| Registrazione senza audio | `Mac/Sorgenti/ContenutoPrincipale.swift`, `Riprese.swift`; Glossario |
| Microfono Mac «WebcamLR (microphone)»; Windows con cavo audio virtuale | `Mac/Sorgenti/Impostazioni.swift`; `Windows/WebcamLR.Ricevitore/Risorse/Testi.resx` |
| 4K su Windows con «Estensioni video HEVC» | `Testi.resx` |
| Webcam virtuale Windows 11 Media Foundation, Windows 10 DirectShow | `Pubblicazione.md` 7, `Compatibilità webcam.md` |
| Avviso Android «WebcamLR · video al computer» con «Scollega» (EN «WebcamLR · video to computer», «Disconnect») | `strings.xml` 354, `values-en` 352, `ServizioInOnda.kt` 116–122 |
| Requisiti: iOS 17, macOS 14, Android 8 (`minSdk 26`), Windows 10/11 64 bit | `iPhone/project.yml`, `Mac/base.yml`, `build.gradle.kts`, `Pubblicazione.md` |
| Nessuna richiesta in rete nell'app iPhone; Mac e Windows solo `versione.json` | ricerca di `URLSession`/`HttpClient`: `ControlloAggiornamenti.swift`, `Aggiornamenti.cs` (e l'installatore per .NET) |
| Dipendenze di terzi: Android MediaPipe 0.10.14, Billing 7.1.1, ZXing; Windows ONNX Runtime 1.24.4, QRCoder, H.NotifyIcon | `build.gradle.kts`, `*.csproj` |
| «Prova la webcam» tolta dall'interfaccia | 49f78ea |

## Fonti

- Limiti e regole Apple e Google come letti il 26 ottobre (elenco in `Materiale store.md`, «Fonti»).
- Microsoft Store, scheda delle app MSI/EXE (descrizione breve 1000, 7 termini di ricerca di 30 caratteri, fino a 20
  funzionalità, screenshot da 1 a 10, didascalie di 200): https://learn.microsoft.com/windows/apps/publish/publish-your-app/msi/create-app-submission ·
  https://developer.microsoft.com/microsoft-store/search-optimization · https://learn.microsoft.com/windows/uwp/publish/store-policies
  (da ricontrollare in Partner Center: la pagina non era raggiungibile da questo ambiente).
- Apple App Review Guidelines 2.4.5 (app Mac: sandbox, aggiornamenti dallo store), 3.1.1 e 3.1.3(b) (acquisti su più
  piattaforme): https://developer.apple.com/app-store/review/guidelines/
