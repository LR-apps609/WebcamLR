# Checklist 1.0 · tutto ciò da provare a mano

Un solo giro, nell'ordine in cui lo faresti davvero. Ogni riga ha un numero: se qualcosa non va, mandami il numero con uno screenshot. Le righe con **(PC)** servono solo se hai un PC Windows.

Il codice Swift è stato scritto e riletto da più revisori ma non compilato qui: se Xcode segnala errori, mandali così come sono, è la prima cosa da sistemare.

È normale vedere molti **avvisi gialli** in Xcode (concorrenza, API deprecate): non bloccano. Mandami solo gli **errori rossi**. Al primo avvio il Mac potrebbe chiedere l'accesso al Portachiavi per «WebcamLR · identità di questo Mac»: scegli «Consenti sempre».

## A · Preparazione (5 minuti)

1. Serve **Xcode 16 o successivo** (Xcode › Informazioni su Xcode). Chiudi Xcode
2. Terminale: `cd ~/Documents/WebcamLR && git fetch && git checkout round-2 && git pull`
3. Doppio clic su `Strumenti/Costruisci e installa.command`, account **N**. Se compare «⚠️ Alcuni test del protocollo non passano», mandami le righe sopra l'avviso (la build continua)
4. In Xcode scegli il tuo iPhone e premi ▶
5. (PC) Doppio clic su `Strumenti\Costruisci e avvia.bat`

- [ ] A1 · La build del Mac arriva a «Fatto» e WebcamLR si apre, con il logo nel Dock
- [ ] A2 · L'app si installa sull'iPhone, con il logo nella schermata Home
- [ ] A3 · (PC) I test passano e la finestra si apre

## B · Primo avvio e primo collegamento

- [ ] B1 · iPhone: compaiono le 3 pagine di benvenuto; «Inizia» chiede la fotocamera, poi la rete locale (rispondi Consenti a entrambe)
- [ ] B2 · Mac senza telefono: al centro il QR code grande e i tre passi
- [ ] B3 · iPhone: il Mac compare da solo nella lista; toccalo
- [ ] B4 · iPhone: «Conferma sul computer» con 4 cifre; Mac: «Consentire «…»?» con le **stesse** 4 cifre; premi Consenti
- [ ] B5 · Entro 2–3 secondi il video dell'iPhone è nel Mac; sotto il video «▮▮▮ Ottimo» e la latenza (annota il numero)
- [ ] B6 · iPhone in alto: «Ottimo» e la stessa latenza
- [ ] B7 · Chiudi del tutto l'app sull'iPhone e riaprila: «Mi ricollego a … tra 3…», poi il video riparte **senza** codice
- [ ] B8 · Nella lista dei computer basta toccare un punto qualsiasi della riga per collegarsi
- [ ] B9 · Aprendo il lettore QR o «Inserisci l'indirizzo» durante «Mi ricollego… tra 3», il conto si annulla e «In onda» non si apre sotto

## C · Qualità del video e velocità

- [ ] C1 · 10 minuti di video senza scatti né blocchi (prova anche con WebcamLR del Mac dietro altre finestre)
- [ ] C2 · Latenza tipica uguale o più bassa di 51 ms: manda il valore
- [ ] C3 · Allontanati dal router o avvia un download pesante: «Rete lenta» sull'iPhone, il video resta fluido; tornando vicino la qualità risale
- [ ] C4 · Tocca l'anteprima sull'iPhone: il riquadro della messa a fuoco compare **subito**
- [ ] C5 · Ogni pulsante, sul Mac e sull'iPhone, risponde subito, senza attese
- [ ] C6 · Spegni il Wi-Fi dell'iPhone per 30 s durante «In onda»: «Nessuna rete…», nessun errore; riaccendendolo si ricollega subito
- [ ] C7 · Dopo «Collega» il video arriva sul computer più in fretta di prima, e l'anteprima dell'iPhone compare subito

## D · Inquadratura e comandi

- [ ] D1 · Cambia obiettivo (0,5 · 1× · Tele · Frontale) dall'iPhone e dal Mac: il video segue entro un paio di secondi
- [ ] D2 · Doppio tocco sull'anteprima: frontale ↔ posteriore
- [ ] D3 · Tieni premuto sull'anteprima: «AE/AF bloccati»; un tocco sblocca
- [ ] D4 · Impostazioni › Inquadratura: griglia e livella; la livella diventa verde con il telefono dritto
- [ ] D5 · Dal Mac: zoom fluido, esposizione, bianco, torcia, «Messa a fuoco automatica»
- [ ] D6 · Dal Mac: «Esposizione manuale», ISO e tempo cambiano l'immagine; sull'iPhone compare «ISO … · 1/…» in ambra
- [ ] D7 · Dal Mac: «Profili» › salva, cambia qualcosa, riapplica: torna tutto come salvato
- [ ] D8 · Gira l'iPhone in verticale e in orizzontale: il video sul Mac segue
- [ ] D9 · «In onda» in verticale: stato, dati tecnici e batteria uno sotto l'altro; in orizzontale su un iPhone piccolo tutti i pulsanti della barra si raggiungono, niente sotto la Dynamic Island
- [ ] D10 · Con «AE/AF bloccati», se il telefono si scalda o la batteria scende sotto il 20%, dopo il cambio di qualità la scritta sparisce

## E · Mac come una regia

