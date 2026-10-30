# Da controllare al ritorno (domenica 1 novembre sera)

Ledion è in Spagna dal 30 ottobre. Questo foglio raccoglie, passo per passo, le cose da provare a mano sui dispositivi.
Si aggiorna a ogni passo finito. Per ogni prova: cosa fare, cosa deve succedere, cosa mandare se non va.

## Prima di tutto: aggiornare
1. Mac: chiudi WebcamLR con ⌘Q, poi nel Terminale
   `cd ~/Documents/WebcamLR && git stash && git pull && git log --oneline -1`
   (l'ultima riga deve iniziare con l'hash scritto in fondo a questo foglio, «Versione da provare»).
2. Doppio clic su `Strumenti/Costruisci e installa.command`, rispondi **N**.
3. iPhone: cavo, scegli l'iPhone in Xcode, **▶**.
4. Windows: GitHub Desktop › Pull, poi `Strumenti/Costruisci e avvia.bat`.
5. Android: Android Studio › Pull, poi ▶ con l'S22 collegato.

Se Xcode o Android Studio danno errori rossi: screenshot e me lo mandi. Swift e Android **non si compilano qui**:
la tua build è la prima vera.

## 1.0 beta 1 · sfocatura sul Mac (ancora da provare)
- Sfondo su **Medio**, 1080p. 20 s solo la stanza: tutto sfocato e **fermo**, niente zone che diventano nitide.
- 20 s tu: tu nitido, il resto sfocato; gira la testa: resti nitido. All'accensione puoi restare sfocato ~1 s.
- Se non va: Settings › Connection log › «Show or hide the person mask», 10 s di video con la maschera + registro (Copy).

## 1.0 beta 2 · «Al sicuro» (build 3: in Xcode, nelle Informazioni dell'app e in Android deve comparire 1.0 (3))
(Le sezioni si aggiungono qui sotto a ogni passo finito. Bozze prima/dopo: https://claude.ai/artifact/SiQBKFKbTKMAhnm9vMrKFm)

### Passo 1 · Pausa «sottofondo» (iPhone, Android, Mac, Windows)
- [ ] iPhone in onda, **blocca lo schermo** → il computer mostra «Webcam in pausa» con «WebcamLR è in sottofondo sul telefono: riaprila per riprendere», **mai** «Riconnessione». Sblocca dopo ~20 s → il video riparte da solo e il telefono dice «Il video si era fermato per 20 s…».
- [ ] Mentre **registri** sul computer, metti l'iPhone in sottofondo → la registrazione si ferma e si salva subito, con un avviso.
- [ ] In onda, apri **FaceTime** o la Fotocamera sull'iPhone → la riga dice «In pausa» in **ambra** e c'è il riquadro «Un'altra app sta usando la fotocamera…»; chiudi l'altra app → il video riprende.
- [ ] Con «Microfono al computer» acceso, **chiama l'iPhone** → avviso del microfono «Tocca per riprovare»; a fine chiamata l'audio torna.
- [ ] Pausa col pulsante o telefono **a faccia in giù** → «In pausa» in ambra, mai «In onda» in corallo.
- [ ] iPhone in sottofondo **più di 10 minuti** → il computer lo dimentica con «Il telefono non è tornato entro 10 minuti».
- [ ] Android: la **notifica** dice lo stato vero (In onda in Zoom · …, In pausa, Mi ricollego…); apri la Fotocamera di sistema → pausa con il motivo, chiudila → riprende; telefonata con il microfono al computer → «Chiamata in corso: il microfono del telefono è in pausa».
- [ ] Windows: stesse prove dell'iPhone viste dal PC (velo «Webcam in pausa» con il motivo; al ritorno «Il video riprende dopo N s di pausa»).

### Passo 2 · Uscire e chiudere senza sorprese (Mac, Windows)
- [ ] Mac, con un telefono collegato premi **⌘Q** → «Un telefono è collegato: se esci, si scollega.»; **Invio = Annulla**, l'app resta aperta. Senza telefono né registrazione ⌘Q esce subito.
- [ ] Mac, registra 20 s e scegli Esci → la domanda nomina la registrazione; conferma → «Chiudo la registrazione…», poi esce; il **Finder non si apre**; il file in Filmati › WebcamLR si apre.
- [ ] Mac, registrando chiudi la finestra con ⌘W → notifica «WebcamLR continua…» (solo la prima volta). **Clic destro sull'icona nel Dock** → stato, «Ferma la registrazione», «Mostra WebcamLR».
- [ ] Mac, con la finestra davanti chiudi WebcamLR sull'iPhone e aspetta 15 s → banner fisso «… non è tornato» con «Il telefono non trova il Mac?»; riapri l'app sul telefono → il banner sparisce.
- [ ] Mac, spegni o riavvia con WebcamLR aperta → nessuna domanda di WebcamLR blocca lo spegnimento.
- [ ] Windows, menu dell'icona › **Esci da WebcamLR** con un telefono collegato → «Uscire da WebcamLR?», Invio = Annulla. C'è anche in Account › Esci da WebcamLR.
- [ ] Windows, premi la **X** due volte senza registrare → notifica solo la prima volta; registrando, a ogni X.
- [ ] Windows, registra e scegli Esci › Esci → «Chiudo la registrazione…», la finestra non si blocca, l'MP4 si apre, Esplora file non si apre.
- [ ] Windows, **primo aggiornamento**: la versione installata oggi non conosce ancora la chiusura gentile, quindi **prima di lanciare l'installatore chiudi tu WebcamLR** (icona accanto all'orologio › Esci). Dagli aggiornamenti successivi l'installatore la chiude da solo, aspettando fino a 15 s. Su un PC senza .NET 8 l'installatore mostra una finestra con «Scarico .NET 8… N MB di 30».

