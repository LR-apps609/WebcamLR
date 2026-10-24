# Checklist 1.10–1.12 · collegamento istantaneo

Da fare dopo la Checklist 1.2–1.9. Se qualcosa non va, mandami il numero con uno screenshot. **(PC)** solo con Windows. Codice Swift non compilato qui: gli errori rossi di Xcode mandameli così come sono.

## Q · QR istantaneo (1.10)

- [ ] Q1 · Con il permesso della fotocamera già dato, «Inquadra il QR code» mostra subito l'immagine, senza rotellina
- [ ] Q2 · Alla lettura: vibrazione, spunta ciano, «QR code letto: mi collego a …», poi «In onda»; dal QR al video in meno di 2 s
- [ ] Q3 · Computer con Wi-Fi + cavo di rete: il QR contiene tutti e due gli indirizzi; staccando il cavo di rete il QR cambia da solo entro 2 secondi
- [ ] Q4 · QR con un indirizzo irraggiungibile per primo: si collega lo stesso senza attese visibili; nel registro «Risponde l'indirizzo …»
- [ ] Q5 · (PC) Con VPN, WSL o Hyper-V accesi gli indirizzi virtuali non sono nel QR
- [ ] Q6 · Prima volta senza permesso della fotocamera: iOS lo chiede dentro il foglio, poi il lettore parte subito
- [ ] Q7 · Dopo il QR il video parte normale (nessuna fotocamera nera o bloccata)

## A · Avvio rapido (1.11)

- [ ] A1 · Modalità avanzata: su iPhone e computer compare «Avvio: x,x s»; nel registro del computer la riga con le tappe (mandami lo screenshot)
- [ ] A2 · Chiudi l'app sull'iPhone e riaprila: «Mi ricollego a … tra 2…», alla fine il video parte subito; «Avvio» sotto i 2–3 s
- [ ] A3 · Durante «tra 2…» apri il QR o «Inserisci l'indirizzo»: il conto si annulla e il computer **non** mostra l'iPhone collegato
- [ ] A4 · «Annulla» durante il conto: il computer non accoglie l'iPhone

## O · In qualsiasi ordine (1.12)

- [ ] O1 · Apri prima l'iPhone, con WebcamLR chiuso sul computer: «Apri WebcamLR su «Nome»: mi collego da solo appena compare»; aprendo il computer, video da solo
- [ ] O2 · Un computer mai collegato non provoca nessun collegamento automatico
- [ ] O3 · In onda, chiudi WebcamLR sul computer: banner calmo «In attesa di «Nome»…», nessun errore; riaprendolo il video riparte da solo, senza codice
- [ ] O4 · In onda, «Scollega» dal computer: l'iPhone resta in attesa e non si ricollega da solo; «Riprova ora» funziona
- [ ] O5 · Cambia Wi-Fi e torna (o spegni e riaccendi il Wi-Fi, o usa l'Hotspot): il video torna da solo
- [ ] O6 · Computer in stop con l'iPhone in attesa, poi risveglio: il telefono ritrova il computer da solo (registro: «Risveglio dallo stop…»)
- [ ] O7 · Con il cavo: stop e risveglio del computer, il cavo riparte senza staccarlo; dopo «Scollega» via cavo resta in pausa anche dopo il risveglio
- [ ] O8 · Alcuni minuti in attesa: nessuna vibrazione ripetuta, fotocamera spenta (niente pallino verde), batteria quasi ferma
