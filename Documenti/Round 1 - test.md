# Round 1 · checklist di test

Funzioni del round: 1 (ricerca automatica), 3 (video H.264), 4 (anteprima nel ricevitore), 5 (latenza sempre visibile).
In più: caratteri e colori della bozza grafica su iPhone, Mac e Windows, e alcune funzioni anticipate dai round successivi (indicate riga per riga). Se il tempo è poco, prova prima le sezioni «Mac» e «iPhone → Mac»: le altre possono aspettare.

Il codice Swift è stato scritto senza poterlo compilare: se Xcode segnala errori, manda le righe così come sono.

## Prima di iniziare

1. Nel Terminale: `cd ~/Documents/WebcamLR && git pull && git checkout round-1`
2. Lancia `./Strumenti/Costruisci\ e\ installa.command`
3. In Xcode premi ▶ con l'iPhone collegato

## Mac

- [ ] La finestra non ha più la barra del titolo grigia: in alto c'è il logo, «WebcamLR» con «LR» rosso e la pillola «NESSUN TELEFONO»
- [ ] I titoli usano il carattere stretto della bozza (Barlow Condensed) e i numeri il carattere a spaziatura fissa (IBM Plex Mono)
- [ ] A sinistra: «In attesa di un telefono» e «Visibile in rete · porta 52740»

## iPhone → Mac

- [ ] Sull'iPhone «Scegli il computer» mostra il Mac; «Collega» apre la schermata «In onda» con l'anteprima della fotocamera
- [ ] Entro 2–3 secondi il video compare nella finestra del Mac
- [ ] Sul Mac la pillola diventa «COLLEGATO · PRONTA» e a sinistra compare il nome dell'iPhone con latenza e batteria
- [ ] Sotto l'anteprima: «1920×1080 · 30 fps · H.264 · … Mbit/s · latenza … ms»
- [ ] **Controllo di passaggio: latenza sotto 100 ms in Wi-Fi** (il numero è ciano sotto 100, ambra sopra). Annota il valore tipico
- [ ] La stessa latenza compare anche sull'iPhone, in alto
- [ ] Cambiando obiettivo (0,5 · 1× · Tele · Front.) il video sul Mac cambia entro un paio di secondi
- [ ] Girando l'iPhone in verticale il video sul Mac diventa verticale, e torna orizzontale girandolo di nuovo
- [ ] Torcia: si accende e si spegne (solo obiettivi posteriori)
- [ ] Toccando l'anteprima sull'iPhone compare un riquadro giallo e il fuoco va lì (funzione 21, anticipata)
- [ ] Con due dita si fa zoom; il valore compare in alto (funzione 22, anticipata)
- [ ] «Effetti» apre il pannello effetti video di iOS; con la fotocamera frontale «Ritratto» sfoca lo sfondo anche nel video sul Mac (funzioni 27–28 nella versione di Apple)
- [ ] Impostazioni › «Specchia l'immagine inviata»: al collegamento successivo il video sul Mac è specchiato (funzione 25)
- [ ] «Oscura»: lo schermo dell'iPhone diventa nero e il video continua sul Mac; due tocchi lo riaccendono
- [ ] «Specchia» e «Schermo intero» sul Mac funzionano
- [ ] «Foto» sul Mac salva l'immagine in Immagini › WebcamLR e la mostra nel Finder (funzione 35, anticipata)
- [ ] Scorciatoie sul Mac: ⌘T scatta una foto, ⌘R avvia e ferma la registrazione, ⌃⌘F schermo intero
- [ ] «Registra» in alto sul Mac: compare il punto rosso con il tempo; «Ferma» salva un .mov in Filmati › WebcamLR che si apre con QuickTime e va avanti e indietro

## Comandi della fotocamera dal Mac (round 4, anticipato)