### Passo 3 · Registrazioni che non si perdono (Mac, Windows)
- [ ] Registra 30 s, poi **chiudi WebcamLR a forza** (Mac: Monitoraggio Attività › Uscita forzata; Windows: Gestione attività) → il file in Filmati/Video › WebcamLR **si apre** e dura fino agli ultimi secondi (al massimo ~10 s in meno: il telefono manda un fotogramma chiave ogni 10 s).
- [ ] Registra su una **chiavetta quasi piena** → prima «Spazio quasi finito: restano circa N minuti», poi «Disco pieno: … salvati i primi mm:ss…» e il file si apre.
- [ ] Mentre registri cambia **obiettivo** (anche tasti 1–4), **qualità**, **profilo**, «Nella webcam» o «Usa prospettiva» (anche dal telefono) → domanda «… ferma la registrazione e la salva. Continuare?»; **Annulla** lascia tutto com'era.
- [ ] **⌘T / Ctrl+T** durante una chiamata → **nessuna finestra** del Finder o di Esplora file; compare l'avviso «Foto salvata…» con «Mostra nel Finder» / «Mostra nella cartella».
- [ ] Passa il mouse su **Registra** → l'aiuto dice «senza audio».
- [ ] Windows, registra con gli **effetti sul PC** e guarda il registro → «MP4 frammentato» o «MP4 normale» (dimmi quale).

