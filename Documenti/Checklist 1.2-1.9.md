# Checklist 1.2–1.9 · collegamento, aiuto e cavo USB

Da fare **dopo** la Checklist 1.0. Stessa regola: ogni riga ha un numero; se qualcosa non va, mandami il numero con uno screenshot. **(PC)** solo con Windows.

Il codice Swift è stato scritto e riletto da revisori diversi ma non compilato qui: se Xcode segnala errori rossi, mandameli così come sono.

## A · Preparazione

1. Terminale: `cd ~/Documents/WebcamLR && git pull`
2. Doppio clic su `Strumenti/Costruisci e installa.command` (account **N**), poi ▶ in Xcode con l'iPhone
3. (PC) `Strumenti\Costruisci e avvia.bat`
4. (PC) Per il cavo: installa l'app gratuita **«Dispositivi Apple»** da Microsoft Store (prima prova la riga P1 senza)

- [ ] A1 · Mac, iPhone e (PC) Windows si costruiscono e si aprono

## B · Indicatore del collegamento (1.2)

- [ ] B1 · In Wi-Fi: accanto alla qualità compaiono l'icona e «Wi-Fi», su iPhone e computer; anche nella riga del telefono a sinistra sul computer
- [ ] B2 · Hotspot personale dell'iPhone con il computer collegato a quello: «Hotspot»
- [ ] B3 · Mac con «Wi-Fi diretto» acceso e nessuna rete in comune: «Wi-Fi diretto»
- [ ] B4 · Computer sul cavo di rete (Ethernet): sul computer «Cavo di rete»
- [ ] B5 · Rete lenta (lontano dal router): compare il consiglio «Con il cavo USB è più stabile»

## C · Diagnosi (1.3)

- [ ] C1 · iPhone, permesso «Rete locale» tolto: nella lista dei computer la scheda con «Apri Impostazioni»; riattivandolo la scheda sparisce
- [ ] C2 · iPhone con il Wi-Fi spento (solo cellulare): «Collegati al Wi-Fi o usa il cavo»
- [ ] C3 · Mac senza Wi-Fi: «Il Mac non è collegato a una rete», con «Accendi il Wi-Fi diretto»
- [ ] C4 · iPhone al cavo con WebcamLR **chiusa** sull'iPhone: il computer dice «Apri WebcamLR sull'iPhone»; aprendola si collega entro pochi secondi
- [ ] C5 · (PC) Rete del PC su «Pubblica»: senza telefono compare l'avviso con «Apri le impostazioni di rete»; resa privata, sparisce entro 10 secondi
- [ ] C6 · (PC) WebcamLR tolta da «Consenti app attraverso il firewall»: compare l'avviso sul firewall con «Apri il firewall»
- [ ] C7 · Ogni avviso ha «Perché succede?» o «Leggi la risposta», che apre la domanda frequente giusta già aperta

## D · Domande frequenti (1.4)

- [ ] D1 · iPhone: App › Domande frequenti; Mac: pulsante «Aiuto» in alto a destra › Domande frequenti; (PC) App e assistenza › Domande frequenti
- [ ] D2 · La ricerca trova «cavo», «lag», «albergo», «qualita» (anche senza accento); una parola a caso mostra «Nessuna risposta…»
- [ ] D3 · Le risposte si aprono e si chiudono; i testi sono uguali sulle tre app

## E · Modalità avanzata (1.5)

- [ ] E1 · Di serie è spenta: niente ms, numeri, grafico, ISO/tempo, bianco e profili; restano obiettivo, zoom, specchia, foto, registra e qualità
- [ ] E2 · Accesa (Impostazioni › «Modalità avanzata»): torna tutto, più il «Registro del collegamento» con gli eventi e l'ora; «Copia» o «Condividi» funziona
- [ ] E3 · La scelta resta dopo aver chiuso e riaperto l'app
- [ ] E4 · Tornando alla modalità semplice con ISO o bianco manuali, la fotocamera torna all'automatico (o i controlli manuali restano visibili per rimetterli in automatico)

## F · Stesso telefono (correzione)

- [ ] F1 · Due iPhone con lo stesso nome: il secondo è trattato come un telefono nuovo (comandi azzerati); lo stesso iPhone che si ricollega ritrova zoom, bianco, ISO

## P · Cavo USB (1.6–1.9)

- [ ] P1 · (PC) Senza «Dispositivi Apple»: compare «Per il cavo USB installa l'app gratuita «Dispositivi Apple»…»; «Apri Microsoft Store» apre la pagina giusta
- [ ] P2 · **Mac** (Apple ID gratuito): iPhone sulla lista dei computer, cavo collegato, WebcamLR aperta sul Mac → «In onda» si apre da sola con «Cavo USB». La prima volta compare il codice di conferma. Se invece il Mac dice che il servizio del cavo non è disponibile, mandami uno screenshot: è il permesso del sandbox
- [ ] P3 · (PC) La stessa prova P2 su Windows
- [ ] P4 · La prima volta l'iPhone può chiedere «Autorizzare questo computer?»: scegli Autorizza e annota se serviva
- [ ] P5 · Latenza col cavo: annota il valore e confrontalo con il Wi-Fi
- [ ] P6 · Già collegato in Wi-Fi, poi collego il cavo: il video passa al cavo senza fermarsi, i comandi restano, l'indicatore passa a «Cavo USB»
- [ ] P7 · Stacco il cavo durante il video: «Cavo scollegato? Riparto…»; se iPhone e computer sono sulla stessa rete, il video torna in Wi-Fi; ricollegando il cavo entro 20 s riparte sul cavo
- [ ] P8 · «Scollega» col cavo (dall'iPhone o dal computer): non si ricollega da solo; «Collega via cavo» (o staccare e riattaccare il cavo) lo fa ripartire
- [ ] P9 · iPhone nuovo sul cavo e scelgo «Non consentire» sul computer: la domanda **non** torna ogni 2 secondi
- [ ] P10 · Dal registro dell'iPhone (modalità avanzata): «In ascolto sul cavo USB (porta 52741)»
- [ ] P11 · 10 minuti col cavo senza scatti; l'iPhone intanto si ricarica
- [ ] P12 · La latenza in Wi-Fi è uguale a prima (nessun peggioramento)
- [ ] P13 · In onda in Wi-Fi, collego il cavo a un **altro** computer: resta il Wi-Fi, nessun errore
- [ ] P14 · Con il Wi-Fi in «mi ricollego…» o nel pannello d'errore, collego il cavo: riparte via cavo da solo
- [ ] P15 · Dopo il passaggio al cavo, sul computer c'è un solo telefono e zoom, torcia e obiettivo funzionano
- [ ] P16 · Modalità avanzata accesa: mandami il «Registro del collegamento» di un giro Wi-Fi → cavo → Wi-Fi
