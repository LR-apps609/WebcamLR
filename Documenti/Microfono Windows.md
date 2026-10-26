# Microfono del telefono su Windows · W2

Obiettivo: usare il microfono del telefono su Windows come microfono in Zoom, Teams, Meet e OBS, con la stessa riga del Mac
(interruttore «Microfono del telefono», livello, nome del dispositivo «WebcamLR (microfono)»).

**In breve**

- **Adesso (W2)**: WebcamLR riceve l'audio del telefono, lo decodifica con il decodificatore AAC di Windows, lo mette a
  tempo con il video e mostra il livello. Lo manda a un'**uscita audio scelta**. Con un **cavo audio virtuale che l'utente
  ha già** (VB-CABLE, Voicemeeter, Virtual Audio Cable: mai inclusi in WebcamLR) le app di chiamata e OBS lo ricevono come
  microfono. Gratis per tutti, non è di WebcamLR Pro.
- **Il microfono «WebcamLR (microfono)» vero**, che compare da solo in tutte le app come sul Mac, su Windows richiede un
  **driver audio in modalità kernel firmato da Microsoft**. Non esiste un'API in modalità utente per crearlo (verificato
  a ottobre 2026, fonti sotto). Il driver non è incluso: qui sotto ci sono il progetto e i passi per la firma, con i costi.

## 1. Ricerca: perché serve un driver firmato

### Non c'è un modo in modalità utente

| Strada | Cosa fa davvero | Va bene per un microfono che le app vedono? |
|---|---|---|
| `MFCreateVirtualCamera` (Windows 11) | Crea una webcam virtuale da un'app, senza driver. È quella che WebcamLR usa per la webcam | **No**: esiste solo per il video. Non c'è un equivalente per l'audio |
| Audio Processing Object (APO) | Effetti in modalità utente sul flusso di un dispositivo **già esistente**; si installa con l'INF del driver | **No**: non crea un dispositivo nuovo, e va comunque installato e firmato come pacchetto driver |
| Windows Studio Effects | Effetti (sfocatura, voce) sulla fotocamera e sul microfono veri, con l'NPU | **No**: nessun dispositivo virtuale |
| ACX (Audio Class Extensions) | Il modello nuovo per i driver audio | **No**: è costruito su KMDF, cioè **in modalità kernel** («ACX is built using KMDF and not UMDF», documentazione ACX) |
| UMDF (driver in modalità utente) | Driver per molte classi di dispositivi | **No** per l'audio: il motore audio di Windows elenca solo i dispositivi del kernel (KS/PortCls/ACX) |
| Novità 2025–2026 (Insider) | Permessi del microfono per app, «audio condiviso» Bluetooth LE | **No**: nessuna API per un ingresso audio virtuale |

Conclusione: per un ingresso audio che le app di chiamata elencano serve un driver audio (WDM/PortCls come SysVAD, o ACX),
cioè **un driver in modalità kernel**. È anche quello che fanno VB-CABLE, Voicemeeter e Virtual Audio Cable: hanno un
driver firmato. Anche gli SDK commerciali «in modalità utente» (per esempio Thesycon TVirtAudio) consegnano in realtà un
driver kernel firmato che si comanda da un'API.

### La firma: su Windows 11 con Secure Boot solo driver firmati da Microsoft

- Da Windows 10 1607, con **Secure Boot attivo** (il caso normale), Windows **non carica driver kernel nuovi che non siano
  firmati dal portale per sviluppatori di Microsoft** (Partner Center, Hardware Dev Center). Un certificato nostro, anche
  costoso, da solo non basta.
- La «modalità di test» (`bcdedit /set TESTSIGNING ON`) funziona solo spegnendo Secure Boot: va bene sul PC di prova, non
  per gli utenti.
