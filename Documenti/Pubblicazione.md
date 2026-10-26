# Pubblicazione di WebcamLR · Mac, iPhone e Windows

Guida passo passo per Ledion: dall'account Apple fino al dmg su GitHub e all'app su TestFlight e App Store.
Le parti già pronte nella repository:

| Cosa | Dove |
| --- | --- |
| Versione e numero di build di Mac e iPhone, in un solo posto | `Strumenti/Versione.xcconfig` (oggi 1.0, build 2) |
| Cambiare versione | doppio clic su `Strumenti/Nuova versione.command` |
| dmg del Mac e pacchetto del microfono, firmati e notarizzati | doppio clic su `Strumenti/Crea dmg.command` |
| Identità di firma e profilo di notarizzazione | `Strumenti/firma.txt` (solo sul tuo Mac; esempio in `Strumenti/firma.esempio.txt`) |
| WebcamLR Pro (acquisto in-app) da provare in Xcode senza App Store Connect | `iPhone/WebcamLR.storekit`, già scelto nello schema (`iPhone/project.yml`) |

Windows: installatore e firma nella sezione 7. Android è in pausa: la sua sezione arriverà con il lavoro su quella piattaforma.

> Gli script sono stati scritti su Linux, dove non ci sono Xcode né gli strumenti di firma di Apple: il primo giro
> sul Mac può segnalare errori da correggere. Se succede, manda a Claude `Strumenti/ultima-build.log`.

---

## 1. Account sviluppatore Apple (una volta)

Serve per tutto quello che è «per gli altri»: webcam virtuale, dmg che si apre senza avvisi, TestFlight, App Store.
Con l'Apple ID gratuito puoi solo provare sui tuoi dispositivi.

