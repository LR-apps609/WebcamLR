# Confronto con i concorrenti · WebcamLR contro iVCam, Iriun, DroidCam, Camo e Continuity Camera

Ottobre 2026, ramo `round-2`. Il confronto parte dal **codice che esiste davvero** nelle quattro app (iPhone, Android, Mac, Windows), non solo dai documenti. Per i concorrenti ho controllato pagine degli store, siti ufficiali e note di rilascio del 2025–2026. Estende `Ricerca utenti e concorrenti.md`, `Compatibilità webcam.md` e `Idee nuove funzioni.md`, senza ripeterli.

Avvertenza sul metodo: i siti dei produttori (e2esoft.com, iriun.com, droidcam.app, camo.com) non si aprivano direttamente da questo ambiente. Le loro informazioni vengono quindi da estratti dei motori di ricerca, dalle pagine dell'App Store e da APKMirror. Prezzi e limiti vanno ricontrollati prima di pubblicare un confronto sul sito. EpocCam non ha una colonna: è abbandonata da Elgato e non riceve aggiornamenti.

## Come leggere lo stato di WebcamLR

Il punto più importante di tutto il documento: **quasi niente di WebcamLR è stato ancora provato sui dispositivi.**

| Segno | Significato |
|---|---|
| **V** | Verificato su dispositivi veri da Ledion. Vale **solo** per il round 0/1: video iPhone → Mac in Wi-Fi, 1080p30, H.264, circa 51 ms |
| **C** | Il codice Mac attuale **compila** (build di oggi), ma non è stato provato con il telefono |
| **T** | Coperto da test automatici su Linux (protocollo e ricevitore Windows: 205 + 65 + 22 test; protocollo Kotlin) ma mai eseguito su un PC Windows o su un telefono vero |
| **S** | Scritto e riletto, **mai compilato né provato** (iPhone dal round 2 in poi, app Android, interfaccia Windows) |
| **A** | Richiede l'account sviluppatore Apple a pagamento, che Ledion oggi non ha |

Nella matrice qui sotto, per WebcamLR, ✅ vuol dire «il codice c'è», non «funziona». La lettera tra parentesi dice quanto è affidabile.

## 1. Matrice delle funzioni

Legenda: ✅ sì · 🟡 in parte o con limiti · ❌ no · 💰 solo a pagamento · ? non verificato

### Collegamento

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Ricerca automatica in Wi-Fi | ✅ Bonjour/mDNS (V su iPhone→Mac; S/T altrove) | ✅ | ✅ | 🟡 IP mostrato dall'app, da scrivere nel client | ✅ | ✅ (stesso Apple ID) |
| QR code | ✅ con tutti gli indirizzi e «gara» tra indirizzi (S/C/T) | ❌ | ❌ | ❌ | 🟡 per abbinare | ❌ (non serve) |
| Indirizzo scritto a mano | ✅ (S) | ✅ | 🟡 | ✅ (è la strada principale) | ? | ❌ |
| Cavo USB con iPhone | ✅ usbmux scritto da zero, Mac e Windows (S/C/T; Windows chiede «Dispositivi Apple») | ✅ | ✅ | ✅ (setup in più) | ✅ (consigliato) | ✅ |
| Cavo USB con Android | 🟡 solo tramite «Tethering USB», nessun USB nativo (S) | ✅ | ✅ | ✅ (ADB) | ✅ | — |
| Passaggio automatico Wi-Fi ↔ cavo senza fermare il video | ✅ (S/C/T) | ❌ | ❌ | ❌ | 🟡 | 🟡 |
| Wi-Fi diretto / hotspot | ✅ Wi-Fi diretto Mac (AWDL, opzione), hotspot e «Cavo di rete» riconosciuti (S/C) | 🟡 hotspot | 🟡 hotspot | ✅ hotspot | ? | ✅ (AWDL di sistema) |
| Ricollegamento in qualsiasi ordine | ✅ (S/C/T) | 🟡 | ❌ prima il PC | 🟡 dalla 8.1 | ✅ | 🟡 inaffidabile secondo le recensioni |
| Indicatore del tipo di collegamento | ✅ «Wi-Fi / Cavo USB / Wi-Fi diretto / Cavo di rete / Hotspot» (S/C/T) | ❌ | ❌ | ❌ | 🟡 | ❌ |