### Passo 4 · Niente gesti distruttivi a sorpresa (tutte le app)
- [ ] Computer, con Zoom che usa WebcamLR premi **Scollega** (pulsante, scheda o icona) → «Scollegare «…»? Zoom …»; Invio = Annulla. Senza app e senza registrazione si scollega subito.
- [ ] Windows con **due telefoni**: clic destro sull'icona → «Scollega ▸» con un telefono per riga.
- [ ] **Profili salvati** › Elimina → chiede prima; salva con un nome già usato → «… Sostituirlo?». Cambia un effetto dopo «Riunione» → clic su «Personalizzato» → «Torna a «Riunione»».
- [ ] **Telefoni fidati** › Rimuovi → chiede prima (Windows: Esc chiude solo la domanda). Rimuovi la webcam virtuale con Zoom aperto → la domanda dice che Zoom la sta usando.
- [ ] Regole fini › muovi Luminosità › **Azzera** → «Regolazioni azzerate · Annulla» per 8 s; Annulla o ⌘Z/Ctrl+Z rimettono i valori.
- [ ] Telefono in onda con Zoom, tocca la **X** → «Zoom sta usando il video: si fermerà anche lì.».
- [ ] iPhone in onda, **scorri dal bordo sinistro** → la diretta non si chiude. Android in onda, **Indietro** → compare la domanda; a schermo oscurato Indietro riaccende lo schermo e basta.
- [ ] In onda, **doppio tocco** sull'anteprima → la fotocamera non cambia e compare «In onda: per cambiare fotocamera…».
- [ ] Android, «Scollega» nella **notifica** → si apre WebcamLR sulla domanda.
- [ ] iPhone in diretta, Impostazioni › **Lingua** → chiede prima; Informazioni › **Privacy** → si apre dentro l'app e il video continua.

### Passi 5 e 6 · Interruzioni dette e stato sempre visibile (tutte le app)
- [ ] Telefono in onda con Zoom, posalo a **2–3 m** → leggi «IN ONDA» su corallo pieno; il telefono **vibra** appena Zoom prende il video.
- [ ] iPhone con l'isola (o Android col foro) in verticale, in onda → accanto all'isola c'è la pillola «IN ONDA», non più «● Wi-Fi».
- [ ] Lascia oscurare lo schermo del telefono → pillola grande «IN ONDA»; metti in pausa → «IN PAUSA» in ambra.
- [ ] Batteria del telefono sotto il 20% → avviso, poi dopo 6 s un'**icona ambra** nella riga; toccala → l'avviso si riapre.
- [ ] Fotocamera posteriore, tocca **Specchia** → «Specchia e Sfoca sfondo funzionano con la fotocamera frontale.».
- [ ] Mac: **icona nella barra dei menu** (videocamera vuota → piena → con il punto in onda → cerchio mentre registri); il suo menu ha lo stato, «Ferma la registrazione», «Mostra WebcamLR», «Esci da WebcamLR» (con la domanda). Impostazioni › Schermo › «Mostra l'icona nella barra dei menu» la toglie.
- [ ] Mac: intestazione **«IN ONDA · ZOOM»**; finestra mini con punto e tempo di registrazione.
- [ ] Windows: **icona accanto all'orologio** con punto corallo in onda/registrazione e ambra in riconnessione; suggerimento «WebcamLR · In onda su Zoom · Registrazione 00:30».
- [ ] Computer: spegni il Wi-Fi del telefono → dopo 15 s banner fisso «… non è tornato»; riaccendi → il banner sparisce. Nel Registro ci sono «In onda su Zoom», «Fuori onda», gli avvisi di batteria.
- [ ] Windows senza telefono: **Tab** arriva su «Specchia» spento; Invio mostra perché è spento.
- [ ] Con **VoiceOver / Assistente vocale / TalkBack** acceso: ricollegamento, in onda, registrazione vengono annunciati.
- [ ] **Riduci movimento** (Mac/iPhone) o Effetti di animazione spenti (Windows) o animazioni a 0 (Android): niente scorrimenti, niente lampo della foto, punto «In onda» fermo.

