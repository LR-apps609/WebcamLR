# Checklist iPhone e Mac · tutto in un giro

Questa checklist **sostituisce** `Checklist 1.0.md`, `Checklist 1.2-1.9.md` e `Checklist 1.10-1.12.md` per iPhone e Mac: dentro c'è tutto quello che è stato costruito finora, fino al pacchetto funzioni P01–P23. Windows e Android restano nei loro file (`Windows/FotocameraVirtuale/LEGGIMI.md`, `Android/LEGGIMI.md`) e per ora sono in pausa.

Come sempre: ogni riga ha un codice (A1, B3…). Se qualcosa non va, mandami il codice con uno screenshot. Le righe con ★ sono le più importanti.

Il codice Swift è stato riletto da più revisori ma **qui non si può compilare**: la prima cosa è la build.

La «Modalità avanzata» non c'è più, né su iPhone né sul Mac: tutto è sempre a vista (millisecondi, grafico, formato, «Avvio», registro del collegamento, ISO/tempo/bianco, profili, regolazioni, «Controlli Pro»).

## Giro veloce (20 minuti)

Se hai poco tempo, fai solo le ★, in quest'ordine:

0 (build) → 03 → Z1 Z2 Z5 Z8 Z10 → X1 X2 X3 X4 X5 X6 → Y1 Y2 Y5 → PR1 PR2 PR4 → A2 A4 A5 → B1 B3 → C2 C3 → D1 D3 D4 D7 → E2 E8 → F1 F3 F5 F7 → G1 G3 G4 G7 G10 → H1 → I1 I3 → L3 → LS1 LS4 → M1 → N2 N4

## 0 · Aggiornare e costruire (10 minuti)

1. Chiudi Xcode. Terminale: `cd ~/Documents/WebcamLR && git fetch && git checkout round-2 && git pull`
2. Doppio clic su `Strumenti/Costruisci e installa.command`; alla domanda sull'account rispondi **N** (Apple ID gratuito)
3. In Xcode scegli il tuo iPhone in alto e premi **▶**
4. Facoltativo, per la sezione L: doppio clic su `Strumenti/Installa microfono.command` (chiede la password del Mac; i suoni del Mac si fermano un attimo)

- [ ] 01 · ★ La build del Mac arriva a «Fatto» e WebcamLR si apre, con il logo nuovo nel Dock
- [ ] 02 · ★ L'app si installa sull'iPhone, con il logo nuovo nella schermata Home
- [ ] 03 · Manifesto della privacy: in Xcode, destinazione **Any iOS Device (arm64)**, **Product › Archive**; nell'Organizer clic destro sull'archivio › **Generate Privacy Report**. Il PDF elenca WebcamLR (e Stile) con «Tracking: No», nessun dato raccolto e le API «UserDefaults: CA92.1» e «System Boot Time: 35F9.1». Mandami il PDF o uno screenshot; un errore sul file `PrivacyInfo.xcprivacy` va mandato così com'è

**Se ci sono errori**: mandami gli **errori rossi** di Xcode così come sono (testo copiato o screenshot) e `Strumenti/ultima-build.log`. Gli avvisi gialli non bloccano: ignorali. Al primo avvio il Mac può chiedere il Portachiavi per «WebcamLR · identità di questo Mac»: «Consenti sempre».

## Presentazione (prima apertura dell'iPhone)

Per rivederla senza reinstallare: in Xcode, Product › Scheme › Edit Scheme… › Run › Arguments, aggiungi `-presentazione` (per il video del sito `-presentazioneAutoplay`, che la fa andare da sola). Togli la spunta quando hai finito.