### Video

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Risoluzione massima dal telefono | 4K (S; V solo 1080p30) | 4K | 4K (dipende dal telefono) | 💰 1080p come webcam, 4K solo nel plugin OBS; gratis 480p | 💰 4K; gratis 720p | circa 1080p (1920×1440), non dichiarato da Apple |
| Risoluzione della **webcam virtuale** | **1080p30 al massimo**, Mac e Windows | 4K | 4K | 1080p | 💰 4K | circa 1080p |
| 60 fps | 🟡 dal telefono sì (S); la webcam virtuale esce a 30 | ✅ | ? | 💰 4K60 in OBS | 💰 | ❌ |
| HDR / 10 bit | ❌ (piano 1.14) | ❌ | ❌ | 💰 nel plugin OBS | ❌ | ❌ |
| Codec | H.264, HEVC, solo hardware (S; V solo H.264) | H.264/HEVC | ? | H.264, HEVC (OBS) | ? | proprietario |
| Controllo del bitrate | 🟡 automatico che segue la rete, nessuna scelta manuale (S) | ✅ qualità a scelta | 🟡 | 🟡 | 🟡 | ❌ |
| Verticale / orientamento | 🟡 video dritto rispetto al telefono; su Windows «bande nere» o «riempi tagliando» per la webcam; niente uscita 9:16 vera | ✅ | ✅ | ✅ | ✅ | 🟡 |
| Specchio | ✅ telefono, anteprima e webcam separati (S/C/T) | ✅ | ✅ | ✅ | ✅ | ✅ |

### Controlli della fotocamera

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Scelta dell'obiettivo (0,5× / 1× / tele / frontale) | ✅ telefono e computer (S/C/T) | ✅ | 💰 | 💰 ultra-grandangolo e tele | 💰 | ❌ (Desk View usa l'ultra-grandangolo) |
| Zoom | ✅ pizzico sul telefono, cursore e tasti dal computer (S/C/T) | ✅ | ✅ | ✅ | ✅ | ❌ (Center Stage) |
| Messa a fuoco | 🟡 tocco e blocco AE/AF sul telefono, «automatica» dal computer; niente fuoco manuale (S) | ✅ manuale | ✅ | 💰 | 💰 | ❌ |
| Esposizione | ✅ compensazione ±2 dal computer (S/C/T) | ✅ | 💰 | 💰 (dalla 10.0) | 💰 | ❌ |
| ISO e tempo manuali | ✅ **solo dal computer**; sul telefono «Controlli Pro: presto» (S/C/T) | ✅ ISO | 💰 | 💰 | 💰 | ❌ |
| Bilanciamento del bianco | ✅ kelvin dal computer (S/C/T; su Android è approssimato a preset) | ✅ | 💰 | 💰 | 💰 | ❌ |
| Torcia | ✅ (S/C/T) | ✅ | ✅ | ✅ | 💰 | ❌ |
| Stabilizzazione | 🟡 spenta o «Standard» in avanzata (S) | ? | ? | ? | ? | ✅ |
| Poca luce | ✅ automatica dove l'iPhone la supporta (S) | ? | ? | ? | ✅ | ✅ |
| Profili salvati | ✅ sul computer (S/C/T) | ❌ | ❌ | ❌ | ✅ scene | ❌ |

### Effetti

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Filtri di colore | ❌ (piano 1.18) | ✅ | ❌ | ❌ | ✅ 18 filtri | ❌ |
| Sfondo sfocato / sostituito | 🟡 solo l'effetto Ritratto di sistema iOS, dal pulsante «Effetti video» (S; potrebbe servire una chiave Info.plist, da verificare) | ✅ sfocato, bokeh, mosaico, green screen | ❌ | ❌ | 💰 sfocatura, sostituzione, chroma key | ✅ Ritratto, sostituzione |
| Luce studio / ritocco pelle | 🟡 Luce studio di sistema dove c'è (S) | ✅ «beauty» | ❌ | ❌ | 💰 Retouch (2.6) | ✅ Luce studio |
| LUT importabili | ❌ (piano 1.20) | ❌ | ❌ | ❌ | ✅ .cube/.3dl | ❌ |
| Inquadratura automatica | ❌ | ❌ | ❌ | ❌ | ✅ fino a 1080p | ✅ Center Stage |
| Overlay, scritte, filigrana propria | ❌ | 🟡 | ❌ | ❌ | ✅ | 🟡 Presenter Overlay (Mac) |
| Griglia e livella per inquadrarsi | ✅ solo sul telefono (S) | ❌ | ❌ | ❌ | 🟡 | ❌ |