- [ ] Con l'iPhone collegato, nella colonna destra del Mac compaiono Obiettivo, Zoom, Esposizione, Bilanciamento del bianco, Torcia e «Fuoco automatico»
- [ ] Cambiando obiettivo dal Mac l'iPhone cambia obiettivo, e il video sul Mac lo segue
- [ ] Zoom ed esposizione si vedono cambiare nel video mentre muovi il cursore
- [ ] Togliendo «Bilanciamento del bianco automatico», il cursore in kelvin rende l'immagine più calda o più fredda
- [ ] La torcia si accende e si spegne dal Mac (solo obiettivi posteriori)
- [ ] «Esposizione manuale (ISO e tempo)» (funzione 19): ISO alto schiarisce, 1/250 s scurisce e congela il movimento
- [ ] Con l'esposizione manuale sull'iPhone, in alto, compare «ISO … · 1/…» in ambra; togliendo l'interruttore torna l'automatico e la scritta sparisce
- [ ] Con l'esposizione manuale accesa, toccare l'anteprima sull'iPhone mette a fuoco ma non cambia la luce
- [ ] A 30 fps, 1/25 s non fa rallentare il video (resta a 30 fps sotto l'anteprima)
- [ ] «Profili» › «Salva i comandi attuali…» con un nome; cambia qualche comando, poi scegli il profilo dal menu: obiettivo, zoom, esposizione e bianco tornano come salvati, anche dopo aver riaperto WebcamLR (funzione 23, anticipata)

## QR code e indirizzo (funzione 2, anticipata dal round 2)

- [ ] Sul Mac, a sinistra, «Collega con QR code» mostra un QR code e l'indirizzo da scrivere
- [ ] Lo stesso QR code compare nel menu in alto quando nessun telefono è collegato
- [ ] Sull'iPhone «Inquadra il QR code del computer» apre la fotocamera; inquadrando il QR il collegamento parte da solo
- [ ] «Inserisci l'indirizzo» con l'indirizzo mostrato dal Mac collega lo stesso
- [ ] Un indirizzo sbagliato (per esempio «192.168.1») mostra «Indirizzo non valido»
- [ ] Con WebcamLR chiusa sul Mac, dopo 8 secondi l'iPhone mostra «Non trovi il computer?» con i passi da controllare (funzione 34, anticipata)

## Webcam virtuale con il video vero (round 2, solo con l'account a pagamento)

- [ ] Con l'iPhone collegato, in FaceTime o Photo Booth la webcam «WebcamLR» mostra il video dell'iPhone
- [ ] Scollegando l'iPhone, dopo un secondo torna l'immagine di prova (fondo scuro, barra ciano)
- [ ] Mentre FaceTime o Photo Booth usa la webcam, sul Mac la pillola diventa rossa «IN ONDA» e anche l'iPhone mostra «IN ONDA» in rosso; chiudendo l'app tornano «COLLEGATO»

## HEVC (funzione 10, anticipata)

- [ ] Sull'iPhone, Impostazioni › Formato › HEVC; ricollegandosi il Mac mostra «HEVC» sotto l'anteprima e il video si vede
- [ ] Con HEVC i Mbit/s scendono di circa un terzo rispetto a H.264, a parità di risoluzione
- [ ] «Registra» funziona anche in HEVC
- [ ] Su Windows HEVC si vede solo con l'estensione «Estensioni video HEVC» di Microsoft Store; senza, al posto del video c'è il messaggio che spiega cosa fare

## Affidabilità

- [ ] 10 minuti di video senza scatti né cadute
- [ ] Chiudendo e riaprendo l'app Mac, l'iPhone mostra «Riconnessione» e poi torna collegato da solo
- [ ] Spegnendo il Wi-Fi dell'iPhone per 5 secondi e riaccendendolo, il video riprende da solo
- [ ] Dopo 30 minuti l'iPhone è tiepido, non caldo (la temperatura è anche nella colonna destra del Mac)
- [ ] Se l'iPhone diventa molto caldo compare «qualità ridotta a 720p» e il Mac riceve 720p; torna alla qualità scelta quando si raffredda (funzione 31, anticipata)
- [ ] Sotto il 20% di batteria, senza caricatore, l'iPhone mostra l'avviso in ambra (funzione 33, anticipata)

## Windows (anticipo del round 3, facoltativo)

- [ ] `Strumenti\Costruisci e avvia.bat` passa i test (protocollo e iPhone simulato) e apre la finestra, con i caratteri della bozza
- [ ] Al primo avvio Windows chiede il permesso per le reti: consenti le **reti private**
- [ ] A destra c'è il QR code con l'indirizzo del PC
- [ ] Sull'iPhone il PC compare da solo nella lista (Windows 10 versione 1903 o successiva); altrimenti si collega con il QR code
- [ ] Collegato: la pillola diventa «COLLEGATO · PRONTA», a sinistra nome dell'iPhone, latenza e batteria
- [ ] Il video dell'iPhone si vede nella finestra; sotto, risoluzione, fps, Mbit/s e latenza (annota il valore)
- [ ] Nella colonna destra ci sono gli stessi comandi della fotocamera del Mac, compresa l'esposizione manuale
- [ ] F11 mette la finestra a schermo intero, F11 o Esc la riportano normale
- [ ] «Specchia» sotto il video lo specchia; chiudendo e riaprendo WebcamLR resta come l'avevi lasciato
- [ ] Passando a un'altra rete Wi-Fi il QR code e l'indirizzo scritto cambiano da soli
- [ ] L'icona di WebcamLR compare accanto all'orologio; chiudendo la finestra l'app resta lì, con un clic la finestra torna, dal menu «Esci» si chiude davvero
- [ ] La webcam virtuale per Zoom e Teams su Windows **non c'è ancora**: arriva con il round 3
