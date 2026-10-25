# Checklist iPhone e Mac · tutto in un giro

Questa checklist **sostituisce** `Checklist 1.0.md`, `Checklist 1.2-1.9.md` e `Checklist 1.10-1.12.md` per iPhone e Mac: dentro c'è tutto quello che è stato costruito finora, fino al pacchetto funzioni P01–P23. Windows e Android restano nei loro file (`Windows/FotocameraVirtuale/LEGGIMI.md`, `Android/LEGGIMI.md`) e per ora sono in pausa.

Come sempre: ogni riga ha un codice (A1, B3…). Se qualcosa non va, mandami il codice con uno screenshot. Le righe con ★ sono le più importanti.

Il codice Swift è stato riletto da più revisori ma **qui non si può compilare**: la prima cosa è la build.

La «Modalità avanzata» non c'è più, né su iPhone né sul Mac: tutto è sempre a vista (millisecondi, grafico, formato, «Avvio», registro del collegamento, ISO/tempo/bianco, profili, regolazioni, «Controlli Pro»).

## Giro veloce (20 minuti)

Se hai poco tempo, fai solo le ★, in quest'ordine:

0 (build) → A2 A4 A5 → B1 B3 → C2 C3 → D1 D3 D4 → E2 E8 → F1 F3 F5 F7 → G1 G3 G4 G7 G10 → H1 → I1 I3 → L3 → M1 → N2 N4

## 0 · Aggiornare e costruire (10 minuti)

1. Chiudi Xcode. Terminale: `cd ~/Documents/WebcamLR && git fetch && git checkout round-2 && git pull`
2. Doppio clic su `Strumenti/Costruisci e installa.command`; alla domanda sull'account rispondi **N** (Apple ID gratuito)
3. In Xcode scegli il tuo iPhone in alto e premi **▶**
4. Facoltativo, per la sezione L: doppio clic su `Strumenti/Installa microfono.command` (chiede la password del Mac; i suoni del Mac si fermano un attimo)

- [ ] 01 · ★ La build del Mac arriva a «Fatto» e WebcamLR si apre, con il logo nuovo nel Dock
- [ ] 02 · ★ L'app si installa sull'iPhone, con il logo nuovo nella schermata Home

**Se ci sono errori**: mandami gli **errori rossi** di Xcode così come sono (testo copiato o screenshot) e `Strumenti/ultima-build.log`. Gli avvisi gialli non bloccano: ignorali. Al primo avvio il Mac può chiedere il Portachiavi per «WebcamLR · identità di questo Mac»: «Consenti sempre».

## A · Primo collegamento in Wi-Fi

- [ ] A1 · iPhone: 3 pagine di benvenuto; «Inizia» chiede fotocamera e rete locale (Consenti a tutte e due)
- [ ] A2 · ★ Mac senza telefono: QR code grande al centro e i tre passi
- [ ] A3 · iPhone: il Mac compare da solo nella lista; basta toccare un punto qualsiasi della riga
- [ ] A4 · ★ iPhone «Conferma sul computer» con 4 cifre; Mac «Consentire «…»?» con le **stesse** cifre; Consenti → video entro 2–3 s, «▮▮▮ Ottimo» e la latenza su tutti e due (annota il numero)
- [ ] A5 · ★ Collegamento col QR (iPhone: «Inquadra il QR code del computer»): il lettore parte subito, vibrazione e spunta ciano, video in meno di 2 s, nessun codice
- [ ] A6 · Mac, «Consentire…?» → **Non consentire**: l'iPhone dice «Collegamento non confermato» e non riprova da solo
- [ ] A7 · «Inserisci l'indirizzo» con l'indirizzo scritto sotto il QR del Mac: si collega
- [ ] A8 · Mac, ingranaggio › Sicurezza: l'iPhone è tra i telefoni fidati; «Rimuovi» → la volta dopo torna il codice di conferma
- [ ] A9 · Accanto alla qualità c'è «Wi-Fi» (iPhone, Mac e riga del telefono a sinistra); con l'Hotspot personale «Hotspot»

## B · Ricollegamento e collegamento istantaneo