### Audio

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Microfono del telefono sul computer | ❌ «In arrivo» (pacchetto audio Opus previsto nel protocollo, non scritto) | ✅ | 🟡 ? | ✅ («DroidCam Audio») | ✅ | ✅ |
| Riduzione del rumore | ❌ | ? | ❌ | ❌ | 🟡 | ✅ isolamento voce di sistema |

### Webcam virtuale e software per dirette

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Mac | 🟡 Camera Extension scritta, 1080p/720p, immagine d'attesa (S, **A**; riceve video solo con la finestra aperta) | ❌ (solo Windows) | ✅ | ❌ (solo plugin OBS) | ✅ | ✅ |
| Windows 11 | 🟡 Media Foundation moderna con immagine d'attesa (T; **mai provata su Windows**) | ✅ | ✅ | ✅ | ✅ | ❌ |
| Windows 10 | ❌ (piano 1.25) | ✅ | ✅ | ✅ | ✅ | ❌ |
| Linux | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| OBS | 🟡 tramite la webcam virtuale | 🟡 webcam | 🟡 webcam | ✅ plugin dedicato, fino a 4K60 | ✅ | 🟡 |
| NDI | ❌ (1.30 da ripensare) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Streaming diretto RTMP | ❌ | ❌ | ❌ | ❌ | 💰 beta (2.6) | ❌ |
| Più telefoni insieme | ❌ («Telefoni: in arrivo» su Windows) | ✅ | 🟡 | ✅ (più sorgenti OBS) | ✅ | ❌ |

### Computer e telefono

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Foto e registrazione sul computer | ✅ **solo Mac** (foto, timer, registra, ⌘C) (C); Windows «in arrivo» | ✅ | ❌ | 🟡 | ✅ | ❌ |
| Finestra mini sempre in primo piano | ✅ Mac e Windows (C/S) | ? | ❌ | ❌ | 🟡 | ❌ |
| Comandi della fotocamera dal computer | ✅ obiettivo, zoom, esposizione, ISO, tempo, bianco, torcia, fuoco, profili, scorciatoie (S/C/T) | ✅ | 💰 | 💰 | ✅ | ❌ |
| Batteria e calore | ✅ 720p quando è molto caldo, 24 fps sotto il 20%, avvisi sul computer (S/C/T) | 🟡 | 🟡 | 🟡 | 🟡 | ❌ (Apple consiglia la carica) |
| Schermo oscurato | ✅ dopo 30 s, a mano o da solo (S) | ✅ | ✅ funziona a schermo spento | ✅ | ✅ | ✅ |
| Pausa quando nessuna app usa la webcam | 🟡 Windows ferma il secondo decodificatore; il telefono continua a codificare | ❌ | ❌ | ❌ | ? | ✅ |

### Fiducia, aiuto, prezzo

| Funzione | WebcamLR | iVCam | Iriun | DroidCam | Camo | Continuity |
|---|---|---|---|---|---|---|
| Collegamento cifrato | ✅ ECDH P-256, AES-256-GCM, chiavi nuove a ogni collegamento (T: test in tre linguaggi; mai provato su dispositivo) | ? | ❌ dichiarato | ❌ dichiarato | ? | ✅ |
| Abbinamento | ✅ codice di 4 cifre, telefoni fidati, rimozione (S/C/T) | ❌ | ❌ | ❌ | 🟡 | ✅ Apple ID |
| Diagnosi con causa e azione | ✅ permesso Rete locale, niente Wi-Fi, rete isolata/firewall, versione vecchia, non trovato (S/C/T) | ❌ rimanda alle FAQ | ❌ pagina web | ❌ pagina web | 🟡 | ❌ |
| Domande frequenti dentro l'app | ✅ 16, senza Internet (S/C/T) | ❌ | ❌ | ❌ | 🟡 | ❌ |
| Registro del collegamento copiabile | ✅ in modalità avanzata (S/C/T) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Lingue | ❌ **solo italiano** | molte | molte | molte | molte | tutte quelle di Apple |
| Accessibilità (VoiceOver, Assistente vocale) | ✅ scritta (S) | ? | ? | ? | ? | ✅ |
| Prezzo | gratis per ora, nessuna filigrana, nessuna pubblicità (monetizzazione da decidere) | pubblicità e filigrana nel gratuito; PC 12,95 $/anno o 25,95 $ a vita | gratis con filigrana; Pro circa 7 $ (una volta, da confermare) | gratis 480p con pubblicità; Pro a pagamento | gratis 720p con filigrana; Pro circa 40 $/anno o 80 $ a vita (dati 2023) | gratis |
| Telefoni | iPhone (iOS 17+), Android (S, mai compilata) | iPhone, Android | iPhone, Android | iPhone, Android | iPhone, Android | iPhone XR+ |
| Computer | Mac, Windows 11 | Windows | Mac, Windows, Linux | Windows, Linux (Mac solo plugin OBS) | Mac, Windows | Mac |

