# Round 1 · checklist di test

Funzioni del round: 1 (ricerca automatica), 3 (video H.264), 4 (anteprima nel ricevitore), 5 (latenza sempre visibile).
In più: caratteri e colori della bozza grafica su iPhone, Mac e Windows.

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
- [ ] «Oscura»: lo schermo dell'iPhone diventa nero e il video continua sul Mac; due tocchi lo riaccendono
- [ ] «Specchia» e «Schermo intero» sul Mac funzionano

## Comandi della fotocamera dal Mac (round 4, anticipato)

- [ ] Con l'iPhone collegato, nella colonna destra del Mac compaiono Obiettivo, Zoom, Esposizione, Bilanciamento del bianco, Torcia e «Fuoco automatico»
- [ ] Cambiando obiettivo dal Mac l'iPhone cambia obiettivo, e il video sul Mac lo segue
- [ ] Zoom ed esposizione si vedono cambiare nel video mentre muovi il cursore
- [ ] Togliendo «Bilanciamento del bianco automatico», il cursore in kelvin rende l'immagine più calda o più fredda
- [ ] La torcia si accende e si spegne dal Mac (solo obiettivi posteriori)

## QR code e indirizzo (funzione 2, anticipata dal round 2)

- [ ] Sul Mac, a sinistra, «Collega con QR code» mostra un QR code e l'indirizzo da scrivere
- [ ] Lo stesso QR code compare nel menu in alto quando nessun telefono è collegato
- [ ] Sull'iPhone «Inquadra il QR code del computer» apre la fotocamera; inquadrando il QR il collegamento parte da solo
- [ ] «Inserisci l'indirizzo» con l'indirizzo mostrato dal Mac collega lo stesso
- [ ] Un indirizzo sbagliato (per esempio «192.168.1») mostra «Indirizzo non valido»

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
- [ ] La webcam virtuale per Zoom e Teams su Windows **non c'è ancora**: arriva con il round 3