### Passo 7 · Permessi e rete senza vicoli ciechi (tutte le app)
- [ ] Mac, nessun telefono, vista Essenziale → al centro il **QR grande** con «Collega il telefono in tre passi». Dopo 30 s compare «Il telefono non trova il Mac?» con «Apri»: **dimmi quale pagina di Impostazioni di Sistema apre** (sul 26 potrebbe aprire Rete invece di Firewall). Nella colonna «Pronto: apri WebcamLR sul telefono.».
- [ ] Mac, Wi-Fi spento → sotto il QR «Apri Impostazioni Wi-Fi».
- [ ] Mac e Windows con Photo Booth / Fotocamera aperta sulla webcam WebcamLR e l'app chiusa → «WebcamLR è chiusa · Apri WebcamLR sul Mac/computer».
- [ ] Windows al **150 %**: prima apertura grande come al 100 %; la finestra **non si stringe sotto 960×600** (se si stringe, dimmelo: è la parte che qui non ho potuto provare); testi del primo avvio leggibili.
- [ ] Windows, rete «Pubblica» in vista Essenziale → la pillola ha il **punto ambra** e il titolo del problema; un clic apre la pagina giusta.
- [ ] Windows, togli la regola WebcamLR dal firewall → **«Sistema»** chiede il permesso dell'amministratore e sistema.
- [ ] Windows senza estensione HEVC, telefono in 4K → avviso con «Apri Microsoft Store» e **«Ricollega in H.264»** (deve arrivare 1080p H.264).
- [ ] iPhone: spegni Fotocamera per WebcamLR nelle Impostazioni, poi tocca un computer → pannello «Serve il permesso «Fotocamera»» con **«Apri Impostazioni»**. Microfono negato → avviso con «Apri Impostazioni».
- [ ] Android: rifiuta due volte la fotocamera → **scheda ambra** con «Apri Impostazioni». Impostazioni › Schermo e batteria → «Senza limiti di batteria: sì/no».
- [ ] Android: Collega a mano, scrivi l'indirizzo e premi **Invio** → collega; riaprendo, l'indirizzo è già scritto. Lettore QR al buio → **torcia** accanto alla X.

### Passi 8 e 9 · Standard di piattaforma, dati e testi veri (tutte le app)
- [ ] Mac, **menu Video**: senza telefono tutto grigio tranne Vista pulita; con il telefono ⌘T foto, ⌘R registra, Obiettivo con 1–4 e la spunta.
- [ ] Mac, **⌘,** (anche in vista Completo) → si apre il pannello Impostazioni; ci sono «Avvio e notifiche», «Sicurezza», «Schermata di attesa», «Microfono». La vecchia finestra separata non c'è più.
- [ ] Mac, **Aiuto › ⌘?** → Guida; «WebcamLR › Verifica aggiornamenti…» risponde sempre.
- [ ] Mac, **clic destro** sul video, sulla scheda del telefono e sulla finestra mini (dimmi se sul video non compare); doppio clic sulla mini → finestra principale.
- [ ] Mac, scrivi «f1+» nel nome di un profilo o nel gobbo → si scrive, l'obiettivo non cambia.
- [ ] Computer, telefono in **pausa** con Zoom aperto → pillola «IN PAUSA» in ambra, bordo del video **non corallo**; icona Mac in riconnessione con il punto vuoto.
- [ ] Windows: **F1** → Guida; **Ctrl+,** → Impostazioni (con «Avvio» e «Telefoni fidati»); **Ctrl+W** → nasconde come la X; clic destro su video, mini, CAM 2, schede e profili.
- [ ] Gobbo (Mac e Windows): scrivi un testo, cambia velocità e dimensione, esci e riapri → tutto come prima.
- [ ] **Segnala un bug** (tutte le app): scrivi mezza descrizione, chiudi e riapri → c'è ancora; con «Includi il registro del collegamento» il registro è in fondo; dopo l'invio la bozza si svuota.
- [ ] Android: **Registro** con «Copia» e «Condividi», righe nuove senza riaprire. iPhone in inglese: «0.5×».
- [ ] Testi: nessun «smartphone» (ora «Collega il tuo telefono»), nessun «account sviluppatore Apple»; la domanda frequente «La registrazione ha l'audio?» c'è.