- Due strade di firma Microsoft:
  - **Firma ad attestazione** (*attestation signing*): si carica il driver in Partner Center, Microsoft lo firma dopo
    controlli automatici, senza i test HLK. Il driver firmato così si carica su **Windows 10 e 11 desktop** (non su Windows
    Server) e non si pubblica su Windows Update per il pubblico: lo installa il nostro installatore. Nella versione del
    23/03/2026 della pagina «Driver signing options» Microsoft la presenta come firma **«per gli scenari di prova»**: oggi
    funziona, ma per un prodotto al pubblico la strada che Microsoft indica è la seconda.
  - **WHCP con i test HLK** (Windows Hardware Compatibility Program): si passano i test del Windows Hardware Lab Kit (gratis,
    ma servono un PC di prova, un controller HLK e tempo) e si carica il risultato. Vale per tutte le versioni di Windows.
- Per tutte e due servono l'**iscrizione al Windows Hardware Developer Program** (gratuita nella documentazione, con un
  tenant Microsoft Entra ID, anche creato gratis durante l'iscrizione, e i dati dell'azienda o un D-U-N-S) e un
  **certificato di firma EV** (*Extended Validation*) da una di queste autorità: Certum, DigiCert, GlobalSign, IdenTrust,
  Sectigo, SSL.com. Azure Trusted Signing **non** è accettato per il programma Hardware (risposta Microsoft Q&A, aprile 2026).
- Con Windows 11 l'«Integrità della memoria» (HVCI) è attiva di serie: il driver deve esserne compatibile (niente memoria
  eseguibile e scrivibile insieme, pool non eseguibili). I campioni Microsoft recenti lo sono.

### Il campione di partenza: SysVAD è MS-PL, non MIT

Il campione Microsoft per un dispositivo audio virtuale è **SysVAD** (`audio/sysvad` in `microsoft/Windows-driver-samples`),
con la variante più piccola **Simple Audio Sample** (`audio/simpleaudiosample`: un altoparlante e un microfono, WaveRT).
La licenza della repository è la **Microsoft Public License (MS-PL)**, non MIT: è permissiva e non è GPL. Si può usare in un
prodotto chiuso; chi distribuisce il **sorgente** dei file derivati deve farlo sotto MS-PL con l'avviso, chi distribuisce
solo il binario deve mantenere gli avvisi e non può distribuirlo con una licenza che contraddica la MS-PL. Va bene per
WebcamLR (nessuna libreria GPL), con un file `LICENZE-TERZE.md` accanto al driver.

### Fonti

learn.microsoft.com non era raggiungibile da questo ambiente: le pagine di Microsoft sono state lette dal loro sorgente
ufficiale su GitHub (`MicrosoftDocs/windows-driver-docs`), con la data `ms.date` indicata.