1. [ ] PR1 · ★ App appena installata: compare la presentazione, con 4 barrette in alto a sinistra e «Salta» in alto a destra; la barretta della pagina si riempie piano
2. [ ] PR2 · ★ Pagina 1: iPhone sul supporto, onde che si muovono, videochiamata sul portatile; la linea si muove da sola una volta col dito, poi trascinandola sul riquadro grande a sinistra si vede «Webcam del computer» (sgranata, scura), a destra «iPhone» (nitido); il puntino «in onda» è corallo, tutto il resto verde e salvia
3. [ ] PR3 · Pagina 2: la freccia scende nel Mac, la barra si riempie e compare il logo, poi lo stesso su Windows; toccando un computer riparte lì. Nessun logo Apple o Microsoft
4. [ ] PR4 · ★ «Mandami il link» apre il foglio di condivisione; mandalo a te stesso (AirDrop o Messaggi): il link apre la pagina dei download di lr-apps609.github.io/WebcamLR
5. [ ] PR5 · Pagina 3: Riunione, Lezione, Diretta e Colloquio cambiano l'anteprima (volto illuminato; inquadratura più larga e ferma, con una sola fotocamera; «60 fps»; sfondo sfocato), con una piccola vibrazione; sotto le due colonne iPhone / computer
6. [ ] PR6 · Pagina 4: toccando Fotocamera, Microfono e Rete locale la scena cambia; «Inizia» chiede fotocamera e poi microfono, poi si apre la lista e iOS chiede la rete locale. Alla seconda apertura la presentazione non c'è più
7. [ ] PR7 · «Salta» da qualsiasi pagina porta alla pagina 4 e sparisce
8. [ ] PR8 · Con `-presentazioneAutoplay` va tutto da solo in circa 33 secondi (il confronto, i download, i profili, i permessi) e si ferma sulla pagina 4 senza toccare «Inizia»
9. [ ] PR9 · Impostazioni › Accessibilità › Movimento › Riduci movimento: le pagine si scambiano in dissolvenza, onde e grana ferme, niente dito
10. [ ] PR10 · Testo più grande (Impostazioni › Schermo e luminosità › Dimensioni testo, e con Accessibilità › Testo più grande al massimo): niente si sovrappone, il testo delle pagine scorre, i pulsanti restano in fondo
11. [ ] PR11 · VoiceOver: ogni scena viene descritta, il confronto si regola scorrendo in su e in giù, i profili e i permessi scelti dicono «selezionato»
12. [ ] PR12 · iPhone in inglese: tutta la presentazione in inglese («Skip», «Send me the link», «Enjoy the experience»…)

## X · Correzioni 1.14 (dai tuoi screenshot del 25 ottobre)

Rifai gli stessi screenshot di prima: iPhone in verticale, frontale, collegato in Wi-Fi.

