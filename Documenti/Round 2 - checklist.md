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

## 0.3 · Si collega da solo

- [ ] Collegati al Mac, chiudi l'app sull'iPhone del tutto e riaprila: compare «Mi ricollego a … tra 3…» e si collega da solo (2)
- [ ] Con «Annulla» resta sulla lista; dopo «Scollega» non riparte da sola (2)
- [ ] Vibra quando si collega, quando cambi obiettivo, al blocco AE/AF, e una volta sola quando chiudi l'app sul Mac (3)
- [ ] Chiudi WebcamLR sul Mac: sull'iPhone compare il banner con i secondi; «Riprova ora» riprova subito (15)
- [ ] Benvenuto: dopo aver cancellato e reinstallato l'app compaiono 3 pagine; «Inizia» chiede la fotocamera e poi la rete locale; alla seconda apertura non compaiono più (16)

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

## 0.9 · Accessibilità (iPhone)

- [ ] Con VoiceOver ogni pulsante ha un nome: obiettivi, torcia, scollega, «Collega a …» (19)
- [ ] Con il testo più grande (Impostazioni › Schermo e luminosità › Dimensioni testo) i riquadri sopra il video non si tagliano (19)