- [ ] B1 · ★ Chiudi del tutto l'app sull'iPhone e riaprila: «Mi ricollego a … tra 2…», poi video **senza** codice
- [ ] B2 · Durante «tra 2…» apri il QR o «Inserisci l'indirizzo», oppure premi «Annulla»: il conto si annulla e il Mac non mostra l'iPhone collegato
- [ ] B3 · ★ In onda, chiudi WebcamLR sul Mac: banner calmo «In attesa di «Nome»…», nessun errore; riaprendolo il video riparte da solo
- [ ] B4 · Apri prima l'iPhone, con WebcamLR chiuso sul Mac: «mi collego da solo appena compare»; aprendo il Mac il video parte da solo
- [ ] B5 · In onda, «Scollega» dal Mac: l'iPhone resta in attesa e non si ricollega da solo; «Riprova ora» funziona
- [ ] B6 · Spegni il Wi-Fi dell'iPhone per 30 s, o cambia rete e torna: nessun errore, il video torna da solo
- [ ] B7 · Mac in stop e risveglio: l'iPhone ritrova il Mac da solo; chiudendo il coperchio, entro 6 s l'iPhone mostra la riconnessione
- [ ] B8 · App in secondo piano sull'iPhone per un minuto e ritorno: il video riparte sul Mac
- [ ] B9 · Su iPhone e Mac «Avvio: x,x s» (sempre a vista) sotto i 2–3 secondi (annota il valore)

## C · Cavo USB e passaggio Wi-Fi ↔ cavo

- [ ] C1 · La prima volta l'iPhone può chiedere «Autorizzare questo computer?»: Autorizza (annota se è comparso)
- [ ] C2 · ★ iPhone sulla lista dei computer, cavo collegato, WebcamLR aperta sul Mac → «In onda» si apre da sola con «Cavo USB». Se il Mac dice che il servizio del cavo non è disponibile, screenshot
- [ ] C3 · ★ Già in Wi-Fi, collega il cavo: il video passa al cavo senza fermarsi, i comandi restano, l'indicatore dice «Cavo USB», sul Mac c'è un solo telefono
- [ ] C4 · Stacca il cavo durante il video: «Cavo scollegato? Riparto…», il video torna in Wi-Fi; ricollegando entro 20 s riparte sul cavo
- [ ] C5 · «Scollega» col cavo: non si ricollega da solo; staccare e riattaccare il cavo lo fa ripartire
- [ ] C6 · WebcamLR **chiusa** sull'iPhone col cavo attaccato: il Mac dice «Apri WebcamLR sull'iPhone»; aprendola si collega in pochi secondi
- [ ] C7 · Latenza col cavo: annota il valore e confrontalo con il Wi-Fi; 10 minuti senza scatti, intanto l'iPhone si ricarica

## D · Finestra del Mac: pulsanti in alto e comandi grigi

- [ ] D1 · ★ Senza telefono il pannello Fotocamera è grigio con «Si attivano quando colleghi un telefono.»; la sezione Effetti e la riga «Microfono del telefono» dicono «Collega un telefono per usarlo.»
- [ ] D2 · Durante una riconnessione: «Mi ricollego al telefono: i comandi tornano appena il video riprende.»
- [ ] D3 · ★ In alto niente più «Modalità avanzata»: con il telefono collegato sotto il video ci sono sempre «▮▮▮ Ottimo» con i ms, il grafico e «1080p30 · H.264» (clic sulla qualità: tutti i numeri); a destra «Profili», «Esposizione manuale (ISO e tempo)», «Bilanciamento del bianco automatico» e «Regolazioni»; a sinistra «Registro del collegamento» con «Copia». Con la finestra al minimo (960×600) il pannello a destra scorre fino a «Torcia» e niente esce dal bordo
- [ ] D4 · ★ «Aiuto» in alto apre Guida, Domande frequenti, «Segnala un bug», Pro e Informazioni; la ricerca nelle domande trova «cavo» e «qualita» (anche senza accento)
- [ ] D5 · L'ingranaggio (o ⌘,) apre le Impostazioni con Avvio, Notifiche, Anteprima, Collegamento, Sicurezza
- [ ] D6 · Nessun menu in più nella barra in alto né icona vicino all'orologio; chiudendo la finestra, l'iPhone trova il Mac lo stesso e un clic sull'icona nel Dock la riapre

## E · Fotocamera dal Mac e dall'iPhone

