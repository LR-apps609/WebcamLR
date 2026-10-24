# Round 2 · checklist per versione

Una sezione per versione (vedi `Documenti/Roadmap.md`). Prova una versione alla volta e mandami l'esito: «tutto ok», oppure il numero della riga che non va con uno screenshot.

Il codice Swift è stato scritto e riletto senza poterlo compilare: se Xcode segnala errori, mandali così come sono.

## Prima di iniziare

1. Chiudi Xcode
2. Nel Terminale: `cd ~/Documents/WebcamLR && git pull && git checkout round-2 && git pull`
3. Doppio clic su `Strumenti/Costruisci e installa.command` (account: **N**)
4. In Xcode scegli il tuo iPhone e premi ▶

La prima volta compaiono le tre schermate di benvenuto: è la novità 16.

## 0.2 · Più veloce e più chiaro

- [ ] iPhone, in alto: «▮▮▮ Ottimo» con i ms accanto (14)
- [ ] Mac, sotto il video: le tacche e la parola; con un clic si vedono i numeri (28)
- [ ] La latenza resta intorno ai 51 ms o scende: manda il valore (5, 6, 20)
- [ ] Allontanati dal router o avvia un download pesante: sull'iPhone compare «Rete lenta: qualità abbassata da sola», il video resta fluido e la qualità dice «Debole» (4)
- [ ] Tornando vicino al router, dopo una decina di secondi l'avviso sparisce e la qualità risale (4)
- [ ] Windows: accanto alle statistiche tacche e parola (verde «Ottimo» in Wi-Fi buono); al passaggio del mouse latenza, media e massima (42)
- [ ] Mac: con WebcamLR dietro altre finestre per 5 minuti, la latenza resta come in primo piano (20)
- [ ] Mac: un clic su «▮▮▮ Ottimo» apre i numeri (28)

## 0.3 · Si collega da solo

- [ ] Collegati al Mac, chiudi l'app sull'iPhone del tutto e riaprila: compare «Mi ricollego a … tra 3…» e si collega da solo (2)
- [ ] Con «Annulla» resta sulla lista; dopo «Scollega» non riparte da sola (2)
- [ ] Vibra quando si collega, quando cambi obiettivo, al blocco AE/AF, e una volta sola quando chiudi l'app sul Mac (3)
- [ ] Chiudi WebcamLR sul Mac: sull'iPhone compare il banner con i secondi; «Riprova ora» riprova subito (15)
- [ ] Benvenuto: dopo aver cancellato e reinstallato l'app compaiono 3 pagine; «Inizia» chiede la fotocamera e poi la rete locale; alla seconda apertura non compaiono più (16)
- [ ] Windows senza telefono: al centro il QR grande e i tre passi con il nome del PC; inquadrandolo dall'iPhone ci si collega. Da collegato, il QR piccolo «Nuovo telefono?» è nella colonna destra (46)
- [ ] Mac senza telefono: QR grande e tre passi; con la finestra piccola resta leggibile (32)

## 0.4 · Inquadratura perfetta

- [ ] Impostazioni › Inquadratura: accendi griglia e livella; la linea segue l'orizzonte e diventa verde con il telefono dritto, in verticale e in orizzontale (11, 12)
- [ ] Tieni premuto sull'anteprima: compaiono il riquadro e «AE/AF bloccati»; muovendo il telefono fuoco ed esposizione non cambiano; un tocco sblocca (10)
- [ ] Doppio tocco sull'anteprima: frontale ↔ posteriore (18)
- [ ] Lo zoom comandato dal Mac scorre invece di saltare; il pizzico sull'iPhone resta immediato (9)
- [ ] Impostazioni › Stabilizzazione «Standard»: camminando l'immagine è più ferma; con «Spenta» la latenza non sale (7)
- [ ] In una stanza buia nessun errore e il video non rallenta (8)

## 0.5 · Batteria e calore

- [ ] Dopo 30 secondi senza tocchi lo schermo dell'iPhone si oscura da solo; un tocco su qualsiasi pulsante fa ripartire il conto; con l'interruttore spento non si oscura (13)
- [ ] Sotto il 20% senza caricatore il Mac riceve 24 fps e l'iPhone lo dice; con il caricatore torna ai fps scelti (17)
- [ ] Windows: con la batteria dell'iPhone sotto il 20% senza caricatore compare la barra ambra sopra il video; col caricatore sparisce. Chiusa con la X non torna finché non c'è un avviso nuovo (49)
- [ ] Mac: telefono sotto il 20% senza caricatore (o molto caldo): banner ambra sul video, sparisce con il caricatore (33)

