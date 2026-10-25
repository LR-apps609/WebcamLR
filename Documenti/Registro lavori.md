# Registro dei lavori

Tutto ciò che Ledion chiede, tutto ciò che Claude fa e tutte le idee, in ordine di tempo. Da rileggere insieme a ogni prova. Il piano per versioni è in `Piano aggiornamenti.md`.

## Richieste di Ledion ancora aperte

- [ ] **Compatibilità webcam ovunque**: WebcamLR deve comparire come webcam vera in Meet, Zoom, Teams, WhatsApp, FaceTime, OBS e in ogni sito che chiede la webcam, sia con il Wi-Fi sia con il cavo USB (Mac: Camera Extension, già scritta, richiede l'account a pagamento; Windows: webcam virtuale da scrivere)
- [ ] **Android**, compresi Xiaomi, Huawei, Samsung, Oppo… (anche senza i servizi Google): app scritta, da compilare e provare
- [ ] **Sito di presentazione** con i download per iPhone, Android, Mac, Windows e Linux: pronto sul ramo `sito`, da mettere online
- [ ] **Linux** come computer che riceve (da valutare: nuova app)
- [x] Opinione onesta sullo stato dell'app rispetto ai concorrenti (qui sotto)
- [x] Nuove funzioni dalla ricerca online (`Idee nuove funzioni.md`)
- [ ] Video illustrativi (più avanti)
- [ ] Voice changer e microfono (molto più avanti)
- [ ] Monetizzazione (quando l'app è perfetta)

## 24 ottobre 2026

**Richiesta (15:00)**: continuare per 5 ore senza fermarsi; Ledion prova tutto verso le 19–20. Bug, compatibilità webcam con Meet/Zoom/WhatsApp/siti via Wi-Fi e USB, ricerca di funzioni e desideri, opinione onesta, Windows, Android (anche Xiaomi/Huawei), sito con download (anche Linux), tutto segnato qui.

**Fatto prima (mattina–pomeriggio)**
- 1.2 Indicatore del collegamento, 1.3 diagnosi, 1.4 domande frequenti, 1.5 modalità avanzata su iPhone, Mac e Windows
- 1.6–1.8 Cavo USB su iPhone, Mac (versione dal sito) e Windows (con «Dispositivi Apple»)
- 1.9 Passaggio automatico Wi-Fi → cavo e ritorno al Wi-Fi
- Stesso telefono riconosciuto dall'identità di sicurezza, non dal nome
- Attesa crescente quando il telefono rifiuta il cavo
- Revisori indipendenti su ogni parte; Windows: 143 + 22 test verdi
- Checklist: `Checklist 1.2-1.9.md`

**Fatto (15–17)**
- 1.10–1.12 Collegamento istantaneo su iPhone, Mac e Windows (QR con tutti gli indirizzi e gara tra indirizzi, avvio misurato e più rapido, ricollegamento in qualsiasi ordine e dopo lo stop). Windows: 178 + 22 test verdi. Checklist: `Checklist 1.10-1.12.md`
- Sito: presentazione, download per tutte le piattaforme, aiuto con le 16 domande frequenti (ramo `sito`, non ancora online)
- Ricerca su compatibilità webcam e nuove funzioni
- Webcam virtuale del Mac pronta per l'account a pagamento: 1080p e 720p, immagine d'attesa «Apri WebcamLR sul telefono», «In onda» quando un'app la usa, attivazione e rimozione guidate (`Webcam virtuale Mac.md`, con 13 prove)
- Da fare: la webcam del Mac riceve il video solo quando la finestra è aperta (anche se WebcamLR parte al login senza finestra)
- Webcam virtuale per Windows 11 (1.24) con rimozione pulita (1.26): scheda «Webcam per le altre app», installazione con un clic, immagine d'attesa, in onda. Le interfacce con Windows sono verificate una per una sulla documentazione Microsoft; 65 test. Nelle app compare come «WebcamLR (Windows Virtual Camera)». Prove: `Windows/FotocameraVirtuale/LEGGIMI.md`
- Revisione completa per gli errori di compilazione di iPhone e Mac: trovati e corretti 2 errori sicuri; sul Mac ora si vede solo il video del telefono attuale durante il passaggio Wi-Fi → cavo
- Guida per la sera: `Stasera - cosa provare.md`
- **Android**:
  - il protocollo in Kotlin è identico a Swift e C# (stessi JSON e vettori di sicurezza) e ha completato una sessione vera con il ricevitore Windows;
  - l'app è completa ma qui non si può compilare: Android Studio da Ledion. Funziona senza servizi Google (Huawei). Ha tutte le schermate come l'iPhone; il cavo passa dal «Tethering USB».
  - Prove: `Android/LEGGIMI.md`

- Mac e Windows pronti per Android: testi «telefono» dove non è specifico dell'iPhone, nome vero del telefono collegato, cavo Android («Tethering USB») riconosciuto su Windows come «Cavo USB» (sul Mac compare come «Cavo di rete»), avviso se la rete del cavo è «Pubblica». Windows: 205 + 65 + 22 test verdi
- Revisione dell'app Android per la prima apertura in Android Studio (5 correzioni)
- Sito: domande frequenti riallineate all'app

**Prossimi passi**
- 1.1: correzioni dalle prove di stasera
- Linux come computer che riceve (dopo Android)
- Filtri (Fase E), dopo la webcam virtuale provata

## Opinione onesta sullo stato dell'app (24 ottobre, 15:30)

**Dove siamo.** Ledion ha visto funzionare round 0 e round 1 (video iPhone → Mac a 1080p30, circa 51 ms). Tutto ciò che è venuto dopo (dal round 2 alla 1.9: sicurezza, sezione App, cavo USB, diagnosi…) è **scritto e riletto da più revisori, ma non ancora compilato né provato sui dispositivi**. Sul lato Windows il cuore è coperto da 143 test automatici, la finestra no. Quindi oggi WebcamLR è un **prototipo avanzato**, non ancora una beta.

**Rispetto ai concorrenti**
- *Più avanti di loro su carta*: collegamento cifrato con conferma a codice (nessuno dei concorrenti lo ha così), diagnosi con la causa e l'azione, domande frequenti dentro l'app, cavo con passaggio automatico, nessuna filigrana, testi chiari in italiano.
- *Indietro*: la cosa che conta di più, **la webcam virtuale**, non è ancora utilizzabile. Sul Mac serve l'account sviluppatore a pagamento; su Windows è in scrittura. Senza, WebcamLR mostra il video in una finestra, ma Zoom/Meet/WhatsApp non lo vedono: è il motivo n. 1 per cui la gente scarica queste app. Mancano anche audio (microfono), filtri, 60 fps/4K provati, Android, installer veri, firma e notarizzazione.
- *Grezza quanto?* Come esperienza d'uso e idee è già all'altezza di Camo e migliore di iVCam/DroidCam/Iriun; come **affidabilità provata** è all'inizio: ogni parte deve passare le checklist sui dispositivi veri.

**Cosa serve per pubblicarla (in ordine)**
1. Compilare e far passare la Checklist 1.0 e la 1.2–1.9 (correzioni 1.1)
2. Webcam virtuale funzionante: Mac (account a pagamento, 99 €/anno) e Windows 11
3. Prove lunghe: 1 ora di chiamata senza cadute, calore e batteria accettabili
4. Installer firmati: .dmg notarizzato per Mac, installer firmato per Windows (certificato di firma del codice), App Store per iPhone
5. Sito con i download veri, privacy, assistenza
6. Poi: audio, filtri, Android

Stima realistica: **una prima versione pubblica (iPhone + Mac + Windows con webcam virtuale) in 4–6 settimane**, se le prove procedono senza intoppi grossi.

## Ricerca del pomeriggio (24 ottobre, 16:00)

File: `Compatibilità webcam.md` e `Idee nuove funzioni.md`.
- **Mac**: la Camera Extension è l'unica strada rimasta. Funziona in FaceTime, Zoom, Teams, Meet e nei siti, ma serve l'account sviluppatore a pagamento e un'approvazione una tantum in Impostazioni di Sistema.
- **Windows 11**: la webcam virtuale moderna è vista da Fotocamera, Chrome ed Edge (quindi Meet e tutti i siti), Zoom e OBS. **Rischio principale: il nuovo Teams** (con alcune webcam virtuali l'altra persona non vede il video): va provato per primo.
- **Windows 10**: serve un filtro DirectShow (1.25).
- **Audio** (più avanti): sul Mac è fattibile; su Windows un microfono virtuale richiede un driver firmato Microsoft con certificato EV, che è costoso.
- **Novità iOS 26** (iPhone 17 e Air): Center Stage ufficiale, video verticale senza ruotare il telefono, stabilizzazione a bassa latenza utilizzabili da WebcamLR.
- **Android**: il cavo via «Tethering USB» funziona senza modalità sviluppatore. Huawei: senza servizi Google; HarmonyOS NEXT non installa APK. Xiaomi e Huawei chiudono le app in background: serve una guida alle eccezioni.
- **Linux**: fattibile con v4l2loopback senza obblighi GPL per WebcamLR; dopo Android.
- **Decisione presa**: la webcam virtuale (Fase F) passa prima dei filtri (Fase E).

**Idee in cima alla classifica**
- Immagine d'attesa nella webcam virtuale («Apri WebcamLR sul telefono») invece dello schermo nero
- Avviso «riavvia Teams o Zoom» e controllo del permesso fotocamera di Windows
- Pausa automatica quando nessuna app usa la webcam (risparmia batteria e calore)
- Pulsante «Prova la webcam»
- Effetti di sistema Apple (Ritratto, Luce studio)

**Da decidere con Ledion**
- Distribuzione del Mac: dal sito (con il cavo USB) e/o Mac App Store (senza cavo)
- Account sviluppatore Apple a pagamento (serve per la webcam virtuale del Mac e per pubblicare)
- NDI (1.30): a banda piena usa un codec software, contro la regola «solo codec hardware»; NDI HX richiede una licenza a pagamento
- Messa online del sito: va unito al ramo principale; servono l'email di assistenza, i dati per la privacy e la verifica del link a «Dispositivi Apple»

## Pacchetto funzioni prima delle prove (24 ottobre, sera)

**Richiesta**: tutte le 8 idee «che nessuno ha» e le funzioni che hanno i concorrenti, divise in mini aggiornamenti tracciati in una pagina; le prove tutte insieme alla fine.

Avanzamento in tempo reale: https://claude.ai/artifact/Ftrt7pBHHDxT5Gwm5T1FbR

- **A · Base comune**: P01 protocollo per le funzioni nuove · P02 pipeline effetti sull'iPhone · P03 Impostazioni da «In onda»
- **B · Le idee che nessuno ha**: P04 inquadratura automatica · P05 Prova la webcam · P06 gobbo · P07 faccia in giù = pausa · P08 luce sul volto · P09 volto + scrivania · P10 pausa intelligente · P11 postura
- **C · Quello che hanno i concorrenti**: P12 60 fps e 4K · P13 filtri · P14 sfondo · P15 ritocco pelle · P16 controlli manuali sul telefono · P17 scritte e logo · P18 foto e registrazione su Windows · P19 webcam del Mac a finestra chiusa · P20 microfono sul Mac · P21 più telefoni · P22 inglese · P23 Windows 10
- **D · Allineamento**: P24 Android allineato · P25 controllo totale e checklist unica

## Notte tra 24 e 25 ottobre: pacchetto funzioni (iPhone e Mac)

Fatto e unito su `round-2` (scritto e riletto da più revisori, **non compilato**):
- Le 8 idee: inquadratura automatica, Prova la webcam, gobbo, faccia in giù = pausa, luce sul volto, volto + scrivania, pausa intelligente, postura
- Effetti: filtri e regolazioni, sfondo sfocato o sostituito, ritocco pelle, scritte e logo; l'anteprima del telefono mostra gli effetti
- 60 fps e 4K nella webcam virtuale; controlli manuali sull'iPhone; Impostazioni da «In onda»
- Mac: comandi di tutti gli effetti, finestra Gobbo, «In pausa», webcam a finestra chiusa, microfono del telefono (da installare con `Strumenti/Installa microfono.command`), due telefoni insieme, pulsante «Modalità avanzata» a vista, comandi grigi senza telefono, niente menu in più
- Inglese su iPhone e Mac (ogni lingua diversa dall'italiano mostra l'inglese)
- Nuovo logo ovunque; installer del Mac (`Strumenti/Crea dmg.command`) e guida `Pubblicazione.md`
- Due revisioni complete di compilazione per iPhone e Mac, più quella finale
- **Checklist unica**: `Checklist iPhone e Mac.md` (95 prove, giro veloce di 20 minuti in cima)

Windows (foto, registrazione, effetti, gobbo, più telefoni, Windows 10) è fatto ma **in pausa** per scelta di Ledion; Android allineamento e installer Windows salvati nei rami `android-allineamento-in-pausa` e `windows-installer-in-pausa`.

**Deciso (25 ottobre)**: allo scambio di telefono la registrazione si ferma e si salva (Mac come Windows); il microfono resta «WebcamLR (microfono)».