- [ ] E1 · Obiettivi (0,5× · 1× · Tele · Frontale) dall'iPhone e dal Mac (anche tasti 1–4): il video segue entro un paio di secondi
- [ ] E2 · ★ Dal Mac: zoom fluido (anche + e −), esposizione, bianco, torcia, «Messa a fuoco automatica» (tasto F): l'immagine cambia subito
- [ ] E3 · iPhone: doppio tocco sull'anteprima frontale ↔ posteriore; tocco lungo «AE/AF bloccati», un tocco sblocca
- [ ] E4 · Sul Mac: «Esposizione manuale (ISO e tempo)» cambia l'immagine; «Profili» › salva, cambia, riapplica: torna tutto come salvato
- [ ] E5 · iPhone verticale e orizzontale: il video sul Mac segue; in orizzontale su un iPhone piccolo tutti i pulsanti della barra si raggiungono
- [ ] E6 · iPhone, ingranaggio nella barra di «In onda»: le Impostazioni si aprono sopra; griglia e livella cambiano dal vivo, un profilo nuovo si applica con «Fine» (il video si ferma solo un attimo)
- [ ] E7 · Pulsante «Effetti video» (quello di Apple): si apre il pannello di iOS con Ritratto e Luce da studio
- [ ] E8 · ★ iPhone, niente più «Modalità avanzata»: in «In onda» sempre la qualità con i ms, «1080p30 · H.264 · Avvio: x,x s», il pulsante «Registro del collegamento» e «Controlli Pro» nella barra; nelle Impostazioni Profili, poi Video (Risoluzione, Fotogrammi, Formato, Stabilizzazione) e in fondo «Diagnosi» › «Registro del collegamento»; lo schermo oscurato in verticale mostra i dati su due righe, niente tagliato

## F · Effetti

Sull'iPhone: pulsante «Effetti» nella barra di «In onda». Sul Mac: sezione «Effetti» sotto i comandi della fotocamera.

- [ ] F1 · ★ iPhone, «Filtri»: le miniature si muovono dal vivo; scegli «Cinema», «Bianco e nero», «Caldo»: il video cambia sull'iPhone e sul Mac; «Nessuno» torna normale
- [ ] F2 · Con un effetto acceso l'anteprima dell'iPhone **non** è specchiata (è il video come lo riceve il Mac) e il pulsante «Effetti» è ciano
- [ ] F3 · ★ Dal Mac scegli un filtro dalla griglia: l'iPhone lo mostra subito nel suo foglio «Effetti»
- [ ] F4 · «Regolazioni» (luminosità, contrasto, saturazione, nitidezza): i cursori agiscono subito; «Azzera» torna a zero (anche sul Mac)
- [ ] F5 · ★ «Sfondo» › «Sfocato» con l'intensità: lo sfondo si sfoca, i bordi di testa e capelli non sfarfallano
- [ ] F6 · «Sostituito»: Studio, Ufficio, Scuro e «Usa una tua foto…»; la foto resta dopo aver chiuso e riaperto l'app. Sul Mac: «L'immagine dello sfondo si sceglie sul telefono.»
- [ ] F7 · ★ «Ritocco della pelle» acceso: pelle più liscia, occhi, labbra e capelli nitidi, mai effetto plastica
- [ ] F8 · «Scritta e logo»: nome e ruolo in basso a sinistra nel video; «Aggiungi un logo…» lo mette in alto a destra; tutti e due si leggono dritti sul Mac anche con «Specchia l'immagine inviata»
- [ ] F9 · Dal Mac: «Nome», «Ruolo (facoltativo)», «Mostra la scritta»: la scritta compare nel video dopo meno di un secondo
- [ ] F10 · Tutti gli effetti accesi insieme per 5 minuti: video fluido, latenza simile a prima, l'iPhone tiepido (annota)

## G · L'assistente: le 8 idee nuove

Sull'iPhone: il pulsante «Inquadratura automatica» (a un tocco) e il pulsante «Assistente» nella barra di «In onda»; gli stessi interruttori sono anche nelle Impostazioni, sezione «Assistente».