## 0.6 · Il Mac come una regia

- [ ] ⌥⌘M apre la finestra mini: sopra le altre app, su tutte le scrivanie, si ridimensiona restando 16:9; il video parte subito; ⌥⌘M di nuovo la chiude (21)
- [ ] Icona nella barra in alto: vuota senza telefono, piena con il telefono, rossa solo quando un'app usa la webcam virtuale (34)
- [ ] Dal menu nella barra funzionano obiettivo, foto, registra/ferma, specchia, finestra mini, scollega, impostazioni (24)
- [ ] 1–4 cambiano obiettivo, + e − lo zoom, F il fuoco; mentre scrivi il nome di un profilo questi tasti non fanno nulla (25)
- [ ] ⇧⌘P lascia solo il video; Esc o il pulsante in alto a destra (passandoci sopra) tornano indietro (29)
- [ ] ⌥⌘F alterna riempi e adatta, anche nella finestra mini (30)
- [ ] Il grafico della latenza si riempie in 60 secondi (31)

## 0.7 · Foto, registrazioni e impostazioni

- [ ] ⌘C e poi incolla in Anteprima o Note: c'è il fotogramma (26)
- [ ] Ogni scatto fa un lampo bianco; dimmi se si sente anche il suono (27)
- [ ] ⇧⌘T: conto alla rovescia 3-2-1 grande sul video, poi la foto; un secondo clic sul timer lo annulla (36)
- [ ] Mentre registri il pulsante mostra «Ferma · 00:12 · 8,4 MB» e la dimensione cresce ogni secondo (37)
- [ ] Al primo telefono collegato macOS chiede il permesso per le notifiche; con WebcamLR in secondo piano arrivano «collegato» e, dopo 15 s senza telefono, «perso» (22)
- [ ] Batteria al 20% senza caricatore: una sola notifica. «Registrazione salvata» arriva anche in primo piano e il clic mostra il file (22)
- [ ] ⌘, apre le Impostazioni; «Apri all'avvio» mostra lo stato vero ed è attivo dopo un riavvio del Mac (23, 35)
- [ ] «Specchia di serie» acceso: chiudi e riapri, l'anteprima parte specchiata; con le notifiche spente non arriva nulla (35)

## 0.8 · Windows (serve un PC)

- [ ] Notifiche: con la finestra nascosta collega l'iPhone → «Telefono collegato»; spegni il Wi-Fi dell'iPhone e aspetta 15 s → «Telefono perso»; un clic sulla notifica apre la finestra (39)
- [ ] «Avvia con Windows»: esci e rientra in Windows; c'è solo l'icona accanto all'orologio, un clic apre la finestra. Spento, WebcamLR sparisce da Gestione attività › App di avvio (40)
- [ ] «Finestra mini»: il video resta sopra le altre finestre; si torna con il pulsante in alto a destra, con Esc o con un doppio clic (41)
- [ ] Con un telefono collegato 1–4 cambiano obiettivo, + e − lo zoom; mentre scrivi il nome di un profilo i tasti vanno nella casella (43)
- [ ] Clic destro sull'icona: stato, Finestra mini, Scollega il telefono, Apri WebcamLR, Esci; ogni voce funziona (44)
- [ ] Passando sull'icona: «WebcamLR · Collegato a … · Ottimo» oppure «WebcamLR · Nessun telefono» (45)
- [ ] Sposta e ridimensiona la finestra, Esci e riapri: torna uguale; se era su uno schermo staccato, compare sul principale (47)
- [ ] Dopo qualche secondo di video, a destra delle statistiche compare la linea della latenza con il tratteggio dei 100 ms (48)

## 0.9 · Accessibilità (iPhone)

- [ ] Con VoiceOver ogni pulsante ha un nome: obiettivi, torcia, scollega, «Collega a …» (19)
- [ ] Con il testo più grande (Impostazioni › Schermo e luminosità › Dimensioni testo) i riquadri sopra il video non si tagliano (19)

## 0.9 · Mac

- [ ] Con VoiceOver ogni pulsante a sola icona dice cosa fa: timer, copia, riempi, vista pulita, finestra mini (38)

## 0.9 · Windows

- [ ] Su Windows 11 dietro la colonna di sinistra si vede lo sfondo Mica (50)
- [ ] Con Tab il fuoco va su Specchia → Finestra mini → Scollega; l'Assistente vocale legge lo stato quando cambia (50)
