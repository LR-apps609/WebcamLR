# Passata sulle prestazioni (2 novembre)

Le 30 regole di velocità applicate a WebcamLR **solo dove hanno senso**. Qui velocità vuol dire latenza, fluidità del
video, tempo di collegamento, processore e GPU del computer, batteria e calore del telefono.

- **Ramo:** `prestazioni`, che parte da `beta4` (6f98b28): la beta 4 ha già rifatto le interfacce, quindi lavorare su
  `round-2` avrebbe creato conflitti all'unione. Si unisce in `round-2` insieme alla beta 4, dopo le prove.
- **Sito:** su `main` (d47020e), già online.
- **Swift e app Android qui non si compilano.** Lo Swift è stato rivisto «come un compilatore» (trovato e corretto un
  errore); il Kotlin passa il banco `compileKotlin` (solo tipi, con stub, non l'SDK Android). Il C# di Windows: vedi
  sotto.
- **Protocollo invariato.** Nessuna modifica a `Protocollo.md`: tutte le modifiche sono interne alle app.
- **Nessun monitoraggio esterno:** le misure restano nel Registro del collegamento e nella Diagnosi.

## 1. Le 30 voci

Legenda: ✅ fatto in questa passata · ☑️ era già a posto · ⏸ serve il tuo ok · ➖ non si applica.
Sforzo S/M/L, rischio B/M/A (basso, medio, alto).

| # | Regola | Si applica? Dove | Stato prima | Cosa cambia | Guadagno | Sforzo | Rischio |
|---|---|---|---|---|---|---|---|
| R01 | Misurare prima e dopo | Tutte | ☑️ iPhone (`MisuraAvvio`, righe «Prestazioni»), Windows (avvio, ritardi ogni 30 s, motore); Mac senza tempo di avvio | ✅ Mac: «Visibile in rete…, N ms dall'avvio dell'app» | misura | S | B |
| R02 | Lavori in parallelo all'avvio | Tutte | ☑️ in gran parte: Bonjour, cavo, QR, fotocamera già in parallelo; StoreKit iPhone in serie | ✅ iPhone: diritti e prodotto Pro in parallelo. ⏸ Mac: Portachiavi fuori dal thread principale (prima misurare con R01) | avvio | S | B |
| R03 | Timeout chiari | Tutte | ☑️ collegamento 8 s, stretta di mano 5–10 s, conferma 60–65 s, aggiornamenti 15 s, cavo 5 s; ❌ StoreKit iPhone senza timeout (rotellina infinita offline); ❌ risoluzione mDNS Android senza timeout | ✅ StoreKit 10 s → «Riprova»; ✅ Android: risoluzione mDNS 5 s e coda senza doppioni | affidabilità | S | B |
| R04 | Retry con backoff | Tutte | ☑️ ovunque (0,5/2 s; 5→60 s; 2→30 s; Billing 1→60 s) | — | — | — | — |
| R05 | Niente doppioni | Tutte | ❌ Android: tentativi di riconnessione che si sommano; ❌ Mac: doppia riapertura dell'ascolto dopo il risveglio; ❌ Windows: gestore `Closed` mai tolto | ✅ tutti e tre | rete, batteria | S | B |
| R06 | Debounce/throttle | Tutte | ☑️ effetti 100–250 ms; ❌ Android: ogni movimento del dito ricomponeva la schermata; ❌ Mac: cursori della fotocamera un comando per passo | ✅ Android 250 ms. ⏸ Mac: cursori della fotocamera a 80 ms (cambia la sensazione dello zoom) | fluidità | S | B/M |
| R07 | Cache in memoria | Mac, iPhone | ☑️ QR, CIContext, richieste Vision in cache | ⏸ Mac: miniatura della tua immagine ridotta a 320 px | memoria | S | B |
| R08 | Meno ridisegni (stati a 1–60 Hz isolati) | Tutte e 4 | ❌ iPhone: «In onda» intera ogni secondo (latenza) e a ogni evento del pizzico; ❌ Android: idem; ❌ Mac: finestra intera ogni secondo (statistiche, registrazione), riga microfono a 10 Hz, «Segnala un bug» ogni secondo; ❌ Windows: `AggiornaDisponibilita` ogni secondo | ✅ tutti (vedi §3) | fluidità, batteria | S–M | B |
| R09 | Liste virtualizzate | Tutte | ☑️ iPhone `List`, Mac `LazyVStack`/`LazyVGrid`, Windows 50 righe in un testo; Android: registro fino a 200 `Text` | ⏸ Android: registro come un solo testo (cambia di poco la spaziatura) | memoria | S | B |
| R10 | Immagini quando servono | Tutte | ☑️ miniature 320×180, `DecodePixelWidth`, immagini aperte in sottofondo | ⏸ Mac: miniatura personale (R07) | memoria | S | B |
| R11 | Optimistic UI (Specchia, Sfoca, Microfono) | Tutte | ☑️ Mac, Windows, Android, iPhone cambiano subito; ❌ iPhone come **telecomando** degli effetti del computer aspetta il giro completo; nessun segno «in attesa del telefono» | ⏸ stato «in attesa» e ritorno indietro dopo 1,5 s (comportamento visibile: bozza prima) | percezione | S–M | B |
| R12 | Lavori lenti fuori dal thread principale | Tutte | ☑️ chiusura registrazioni, modelli Vision/ONNX, sfondi; ❌ Mac e Windows: spazio libero e dimensione del file letti sul thread principale | ✅ Mac e Windows. ⏸ Mac: ⌘C in PNG fuori dal thread principale | scatti | S | B |
| R13 | Caricamento differito | Android, Windows | ❌ Android: modello a più classi (16 MB, GPU) caricato a ogni sessione anche senza effetti; ❌ Windows: diagnosi rete/firewall ogni 10 s anche nel vassoio | ✅ Windows: diagnosi solo a finestra visibile. ⏸ Android: modello alla prima maschera | avvio, batteria | S–M | B/M |
| R14 | Dipendenze | Android | ❌ MediaPipe manda statistiche a Google (dichiarato nella privacy) | ⏸ decisione: LiteRT con gli stessi modelli (2–4 giorni) o escludere DataTransport (rischio) | privacy, peso | M–L | M |
| R15 | Codice morto | Tutte | `FoglioEffetti`/`Assistente`/`ControlliPro` (Android) e `VistaProvaWebcam`/`IndicatoreCollegamento` (iPhone) erano **già tolti** nella beta 4; restavano altri resti | ✅ iPhone 2, Mac 1, Android 7 definizioni tolte | manutenzione | S | B |
| R16 | Dimensione del pacchetto | Android, sito | ☑️ R8 e shrinkResources in release; caratteri del sito | ✅ sito (sotto). ⏸ Android `abiFilters` per l'APK fuori da Play (perde i Chromebook x86) | download | S | B |
| R17 | Animazioni ferme quando non servono | Tutte | ❌ iPhone: livella attiva a schermo oscurato; ❌ Android: radar creato anche con «Rimuovi animazioni»; ❌ sito: 4 animazioni infinite fuori dallo schermo | ✅ tutti e tre. ⏸ iPhone: Gobbo a 60 Hz invece di 120 | batteria, GPU | S | B |
| R18 | Lavoro ripetuto per fotogramma | Tutte | ❌ Windows: anteprima elaborata copiata (~8 MB a 1080p) anche a finestra nascosta; ❌ Android: un array da 256 KB nuovo per maschera; ❌ Windows: nonce allocato per pacchetto | ✅ tutti e tre. Solo segnalate, non toccate: 4–5 copie per fotogramma nel codificatore iPhone, doppia copia AVCC sul Mac | processore, GC | S | B |
| R19 | Riuso delle connessioni | Tutte | ☑️ una connessione per sessione, `HttpClient` statico | — | — | — | — |
| R20 | Prove su dispositivi lenti e reti deboli | Tutte | non ancora fatte | checklist §5. ⏸ Windows: ripiego del modello leggero sul processore se DirectML è lento | PC deboli | M | M |
| R21 | Sito: caratteri | Sito | 178 KB (WOFF2 dalla RC) | ✅ 139 KB: Barlow ritagliato; IBM Plex Mono dai sottoinsiemi ufficiali IBM | download | S | B |
| R22 | Sito: immagini | Sito | `anteprima.png` serve solo come anteprima per i social (`og:image`), le pagine non la scaricano | ➖ niente WebP: non tutti i social la leggono | — | — | — |
| R23 | Sito: nomi con impronta | Sito | GitHub Pages manda `max-age=600` a tutto e non si può cambiare | ➖ l'impronta non allungherebbe la cache; dopo una pubblicazione i file vecchi durano al massimo 10 minuti | — | — | — |
| R24 | Compressione | Sito, video | ☑️ gzip di GitHub Pages; video con codec hardware | — | — | — | — |
| R25 | CDN | — | ➖ c'è GitHub Pages | — | — | — | — |
| R26 | Cache distribuita / Redis | — | ➖ nessun server | — | — | — | — |
| R27 | Database (indici, N+1, pooling) | — | ➖ nessun database | — | — | — | — |
| R28 | Paginazione delle API | — | ➖ nessuna API | — | — | — | — |
| R29 | SSR / load balancing | — | ➖ sito statico | — | — | — | — |
| R30 | Streaming di risposte AI | — | ➖ | — | — | — | — |

## 2. Misure

**Sito (misurato qui):** Playwright, Chromium, telefono 390 px, rete «3G veloce» (150 ms, 1,6 Mbit/s), media di 3 giri.

| Home | Prima | Dopo |
|---|---|---|
| Byte scaricati | 294 KB (13 file) | 257 KB (14 file) |
| Caratteri | 178 KB | 139 KB (Plex «Pi» solo dove servono frecce e ✓) |
| Pagina caricata | ~2,0 s | ~1,8 s |
| Animazioni in corso a fondo pagina | 4 | 0 |
| Screenshot 1280 e 390 px, 5 pagine | — | uguali (al massimo 7 pixel di antialiasing) |

**App (da misurare sui dispositivi):** qui non ci sono telefoni né GPU, quindi i numeri prima/dopo li prendi tu con la
checklist §5. Dove guardare:

| Misura | iPhone | Android | Mac | Windows |
|---|---|---|---|---|
| Latenza (oggi ~51 ms in Wi-Fi) | Dettagli · registro «Prestazioni» | Dettagli · registro | grafico della latenza | grafico della latenza |
| Fotogrammi persi | registro «Prestazioni» | registro | Diagnosi | registro ogni 30 s |
| Tempo di collegamento | registro (`MisuraAvvio`) | registro | **nuovo:** «…ms dall'avvio dell'app» | registro (avvio) |
| Processore/GPU | Xcode › Debug Navigator | Android Studio › Profiler | Monitoraggio Attività | Gestione attività (GPU 3D) |
| Ridisegni | Instruments › SwiftUI (View Body) | Layout Inspector (ricomposizioni) | Instruments › SwiftUI | — |
| Batteria/temperatura dopo 30 min | Impostazioni › Batteria; riga in onda | registro (batteria/temperatura) | — | — |

## 3. Modifiche fatte

**iPhone** (5 commit)
- R08: la schermata «In onda» segue `qualitaCollegamento` (cambia solo quando cambia la categoria) invece della
  latenza di ogni secondo; i ms restano nei Dettagli e nello schermo oscurato.
- R08: l'etichetta dello zoom è una vista a parte: durante il pizzico si ridisegna solo lei.
- R17: livella (CoreMotion a 10 Hz) ferma a schermo oscurato, riparte al tocco.
- R02/R03: Pro, diritti e prodotto in parallelo; prodotto con 10 s al massimo, poi «Riprova».
- R15: tolti `GestorePausa.trattieni` e `PipelineEffetti.rimuovi`.

**Mac** (9 commit)
- R08: la finestra non si ridisegna più ogni secondo (statistiche → `videoConMisura`, pulsante Registra in una vista
  sua, «Segnala un bug» in una vista sua); il misuratore del microfono ridisegna solo le sue 12 tacche e solo quando
  cambiano, senza animazione con «Riduci movimento».
- R05: dopo il risveglio l'ascolto si riapre una volta sola.
- R12: dimensione del file e spazio libero letti fuori dal thread principale.
- R01: tempo dall'avvio a «Visibile in rete» nel registro (IT/EN).
- R15: tolto `DisposizioneACapo`.

**Android** (7 commit; banco `compileKotlin` verde, test del protocollo verdi)
- R08: «rete debole» con `derivedStateOf`: la schermata non si ricompone a ogni latenza.
- R08/R06: `ultimoTocco` al massimo ogni 250 ms durante pizzico e trascinamento.
- R05: un solo tentativo di riconnessione in attesa.
- R18: due array alternati per la maschera (niente 256 KB nuovi a ogni maschera).
- R17: radar senza transizione infinita con «Rimuovi animazioni».
- R03: risoluzione mDNS con 5 s al massimo, coda senza doppioni, risposte tardive ignorate.
- R15: tolte 7 definizioni non usate.

**Windows** (7 commit; il C# dell'App compila nel banco XAML; dotnet test: Protocollo 44, Ricevitore 500 con 5 test
nuovi, Effetti 49, Webcam.Logica 148, Setup.Logica 76)
- R18: con gli effetti accesi e la finestra nel vassoio non si copia più l'anteprima elaborata (~8 MB per fotogramma a
  1080p sul thread dell'interfaccia); alla riapertura l'ultima immagine compare subito. Il motore continua a lavorare
  per la webcam e la registrazione (fermarlo: decisione 4 bis).
- R08: le statistiche di ogni secondo rinfrescano solo i numeri (chip, menu qualità, icona del vassoio, dettagli);
  il giro completo solo alla prima misura del video. Il tick della registrazione aggiorna solo durata e spazio.
- R12: spazio libero letto fuori dal thread dell'interfaccia.
- R18: nonce di AES-GCM sullo stack (stessi byte: protocollo invariato).
- R13: diagnosi di rete e firewall ogni 10 s solo a finestra visibile, rifatta quando la finestra ricompare.
- R05: il gestore `Closed` dei dialoghi si toglie.
- Da sapere: a finestra nascosta con effetti accesi e nessuna app sulla webcam, la latenza mandata al telefono usa il
  ripiego già previsto da `Protocollo.md` (ritardo del lettore), perché l'anteprima elaborata non si misura più.

**Sito** (`main` d47020e, online)
- Caratteri ridotti a quelli usati; onde e punto «in onda» in pausa fuori dallo schermo.

## 3 ter. Revisioni e correzioni

Due revisioni indipendenti, in sola lettura:
- **Swift (iPhone e Mac), «come un compilatore»:** un errore che bloccava la compilazione del Mac (`p_starttime` è una
  macro C che Swift non importa → `p_un.__p_starttime`) e una regressione di VoiceOver sulla batteria del Mac (tolto
  per sbaglio `.accessibilityElement(children: .ignore)`). Corretti in bd85fa2.
- **Comportamento (Windows e Android):** su Android una risposta mDNS arrivata dopo i 5 s veniva scartata e quel
  computer non compariva più (corretto in 9109144, con attesa 0,3 → 1 → 3 s per FAILURE_ALREADY_ACTIVE); su Windows due
  controlli dello spazio potevano accavallarsi su un disco di rete lento (corretto in 92caca1).
- Restano da sapere: sul Mac il valore del microfono letto da VoiceOver va a passi di una tacca (circa 8%); dopo
  l'oscuramento la livella dell'iPhone compare circa 100 ms dopo il video.

## 3 quater. Skill di grafica

Le skill che hai chiesto (frontend-design, design-critique, design-system, accessibility-review, ux-copy) le ho
caricate dopo che le modifiche alle app erano già fatte. Questa passata **non cambia l'aspetto** di nessuna app, quindi
non ci sono bozze nuove. Cosa hanno cambiato comunque:
- **accessibility-review:** controllo di VoiceOver e di «Riduci movimento» sulle viste spostate. La regressione della
  batteria del Mac rientra qui; il misuratore del microfono ora rispetta «Riduci movimento» (WCAG 2.3.3).
- **frontend-design (sito):** «Riduci movimento» rispettato, focus visibile, nessun colore nuovo; animazioni infinite
  ferme fuori dallo schermo. I tratti che la skill chiama «predefiniti» (numeri in carattere a spaziatura fissa,
  «A · B · C», «→» nei link) **restano**, perché sono della direzione A che hai scelto: li propongo in una critica a
  parte.
- **design-system:** nessun token toccato; `genera_token.py --controlla` verde.
- **design-critique e ux-copy:** si applicano dalle bozze delle decisioni 2 (telecomando con «in attesa del telefono»)
  e 6 (registro Android). Nessun testo nuovo visibile, a parte la riga del registro del Mac.

## 4. Decisioni da confermare

1. **MediaPipe su Android** (R14): sostituirlo con LiteRT e gli stessi modelli (2–4 giorni più prove, niente statistiche a
   Google) o tenerlo dichiarato com'è.
2. **Telecomando degli effetti dall'iPhone** (R11): pulsante che cambia subito con un segno «in attesa del telefono» e
   torna indietro dopo 1,5 s se il computer non conferma. Prima la bozza grafica.
3. **Modello a più classi su Android** (R13): caricarlo alla prima maschera invece che a ogni sessione (16 MB e GPU in
   meno quando lo sfondo è spento; la prima maschera arriva una volta in ritardo).
4 bis. **Windows nel vassoio** (R18): fermare anche il motore degli effetti quando la finestra è nascosta e nessuna app
   usa la webcam (più risparmio; alla riapertura per un istante si vede l'ultima immagine).
4. **Windows su PC senza GPU dedicata** (R20): se anche il modello leggero su DirectML è lento, passare al processore
   con metà dei core.
5. **Cursori della fotocamera dal Mac** (R06): un comando ogni 80 ms invece di uno per passo.
6. **Piccole:** Gobbo a 60 Hz (iPhone), registro Android come un solo testo, `abiFilters` per l'APK fuori da Play,
   ⌘C in PNG sul Mac, Portachiavi del Mac fuori dal thread principale (dopo la misura R01).

## 4 ter. Qualità a scelta (Qualità 15)

**Auto, Alta, Massima** per il flusso dal telefono al computer, oltre alla qualità che segue la rete (Auto, quella di
prima). Ramo `qualita-scelta`. Valori e regole in `Protocollo.md`, «Qualità a scelta»; in breve: Alta bitrate × 1,5,
Massima × 2 con risoluzione e fps più alti dell'obiettivo, tetto 80 Mbit/s; con la rete che non regge Alta e Massima si
fermano al bitrate di Auto e scendono sotto solo dopo 3 secondi di fila.

- **Dove:** sul computer, nel menu dell'etichetta della qualità sopra il video (Mac e Windows), sezione «Qualità del
  flusso» sotto le risoluzioni. Il telefono la mostra soltanto (Impostazioni › Video › Qualità, «… · Alta»).
- **Nuovi campi, facoltativi:** `capacita.sceltaQualita`, `comando.qualita`, `stato.qualita`. Con un telefono vecchio
  la sezione non compare; un computer vecchio non la manda e il telefono resta in Auto.
- **Pro:** la scelta è gratis. Con un telefono gratis Massima resta a 720p 30 (il limite di sempre), con più bitrate.
- **Non compilati qui:** Swift (iPhone, Mac), l'app Android, l'app WinUI. Provati: i tre protocolli
  (`QualitaComeNelDocumento`), `AdattamentoRete` e `NumeriQualita` in Kotlin, `SceltaFormato` e `BitrateVideo` con un
  banco Kotlin a parte, `QualitaScelta` in `WebcamLR.Ricevitore.Test`.

**Checklist sui dispositivi veri** (annota la riga «Codifica … Mbit/s» del registro del telefono e i Numeri del computer):
- [ ] Q1 · iPhone con Pro → Mac, Wi-Fi, 1080p 30: il menu della qualità ha «Qualità del flusso» con Auto spuntato. Scegli
      Alta: nessuna pausa nel video, il registro del telefono dice «Qualità scelta sul computer: Alta» e i Numeri del Mac
      salgono verso ~24 Mbit/s; la spunta passa su Alta.
- [ ] Q2 · Scegli Massima: il video si ferma un attimo e riparte in 4K 30 HEVC (posteriore) o al massimo della frontale;
      etichetta «… · 4K 30 · HEVC». Le Impostazioni dell'iPhone dicono «4K · 30 fps · HEVC · Massima».
- [ ] Q3 · In Massima cambia obiettivo (frontale ↔ posteriore): ogni volta la risoluzione più alta di quell'obiettivo.
- [ ] Q4 · In Massima scegli «1080p · 30 fps» nel menu: arriva 1080p 30 e la spunta passa da sola su Alta.
- [ ] Q5 · Chiudi e riapri l'app del telefono (o scollega e ricollega): la scelta torna da sola, senza toccare nulla.
- [ ] Q6 · Alta in Wi-Fi lontano dal router o con un download pesante: per qualche secondo il bitrate si ferma a quello di
      Auto (~16 Mbit/s a 1080p 30); se la rete non regge ancora scende sotto, il video resta fluido; tornando vicino risale.
- [ ] Q7 · Telefono gratis: Alta e Massima si scelgono (niente «PRO»); Massima resta a 720p 30.
- [ ] Q8 · (PC) Gli stessi Q1, Q2, Q4 e Q5 con Windows; con un PC senza l'estensione HEVC, Massima in 4K mostra la
      barra «Ricollega in H.264» come il 4K scelto a mano.
- [ ] Q9 · Android → Mac o PC: Q1, Q2, Q6; nelle Impostazioni del telefono «Qualità video … · Massima».
- [ ] Q10 · Telefono vecchio (versione di prima) con il computer nuovo: la sezione non compare, tutto come prima.
- [ ] Q11 · Mentre registri sul computer, Massima chiede prima di fermare la registrazione; Alta no.

## 5. Checklist per le prove sui dispositivi

Da fare **prima** su `beta4` e **poi** su `prestazioni`, annotando i numeri.

**Rete e collegamento (tutte le app)**
- [ ] Tempo di collegamento: apri l'app sul computer, poi sul telefono; annota i ms nel registro (Mac: nuova riga «…ms
      dall'avvio dell'app»). Tre volte, prima e dopo.
- [ ] 10 minuti in onda in Wi-Fi a 5 GHz: latenza media e fotogrammi persi (Dettagli / grafico / registro).
- [ ] Stessa prova con Wi-Fi a 2,4 GHz affollato (Mac: Network Link Conditioner «Wi-Fi» o «Lossy»): l'avviso «rete
      debole» compare e sparisce come prima, tacche e chip giusti.
- [ ] Spegni e riaccendi il Wi-Fi del telefono in onda: nel registro **una sola** sequenza di tentativi (Android:
      niente tentativi doppi).
- [ ] Android con 2 computer accesi, uno dei due bloccato: compaiono tutti e due entro pochi secondi.

**Telefono**
- [ ] 30 minuti in onda **a batteria**, schermo oscurato dopo 30 s: % di batteria e temperatura all'inizio e alla fine
      (iPhone 16 Pro Max, S22 Ultra; se puoi anche un iPhone XR/11 e un Android di fascia media).
- [ ] Pizzico lungo per lo zoom: fluido, «1,0×» al centro come prima; lo schermo non si oscura durante il gesto.
- [ ] iPhone con la Livella accesa: oscura, tocca, la livella riprende.
- [ ] iPhone, Pro in modalità aereo: «Riprova» entro 10 s; con la rete il prezzo arriva.
- [ ] Android, «Rimuovi animazioni» attivo: il radar della ricerca è fermo; spento: gira.

**Computer**
- [ ] Mac con telefono collegato e una registrazione di 1 minuto: etichette sopra il video, «● mm:ss», tacche del
      microfono come prima. Con Instruments › SwiftUI: `ContenutoPrincipale.body` non compare più ogni secondo.
- [ ] Mac: stop e risveglio con il Wi-Fi che torna dopo qualche secondo: una sola riapertura dell'ascolto, il telefono
      ritrova il Mac.
- [ ] Windows con effetti accesi: finestra nel vassoio 1 minuto (Gestione attività: processore e GPU prima/dopo),
      poi riaprila da icona e da mini finestra: l'anteprima elaborata compare subito e si muove.
- [ ] Windows: chip qualità/fps, latenza della scheda e suggerimento dell'icona si aggiornano ogni secondo; al
      collegamento «Tra un attimo» sparisce e i comandi si accendono.
- [ ] Windows su un **PC senza GPU dedicata**: sfondo sfocato 5 minuti, annota i ms del motore nel registro (serve per
      la decisione 4).
- [ ] Windows: firewall cambiato con la finestra nel vassoio, poi riapri: la barra della diagnosi si aggiorna subito.

**Sito**
- [ ] https://lr-apps609.github.io/WebcamLR/ sul telefono: caratteri, frecce «→» e ✓ come prima.

## 6. Latenza da un capo all'altro (Qualità 14)

Obiettivo: **50 ms o meno in Wi-Fi, 30 ms o meno con il cavo**, dalla cattura sul telefono all'immagine nella finestra
del computer. Ramo `latenza`. Protocollo invariato: si usano il timestamp di cattura che ogni fotogramma ha già e lo
scarto degli orologi dei `pong`.

**Cosa c'era già.** iPhone: VideoToolbox in tempo reale, codifica a bassa latenza, nessun riordino
(`AllowFrameReordering` falso), `MaxFrameDelayCount` 0: niente da cambiare. Android: `KEY_PRIORITY` 0, `KEY_LATENCY` 1,
`KEY_MAX_B_FRAMES` 0; quest'ultima però esiste solo da Android 10.

**Cosa cambia.**
- **Android 8 e 9:** profilo Constrained High (senza fotogrammi B per definizione) quando il codificatore lo dichiara.
  Su ogni versione, se i tempi dei fotogrammi tornano indietro di qualche fotogramma (fotogrammi B), il codificatore si
  rifà una volta in Constrained Baseline (nel registro del telefono una riga «codificatore fermo»).
- **Coda di ricezione che si adatta** (`CodaAdattiva`, uguale su Mac e Windows, provata con tempi finti in
  `CodaAdattivaTest.cs`). Per ogni fotogramma il margine: quanto prima del suo momento è pronto. Degli ultimi 150, tolti
  i 3 peggiori, il più piccolo va portato all'obiettivo (Mac 2 ms, Windows 12 ms per la decodifica nel lettore): con la
  rete stabile la coda è minima, si allunga solo con il jitter, al massimo 100 ms, 2 ms a fotogramma. Una pausa isolata
  della rete (fino a 3 fotogrammi ogni 5 secondi) resta uno scatto e non allunga la coda per tutti.
  - Mac: prende il posto della «riserva per la fluidità» di prima, che teneva fino a 120 ms. Le immagini arrivate a
    gruppo già scadute si buttano (esce solo la più recente) invece di uscire tutte insieme in ritardo.
  - Windows: la coda è la linea del tempo del lettore; prima si poteva solo accorciare fino a 20 ms di anticipo, ora
    anche allungare un poco. Oltre 6 fotogrammi in fila si salta ancora al prossimo fotogramma chiave (chiesto subito).
- **Latenza divisa nelle parti**, nei Numeri del computer (Mac e Windows), riga «Parti»: **rete** (dalla cattura
  all'arrivo, compresa la codifica sul telefono), **decodifica** (Mac: dall'arrivo all'immagine pronta; Windows: il resto
  fino all'anteprima, decodifica e disegno; con gli effetti del computer accesi anche il loro tempo), **coda** (l'attesa
  sul computer). Sono mediane di un secondo: la somma è vicina alla latenza della finestra, non sempre uguale.
- **Registro**, ogni 30 secondi con il video: «Parti della latenza: rete · decodifica · coda»; Windows aggiunge la
  profondità della coda e i fotogrammi buttati, il Mac le immagini buttate nella riga «Riserva per la fluidità».

**Checklist sui dispositivi veri** (annota la riga «Parti» dei Numeri e le righe del registro):
- [ ] Cavo USB, iPhone → Mac, 1080p30, senza effetti, 2 minuti: latenza della finestra ≤ 30 ms? Annota rete,
      decodifica e coda; la coda deve restare sui 2-5 ms. Il video è fluido (niente scatti a ogni secondo).
- [ ] Come sopra, iPhone → Windows e Android → Windows (cavo o Tethering USB): latenza ≤ 30 ms, coda sui 12-15 ms.
- [ ] Wi-Fi a 5 GHz vicino al router, 5 minuti, Mac e Windows: latenza ≤ 50 ms; la coda resta sotto i 20 ms.
- [ ] Wi-Fi lontano dal router (o 2,4 GHz affollato) 2 minuti, poi torna vicino: la coda sale (fino a qualche decina
      di ms, mai oltre 100), il video resta fluido o quasi; tornato vicino, entro 10-15 secondi la coda torna bassa.
- [ ] Copri e scopri l'obiettivo guardando telefono e computer insieme: a occhio il ritardo è più basso di prima.
- [ ] Una chiamata vera (Zoom o Meet) di 10 minuti con il telefono nella webcam: audio e labbra insieme, niente salti.
- [ ] Un Android con Android 8 o 9 (se c'è): il video si vede giusto, nessun fotogramma che va avanti e indietro.
- [ ] Se il video **scatta** più di prima in Wi-Fi: manda le righe «Parti della latenza» e «Riserva per la fluidità»
      (Mac) del registro; si possono alzare i 3 fotogrammi tollerati o l'obiettivo.