- Driver signing options (ms.date 23/03/2026) — https://learn.microsoft.com/windows-hardware/drivers/dashboard/driver-signing-offerings
  (sorgente: https://github.com/MicrosoftDocs/windows-driver-docs/blob/staging/windows-driver-docs-pr/dashboard/driver-signing-offerings.md)
- Attestation sign Windows drivers (ms.date 15/07/2025) — https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-attestation
- Driver code signing requirements, EV (ms.date 29/05/2025) — https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-reqs
- Register for the Hardware Developer Program (ms.date 11/08/2026) — https://learn.microsoft.com/windows-hardware/drivers/dashboard/hardware-program-register
- Driver Signing Policy, Windows 10 1607 e Secure Boot (ms.date 19/08/2024) — https://learn.microsoft.com/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-
- ACX, Audio Class Extensions overview — https://github.com/MicrosoftDocs/windows-driver-docs/blob/staging/windows-driver-docs-pr/audio/acx-audio-class-extensions-overview.md
- SysVAD e Simple Audio Sample — https://github.com/microsoft/Windows-driver-samples/tree/main/audio/sysvad ,
  https://github.com/microsoft/Windows-driver-samples/tree/main/audio/simpleaudiosample ; licenza MS-PL:
  https://github.com/microsoft/Windows-driver-samples/blob/main/LICENSE
- Azure Trusted Signing non accettato per il programma Hardware (Microsoft Q&A, 2026) — https://learn.microsoft.com/en-us/answers/questions/5866910/hardware-program-verification-using-azures-trusted
- Un ingresso audio per app non modificate non si fa in modalità utente (forum OSR) — https://community.osr.com/t/is-a-user-mode-virtual-mic-speaker-driver-based-on-sysvad-possible/55395
- SDK commerciale con driver kernel firmato — https://www.thesycon.de/eng/virtual_audiodriver.shtml
- Novità Insider 2026 (nessuna API per l'audio virtuale) — https://blogs.windows.com/windows-insider/2026/03/20/announcing-windows-11-insider-preview-build-28020-1743-canary-channel/
- Acquisizione audio per applicazione in OBS (OBS 28+, Windows 10 2004 o successivo) — https://obsproject.com/kb/application-audio-capture-guide
- Prezzi indicativi dei certificati EV (rivenditori, 2026) — https://sslinsights.com/digicert-vs-sectigo-code-signing/ ,
  https://www.ssldragon.com/ssl-certificates/code-signing/extended-validation/

## 2. Come funziona adesso (W2)

```
telefono ──(pacchetti tipo 3, AAC-LC, cifrati)──▶ SessioneComputer ─▶ MicrofonoTelefono (WebcamLR.Ricevitore)
                                                                        │ DecodificatoreAac (Media Foundation)
                                                                        │ RicampionatoreAudio → 48 kHz mono
                                                                        │ TempiAudio: cattura + ritardo del video
                                                                        ▼
                                                              AnelloAudio (buffer anti-jitter, 683 ms)
                                                                        │ letto 20 ms dietro «adesso»,
                                                                        │ passo ±0,5% per la deriva della scheda
                                                                        ▼
                                                    UscitaAudio (WASAPI) ─▶ «CABLE Input» ─▶ Zoom, Teams, Meet, OBS
```

| Pezzo | Dove | Cosa fa |
|---|---|---|
| Sessione | `Windows/WebcamLR.Ricevitore/SessioneComputer.cs` | Passa `formato-audio` (nei limiti, `ValoriSicuri`) e i pacchetti di tipo 3, con la differenza degli orologi del `pong` più rapido (`ScartoOrologi`) e la latenza del video (`LatenzaVideoMs`). Conta i pacchetti audio al secondo nelle statistiche |
| Logica | `Windows/WebcamLR.Ricevitore/AudioTelefono.cs`, `MicrofonoTelefono.cs` | La stessa del Mac (`MicrofonoTelefono.swift`, `CollegamentoMicrofono.c`): linea del tempo comune in campioni a 48 kHz, frame puntuali attaccati (tolleranza 10 ms), parte in ritardo scartata, dissolvenze di 128 campioni su buchi e sovrapposizioni, ritardo = latenza del video tra 60 e 300 ms con isteresi di 20 ms, livello RMS da −60 a 0 dB. Provata in `MicrofonoTest.cs` |
| Decodificatore | `Windows/WebcamLR.Microfono/DecodificatoreAac.cs` | «Microsoft AAC Audio Decoder MFT» di Windows (componente di sistema, nessuna libreria esterna, niente GPL). Frame grezzi (`MF_MT_AAC_PAYLOAD_TYPE` = 0), con l'AudioSpecificConfig del telefono in `MF_MT_USER_DATA`. Uscita float se c'è, altrimenti PCM 16 bit |
| Uscita | `Windows/WebcamLR.Microfono/UscitaAudio.cs` | WASAPI condiviso, 48 kHz mono float, Windows converte per la scheda (`AUTOCONVERTPCM`); thread suo svegliato a ogni periodo; elenco delle uscite con i nomi di Windows |
| Finestra | `Windows/WebcamLR.App/MainWindow.Microfono.cs`, riga in `MainWindow.xaml` | Interruttore, livello (12 tacche, le ultime due ambra), stato «spento/attivo» (verde solo quando l'audio arriva), nota onesta, tendina «Manda l'audio a», link a questa guida. Testi in `StatoMicrofono.cs` |

Differenze dal Mac:

- **Chi legge sta 20 ms dietro «adesso»**: la scheda audio chiede un periodo (circa 10 ms) alla volta e ogni campione
  richiesto deve essere già al suo posto. La voce si sente quindi 20 ms più il buffer della scheda (circa 10–20 ms) dopo il
  momento scelto: meno di un fotogramma.
- **Deriva dell'orologio**: sul Mac il driver usa lo stesso orologio del sistema. Su Windows la scheda audio (anche un cavo
  virtuale) ha il suo. Chi legge confronta la sua posizione con «adesso» (media mobile) e regola il passo al massimo dello
  0,5% (inaudibile sulla voce); oltre 50 ms di distanza salta. Il test simula una deriva dello 0,1% per dieci minuti.
- **Uscita scelta**: di serie il **primo cavo audio virtuale** trovato, altrimenti **nessuna** (solo il livello). Mai gli
  altoparlanti da soli: con il telefono vicino al PC farebbero eco e fischi. La scelta resta salvata
  (`%LOCALAPPDATA%\WebcamLR\microfono-uscita`; vuoto = «nessuna»).
- Il microfono segue il telefono nella webcam (P21), come sul Mac: il telefono di prima riceve `comando.audio = false`.
  L'audio si chiede con `comando.audio = true` appena il telefono dichiara `capacita.audio`; se lo si spegne sul telefono
  (`stato.audio`), l'interruttore del PC lo segue.

## 3. Usarlo nelle app di chiamata e in OBS

### Con un cavo audio virtuale (consigliato)

WebcamLR non include nessun cavo virtuale e non lo installa: ognuno ha la sua licenza (VB-CABLE è *donationware* e non si
può ridistribuire). Chi ne ha già uno lo usa così:

1. Se non ce l'hai: **VB-CABLE** da https://vb-audio.com/Cable/ → estrai lo zip → clic destro su
   `VBCABLE_Setup_x64.exe` → **Esegui come amministratore** → **Install Driver** → riavvia il PC.
2. In WebcamLR, colonna sinistra → **Uscite** → **Microfono del telefono**: accendi l'interruttore. In **Manda l'audio a**
   scegli **CABLE Input (VB-Audio Virtual Cable)** (di solito è già scelto).
3. Nell'app di chiamata scegli come **microfono** **CABLE Output (VB-Audio Virtual Cable)** (la nota sotto l'interruttore
   scrive il nome giusto):
   - **Zoom**: Impostazioni → Audio → Microfono.
   - **Teams**: Impostazioni → Dispositivi → Microfono.
   - **Meet** (Chrome/Edge): ⋮ → Impostazioni → Audio → Microfono.
4. Non impostare «CABLE Input» come uscita predefinita di Windows: tutti i suoni del PC finirebbero nella chiamata.
5. Con **Voicemeeter**: in WebcamLR scegli **Voicemeeter Input**, nell'app di chiamata **Voicemeeter Output** (o il bus che
   usi). Con **Virtual Audio Cable**: «Line 1» da tutte e due le parti.