- [ ] E1 · ⇧⌘M: la finestra mini sopra le altre app; ⇧⌘M di nuovo la chiude
- [ ] E2 · ⌘T foto (lampo bianco), ⇧⌘T timer 3-2-1, ⌘C e incolla in Note: c'è il fotogramma
- [ ] E3 · ⌘R registra: «Ferma · 00:12 · 8,4 MB»; ⌘R di nuovo salva in Filmati › WebcamLR
- [ ] E4 · ⇧⌘P vista pulita, Esc torna; ⌥⌘F riempi/adatta
- [ ] E5 · 1–4 obiettivi, + e − zoom, F messa a fuoco
- [ ] E6 · Icona nella barra in alto: vuota senza telefono, piena con il telefono; dal suo menu funzionano foto, registra, finestra mini, scollega
- [ ] E7 · ⌘, Impostazioni: «Apri all'avvio», notifiche, «Specchia di serie»
- [ ] E8 · Con WebcamLR in secondo piano: notifiche «collegato» e, 15 s dopo aver chiuso l'app sull'iPhone, «perso»; il clic riapre la finestra
- [ ] E9 · Chiudi la finestra principale e riapri WebcamLR: l'iPhone trova subito il Mac anche a finestra chiusa; il QR nel menu della barra c'è già
- [ ] E10 · Dalla barra in alto, l'ingranaggio apre le Impostazioni **davanti** alle altre app; le sezioni sono Avvio, Notifiche, Anteprima, Sicurezza
- [ ] E11 · Registrazione di un solo secondo: «Registrazione troppo breve…» invece di un errore tecnico

## F · Batteria e calore

- [ ] F1 · Dopo 30 secondi senza tocchi lo schermo dell'iPhone si oscura da solo; il video continua
- [ ] F2 · Sotto il 20% senza caricatore: 24 fps e banner ambra sul Mac
- [ ] F3 · Dopo 30 minuti l'iPhone è tiepido, non caldo

## G · Sicurezza

- [ ] G1 · Sul Mac, alla domanda «Consentire …?», premi **Non consentire**: l'iPhone dice «Collegamento non confermato» e non riprova da solo
- [ ] G2 · Collegamento con il QR code (sull'iPhone «Inquadra il QR code del computer»): nessun codice, si collega subito; dopo, il QR del Mac è cambiato
- [ ] G3 · Mac, Impostazioni › Sicurezza: l'iPhone è tra i telefoni fidati; «Rimuovi» → la volta dopo il Mac chiede di nuovo il codice
- [ ] G4 · Con l'iPhone collegato, collega un secondo telefono (o lo stesso dopo averlo rimosso dai fidati): il primo **non** cade mentre il secondo aspetta la conferma
- [ ] G5 · (PC) Le stesse prove G1–G3 con Windows

## H · Altri modi per collegarsi

- [ ] H1 · iPhone e Mac senza una rete in comune (Wi-Fi acceso, nessun router): il Mac compare lo stesso
- [ ] H2 · Hotspot personale dell'iPhone con il cavo collegato al Mac: il Mac compare e il video parte
- [ ] H3 · «Inserisci l'indirizzo» con l'indirizzo scritto sotto il QR del Mac: si collega

## I · Sezione App

- [ ] I1 · iPhone, pulsante (i): Pro con «Presto disponibile», «Modalità senza account», Guida, Segnala un bug, Computer conosciuti, Informazioni
- [ ] I2 · «Segnala un bug»: i dati tecnici non contengono nomi di persone o di computer; «Invia la segnalazione» apre la condivisione
- [ ] I3 · Mac: menu Aiuto › «Guida di WebcamLR» (⌘?) e «Segnala un bug…»; menu WebcamLR › «Informazioni su WebcamLR»
- [ ] I4 · (PC) «App e assistenza» con le schede Pro, Guida, Sicurezza, Segnala un bug, Informazioni

## L · Windows (PC)

- [ ] L1 · Il video dell'iPhone nella finestra, con qualità e grafico della latenza
- [ ] L2 · Finestra mini, F11, Specchia, Scollega
- [ ] L3 · Icona accanto all'orologio: stato al passaggio del mouse, menu completo, notifiche
- [ ] L4 · «Avvia con Windows»; dimensione e posizione ricordate

## M · Aspetto e parole

- [ ] M1 · Nessun testo in inglese, nessun «round», nessuna parola tecnica strana, in tutte le app
- [ ] M2 · Le tre app sembrano della stessa famiglia: colori, caratteri, logo
- [ ] M3 · Il rosso compare solo per «In onda» e per la registrazione
- [ ] M4 · Mac: microfono e uscita NDI mostrano «IN ARRIVO» in una capsula tenue; la webcam virtuale dice «Richiede l'account sviluppatore Apple a pagamento.»
- [ ] M5 · iPhone: microfono e PRO in «In onda» tratteggiati con «PRESTO»; la scheda «Via cavo USB» con «IN ARRIVO» spiega l'Hotspot personale
- [ ] M6 · Testo più grande al massimo (Impostazioni › Schermo e luminosità › Dimensioni testo): le schermate dell'iPhone restano leggibili; con VoiceOver l'errore o il codice di conferma si leggono per primi
- [ ] M7 · Lettore QR con il permesso della fotocamera negato: spiegazione e «Apri Impostazioni»
- [ ] M8 · Chiudi WebcamLR sul computer: dopo i tentativi l'iPhone mostra un errore in italiano che dice cosa fare