- [ ] G1 · ★ **Inquadratura automatica**: spostati a destra e a sinistra; lo zoom (fino a 1,6×) ti segue piano e ti tiene al centro, senza tremolii; uscendo dall'inquadratura torna lentamente intera. Dal Mac, «Inquadratura automatica» nella sezione Effetti fa lo stesso
- [ ] G2 · Con due persone nell'inquadratura tiene dentro tutti e due
- [ ] G3 · ★ **Prova la webcam** (foglio «Assistente») › «Inizia la prova»: dopo 5 s un elenco con ✓ e ⚠ (luce, volto al centro, distanza, iPhone dritto)
- [ ] G4 · ★ Rifai la prova al buio o in controluce: compare ⚠; «Sistema» accende la luce sul volto e alza l'esposizione; «Prova di nuovo» dà più ✓
- [ ] G5 · **Gobbo dal Mac**: sezione Effetti › «Gobbo», incolla un testo, «Avvia» (⌘↩): il testo scorre sull'iPhone in alto vicino all'obiettivo e **non** è nel video del Mac
- [ ] G6 · Gobbo: velocità e dimensione (Piccola, Media, Grande) cambiano subito; «Pausa» e «Dall'inizio» funzionano; la «Posizione» sul Mac segue; sull'iPhone un tocco mette in pausa e «×» chiude
- [ ] G7 · ★ **Faccia in giù = pausa**: appoggia l'iPhone con lo schermo in giù: dopo un secondo vibrazione, «In pausa: iPhone a faccia in giù» e sul Mac «In pausa» calmo (non rosso); giralo: il video riparte subito, senza riconnettersi
- [ ] G8 · **Luce sul volto** accesa con una finestra luminosa alle spalle: il volto si schiarisce invece di restare scuro; con ISO e tempo manuali non cambia nulla
- [ ] G9 · **Volto e scrivania** (iPhone sul supporto con la fotocamera posteriore verso di te): l'obiettivo passa al Grandangolo 0,5×, nel video volto e scrivania raddrizzata; prova «Affiancate» e «Scrivania e riquadro»; spegnendo torna l'obiettivo di prima (sul Mac: «Volto + scrivania»)
- [ ] G10 · ★ **Pausa intelligente**: riduci a icona la finestra del Mac (e chiudi la finestra mini): dopo circa 10 s l'iPhone dice «In pausa: nessuna app usa la webcam» e la fotocamera si spegne (niente pallino verde); riapri la finestra: il video torna in un attimo, senza riconnettersi
- [ ] G11 · **Postura**: «Promemoria della postura» acceso, avvicinati molto allo schermo per più di 10 s: avviso discreto sull'iPhone con una vibrazione leggera, sparisce da solo; sul Mac non si vede; non si ripete prima di 3 minuti

## H · Controlli manuali sul telefono e 60 fps

- [ ] H1 · ★ iPhone, pulsante «Controlli Pro»: ISO, tempo di posa, bianco in kelvin, esposizione e «Messa a fuoco manuale» cambiano l'immagine; la riga «Adesso: ISO …» segue
- [ ] H2 · Il Mac vede gli stessi valori nei suoi comandi; «Tutto automatico» rimette tutto in automatico; con «AE/AF bloccati» compare «Sblocca»
- [ ] H3 · iPhone, Impostazioni › Profili › «Dirette» (1080p a 60): il Mac mostra «1080p60», video fluido (annota la latenza)

## I · Foto, registrazione e finestra mini sul Mac

- [ ] I1 · ★ ⌘T foto con lampo bianco, salvata in Immagini › WebcamLR; ⇧⌘T timer 3-2-1; ⌘C e incolla in Note: c'è il fotogramma
- [ ] I2 · Con un filtro e la scritta accesi, la foto li contiene
- [ ] I3 · ★ ⌘R registra: «Ferma · 00:12 · 8,4 MB»; ⌘R di nuovo salva in Filmati › WebcamLR e il file si apre
- [ ] I4 · ⇧⌘M finestra mini sopra le altre app; ⇧⌘P vista pulita, Esc torna; ⌥⌘F riempi/adatta

## L · Microfono del telefono (serve il passo 4 della sezione 0)

- [ ] L1 · Senza installazione: la riga «Microfono del telefono» in Uscite dice «non installato»; dopo `Installa microfono.command`, entro 2 s «spento» e in Impostazioni di Sistema › Suono › Ingresso c'è «WebcamLR (microfono)»
- [ ] L2 · Accendi l'interruttore sul Mac o il pulsante «Microfono al computer» sull'iPhone: la prima volta iOS chiede il microfono; sull'iPhone compare «Microfono al computer» in ciano, sul Mac «attivo» e la barra del livello si muove quando parli
- [ ] L3 · ★ QuickTime › Nuova registrazione audio con «WebcamLR (microfono)»: 20 s parlando senza clic né buchi; sul Mac lo stato diventa «in uso»
- [ ] L4 · Spegni l'interruttore: il microfono resta nell'elenco ma tace, senza clic; scollega e ricollega il telefono con l'interruttore acceso: l'audio riparte da solo
- [ ] L5 · In pausa (faccia in giù) l'audio si ferma e riparte con il video
- [ ] L6 · Alla fine, se vuoi: `Rimuovi microfono.command` → il dispositivo sparisce e la riga torna «non installato»

## M · Due telefoni insieme (serve un secondo telefono con WebcamLR)