### In OBS

- **Con il cavo**: Fonti → **+** → **Cattura ingresso audio** (*Audio Input Capture*) → dispositivo **CABLE Output**.
- **Senza cavo, solo WebcamLR** (OBS 28 o successivo, Windows 10 2004 o successivo): in WebcamLR scegli un'uscita qualsiasi
  (meglio le **cuffie**: non fanno eco), poi in OBS Fonti → **+** → **Cattura audio applicazione (BETA)** (*Application Audio
  Capture*) → finestra **WebcamLR**. OBS prende solo l'audio di WebcamLR.
- **Senza cavo, tutta un'uscita**: Fonti → **+** → **Cattura uscita audio** (*Audio Output Capture*) → l'uscita scelta in
  WebcamLR. Prende anche gli altri suoni che vanno a quell'uscita.
- In OBS il video della webcam WebcamLR e l'audio arrivano già allineati; se serve, Proprietà audio avanzate → **Ritardo
  di sincronizzazione**.

## 4. Il driver «WebcamLR (microfono)» (più avanti, non incluso)

Niente codice del driver nella repository finché non si decide di pagare la firma: non si compila qui (serve Windows con
Visual Studio e il WDK) e non si potrebbe nemmeno provare senza firma con Secure Boot attivo. Qui il progetto, pronto.

### Forma