## 1.0 beta 3 · «Sistema» (build 4: deve comparire 1.0 (4))
Sotto il cofano: un'unica tabella di colori, caratteri, spazi e raggi (`Documenti/token.json`) e un componente per ogni
ruolo (pulsante pieno, secondario, link, distruttivo, chip, avviso) sulle quattro app. L'aspetto deve restare **quasi** lo
stesso: piccole differenze di misura (raggi, spazi alla griglia di 4, qualche testo di 0,5–1 punto, liste in Barlow) sono
attese e verranno sistemate con la grafica nuova della beta 4.
- [ ] **Le quattro app si compilano e si aprono** (è il cambio più grande finora: se Xcode, Android Studio o Windows danno
  errori, mandami lo screenshot dell'errore).
- [ ] Giro rapido su ogni app: pulsanti, avvisi e pannelli si leggono, niente testo tagliato, niente pulsanti spariti.
- [ ] iPhone e Android con il **testo grande** (Impostazioni › Accessibilità): le liste e i pulsanti crescono e vanno a capo.
- [ ] Windows: si apre senza chiudersi da sola (prima della revisione mancava una risorsa).
- [ ] Se qualcosa ti sembra **peggiorato** rispetto a prima, uno screenshot basta: lo sistemo.

## 1.0 beta 4 · «Volto nuovo» (build 5, **ramo `beta4`**: deve comparire 1.0 (5))
Prima prova tutto quello sopra (beta 2 e 3, ramo `round-2`). Solo dopo passa alla beta 4, che è su un ramo a parte, così
la beta 3 resta sempre provabile. Per passare: Mac `git fetch && git checkout beta4 && git pull`; Windows e Android in
GitHub Desktop / Android Studio scegli il ramo `beta4`. Per tornare indietro: `git checkout round-2`.
È la grafica nuova (direzione A, bordi nativi di C, stato scritto sui comandi di B). Nessuna funzione nuova.
- [ ] **Le quattro app si compilano** (cambiano molti file di grafica: errori rossi → screenshot).
- [ ] **Un solo pulsante pieno per schermata**; secondari trasparenti con il bordo; «Scollega» è un comando di testo con
  l'anello spezzato dentro la scheda del telefono (non più a tutta larghezza in fondo).
- [ ] **Comandi di regia** (Mac e Windows): acceso = fondo salvia tenue, bordo salvia e la scritta «Acceso» sotto il nome;
  Registra è neutro da fermo e mostra «● 0:12» in corallo solo mentre registra.
- [ ] **In onda**: una barra corallo sottile sul bordo alto del video al posto della cornice; chip di qualità e
  collegamento bordati.
- [ ] Il menu «Account» ora si chiama **«WebcamLR»**; la lista dei telefoni si chiama **«Telefoni»** ovunque.
- [ ] **Mac**: intestazione come una barra di macOS; pannello Impostazioni distinguibile dalla colonna sotto.
  Da guardare: «Telefoni…» nella pillola apre la pagina delle Impostazioni, «Telefoni…» nel menu WebcamLR apre il foglio:
  dimmi se ti confonde. Finestra stretta (600 pt): i comandi di regia ci stanno?
- [ ] **Windows**: una sola barra del titolo (con la Mica) che si trascina, doppio clic che ingrandisce, pulsanti
  dell'intestazione cliccabili anche al 150 %; **Contrasto elevato** (Impostazioni di Windows › Accessibilità › Temi a
  contrasto) leggibile; installatore con due finestre (Installa / Fatto) invece di cinque messaggi.
  Poi: finestra mini e ritorno (riduci/ingrandisci/chiudi visibili, intestazione di nuovo cliccabile).
- [ ] **iPhone**: in alto solo l'ingranaggio e la pillola Pro; i fogli si chiudono sempre con «Fine» in alto a destra;
  in onda Impostazioni e Scollega sotto l'isola, staccati; obiettivi e tondi facili da toccare.
- [ ] **Android**: barra in alto Material con la freccia; in Cerco il pulsante pieno è «Inquadra il QR code del computer».
  Da «In onda» apri «App e assistenza» e torna con Indietro: il video deve continuare.
- [ ] Contorni dei controlli visibili ovunque (anche al sole); niente testo grigio difficile da leggere sui pannelli chiari.

## Versione da provare
Vedi l'ultima riga di «git log --oneline -1»: va bene qualsiasi versione uguale o successiva a quella scritta nell'ultimo aggiornamento che ti ho mandato.
