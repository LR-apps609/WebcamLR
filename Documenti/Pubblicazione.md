# Pubblicazione di WebcamLR · Mac e iPhone

Guida passo passo per Ledion: dall'account Apple fino al dmg su GitHub e all'app su TestFlight e App Store.
Le parti già pronte nella repository:

| Cosa | Dove |
| --- | --- |
| Versione e numero di build di Mac e iPhone, in un solo posto | `Strumenti/Versione.xcconfig` (oggi 1.0, build 2) |
| Cambiare versione | doppio clic su `Strumenti/Nuova versione.command` |
| dmg del Mac e pacchetto del microfono, firmati e notarizzati | doppio clic su `Strumenti/Crea dmg.command` |
| Identità di firma e profilo di notarizzazione | `Strumenti/firma.txt` (solo sul tuo Mac; esempio in `Strumenti/firma.esempio.txt`) |

Windows e Android sono in pausa: le loro sezioni arriveranno con il lavoro su quelle piattaforme.

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
   compare «WebcamLR (microfono)».
4. Webcam virtuale: attivazione come in `Documenti/Webcam virtuale Mac.md` (l'utente deve approvarla in Impostazioni di Sistema).
5. Un giro di `Documenti/Checklist 1.0.md` con il telefono.

### Prima della prima pubblicazione pubblica

- **Controllo di chi chiede il microfono**: l'aiutante oggi dà la memoria condivisa a qualsiasi processo. Prima di distribuirlo
  deve accettare solo WebcamLR con il nostro Team ID e coreaudiod (`Documenti/Microfono Mac.md`, *Sicurezza*). È un lavoro da
  fare in un round, non una cosa della firma.
- **Disinstallazione del microfono**: per ora `Strumenti/Rimuovi microfono.command`. Per gli utenti servirà un modo dall'app o un
  secondo pacchetto (`Microfono Mac.md`, *Distribuzione*, punto 7).
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

### A ogni versione (TestFlight)

1. `Strumenti/Nuova versione.command`: ogni invio ad App Store Connect vuole un **numero di build nuovo**, anche se la versione
   resta uguale (in quel caso premi solo Invio).
2. Doppio clic su `Strumenti/Costruisci e installa.command` (rigenera il progetto iPhone con la versione nuova e lo apre in Xcode).
3. In Xcode, in alto, scegli come destinazione **Any iOS Device (arm64)**, poi menu **Product › Archive**.
4. Si apre l'Organizer: **Distribute App** › **App Store Connect** › **Distribute**. Xcode firma e carica.
5. Dopo 10–30 minuti la build compare in App Store Connect › la tua app › **TestFlight**.
   - **Conformità crittografica**: WebcamLR cifra video e comandi (AES-256-GCM, protocollo versione 2) con algoritmi standard
     del sistema. Alla domanda rispondi che l'app usa la cifratura e che è solo cifratura standard (esente). Per non rispondere
     a ogni build si potrà aggiungere `ITSAppUsesNonExemptEncryption` all'Info.plist (`iPhone/project.yml`): da decidere con Claude
     dopo la prima risposta.
   - **Tester interni** (fino a 100 persone del team): subito, senza revisione.
   - **Tester esterni** (fino a 10 000, anche con un link pubblico): la prima build passa una breve revisione di Apple (di solito
     un giorno). Crea un gruppo, aggiungi la build e attiva il **link pubblico**: è il link per il sito («iphone-testflight»).
6. Chi prova installa l'app **TestFlight** dall'App Store e apre il link.

### App Store

1. App Store Connect › la tua app › la versione (per esempio 1.0):
   - **Screenshot**: almeno quelli per iPhone da 6,9" (1320 × 2868 o 2868 × 1320); gli altri formati si ricavano da quelli;
   - descrizione, parole chiave, URL di supporto (`https://lr-apps609.github.io/WebcamLR/aiuto.html`) e URL della privacy
     (`https://lr-apps609.github.io/WebcamLR/privacy.html`: prima va completata la bozza, vedi `Sito/LEGGIMI.md` sul ramo `sito`);
   - **Privacy dell'app**: WebcamLR non raccoglie dati (video e audio vanno solo al computer dell'utente, cifrati): «Nessun dato raccolto»,
     se è ancora vero quando pubblichi;
   - categoria Foto e video; classificazione per età dal questionario.
2. **Note per la revisione**: spiega che l'app manda il video a WebcamLR per Mac o Windows sulla stessa rete Wi-Fi, e allega un
   breve video che lo mostra (il revisore di solito non ha il programma sul computer). Indica il link per scaricare WebcamLR per Mac.
3. Scegli la build già provata su TestFlight › **Aggiungi per la revisione** › **Invia**. La revisione dura di solito 1–2 giorni.
4. Dopo l'approvazione: pubblicazione manuale o automatica. Il link dell'App Store (`https://apps.apple.com/app/id<numero>`, il numero
   è in App Store Connect › Informazioni sull'app › ID Apple) va nel sito («iphone-app-store»).

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

## Riepilogo: cosa serve da Ledion

| Passo | Una volta / ogni versione | Costo |
| --- | --- | --- |
| Iscrizione all'Apple Developer Program, `team.txt` e `account.txt` = `completo` | una volta | 99 USD/anno |
| Certificati Developer ID Application e Installer, copia `.p12` | una volta | incluso |
| Password specifica per app e `notarytool store-credentials`, `firma.txt` | una volta | — |
| App in App Store Connect, contratto app gratuite | una volta | — |
| `Nuova versione.command` → `Crea dmg.command` → prova su un altro Mac → GitHub Release | ogni versione Mac | — |
| `Nuova versione.command` → Archive in Xcode → TestFlight → revisione App Store | ogni versione iPhone | — |
| Link in `Sito/download.js` (ramo `sito`) | la prima volta; poi solo se cambia un link | — |