1. Vai su https://developer.apple.com/programs/enroll/ e accedi con il tuo Apple ID (con l'autenticazione a due fattori attiva).
2. Scegli il tipo:
   - **Individuale**: il venditore che compare sull'App Store è il tuo nome e cognome. Bastano i documenti personali.
   - **Organizzazione** (per esempio «LR Apps» se è un'azienda vera): serve il **numero D-U-N-S** dell'azienda (gratuito, da
     richiedere a Dun & Bradstreet: può volerci anche una settimana) e un sito web dell'azienda.
3. Paga la quota annuale (99 USD, in Italia circa 99 € all'anno). L'approvazione arriva di solito in 1–2 giorni.
4. Quando l'account è attivo, in Xcode › Impostazioni › **Account** aggiungi l'Apple ID: deve comparire il team con «Developer Program».
5. Copia il **Team ID** (10 caratteri, su https://developer.apple.com/account › Membership details) in `Strumenti/team.txt`
   e scrivi `completo` in `Strumenti/account.txt`. Da qui gli script costruiscono anche la webcam virtuale.

## 2. Certificati per il Mac (una volta)

Per distribuire il Mac fuori dal Mac App Store servono due certificati **Developer ID**. Li può creare solo il
**titolare dell'account** (Account Holder), cioè tu.

1. Xcode › Impostazioni › Account › seleziona il team › **Manage Certificates…**
2. Pulsante **+** in basso a sinistra › **Developer ID Application**. Firma l'app, il driver audio e il dmg.
3. Di nuovo **+** › **Developer ID Installer**. Firma il pacchetto del microfono (`.pkg`).
4. Controlla nel Terminale che ci siano tutti e due:
   ```
   security find-identity -v
   ```
   Devono comparire due righe come `"Developer ID Application: Nome Cognome (TEAMID1234)"` e `"Developer ID Installer: …"`.
5. **Fai una copia di sicurezza**: in Accesso Portachiavi › Certificati, seleziona i due certificati (con la chiave privata),
   clic destro › Esporta… › formato `.p12` con una password. Tienila in un posto sicuro (non nella repository): se perdi la chiave
   privata, devi revocare e rifare i certificati. Apple ne concede pochi (Developer ID Application al massimo 5).

`Crea dmg.command` trova da solo i certificati se ce n'è uno per tipo. Se ne hai più di uno, scrivi i nomi esatti in
`Strumenti/firma.txt` (vedi `firma.esempio.txt`).

### Webcam virtuale con Developer ID

La webcam virtuale (Camera Extension) ha bisogno dei profili di provisioning **Developer ID** con il permesso
«System Extension». `Crea dmg.command` li fa creare a Xcode da solo (`-allowProvisioningUpdates`, firma automatica):
basta che Xcode sia collegato all'account. Se l'esportazione si ferma con un errore sui profili:

1. https://developer.apple.com/account/resources/identifiers › `it.lrapps.webcamlr.mac` › controlla che **System Extension**
   e **App Groups** siano accesi (Xcode li accende alla prima build con l'account).
2. Rilancia lo script. Se ancora non va, manda a Claude `Strumenti/ultima-build.log`.

## 3. Notarizzazione (una volta)

La notarizzazione è il controllo automatico di Apple: senza, macOS blocca l'app scaricata da Internet («Apple non può
verificare…»). Lo script usa `notarytool` con un **profilo** salvato nel Portachiavi, così la password non è mai in un file.

1. Vai su https://account.apple.com › **Accesso e sicurezza** › **Password specifiche per le app** › **+**, chiamala «notarytool»
   e copia la password (formato `abcd-efgh-ijkl-mnop`).
2. Nel Terminale (sostituisci email e Team ID):
   ```
   xcrun notarytool store-credentials "webcamlr" --apple-id TUA@EMAIL --team-id TEAMID1234
   ```
   Alla domanda incolla la password del punto 1.
3. In `Strumenti/firma.txt` scrivi `PROFILO_NOTARIZZAZIONE=webcamlr`.

In alternativa puoi usare le variabili d'ambiente `WEBCAMLR_FIRMA_APP`, `WEBCAMLR_FIRMA_INSTALLER` e
`WEBCAMLR_PROFILO_NOTARIZZAZIONE` al posto di `firma.txt`.

## 4. Creare il dmg del Mac (a ogni versione)

1. Se è una versione nuova: doppio clic su `Strumenti/Nuova versione.command`, scrivi la versione (per esempio `1.1`) e fai il commit
   di `Strumenti/Versione.xcconfig`. Con Invio senza scrivere niente sale solo il numero di build.
2. Doppio clic su **`Strumenti/Crea dmg.command`**. Lo script:
   - costruisce WebcamLR in **Release** (con l'account a pagamento anche la webcam virtuale);
   - con «Developer ID Application»: archivia ed esporta con Developer ID (runtime protetto);
     senza: firma «Apple Development» (account a pagamento, va solo sui Mac registrati) o locale
     («Sign to Run Locally», Apple ID gratuito, va solo su questo Mac);
   - costruisce **`WebcamLR Microfono.pkg`**: il driver audio in `/Library/Audio/Plug-Ins/HAL`, l'aiutante in
     `/Library/Application Support/WebcamLR` e il suo LaunchDaemon. Lo script dopo l'installazione avvia l'aiutante e riavvia
     l'audio del Mac (come `Installa microfono.command`). Driver e aiutante sono firmati Developer ID con il runtime protetto,
     il pacchetto con «Developer ID Installer»;
   - notarizza il pacchetto e attacca il ticket («staple»);
   - crea **`WebcamLR.dmg`** (formato compresso UDZO) con WebcamLR, il collegamento ad «Applicazioni» e il pacchetto del
     microfono, lo firma, lo notarizza e attacca il ticket.
3. Alla fine si apre la cartella `~/Library/Developer/WebcamLR/Pubblicazione/<versione>` con i file. Il riepilogo dice
   chiaramente cosa manca (certificato, profilo) e se il dmg è pronto da pubblicare.

Se Apple rifiuta la notarizzazione, il motivo è nel file `notarizzazione-….json` nella stessa cartella: mandalo a Claude.

### Prova prima di pubblicare (su un altro Mac o un altro utente del Mac)

1. Scarica il dmg come lo scaricherebbe un utente (per esempio da un'anteprima della release su GitHub) e aprilo con un doppio clic:
   nessun avviso «sviluppatore non identificato».
2. Trascina WebcamLR in Applicazioni e aprila: si apre senza avvisi. Controllo nel Terminale:
   ```
   spctl -a -vv /Applications/WebcamLR.app        # deve dire: accepted, source=Notarized Developer ID
   xcrun stapler validate /Applications/WebcamLR.app
   ```
3. Doppio clic su «WebcamLR Microfono.pkg» nel dmg: installa chiedendo la password; in Impostazioni di Sistema › Suono › Ingresso
   compare «WebcamLR (microfono)». In WebcamLR › Impostazioni › Microfono del telefono: «Microfono installato · versione …»;
   «Rimuovi il microfono…» lo toglie senza password.
4. Webcam virtuale: attivazione come in `Documenti/Webcam virtuale Mac.md` (l'utente deve approvarla in Impostazioni di Sistema).
5. Un giro di `Documenti/Checklist 1.0.md` con il telefono.

### Prima della prima pubblicazione pubblica

- ✅ **Controllo di chi chiede il microfono**: l'aiutante dà la memoria condivisa solo a WebcamLR con il Team ID della propria
  firma e a coreaudiod (`Documenti/Microfono Mac.md`, *Sicurezza*). Con Developer ID il team è quello del dmg: niente da fare in più.
- ✅ **Disinstallazione del microfono**: dall'app, Impostazioni › Microfono del telefono › «Rimuovi il microfono…» (un secondo
  LaunchDaemon, root, che risponde solo a WebcamLR). Resta anche `Strumenti/Rimuovi microfono.command`.
- **Mac App Store**: non ora. Le eccezioni del sandbox per il cavo USB e per il microfono non sono accettate (decisione in sospeso,
  `Documenti/Piano aggiornamenti.md`, 1.8): il Mac si distribuisce dal sito.

## 5. iPhone: TestFlight, poi App Store

### Una volta

1. https://appstoreconnect.apple.com › **App** › **+** › **Nuova app**:
   - Piattaforma iOS, nome «WebcamLR» (se è già preso, per esempio «WebcamLR – webcam dal telefono»), lingua principale Italiano;
   - ID pacchetto: `it.lrapps.webcamlr.iphone` (se non c'è nell'elenco, prima fai una build con l'account a pagamento:
     Xcode lo registra da solo);
   - SKU: un codice tuo, per esempio `webcamlr-iphone`.
2. In **Contratti** (Business) accetta il contratto delle app gratuite; per le app a pagamento o gli acquisti servono anche
   dati bancari e fiscali.

### WebcamLR Pro: l'acquisto in-app (una volta)

WebcamLR resta gratis (720p a 30 fps, senza filigrana). **WebcamLR Pro** è un solo acquisto **non consumabile**, senza account:
si compra sull'iPhone, vale per sempre, si condivide In famiglia e sblocca anche il Mac tramite il telefono collegato
(`capacita.pro`, `Documenti/Protocollo.md`). Nel codice: `iPhone/Sorgenti/NegozioPro.swift` (StoreKit 2). Il prezzo non è
scritto da nessuna parte nell'app: si legge sempre dall'App Store (`displayPrice`), quindi il prezzo di lancio compare da solo.

1. **Contratto per le app a pagamento**: App Store Connect › **Contratti** › «Paid Apps» (app a pagamento), con dati bancari e
   fiscali compilati. Senza, l'acquisto non compare nemmeno in TestFlight.
2. App Store Connect › la tua app › **Monetizzazione** › **Acquisti in-app** › **+**:
   - Tipo: **Non consumabile**
   - Nome di riferimento: `WebcamLR Pro` (lo vedi solo tu)
   - ID prodotto: **`it.lrapps.webcamlr.pro`**: uguale al codice (`ConfrontoPro.idProdotto` in `Stile/Sources/Stile/Pro.swift`) e a
     `iPhone/WebcamLR.storekit`. Una volta creato non si cambia e non si riusa.
3. **Disponibilità**: tutti i paesi in cui c'è l'app.
4. **Programma dei prezzi** (Price Schedule): i non consumabili non hanno offerte introduttive, il prezzo di lancio si fa con una
   modifica di prezzo a tempo.
   - **Prezzo base**: paese di riferimento **Italia**, **14,99 €** (gli altri paesi li calcola Apple; si possono ritoccare a mano).
   - **Prezzo di lancio**: «Aggiungi modifica di prezzo» (Add Pricing / Planned Price Change) › **9,99 €**, data di inizio = il giorno
     dell'uscita, data di fine = fine del lancio (per esempio 4 settimane dopo). Alla data di fine torna da solo a 14,99 €.
   - Nell'app il pulsante dice «Sblocca Pro · 9,99 €» durante il lancio e «Sblocca Pro · 14,99 €» dopo, senza nuove versioni.
5. **Localizzazione** (Italiano e Inglese), nome al massimo 35 caratteri e descrizione al massimo 55:
   - IT: nome «WebcamLR Pro», descrizione «1080p, 4K, 60 fps, effetti e tutto il Mac. Per sempre.»
   - EN: nome «WebcamLR Pro», descrizione «1080p, 4K, 60 fps, effects and the whole Mac. Forever.»
6. **In famiglia**: attiva **Condivisione in famiglia**. Attenzione: una volta attivata non si può più spegnere (va bene così, è
   la scelta di Ledion).
7. **Informazioni per la revisione** dell'acquisto: uno screenshot della pagina «WebcamLR Pro» sull'iPhone (App › WebcamLR Pro, con
   il pulsante «Sblocca Pro») e la nota qui sotto (*Note per la revisione*).
8. Il **primo** acquisto in-app si invia **insieme a una versione dell'app**: nella pagina della versione, sezione «Acquisti in-app e
   abbonamenti», seleziona WebcamLR Pro prima di «Aggiungi per la revisione». Dalla volta dopo l'acquisto è già approvato.
9. Nell'app non serve altro: con StoreKit 2 non ci sono entitlement da aggiungere né ricevute da controllare su un server
   (la verifica la fa StoreKit sul telefono, `VerificationResult`).

**Provarlo prima di App Store Connect (Apple ID gratuito, in Xcode)**: lo schema «WebcamLR» usa già `iPhone/WebcamLR.storekit`
(Product › Scheme › Edit Scheme › Run › Options › StoreKit Configuration). Con ▶ gli acquisti sono finti e gratuiti; da Xcode,
menu **Debug › StoreKit › Manage Transactions…** si vedono gli acquisti, si **rimborsano** (Refund), si cancellano e si prova
«Chiedi di acquistare» (Enable Ask to Buy). Il prezzo del file è 14,99 € (Italia): per vedere il prezzo di lancio cambialo a 9,99 nel
file aperto in Xcode, senza salvarlo nella repository. Le prove sono nella sezione **Z** di `Checklist iPhone e Mac.md`.

**In TestFlight** gli acquisti usano la sandbox di Apple: sono gratuiti, «Ripristina acquisti» funziona, il prezzo è quello di
App Store Connect. In famiglia e i rimborsi veri non si provano in sandbox (i rimborsi si provano in Xcode, sopra).

**Privacy**: l'acquisto lo gestisce Apple. WebcamLR non manda a nessuno dati dell'acquisto; tiene sul telefono solo l'`originalID`
della transazione (per collegare un account facoltativo in futuro). «Nessun dato raccolto» resta valido.

### A ogni versione (TestFlight)

1. `Strumenti/Nuova versione.command`: ogni invio ad App Store Connect vuole un **numero di build nuovo**, anche se la versione
   resta uguale (in quel caso premi solo Invio).
2. Doppio clic su `Strumenti/Costruisci e installa.command` (rigenera il progetto iPhone con la versione nuova e lo apre in Xcode).
3. In Xcode, in alto, scegli come destinazione **Any iOS Device (arm64)**, poi menu **Product › Archive**.
4. Si apre l'Organizer: **Distribute App** › **App Store Connect** › **Distribute**. Xcode firma e carica.
5. Dopo 10–30 minuti la build compare in App Store Connect › la tua app › **TestFlight**.
   - **Conformità crittografica**: non compare più. L'Info.plist dichiara `ITSAppUsesNonExemptEncryption = NO`
     (`iPhone/project.yml`): WebcamLR cifra video e comandi solo con la crittografia di iOS (CryptoKit). Il perché è nella
     sezione *Cifratura ed esportazione* qui sotto. Se App Store Connect chiede comunque qualcosa, rispondi come lì.
   - **Tester interni** (fino a 100 persone del team): subito, senza revisione.
   - **Tester esterni** (fino a 10 000, anche con un link pubblico): la prima build passa una breve revisione di Apple (di solito
     un giorno). Crea un gruppo, aggiungi la build e attiva il **link pubblico**: è il link per il sito («iphone-testflight»).
6. Chi prova installa l'app **TestFlight** dall'App Store e apre il link.

### Manifesto della privacy (fatto)

Apple vuole un file `PrivacyInfo.xcprivacy` in ogni bundle che contiene un eseguibile e usa le API «con motivo» (*required
reason API*); da maggio 2024 App Store Connect rifiuta le app iOS che le usano senza dichiararle. Ci sono già:

| Bundle | File | Cosa dichiara |
| --- | --- | --- |
| App iPhone | `iPhone/Privacy/PrivacyInfo.xcprivacy` | UserDefaults **CA92.1**; tempo dall'avvio (`ProcessInfo.systemUptime`) **35F9.1** |
| App Mac | `Mac/Privacy/App/PrivacyInfo.xcprivacy` | UserDefaults **CA92.1**; spazio libero (`volumeAvailableCapacityForImportantUsageKey`, avviso durante la registrazione) **85F4.1** ed **E174.1**; tempo dall'avvio **35F9.1** (per prudenza, vedi sotto) |
| Webcam virtuale (Camera Extension) | `Mac/Privacy/FotocameraVirtuale/PrivacyInfo.xcprivacy` | tempo dall'avvio **35F9.1** (per prudenza) |
| Pacchetto Stile (`Stile_Stile.bundle`, solo risorse) | `Stile/Sources/Stile/Resources/PrivacyInfo.xcprivacy` | niente: il suo codice è collegato nelle app e conta nei loro manifesti |

In tutti: `NSPrivacyTracking` falso, nessun dominio di tracciamento, **nessun tipo di dato raccolto**. Controllato nel codice:
- l'unica richiesta in rete è `versione.json` dal Mac (`ControlloAggiornamenti.swift`), senza dati dell'utente;
- video, audio e comandi vanno solo dal telefono al computer dell'utente, cifrati, sulla rete locale o sul cavo;
- l'acquisto di WebcamLR Pro passa da StoreKit (lo gestisce Apple; sul telefono resta solo l'`originalID`);
- «Segnala un bug» apre Mail (`mailto:`) o il foglio di condivisione: il testo lo vede e lo manda l'utente, se vuole. Per Apple i dati
  mandati dall'utente in una segnalazione facoltativa non contano come raccolti (*App privacy details*, «optional disclosure»).

Le API cercate nel codice (`grep`): UserDefaults/`@AppStorage` (iPhone e Mac), `systemUptime` (iPhone), spazio libero (Mac). Nessuna
data di file (`creationDate`, `modificationDate`, `stat`…: `Riprese.swift` usa `attributesOfItem` solo per la dimensione, e
`attributesOfItem` non è nell'elenco di Apple), nessuna tastiera attiva. Il tempo dall'avvio sul Mac passa da `DispatchTime` e
`clock_gettime(CLOCK_UPTIME_RAW)`, che l'elenco di Apple non nomina (nomina `systemUptime` e `mach_absolute_time`): dichiararlo con
35F9.1 (tempo tra eventi dell'app) è innocuo e copre il caso in cui Apple li consideri equivalenti.

Fonti: Apple, *Describing use of required reason API* e *NSPrivacyAccessedAPIType* (developer.apple.com/documentation/bundleresources,
lette il 26 ottobre 2026: codici e testi dei motivi qui sopra presi da lì); *Privacy manifest files*. Il driver e l'aiutante del
microfono non sono nell'app (si installano a parte) e non hanno bisogno del manifesto. Fuori dall'App Store Apple non controlla i
manifesti del Mac: li teniamo veri lo stesso. Prova in Xcode (Privacy Report dell'archivio): riga **03** di `Checklist iPhone e Mac.md`.

### Cifratura ed esportazione (fatto)

**Decisione:** `ITSAppUsesNonExemptEncryption = NO` nell'Info.plist dell'iPhone (`iPhone/project.yml`) e, per il futuro, del Mac
(`Mac/base.yml`).

Perché:
- WebcamLR cifra solo i **propri dati in viaggio** (video, audio, comandi verso il computer dell'utente) con **CryptoKit**, cioè la
  crittografia di iOS e macOS: AES-GCM, accordo di chiavi ECDH P-256, firme ECDSA P-256, HKDF e SHA-256 (`Protocollo/…/Sicurezza.swift`).
  Nessun algoritmo nostro e nessuna libreria di crittografia inclusa (niente OpenSSL, niente libsodium).
- Apple, *Complying with Encryption Export Regulations*: «Set the value to NO if your app … only uses forms of encryption that are
  exempt from export compliance documentation requirements … Typically, the use of encryption that's built into the operating
  system … is exempt … whereas the use of proprietary encryption is not.»
- App Store Connect, *Export compliance documentation for encryption*: «Your app uses encryption limited to that within the Apple
  operating system → No documentation required». Documenti servono solo per algoritmi standard **non** forniti dal sistema
  (dichiarazione francese) o per algoritmi proprietari (CCATS e dichiarazione francese).
- Quindi WebcamLR è nel caso «senza documenti» e NO è la risposta giusta: non serve rispondere SÌ e poi chiedere l'esenzione.
  Nel questionario di App Store Connect (se ricompare) le risposte equivalenti sono: usa la cifratura → sì; tipo di algoritmi →
  «nessuno di quelli elencati» (cioè solo quelli del sistema operativo).
- Rapporto annuale di autoclassificazione negli Stati Uniti: Apple dice che con la cifratura esente «potrebbe» servire. Dal 2021 le
  regole statunitensi (EAR, 740.17(b)(1)) non lo chiedono più per i prodotti «mass market» come questo; **da ricontrollare** con
  chi segue la parte legale prima del lancio (non è una cosa che Apple verifica).
- **Mac fuori dallo store**: la notarizzazione non chiede nulla sulla cifratura e il dmg non passa da App Store Connect. La chiave
  nel Mac non serve oggi; c'è perché è vera e servirà se l'app andrà sul Mac App Store.
- Se un giorno entra un algoritmo o una libreria di crittografia non di Apple, la decisione va rifatta.

Fonti: developer.apple.com/documentation/security/complying-with-encryption-export-regulations;
developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption;
developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption (lette il 26 ottobre 2026).

### App Store

1. App Store Connect › la tua app › la versione (per esempio 1.0):
   - **Screenshot**: almeno quelli per iPhone da 6,9" (1320 × 2868 o 2868 × 1320); gli altri formati si ricavano da quelli;
   - descrizione, parole chiave, URL di supporto (`https://lr-apps609.github.io/WebcamLR/aiuto.html`) e URL della privacy
     (`https://lr-apps609.github.io/WebcamLR/privacy.html`: prima va completata la bozza, vedi `Sito/LEGGIMI.md` sul ramo `sito`).
     I testi della scheda in italiano e in inglese (localizzazione Inglese (Stati Uniti), che Apple mostra anche negli altri paesi
     senza una lingua propria) sono qui sotto, in *Testi della scheda*: **bozza da rivedere** prima della prima pubblicazione;
   - **Privacy dell'app**: WebcamLR non raccoglie dati (video e audio vanno solo al computer dell'utente, cifrati): «Nessun dato raccolto»,
     se è ancora vero quando pubblichi;
   - categoria Foto e video; classificazione per età dal questionario.
2. **Note per la revisione**: spiega che l'app manda il video a WebcamLR per Mac o Windows sulla stessa rete Wi-Fi, e allega un
   breve video che lo mostra (il revisore di solito non ha il programma sul computer). Indica il link per scaricare WebcamLR per Mac.
   Per l'acquisto in-app aggiungi (in inglese, così lo legge chiunque):
   > WebcamLR Pro (it.lrapps.webcamlr.pro) is a one-time, non-consumable in-app purchase with Family Sharing. The free version
   > is fully usable (720p at 30 fps, no watermark). Pro unlocks 1080p/4K/60 fps, filters, background replacement, skin smoothing,
   > captions, auto framing, face + desk and manual camera controls, plus the matching features of the free WebcamLR for Mac app
   > when this iPhone is connected (the Mac app sells nothing: it only reads whether the connected iPhone has Pro). Purchase and
   > “Restore Purchases” are in the app: tap (i) › WebcamLR Pro. Pro-only controls show a “PRO” badge and open that page.
   Il video allegato può mostrare anche il segno «PRO» e lo sblocco dopo l'acquisto (registrato in Xcode o in TestFlight).
3. Scegli la build già provata su TestFlight › **Aggiungi per la revisione** › **Invia**. La revisione dura di solito 1–2 giorni.
4. Dopo l'approvazione: pubblicazione manuale o automatica. Il link dell'App Store (`https://apps.apple.com/app/id<numero>`, il numero
   è in App Store Connect › Informazioni sull'app › ID Apple) va nel sito («iphone-app-store»).

### Testi della scheda (bozza)

Le stesse parole dell'app e del Glossario. Limiti di Apple: sottotitolo 30 caratteri, testo promozionale 170, parole chiave 100
(separate da virgole, senza spazi, senza marchi di altri come Zoom o Teams). Prima di pubblicare va ricontrollato che ogni frase sia
ancora vera (per esempio la webcam virtuale del Mac, che richiede l'account sviluppatore a pagamento).

| Campo | Italiano | English |
| --- | --- | --- |
| Sottotitolo | La webcam è il tuo iPhone | Your iPhone as a webcam |
| Testo promozionale | Il video della fotocamera dell'iPhone sul Mac o sul PC, con pochissimo ritardo. Gratis fino a 720p a 30 fps, senza filigrana. | Your iPhone camera’s video on your Mac or PC, with very little delay. Free up to 720p at 30 fps, no watermark. |
| Parole chiave | webcam,fotocamera,videochiamata,riunione,lezione,diretta,streaming,mac,pc,windows,usb,wi-fi | webcam,camera,video call,meeting,lesson,live stream,streaming,mac,pc,windows,usb,wi-fi |

Descrizione, italiano:

> WebcamLR manda il video della fotocamera dell'iPhone al Mac o al PC, per videochiamate, lezioni e dirette. Molto più nitido della
> webcam del computer, con pochissimo ritardo.
>
> • Sulla stessa rete Wi-Fi o con il cavo USB, il collegamento più stabile.
> • Il video va dal telefono al computer solo sulla tua rete o sul cavo, cifrato. Niente account, nessun dato raccolto.
> • Gratis per sempre fino a 720p a 30 fps, senza filigrana né pubblicità, con specchio, sfondo sfocato, zoom e torcia.
> • WebcamLR Pro, un solo acquisto senza abbonamento: 1080p, 4K, 60 fps, effetti, inquadratura automatica, controlli Pro e tutti
>   i comandi del computer.
>
> Serve WebcamLR sul computer, gratis dal sito: lr-apps609.github.io/WebcamLR

Description, English:

> WebcamLR sends the iPhone camera’s video to your Mac or PC, for video calls, lessons and live streams. Much sharper than the
> computer’s webcam, with very little delay.
>
> • On the same Wi-Fi network or with the USB cable, the most stable connection.
> • The video goes from the phone to the computer only over your network or the cable, encrypted. No account, no data collected.
> • Free forever up to 720p at 30 fps, with no watermark or ads, with mirror, background blur, zoom and flashlight.
> • WebcamLR Pro, a one-time purchase with no subscription: 1080p, 4K, 60 fps, effects, auto framing, Pro controls and all the
>   computer’s controls.
>
> You need WebcamLR on your computer, free from the website: lr-apps609.github.io/WebcamLR

## 6. GitHub Releases e link nel sito

I file da scaricare (il dmg, e più avanti l'installer di Windows e l'APK) stanno nelle **Releases** di GitHub. Perché chiunque possa
scaricarli, la repository `LR-apps609/WebcamLR` deve essere **pubblica** (oppure le release vanno in una repository pubblica a parte).

1. Pubblica una release, dal sito o dal Terminale (dalla cartella della repository, con `gh` collegato al tuo account):
   ```
   git tag v1.0 && git push origin v1.0
   gh release create v1.0 ~/Library/Developer/WebcamLR/Pubblicazione/1.0/WebcamLR.dmg \
     --title "WebcamLR 1.0" --notes "Prima versione pubblica."
   ```
   Dal sito: https://github.com/LR-apps609/WebcamLR/releases › **Draft a new release** › tag `v1.0` › trascina il dmg › **Publish release**.
   Il pacchetto del microfono è già dentro il dmg: caricarlo anche a parte è facoltativo (GitHub cambia gli spazi del nome in punti:
   `WebcamLR.Microfono.pkg`).
2. Tieni sempre lo stesso nome del file (`WebcamLR.dmg`): così il link
   ```
   https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR.dmg
   ```
   porta sempre all'ultima versione, e il sito non va cambiato a ogni release.
3. Sul ramo **`sito`**, in cima a `Sito/download.js`:
   ```js
   "mac-dmg":           { url: "https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR.dmg",
                          testo: "Scarica per Mac (.dmg)", dettaglio: "Versione 1.0 · macOS 14 o successivo · NN MB" },
   "iphone-testflight": { url: "https://testflight.apple.com/join/XXXXXXXX", testo: "Prova la beta con TestFlight", dettaglio: null },
   "iphone-app-store":  { url: "https://apps.apple.com/app/idNNNNNNNNNN", testo: "Scarica da App Store", dettaglio: null },
   ```
   Poi in `Sito/download.html` trasforma lo `<span data-download="mac-dmg">` (e gli altri che hai attivato) in un link
   `<a href="…">`, per chi visita senza JavaScript, e aggiorna la frase «Non ancora pubblicata». Il sito si ripubblica da solo
   (`.github/workflows/sito.yml`).
4. Sempre sul ramo **`sito`**, aggiorna **`Sito/versione.json`** (pubblicato su
   `https://lr-apps609.github.io/WebcamLR/versione.json`). Il Mac lo legge all'avvio e ogni 6 ore
   (`Mac/Sorgenti/ControlloAggiornamenti.swift`, indirizzo in `InfoApp.versioneRecente`) e, se la versione è più nuova della sua,
   mostra in alto a destra la pillola **«Aggiornamento disponibile»**: il foglio dice versione, data e novità, «Scarica» apre
   `pagina` nel browser, «Più tardi» la nasconde fino alla versione dopo. Senza rete o con il file assente non compare niente.
   ```json
   {
     "versione": "1.0.1",
     "build": 3,
     "data": "2026-11-02",
     "pagina": "https://lr-apps609.github.io/WebcamLR/download.html",
     "novita": "Finestra del Mac rifatta con i colori di LR Apps.\nProfili pronti: Riunione, Lezione, Diretta, Colloquio."
   }
   ```
   - `versione` (obbligatoria) e `build`: gli stessi valori di `Strumenti/Versione.xcconfig` (`MARKETING_VERSION`,
     `CURRENT_PROJECT_VERSION`). Il confronto è prima sulla versione, numero per numero (1.10 viene dopo 1.9), poi sulla build;
     `build` può essere un numero o un testo.
   - `data`, `pagina`, `novita`: facoltativi. Senza `pagina` «Scarica» apre la pagina di download del sito. `novita` è un testo
     solo (a capo con `\n`), mostrato così com'è.
   - Va aggiornato **dopo** aver pubblicato il dmg: altrimenti chi preme «Scarica» trova ancora la versione vecchia.

## 7. Windows: installatore, avviso di Windows e firma

### Cosa c'è già

| Cosa | Dove |
| --- | --- |
| Installatore per l'utente, senza strumenti di terzi (niente WiX, Inno Setup o NSIS) | `Windows/WebcamLR.Setup` (programma) e `Windows/WebcamLR.Setup.Logica` (parte provata con i test) |
| Costruirlo | doppio clic su `Strumenti/Crea installer Windows.bat` → `Distribuzione/WebcamLR-Setup-<versione>.exe` |
| Versione | la stessa di Mac e iPhone, da `Strumenti/Versione.xcconfig` (letta da `Strumenti/Versione.props`); per cambiarla `Strumenti/Nuova versione.bat` |
| Guida per provarlo | `Documenti/Windows - installazione e prova.md` |

Cosa fa: installa WebcamLR per l'utente in `%LOCALAPPDATA%\Programs\WebcamLR` (senza amministratore), il collegamento
nel menu Start e la voce in Impostazioni → App installate; scarica .NET 8 da Microsoft se manca; poi chiede **una sola volta**
il permesso dell'amministratore per la webcam (Windows 11: Media Foundation; Windows 10: filtro DirectShow, in
`C:\Program Files\WebcamLR\Webcam`) e per la regola del firewall «WebcamLR» (in ingresso, solo reti private). Il
disinstallatore toglie tutto, webcam e regola comprese. Per l'utente è un exe solo, autonomo (qualche decina di MB, con l'app dentro).

### Senza firma (adesso)

L'installatore non è firmato. Chi lo scarica:
1. nel browser: Edge «non viene scaricato comunemente» → **…** → **Mantieni** → **Mostra altro** → **Mantieni comunque**
   (Chrome: **Mantieni**);
2. all'apertura: **«PC protetto da Windows»** (SmartScreen) → **Ulteriori informazioni** → **Esegui comunque**;
3. alla domanda dell'amministratore: «Autore: **Sconosciuto**» → **Sì**.

Va bene per Ledion e per i primi tester (scriverlo nella pagina di download). Non va bene per il pubblico: molti si fermano
al punto 2, e **Smart App Control** (attivo su alcuni Windows 11 installati da zero) blocca le app non firmate senza
nessun pulsante per proseguire.

### Firmare più avanti: le tre strade

In tutti i casi si firmano, con `signtool` (Windows SDK) e un timestamp, i nostri eseguibili e DLL **prima** di metterli
nel pacchetto (WebcamLR.exe, le DLL `WebcamLR.*`, `WebcamLR.Webcam.Installa.exe`, i comhost, `Disinstalla WebcamLR.exe`),
poi `WebcamLR-Setup-….exe`. Il punto giusto è un passo in più in `Windows/WebcamLR.Setup/Pacchetto.proj` (tra
«PreparaZip» e lo zip, e dopo l'ultima pubblicazione), con i dati della firma fuori dalla repository, come `firma.txt` sul Mac.
La firma toglie anche «Autore: Sconosciuto» dalla domanda dell'amministratore.

1. **Azure Trusted Signing** (servizio di firma di Microsoft, chiamato anche «Artifact Signing»): circa 10 USD al mese
   (piano Basic), nessuna chiavetta da comprare: la chiave sta in Azure e `signtool` firma con un plug-in. Serve una
   verifica d'identità; all'inizio era solo per aziende con qualche anno di storia in alcuni paesi, poi aperto anche ai
   singoli sviluppatori in alcuni paesi. **Da verificare se oggi si può come privato o ditta individuale in Italia**:
   portal.azure.com → crea una risorsa «Trusted Signing» → «Identity validation». È la strada più economica e più semplice
   da automatizzare, se è disponibile.
2. **Certificato di firma del codice** (OV) da un'autorità (Certum, Sectigo, SSL.com, DigiCert…): circa da 100 a 400 € l'anno;
   per un progetto open source Certum offre un certificato economico. Dal 2023 la chiave deve stare su una chiavetta
   hardware o in un servizio cloud dell'autorità (niente più file .pfx). I certificati EV, più cari, **non** danno più
   la fiducia immediata di SmartScreen (Microsoft lo ha cambiato nel 2024): sia OV sia EV la guadagnano con i download.
3. **Microsoft Store**: l'iscrizione come sviluppatore singolo è gratuita (verificare le condizioni del momento in Partner
   Center). Due modi:
   - **pacchetto MSIX**: lo firma lo Store e l'avviso di SmartScreen sparisce. Ma la webcam ha bisogno di HKLM, di
     `Program Files` e dell'amministratore: dentro un MSIX servirebbe la registrazione COM del pacchetto per Frame Server,
     da provare (l'esempio VirtualCamera di Microsoft ha una versione pacchettizzata); il filtro DirectShow di Windows 10
     non si può installare da MSIX. È un lavoro a sé, di qualche giorno.
   - **installatore EXE o MSI elencato nello Store**: lo Store mostra la pagina e scarica il nostro `WebcamLR-Setup`, che però
     deve già essere firmato con la strada 1 o 2. Utile per farsi trovare, non per evitare la firma.

Consiglio: per la prima versione pubblica la strada 1 se disponibile in Italia, altrimenti la 2 (OV); lo Store dopo, come
canale in più. Le richieste d'identità richiedono giorni: vanno avviate prima del lancio.

### Microfono del telefono: il driver è un passo a parte (non ora)

Il microfono del telefono su Windows oggi esce su un'uscita audio scelta (di solito un cavo audio virtuale che l'utente ha
già): non serve nessuna firma in più. Un vero ingresso «WebcamLR (microfono)» richiede un **driver kernel firmato da
Microsoft** (iscrizione al Windows Hardware Developer Program con un **certificato EV**, poi firma ad attestazione o WHCP):
ricerca, progetto, passi e costi in `Documenti/Microfono Windows.md`, sezione 4. Il certificato OV o Azure Trusted Signing
della strada qui sopra **non** bastano per un driver.

### Pubblicare (a ogni versione)

1. `Strumenti/Nuova versione.bat` (o `.command` sul Mac): versione e build salgono per tutte le piattaforme.
2. `Strumenti/Crea installer Windows.bat` → prova l'installatore su un altro utente Windows (punto 4 della guida).
3. GitHub Release: carica `Distribuzione/WebcamLR-Setup-<versione>.exe` **rinominato** `WebcamLR-Setup.exe`, così il link
   `https://github.com/LR-apps609/WebcamLR/releases/latest/download/WebcamLR-Setup.exe` resta sempre lo stesso.
4. Ramo `sito`: la voce Windows in `Sito/download.js`, come per il Mac (sezione 6).

## Obbligatori prima del lancio (iPhone e Mac)

- [x] Manifesti della privacy: app iPhone, app Mac, webcam virtuale, Stile (*Manifesto della privacy*, sezione 5)
- [x] Cifratura: `ITSAppUsesNonExemptEncryption = NO`, con il ragionamento (*Cifratura ed esportazione*, sezione 5)
- [x] Microfono del Mac: l'aiutante accetta solo WebcamLR dello stesso team e Core Audio (`Microfono Mac.md`, *Sicurezza*)
- [x] Microfono del Mac: «Rimuovi il microfono…» e stato con la versione nelle Impostazioni dell'app
- [x] Domande frequenti «Quanto costa» e «Zoom e Teams» allineate su iPhone, Mac, Android e Windows
- [ ] Da Ledion: riga **03** (Privacy Report nell'archivio) e sezione **L2** (microfono: sicurezza e rimozione) di `Checklist iPhone e Mac.md`
- [ ] Da Ledion: Privacy dell'app in App Store Connect («Nessun dato raccolto») e URL della privacy

## Riepilogo: cosa serve da Ledion

| Passo | Una volta / ogni versione | Costo |
| --- | --- | --- |
| Iscrizione all'Apple Developer Program, `team.txt` e `account.txt` = `completo` | una volta | 99 USD/anno |
| Certificati Developer ID Application e Installer, copia `.p12` | una volta | incluso |
| Password specifica per app e `notarytool store-credentials`, `firma.txt` | una volta | — |
| App in App Store Connect, contratto app gratuite | una volta | — |
| Contratto app a pagamento, dati bancari e fiscali; acquisto in-app WebcamLR Pro con prezzo 14,99 € e lancio a 9,99 € | una volta | — (Apple trattiene la sua commissione) |
| `Nuova versione.command` → `Crea dmg.command` → prova su un altro Mac → GitHub Release | ogni versione Mac | — |
| `Nuova versione.command` → Archive in Xcode → TestFlight → revisione App Store | ogni versione iPhone | — |
| Link in `Sito/download.js` (ramo `sito`) | la prima volta; poi solo se cambia un link | — |
| Windows: `Nuova versione.bat` → `Crea installer Windows.bat` → prova su un altro utente → GitHub Release | ogni versione Windows | — |
| Windows: firma (Azure Trusted Signing o certificato OV), da avviare prima del lancio pubblico | una volta | circa 10 USD/mese o 100–400 €/anno |
| Windows, solo se si vuole il microfono virtuale «WebcamLR (microfono)»: certificato EV + Hardware Developer Program + firma del driver (`Microfono Windows.md`) | una volta, poi a ogni modifica del driver | circa 290–690 USD/anno |