- [ ] M1 · ★ Con il primo iPhone in onda, collega il secondo: il primo **non** cade; a sinistra, sotto «Telefoni», tutti e due con «Nella webcam» (ciano) e «Scollega»
- [ ] M2 · In alto a destra del video la miniatura dell'altro telefono; un clic lo porta nella webcam subito; il pannello Fotocamera dice di quale telefono sono i comandi
- [ ] M3 · Foto, registrazione, effetti, microfono e finestra mini seguono il telefono «Nella webcam»
- [ ] M3b · Durante una registrazione scegli l'altro telefono: la registrazione si ferma, compare «Hai cambiato telefono: registrazione fermata e salvata in Filmati › WebcamLR» e il file c'è; ⌘R ne fa partire una nuova sul telefono scelto
- [ ] M4 · Un terzo telefono: il Mac avvisa «Già collegati due telefoni…» e i primi due restano

## N · Inglese

Come cambiare lingua senza cambiare quella di tutto il telefono o del Mac:
- **iPhone**: Impostazioni › WebcamLR › Lingua › English (per tornare: Italiano)
- **Mac**: Impostazioni di Sistema › Generali › Lingua e zona › Applicazioni › **+** › WebcamLR › English, poi chiudi (⌘Q) e riapri WebcamLR

- [ ] N1 · In italiano: nessun testo in inglese, nessuna parola tecnica strana; il rosso solo per «In onda» e la registrazione
- [ ] N2 · ★ iPhone in inglese: benvenuto, lista, «In onda» («Live»), foglio «Effects», «Assistant», «Pro controls», Impostazioni («Settings»), errori e banner tutti in inglese, nessun pezzo in italiano tranne il registro del collegamento
- [ ] N3 · Le richieste dei permessi (fotocamera, rete locale, microfono) sono in inglese
- [ ] N4 · ★ Mac in inglese: finestra, pulsanti in alto («Help»), Effetti, Gobbo («Teleprompter»), Impostazioni e notifiche in inglese; numeri col punto («0.5×»)
- [ ] N5 · Mandami screenshot di ogni testo tagliato, troppo lungo o rimasto in italiano

## O · Batteria, calore, sicurezza

- [ ] O1 · Dopo 30 s senza tocchi lo schermo dell'iPhone si oscura (anche col pulsante «Oscura lo schermo»); il video continua; col gobbo acceso non si oscura
- [ ] O2 · Sotto il 20% senza caricatore: 24 fps e avviso; dopo 30 minuti l'iPhone è tiepido, non caldo
- [ ] O3 · Telefono rimosso dai fidati che si ricollega mentre un altro è in onda: quello in onda non cade
- [ ] O4 · iPhone, pulsante (i): «Segnala un bug» senza nomi di persone o computer nei dati tecnici; Domande frequenti uguali al Mac
- [ ] O5 · Permesso «Rete locale» tolto: nella lista la scheda con «Apri Impostazioni»; riattivandolo sparisce

## P · Più avanti: solo con l'account sviluppatore a pagamento

**Da non fare adesso.** Con l'Apple ID gratuito la webcam virtuale non c'è e la riga in Uscite dice «Richiede l'account sviluppatore Apple a pagamento.»: è giusto così.

- [ ] P0 · Con l'Apple ID gratuito: in Uscite «Webcam virtuale» dice «Richiede l'account sviluppatore Apple a pagamento.» e tutto il resto di questa checklist funziona

Quando avrai l'account (`completo` in `Strumenti/account.txt`, Team ID in `Strumenti/team.txt`), segui `Webcam virtuale Mac.md` (attivazione e 13 prove) e in più:

- [ ] P1 · «Attiva la webcam virtuale» e approvazione: accanto a «Webcam virtuale» compare «attiva»
- [ ] P2 · FaceTime, Zoom, Meet, Teams, WhatsApp, OBS: «WebcamLR» c'è, l'altra persona ti vede; senza telefono l'immagine d'attesa
- [ ] P3 · Un'app usa la webcam: «IN ONDA» rosso su Mac e iPhone, e la pausa intelligente non scatta; chiusa l'app, dopo circa 10 s la pausa
- [ ] P4 · webcamtests.com a 60 fps: il Mac chiede i 60 fps al telefono; con il telefono in 4K, l'app vede 3840×2160
- [ ] P5 · WebcamLR aperto al login senza finestra: le app di chiamata ricevono lo stesso il video
- [ ] P6 · Con il microfono installato: prova del battito di mani (riga 7 della checklist in `Microfono Mac.md`), annota anticipo o ritardo

## Cosa mandarmi alla fine

- I codici delle righe che non vanno, con screenshot
- La latenza in Wi-Fi e col cavo, e il tempo di «Avvio»
- Il «Registro del collegamento» (Copia) dopo un giro Wi-Fi → cavo → Wi-Fi