- [ ] X1 · ★ «In onda» sull'iPhone: in alto **una sola riga** («● Collegato · MacBook Air…»), niente testi tagliati; toccandola si apre «Dettagli» (ms, formato, avvio, batteria, temperatura, registro)
- [ ] X2 · ★ Barra laterale: Specchia · Sfoca sfondo · Microfono · Torcia (solo con la posteriore, con la frontale sparisce) · Pausa · Impostazioni, e «Scollega» in basso. Il pulsante «Effetti video» di Apple non c'è più
- [ ] X3 · ★ **Specchia dall'iPhone**: con un tocco l'immagine si gira subito, senza che il video si fermi, sull'iPhone **e** sul Mac (e in Zoom/Photo Booth); il pulsante del Mac si accende in salvia entro 1–2 s
- [ ] X4 · ★ **Specchia dal Mac** (barra sotto il video): si gira anche sull'iPhone e il pulsante dell'iPhone si accende. La scritta col nome resta leggibile dritta
- [ ] X5 · ★ **Sfoca sfondo** dall'iPhone e dal Mac: lo sfondo si sfoca, i due pulsanti restano allineati
- [ ] X6 · ★ Nessuna **striscia spostata** sul bordo sinistro (né sull'iPhone né sul Mac), anche con l'inquadratura automatica accesa. Mandami dal registro le righe che iniziano con «Fotogrammi…»
- [ ] X7 · Griglia e livella stanno **solo sopra il video**, non sulle bande nere né sulla barra degli obiettivi
- [ ] X8 · I consigli («Con il cavo USB…», «Gira l'iPhone…») compaiono uno alla volta e spariscono da soli dopo qualche secondo
- [ ] X9 · Accendendo e spegnendo un effetto l'anteprima dell'iPhone **non** si capovolge
- [ ] X10 · Con l'inquadratura automatica lo zoom non salta avanti e indietro ogni pochi secondi
- [ ] X11 · Tocco per mettere a fuoco, con la frontale e lo zoom automatico: il fuoco va dove tocchi
- [ ] X12 · Impostazioni dell'iPhone (dai computer e da «In onda», sempre in un foglio con «Fine»): una lista sola, la barra del titolo è piena (il testo non scorre sotto «Impostazioni / Fine»). In ordine: WebcamLR Pro («Sblocca» o «Attivo ✓») · Video (Qualità, Fotogrammi, Formato, Stabilizzazione) · Fotocamera (Griglia, Livella) · Collegamento · Schermo e batteria · Altro. Niente Effetti, Inquadratura automatica, Assistente, Controlli Pro; da «In onda» solo «Sfondo sostituito e logo» e «Messa a fuoco manuale» (esistono solo sul telefono). Scegliendo 4K sparisce 60 fps
- [ ] X13 · Qualità 4K dal Mac o dall'iPhone: sotto compare «2160p30 · HEVC», mai 2160p60
- [ ] X14 · «Avvio» dopo aver toccato il Mac: pochi secondi, non 15
- [ ] X15 · Pizzico sull'iPhone: il cursore Zoom del Mac si allinea; torcia accesa dall'iPhone: si accende anche sul Mac; passando alla frontale sul Mac risulta spenta
- [ ] X16 · Microfono acceso o spento dall'iPhone: l'interruttore del Mac (colonna sinistra, «Uscite») segue
- [ ] X17 · Pausa dall'iPhone: il video si ferma e il Mac dice che è in pausa; ▶ riprende
- [ ] X18 · Sul Mac non c'è più «Specchia l'anteprima» né la sezione «Anteprima» nelle Impostazioni
- [ ] X19 · 10 minuti in 1080p30: se il telefono si scalda compare un solo avviso e la qualità scende a gradini; raffreddato, risale

## Y · Debug completo del 25 ottobre (sera)

- [ ] Y1 · ★ iPhone sul cavo, «Scollega» sul Mac: la diagnosi dice «Cavo USB in pausa» e «Collega via cavo» lo ricollega (prima restava bloccato)
- [ ] Y2 · ★ Registra 10 secondi sul Mac e premi ⌘Q: il .mov in Filmati › WebcamLR si apre e dura quanto la registrazione
- [ ] Y3 · Registra e chiudi l'app sull'iPhone: dopo circa 15 s compare «Telefono non più collegato: registrazione salvata…» e il file si apre. Uguale con «Scollega»
- [ ] Y4 · Registrazione di 2 minuti con un cambio di zoom e una breve riconnessione: il file si apre in QuickTime
- [ ] Y5 · ★ Wi-Fi lento (lontano dal router o con un download grande), 2 minuti: il ritardo sul Mac resta sotto 1 secondo e torna normale quando la rete migliora
- [ ] Y6 · 4K30 con «Sfoca sfondo» e inquadratura automatica per 5 minuti: bordo della persona e zoom reattivi come in 1080p
- [ ] Y7 · Microfono del telefono per 2 minuti: nel registro un solo «formato-audio» all'inizio, voce continua sul Mac senza buchi
- [ ] Y8 · Controlli Pro dal Mac: tempo di posa al minimo e al massimo, poi «auto»: niente crash, l'esposizione torna automatica
- [ ] Y9 · Zoom a 3× sul Mac, poi una riconnessione: il cursore non salta a 1× e indietro
- [ ] Y10 · «In onda» › Impostazioni › Effetti (a metà schermo), poi tocca la riga di stato: Effetti si chiude e si apre «Dettagli»
- [ ] Y11 · Schermo oscurato in orizzontale, doppio tocco vicino alla tacca: lo schermo si riaccende, la fotocamera non cambia
- [ ] Y12 · «Inserisci l'indirizzo» › scrivi «abc» › «Riprova»: l'avviso dell'indirizzo ricompare
- [ ] Y13 · Mac: apri «Collega con QR code» e collega il telefono col QR: il riquadro si chiude e scollegando non ricompare da solo
- [ ] Y14 · «Consenti» (telefono nuovo), «Avvia» del gobbo e «Invia la segnalazione»: testo scuro e leggibile sul verde chiaro

## Z · WebcamLR Pro

WebcamLR è gratis fino a 720p a 30 fps, senza filigrana; **WebcamLR Pro** si compra una volta sull'iPhone e sblocca anche il Mac. Qui l'acquisto è **finto e gratuito**: lo schema di Xcode usa `iPhone/WebcamLR.storekit`, niente App Store Connect né account a pagamento. Il pannello degli acquisti di prova è in Xcode, menu **Debug › StoreKit › Manage Transactions…** (con l'app avviata da ▶).

**Fai questa sezione prima delle sezioni E–M**: senza Pro filtri, sfondo sostituito, ritocco, scritta, inquadratura automatica, volto e scrivania, controlli manuali, 1080p/4K/60 fps, profili, foto, registrazione, gobbo e due telefoni sono bloccati. Dopo Z7 hai Pro e il resto della checklist vale come prima.

Prima, da gratis (iPhone collegato al Mac):
- [ ] Z1 · ★ iPhone, (i) › sezione «WebcamLR Pro» › pagina: confronto «Gratis» e «Pro», pulsante «Sblocca Pro · 14,99 €» (verde chiaro, testo scuro), sotto «Una volta sola, per sempre. Vale per tutta la famiglia.» e «Ripristina acquisti». Niente «Accedi» né «Abbonamento» da nessuna parte
- [ ] Z2 · ★ Gratis = 720p a 30 fps: sul Mac «Qualità video» dice «Arriva ora: 720p · 30»; 1080p, 4K e 60 fps compaiono con «· PRO» e sceglierli non cambia nulla. Sull'iPhone Impostazioni › Video mostra 720p e 30 fps; 1080p, 4K e 60 fps hanno «· PRO» e aprono la pagina WebcamLR Pro
- [ ] Z3 · ★ Restano gratis e funzionano: Specchia, Sfoca sfondo (anche l'intensità), Luce sul volto, microfono del telefono sul Mac, zoom, torcia, esposizione (compensazione), collegamento sicuro. Nessuna scritta o filigrana nel video
- [ ] Z4 · iPhone, segno «PRO» e un tocco apre la pagina Pro invece del comando: Effetti (filtri tranne «Naturale», regolazioni, «Sostituito», ritocco, scritta e logo), Assistente (inquadratura automatica, volto e scrivania), Impostazioni di «In onda» (inquadratura automatica), Controlli Pro (ISO, tempo, bianco, messa a fuoco; la compensazione resta libera)
- [ ] Z5 · ★ Mac con il telefono gratis: Profilo, «Regole fini», gli effetti Pro, Gobbo, Foto e Registra sono grigi con «PRO»; al passaggio del mouse «Sblocca WebcamLR Pro sull'iPhone», al clic la nota «Si sblocca dall'iPhone: apri WebcamLR › App › WebcamLR Pro.». ⌘T e ⌘R mostrano l'avviso invece di fotografare o registrare. Sul Mac non c'è nessun pulsante per comprare
- [ ] Z6 · Mac › Aiuto › scheda «WebcamLR Pro»: «‹nome del telefono› usa la versione gratuita.», la strada per sbloccarlo e lo stesso confronto dell'iPhone; senza telefono «Nessun telefono collegato…»
- [ ] Z7 · Due telefoni con il primo gratis: il secondo non si collega e sul Mac compare «Due telefoni insieme sono di WebcamLR Pro…» (una volta al minuto al massimo)

Acquisto, ripristino e rimborso:
- [ ] Z8 · ★ Tocca «Sblocca Pro · 14,99 €» e conferma nel foglio di Apple (di prova): la pagina dice «Pro attivo» con il grazie. Senza scollegare, entro un paio di secondi sul Mac spariscono i «PRO», la scheda «WebcamLR Pro» dice «Pro attivo su ‹nome›…» e il video torna alla qualità chiesta (1080p30 di partenza), con un solo attimo di nero
- [ ] Z9 · Chiudi l'app dal multitasking e riaprila (sempre con ▶ o dall'icona): Pro c'è ancora, il video parte subito nella qualità piena (nessun passaggio da 720p)
- [ ] Z10 · ★ Con Pro accendi dal Mac un filtro, la scritta e l'inquadratura automatica, e lo sfondo sfocato. Poi in Xcode › Debug › StoreKit › Manage Transactions seleziona l'acquisto › **Refund**: in pochi secondi sull'iPhone la pagina torna a «Sblocca Pro», filtro, scritta e inquadratura si spengono (sul Mac e nel video), lo sfondo sfocato resta, il video torna a 720p30 e i «PRO» ricompaiono sul Mac
- [ ] Z11 · Dopo il rimborso, dal Mac (con il telefono gratis) i comandi Pro non partono; se ne arriva uno vecchio (per esempio al ricollegamento il bianco manuale) il telefono lo ignora e il Mac si riallinea. Nel registro dell'iPhone «Senza WebcamLR Pro: comando Pro ignorato»
- [ ] Z12 · ★ Ripristino: ricompra Pro (Z8), poi elimina l'app dall'iPhone e reinstallala con ▶: Pro torna da solo; «Ripristina acquisti» dice comunque «Pro attivo». Con l'acquisto cancellato in Manage Transactions (Delete) «Ripristina acquisti» dice «Nessun acquisto di WebcamLR Pro per questo Apple ID.»
- [ ] Z13 · «Chiedi di acquistare»: Manage Transactions › Enable Ask to Buy, poi «Sblocca Pro»: compare «Acquisto in attesa di approvazione…»; approvalo in Manage Transactions (Approve): Pro si attiva da solo, senza toccare nulla
- [ ] Z14 · In inglese (sezione N): «Unlock Pro · …», «Restore Purchases», «Pay once, keep it forever…», confronto «Free»/«Pro»; sul Mac «Unlock WebcamLR Pro on the iPhone»

Più avanti, con l'account a pagamento e l'acquisto creato in App Store Connect (`Pubblicazione.md`, «WebcamLR Pro: l'acquisto in-app»):
- [ ] Z15 · TestFlight (sandbox, gratis): acquisto, «Ripristina acquisti» su un secondo iPhone con lo stesso Apple ID, prezzo uguale a App Store Connect (9,99 € durante il lancio)

## A · Primo collegamento in Wi-Fi

- [ ] A1 · iPhone: la presentazione (sezione «Presentazione» qui sotto); «Inizia» chiede fotocamera e microfono, poi la lista chiede la rete locale (Consenti a tutte)
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
- [ ] D7 · ★ Mac senza telefono: sotto il riquadro «Collega il telefono» e i pulsanti c'è «Compatibile con» con Zoom, Google Meet, Microsoft Teams, FaceTime, WhatsApp, OBS, Discord, Webex, Slack e «Tutti i siti con la webcam» (riquadri grigi con un simbolo o l'iniziale, niente loghi) e sotto «Con la webcam virtuale (richiede l'account sviluppatore Apple).»; a 960×600 i riquadri vanno a capo e la sezione scorre; collegando il telefono sparisce (screenshot a 960×600 e a finestra grande)

## E · Fotocamera dal Mac e dall'iPhone

- [ ] E1 · Obiettivi (0,5× · 1× · Tele · Frontale) dall'iPhone e dal Mac (anche tasti 1–4): il video segue entro un paio di secondi
- [ ] E2 · ★ Dal Mac: zoom fluido (anche + e −), esposizione, bianco, torcia, «Messa a fuoco automatica» (tasto F): l'immagine cambia subito
- [ ] E3 · iPhone: doppio tocco sull'anteprima frontale ↔ posteriore; tocco lungo «AE/AF bloccati», un tocco sblocca
- [ ] E4 · Sul Mac: «Esposizione manuale (ISO e tempo)» cambia l'immagine; «Profili» › salva, cambia, riapplica: torna tutto come salvato
- [ ] E4b · Sul Mac, profilo «Lezione» («Una fotocamera, inquadratura ferma»): resta un solo obiettivo; se «Volto e scrivania» era accesa si spegne e l'obiettivo torna com'era. Lo stesso su Windows
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

- [ ] L1 · Senza installazione: la riga «Microfono del telefono» in Uscite dice «non installato»; dopo `Installa microfono.command`, entro 2 s «spento» e in Impostazioni di Sistema › Suono › Ingresso c'è «WebcamLR (microphone)»
- [ ] L2 · Accendi l'interruttore sul Mac o il pulsante «Microfono al computer» sull'iPhone: la prima volta iOS chiede il microfono; sull'iPhone compare «Microfono al computer» in ciano, sul Mac «attivo» e la barra del livello si muove quando parli
- [ ] L3 · ★ QuickTime › Nuova registrazione audio con «WebcamLR (microphone)»: 20 s parlando senza clic né buchi; sul Mac lo stato diventa «in uso»
- [ ] L4 · Spegni l'interruttore: il microfono resta nell'elenco ma tace, senza clic; scollega e ricollega il telefono con l'interruttore acceso: l'audio riparte da solo
- [ ] L5 · In pausa (faccia in giù) l'audio si ferma e riparte con il video
- [ ] L6 · Alla fine, se vuoi: `Rimuovi microfono.command` → il dispositivo sparisce e la riga torna «non installato»

## L2 · Microfono: sicurezza e rimozione

Prima rifai `Strumenti/Installa microfono.command` (l'aiutante nuovo controlla chi chiede la memoria). Il registro dell'aiutante si legge nel Terminale con:
`log show --last 10m --predicate 'subsystem == "it.lrapps.webcamlr.microfono"' --info`

- [ ] LS1 · ★ Dopo l'installazione L3 funziona come prima (QuickTime registra la voce). Nel registro c'è «Team ID dell'aiutante: …» e **nessuna** riga «Rifiutato». Se c'è «Rifiutato … firma «com.apple.audio…»», mandamela: è il processo di Core Audio da aggiungere
- [ ] LS2 · Impostazioni del Mac (⌘,) › **Microfono del telefono**: «Microfono installato · versione 1.0 (…)» con la versione e la build di adesso
- [ ] LS3 · Prova del rifiuto: un programma qualsiasi chiede la memoria. Nel Terminale incolla queste due righe:
  `printf '%s\n' 'import XPC' 'let c = xpc_connection_create_mach_service("it.lrapps.webcamlr.microfono", nil, 0)' 'xpc_connection_set_event_handler(c) { _ in }' 'xpc_connection_resume(c)' 'let m = xpc_dictionary_create(nil, nil, 0)' 'xpc_dictionary_set_string(m, "richiesta", "memoria")' 'print(xpc_connection_send_message_with_reply_sync(c, m))' > /tmp/prova-microfono.swift`
  `swift /tmp/prova-microfono.swift`
  Deve stampare un errore («Connection interrupted» o «invalid»), **non** un dizionario con «memoria»; nel registro compare «Rifiutato … swift…»
- [ ] LS4 · ★ «Rimuovi il microfono…» › conferma «Rimuovi»: per un attimo i suoni del Mac si fermano, poi «Microfono rimosso…»; entro 2 s la sezione dice «Microfono non installato» e in Impostazioni di Sistema › Suono › Ingresso «WebcamLR (microphone)» non c'è più. Nel Terminale `ls /Library/LaunchDaemons | grep webcamlr` e `ls "/Library/Application Support/WebcamLR"` non trovano niente
- [ ] LS5 · «Installa…»: si apre il pannello; scegli `Strumenti/Installa microfono.command` → si apre il Terminale con lo script (password del Mac) e alla fine la sezione torna «Microfono installato · versione …»
- [ ] LS6 · Solo se hai ancora un microfono installato con lo script di prima (senza il secondo LaunchDaemon): «Rimuovi il microfono…» dice che serve «Rimuovi microfono.command» e mostra il pulsante per aprirlo

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
- [ ] N2 · ★ iPhone in inglese: presentazione, lista, «In onda» («Live»), foglio «Effects», «Assistant», «Pro controls», Impostazioni («Settings»), errori e banner tutti in inglese, nessun pezzo in italiano tranne il registro del collegamento
- [ ] N3 · Le richieste dei permessi (fotocamera, rete locale, microfono) sono in inglese
- [ ] N4 · ★ Mac in inglese: finestra, pulsanti in alto («Help»), «Works with» senza telefono, Effetti, Gobbo («Teleprompter»), Impostazioni e notifiche in inglese; numeri col punto («0.5×»)
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
- [ ] P4 · webcamtests.com a 60 fps: il Mac chiede i 60 fps al telefono; con il telefono in 4K, l'app vede 3840×2160; sotto «Compatibile con» la riga dice «Scegli «WebcamLR» come videocamera nell'app.»
- [ ] P5 · WebcamLR aperto al login senza finestra: le app di chiamata ricevono lo stesso il video
- [ ] P6 · Con il microfono installato: prova del battito di mani (riga 7 della checklist in `Microfono Mac.md`), annota anticipo o ritardo

## Cosa mandarmi alla fine

- I codici delle righe che non vanno, con screenshot
- La latenza in Wi-Fi e col cavo, e il tempo di «Avvio»
- Il «Registro del collegamento» (Copia) dopo un giro Wi-Fi → cavo → Wi-Fi