```
WebcamLR.exe ── MicrofonoTelefono scrive nell'anello (stessa forma di AnelloMicrofono.h) ──┐
                                                                                            │ memoria condivisa
          IOCTL «dammi la memoria» sull'interfaccia di controllo del driver ───────────────┤ (MDL bloccata dal driver)
                                                                                            ▼
webcamlr-microfono.sys (WDM/PortCls, da Simple Audio Sample) ── WaveRT, un solo ingresso 48 kHz mono ──▶ Zoom, Teams, OBS
```

1. **Base**: `audio/simpleaudiosample` (un altoparlante e un microfono, WaveRT, componentizzato), tenendo solo il microfono.
   Nome del dispositivo «WebcamLR (microfono)», ID hardware `Root\WebcamLR_Microfono`. Formati: 48 kHz, mono, 16 bit e float.
2. **Al posto del generatore di tono** del campione (`ToneGenerator`, che il campione usa per «catturare»): la lettura della
   memoria condivisa, come `DoIOOperation` nel driver del Mac. Il flusso WaveRT calcola la posizione da
   `KeQueryPerformanceCounter`: la stessa base di `Stopwatch` in .NET, quindi la **stessa linea del tempo** dell'app
   (indice = microsecondi × 48 / 1000) e nessuna deriva. Dove l'app non ha scritto: ultimo valore portato a zero in 64
   campioni, come sul Mac.
