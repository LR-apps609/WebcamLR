# Registro dei lavori

Tutto ciò che Ledion chiede, tutto ciò che Claude fa e tutte le idee, in ordine di tempo. Da rileggere insieme a ogni prova. Il piano per versioni è in `Piano aggiornamenti.md`.

## Richieste di Ledion ancora aperte

- [ ] **Compatibilità webcam ovunque**: WebcamLR deve comparire come webcam vera in Meet, Zoom, Teams, WhatsApp, FaceTime, OBS e in ogni sito che chiede la webcam, sia con il Wi-Fi sia con il cavo USB (Mac: Camera Extension, già scritta, richiede l'account a pagamento; Windows: webcam virtuale da scrivere)
- [ ] **Android**, compresi Xiaomi, Huawei, Samsung, Oppo… (anche senza i servizi Google)
- [ ] **Sito di presentazione** con i download per iPhone, Android, Mac, Windows e Linux
- [ ] **Linux** come computer che riceve (da valutare: nuova app)
- [ ] Opinione onesta sullo stato dell'app rispetto ai concorrenti
- [ ] Nuove funzioni dalla ricerca online
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

**In corso (dalle 15)**
- 1.10–1.12 Collegamento istantaneo (iPhone; Mac e Windows)
- 1.24 Webcam virtuale per Windows 11 (Media Foundation)
- Android: protocollo in Kotlin con test, poi l'app
- Sito: pagina download per tutte le piattaforme
- Ricerca: compatibilità webcam (Meet, Zoom, WhatsApp, browser) e nuove funzioni

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