Fonti principali dei concorrenti: [iVCam App Store](https://apple.co/2AjUF2v) · [iVCam prezzi e2eSoft](https://www.e2esoft.com/?p=99255) · [Gizmodo iVCam, gennaio 2026](https://gizmodo.com/download/ivcam-webcam) · [Iriun App Store, 2.9.3 aprile 2026](https://apps.apple.com/app/id1439303579) · [Iriun 2.9.x APKMirror](https://www.apkmirror.com/?p=13456895) · [DroidCam App Store](https://apps.apple.com/us/app/-/id1510258102) · [DroidCam 10.0, luglio 2026](https://www.apkmirror.com/apk/dev47apps/droidcam-obs/droidcam-webcam-obs-camera-10-0-release/) · [DroidCam Pro](https://droidcam.app/pro-info.html) · [DroidCam FAQ](https://droidcam.app/help/) · [Camo prezzi](https://camo.com/pricing) · [Camo note di rilascio](https://camo.com/support/camo/release-notes) · [Camo Studio 2.6](https://camo.com/blog/camo-retouch-razer) · [TechCrunch, prezzi Camo 2023](https://techcrunch.com/2023/03/16/camo-2-launches-with-support-for-any-camera-new-effects-and-more) · [Apple, Continuity Camera](https://support.apple.com/102546) · [Apple, requisiti degli effetti](https://support.apple.com/en-kz/guide/mac-pro-rack/apd1c059dc3b/mac).

## 2. Cosa manca a WebcamLR

Sforzo: **S** = pochi giorni · **M** = un round · **L** = più round o dipendenze esterne (account, certificati, hardware). Versione secondo `Piano aggiornamenti.md`.

### Per l'utente medio (videochiamate)

| # | Cosa manca | Perché conta | Sforzo | Versione |
|---|---|---|---|---|
| 1 | **Prove sui dispositivi di tutto ciò che c'è** (Checklist 1.0, 1.2–1.9, 1.10–1.12) | Oggi ogni ✅ è sulla carta. I concorrenti, per quanto fragili, funzionano | M (tempo di Ledion) | 1.1 |
| 2 | **Webcam virtuale funzionante su Windows 11**, provata in Teams nuovo, Zoom, Meet, WhatsApp | Senza, su Windows WebcamLR è una finestra con il video, e iPhone→Windows è il caso principale | M (scritta, da provare e correggere) | 1.24 |
| 3 | **Webcam virtuale sul Mac**: account a pagamento e video anche con la finestra chiusa | Senza, sul Mac vince Continuity, gratis. Oggi la webcam riceve il video solo con la finestra aperta | S per il codice, L per l'account (99 €/anno) | 1.23 |
| 4 | **Microfono del telefono** | Tutti i concorrenti tranne Iriun (forse) lo hanno. Chi usa il telefono lontano dal computer resta senza audio | M sul Mac (Audio Server Plug-in), L su Windows (driver firmato Microsoft, certificato EV) | anticipare la parte Mac dalla 2.x a subito dopo la 1.26 |
| 5 | **Installer firmati**: .dmg notarizzato, installer Windows firmato, App Store | Senza firma Windows e macOS mostrano avvisi che spaventano l'utente medio | M + costi | prima della pubblicazione (non è nel piano: va aggiunto) |
| 6 | **Lingue: almeno l'inglese** | Solo italiano esclude quasi tutto il mercato. Tutti i concorrenti sono multilingue | M (testi in tre app e nel sito) | da aggiungere prima della pubblicazione, insieme alla 1.33 |
| 7 | **Windows 10** (filtro DirectShow) | Ancora molto diffuso nonostante la fine del supporto; tutti i concorrenti Windows lo coprono | M | 1.25 |
| 8 | **Uscita a 60 fps e oltre 1080p nella webcam virtuale** | Il telefono manda 4K60, la webcam esce sempre a 1080p30: chi sceglie 4K paga calore e batteria senza vantaggio | S–M | 1.13 |
| 9 | **Sfondo sfocato garantito** su tutti gli iPhone (non solo l'effetto di sistema) | È la funzione «effetto» più chiesta in chiamata; iVCam la dà, Camo la fa pagare | M | 1.21, dopo aver verificato l'effetto Ritratto di sistema |
| 10 | **Pausa quando nessuna app usa la webcam** | Batteria e calore nelle giornate di riunioni | M (modifica del protocollo) | Fase F |

### Per gli streamer e i creator

| # | Cosa manca | Perché conta | Sforzo | Versione |
|---|---|---|---|---|
| 1 | **60 fps stabili e latenza costante misurata** fino a OBS | È la prima cosa che guarda uno streamer | S–M | 1.13 e 1.17 |
| 2 | **Più telefoni insieme** | iVCam, DroidCam e Camo lo fanno; serve per la seconda inquadratura | L (ricevitore, webcam con più dispositivi) | 1.29 |
| 3 | **Sorgente OBS dedicata o uscita a 4K/HEVC verso OBS** | DroidCam porta 4K60 e HDR in OBS con un plugin; la webcam virtuale a 1080p30 non regge il confronto | M–L | Fase G (al posto della 1.30 NDI) |
| 4 | **Controlli manuali sul telefono** (oggi solo dal computer; «Controlli Pro: presto») e fuoco manuale | Chi riprende sé stesso a distanza usa il computer, ma chi fa una ripresa a mano li vuole sul telefono | M | 1.5 (completare la modalità avanzata) |
| 5 | **Filtri e LUT** | Camo ne ha fatto il suo punto forte; priorità di Ledion | M | 1.18–1.20 |
| 6 | **Verticale 9:16 vero** nella webcam | TikTok e Shorts; oggi su Windows si sceglie solo tra bande nere e taglio | S–M | 1.27 |
| 7 | **Registrazione su Windows** e registrazione in piena qualità sul telefono | Il Mac l'ha già; Windows no | M | 1.28 |
| 8 | **Comandi esterni** (Stream Deck, scorciatoie globali) | Piccolo ma molto apprezzato | M | Fase G |
| 9 | **HDR 10 bit** | Solo DroidCam (in OBS) lo ha; nicchia | M | 1.14 |
| 10 | **Linux** | Iriun e DroidCam lo coprono; pubblico piccolo | L | 2.x tardi |

## 3. Dove WebcamLR è già meglio (sulla carta)

Tutto ciò che segue è scritto e riletto, ma va confermato sui dispositivi.

1. **Spiega perché non si collega.** Diagnosi con causa e pulsante (permesso Rete locale, rete ospiti o isolata, firewall di Windows, versione vecchia), 16 domande frequenti dentro l'app senza Internet, registro copiabile. Nessun concorrente lo fa: tutti rimandano a pagine web.
2. **Sicurezza vera.** Collegamento cifrato con chiavi nuove a ogni sessione, codice di conferma di 4 cifre, telefoni fidati. Iriun e DroidCam mandano il video in chiaro sulla rete locale.
3. **Collegamento più completo.** QR con tutti gli indirizzi, cavo USB scritto da zero su Mac e Windows, passaggio Wi-Fi → cavo senza fermare il video, Wi-Fi diretto sul Mac, indicatore del tipo di collegamento, ricollegamento in qualsiasi ordine. Iriun impone ancora di aprire prima il PC.
4. **Gratis senza filigrana e senza pubblicità, a piena qualità.** DroidCam gratis è a 480p con pubblicità, Camo a 720p con filigrana, iVCam con filigrana e pubblicità.
5. **iPhone su Windows con controlli completi.** Continuity non c'è, EpocCam è abbandonata, iVCam ha la pubblicità. WebcamLR comanda dal PC obiettivo, zoom, esposizione, ISO, tempo, bianco e torcia, con profili.
6. **Webcam virtuale pensata per i guasti noti.** Immagine d'attesa «Apri WebcamLR sul telefono» invece del nero (così l'ordine di avvio non conta), Media Foundation moderna per il nuovo Teams, rimozione pulita senza riavvio, specchio separato per sé e per gli altri.
7. **Cura nei dettagli che gli altri non hanno.** Qualità del collegamento in parole, grafico della latenza, griglia e livella, tocco lungo per AE/AF, finestra mini, foto con timer e ⌘C sul Mac, avvisi di calore e batteria sul computer, VoiceOver e Assistente vocale, modalità avanzata che nasconde i numeri a chi non li vuole.
8. **Batteria e calore gestiti da soli** (720p quando è molto caldo, 24 fps sotto il 20%, schermo che si oscura), con l'avviso sul computer.
9. **Nessun servizio Google su Android**, quindi funziona anche sui Huawei (sulla carta: l'app Android non è mai stata compilata).
10. **Stessa esperienza su Mac e Windows**, con testi chiari. Camo è l'unico che si avvicina, ma costa circa 40 $ l'anno.

## 4. Cose da togliere o semplificare

1. **Pulsanti «PRESTO» sul telefono** (Microfono, Controlli Pro) e voci grigie su Windows («Telefoni», «Registrazioni», «Diagnostica: in arrivo»). In un'app pubblicata sembrano incompiuta. Meglio nasconderle finché non esistono e raccontarle nella sezione «Novità».
2. **Scelta 4K e 60 fps sul telefono quando la webcam virtuale esce a 1080p30.** Consuma batteria e scalda per niente. Finché la 1.13 non arriva, limitare la scelta o dire chiaramente che serve solo per l'anteprima e le registrazioni sul Mac.
3. **Due interruttori «Specchia» su Windows** (anteprima e «Specchia anche per chi guarda»), più quello sul telefono e «Specchia di serie» sul Mac. Sono quattro posti per la stessa idea. Proposta: uno solo sul computer per la propria anteprima, e quello per chi guarda in modalità avanzata.
4. **«Wi-Fi diretto, anche senza router» sul Mac.** Le ricerche citate documentano scatti di 50–100 ms ogni 1–2 secondi con AWDL. Per l'utente medio è una trappola: tenerlo in modalità avanzata con un avviso.
5. **Bianco in kelvin su Android**: viene arrotondato a 7 preset (lampadina, fluorescente, giorno…). Mostrare i preset con il loro nome invece di un cursore che finge precisione.
6. **Stabilizzazione «Standard»** in modalità avanzata: con la stabilizzazione a bassa latenza di iOS 26 (vedi `Idee nuove funzioni.md`) la scelta può sparire sui telefoni nuovi.
7. **Due app Mac** (`project-senza-account.yml` e `project.yml`) vanno bene per lo sviluppo, ma all'utente deve arrivare una sola app: con la pubblicazione serve comunque l'account a pagamento.

## 5. Verdetto onesto

1. WebcamLR oggi è un **prototipo avanzato**: l'unica cosa vista funzionare è iPhone → Mac in Wi-Fi a 1080p30 con 51 ms (round 0/1). Il codice Mac attuale compila. Tutto il resto è scritto e riletto, ma non provato.
2. Come **progetto e idee** è già al livello di Camo e sopra iVCam, Iriun e DroidCam: diagnosi, sicurezza, collegamento, nessuna filigrana.
3. Come **prodotto usabile** è dietro a tutti, perché manca ancora la cosa per cui la gente scarica queste app: **una webcam che Zoom, Teams e Meet vedono**. Su Windows è scritta ma mai avviata; sul Mac serve l'account a pagamento.
4. Mancano anche **audio**, **inglese**, **installer firmati** e **Windows 10**: tutti e quattro sono normali nei concorrenti.
5. Il concorrente da battere per l'utente medio su Windows è **iVCam** (4K, microfono, sfondo, più telefoni, ma pubblicità e niente Mac). Per chi paga, su Mac, è **Camo**. Per chi ha un Mac e un iPhone recente è **Continuity**, gratis.
6. Dove WebcamLR vince davvero (affidabilità spiegata, cavo, sicurezza, gratuito pulito) si vedrà solo **dopo** le prove: oggi è un vantaggio dichiarato, non dimostrato.
7. Gli effetti (filtri, LUT, sfondo) e 4K/60 nella webcam sono il secondo passo; prima vengono webcam virtuale, microfono e stabilità di un'ora.
8. Stima: se le checklist passano senza grossi intoppi, **4–6 settimane** per una prima versione pubblica iPhone + Mac + Windows 11 con webcam virtuale, senza audio. Coincide con la stima del `Registro lavori.md`.
9. Con il microfono e l'inglese, altre **3–5 settimane**. Il microfono su Windows (driver firmato) può spostare tutto di mesi: conviene uscire prima con l'audio solo sul Mac.
10. In sintesi: **a circa due mesi da un prodotto che regge il confronto con iVCam su Windows**, e più lontano da Camo sul fronte effetti. L'architettura però è più solida di entrambi.