3. **La memoria condivisa**: l'app la alloca (la stessa struttura di `Mac/Microfono/Comune/AnelloMicrofono.h`: magia
   «WLRM», versione, frequenza, capacità 32768, `fine`, `ultimaScrittura`, `ultimaLettura`, campioni float) e la passa al
   driver con un IOCTL sull'interfaccia di controllo (GUID nostro, `IoRegisterDeviceInterface`). Il driver la blocca con
   una MDL (`MmProbeAndLockPages`, `MmGetSystemAddressForMdlSafe`) e la lascia alla chiusura dell'handle
   (`IRP_MJ_CLEANUP`). Controlli: dimensione esatta, magia e versione; il driver legge e non scrive (tranne `ultimaLettura`).
   Il descrittore di sicurezza dell'interfaccia (SDDL) la apre solo agli utenti interattivi.
   È lo schema del Mac (l'aiutante lì serve per il sandbox di coreaudiod, qui non serve).
4. **Lato app**: `AnelloAudio` diventa un'interfaccia con due realizzazioni, quella in memoria di oggi e quella condivisa.
   Con il driver presente l'uscita WASAPI non serve: il driver legge direttamente. La riga torna quella del Mac: *non
   installato*, *spento*, *attivo*, *in uso* (da `ultimaLettura` recente, o dalle sessioni audio del dispositivo).
5. **Installazione**: `WebcamLR.Setup` già chiede l'amministratore una volta per la webcam. Si aggiunge: `pnputil
   /add-driver webcamlr-microfono.inf /install` e la creazione del dispositivo «root» (come `devcon install`:
   `SetupDiCreateDeviceInfo` + `DIF_REGISTERDEVICE` + `UpdateDriverForPlugAndPlayDevicesW`). Disinstallazione: togliere il
   dispositivo, poi `pnputil /delete-driver oemNN.inf /uninstall`.
6. **Prove prima di firmare**: un PC di prova con Secure Boot spento e `bcdedit /set TESTSIGNING ON`, Driver Verifier
   acceso sul driver, «Integrità della memoria» accesa, CodeQL / Static Driver Verifier del WDK.

### Firma: i passi per Ledion

1. **Certificato EV di firma del codice** a nome della ditta (Certum, DigiCert, GlobalSign, IdenTrust, Sectigo o SSL.com).
   La chiave sta su una chiavetta hardware o in un servizio cloud dell'autorità. Serve un'attività registrata (partita IVA):
   l'EV verifica l'organizzazione. Alcune autorità (per esempio SSL.com) offrono l'EV anche alle ditte individuali:
   **da verificare con l'autorità prima di comprare**. Tempi: da qualche giorno a due settimane per la verifica.
2. **Partner Center**: https://partner.microsoft.com → iscrizione al **Windows Hardware Developer Program** con un account
   Microsoft Entra ID (si crea gratis durante l'iscrizione), i dati della ditta (o il D-U-N-S, gratuito) e la prova con il
   certificato EV (si firma un file che Partner Center fornisce).
3. **Compilare** il driver in Release per x64 e ARM64 (Visual Studio 2022 + WDK) e preparare il **CAB**: una cartella per
   architettura con `.inf`, `.sys` (e `.cat` se c'è), un file `.ddf` e `MakeCab /f webcamlr-microfono.ddf` (cartelle con
   nomi semplici, meno di 40 caratteri, niente percorsi di rete).
4. **Firmare il CAB** con il certificato EV: `signtool sign /fd sha256 /tr <timestamp dell'autorità> /td sha256 /a webcamlr-microfono.cab`.
5. Partner Center → **Hardware** → **Submit new hardware** → carica il CAB → nome → **Requested signatures**: Windows 10/11
   client x64 e ARM64 → **lasciare spente** le opzioni di firma di test → invia. Dopo minuti o qualche ora: **Download
   signed files**.
6. **Verificare**: `signtool verify /kp /v webcamlr-microfono.sys` (catena fino a «Microsoft Windows Hardware Compatibility
   Publisher») e installazione su un Windows 11 pulito con Secure Boot e Integrità della memoria accesi: nessun avviso
   «Windows non può verificare l'autore».
7. Il driver firmato va nell'installatore `WebcamLR-Setup` (non su Windows Update). **Ogni modifica del driver è un nuovo
   invio.** L'app e l'installatore si firmano a parte (Pubblicazione.md, sezione 7).
8. Più avanti, per la strada che Microsoft indica per il pubblico: **WHCP con HLK** (Windows HLK gratis, un PC di prova e
   un controller; il driver deve passare i test della classe audio).

### Costi

| Voce | Costo | Note |
|---|---|---|
| Certificato EV | circa 290–690 USD l'anno (prezzi dei rivenditori nel 2026: Sectigo da circa 290, DigiCert 515–685), più la chiavetta o il servizio cloud | Dal 1° marzo 2026 i certificati durano al massimo 460 giorni: niente più sconti su tre anni |
| Windows Hardware Developer Program | nessuna quota indicata nella documentazione Microsoft | Serve il certificato EV per iscriversi |
| Firma ad attestazione | inclusa | Per Windows 10/11 desktop; Microsoft la chiama «per gli scenari di prova» (2026) |
| WHCP con HLK | strumenti gratuiti | Tempo: giorni di prove e un PC dedicato |
| Strumenti di sviluppo | gratuiti | Visual Studio Community 2022 + WDK |
| Alternativa: SDK commerciale con driver già firmato (Thesycon TVirtAudio) | su preventivo | Licenza per prodotto; niente firma nostra |

Consiglio: tenere per ora la strada del cavo virtuale (funziona oggi, gratis, onesta nella finestra). Il driver vale la
spesa quando WebcamLR per Windows ha utenti che lo chiedono: allora EV + attestazione per partire, WHCP dopo.

## 5. Limiti noti e cose da verificare su Windows

- Il codice di Media Foundation e WASAPI è scritto su Linux: compila, ma gira solo su Windows. Da provare: che il
  decodificatore AAC accetti la configurazione (`EYg=`) e dia l'uscita float, e che WASAPI accetti 48 kHz mono float con la
  conversione automatica su ogni scheda (anche VB-CABLE e Voicemeeter).
- Il decodificatore AAC può aggiungere un ritardo fisso (*priming*). Se la prova del battito di mani mostra la voce sempre
  in ritardo, si corregge `TempiAudio.CorrezioneDecodifica`.
- Il ricampionamento (da 44,1 kHz o stereo) usa l'interpolazione cubica senza filtro: va bene per la voce; i telefoni
  mandano 48 kHz mono.
- Se l'uscita scelta sparisce (cuffia staccata, cavo disinstallato), la nota dice «Uscita audio non disponibile: …»: scegli
  un'altra uscita o riaccendi l'interruttore. L'elenco si rilegge a ogni apertura della tendina.
- Con le uscite di «Comunicazioni» Windows può abbassare gli altri suoni durante le chiamate: Impostazioni audio → Altre
  impostazioni → Comunicazioni → «Non fare nulla».
