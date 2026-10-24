# Compatibilità della webcam virtuale · chi la vede e a quali condizioni

Ricerca di ottobre 2026. Estende `Documenti/Ricerca utenti e concorrenti.md`, che indicava già il problema (il nuovo Teams e le webcam virtuali DirectShow, l'ordine di avvio), ma non verificava come ogni app e ogni browser cercano le fotocamere. Qui la domanda è una sola: **la webcam virtuale di WebcamLR verrà vista come una webcam vera?**

Avvertenza sul metodo: Reddit, obsproject.com, eclecticlight.co e help.webex.com non erano raggiungibili direttamente da questo ambiente. Per quelle fonti le informazioni vengono da estratti dei motori di ricerca. Il codice di Chromium e il README di VCamSample (Microsoft MVP Simon Mourier) li ho invece letti per intero. Dove una cosa è dedotta e non documentata, lo scrivo.

## In breve

1. **Mac**: la Camera Extension (CoreMediaIO, macOS 12.3+) è l'unica strada ancora viva. Dal macOS 14.1 i vecchi plug-in DAL non vengono più caricati. Una Camera Extension gira in un processo separato, quindi le app con «hardened runtime» (FaceTime, Teams, Zoom, Safari) non devono caricare codice estraneo, e la vedono come una camera qualunque. Serve l'**account sviluppatore a pagamento**, e l'utente la deve approvare una volta nelle Impostazioni di Sistema.
2. **Windows 11**: con `MFCreateVirtualCamera` la camera entra nel **Frame Server** di Windows ed è vista come una camera hardware. La vedono l'app Fotocamera, Chrome/Edge, OBS e Firefox (prove di VCamSample). Il nuovo Teams la mostra in anteprima. Le prove documentate segnalano però un caso in cui l'altra persona non riceveva il video: va provato per primo.
3. **Chromium (Chrome, Edge, WebView2, e quindi Meet, Slack, WhatsApp Windows nuovo)** usa Media Foundation come predefinito e **aggiunge in coda i dispositivi che esistono solo in DirectShow**. Nei browser Chromium funzionano quindi tutte e due le strade.
4. Un **filtro DirectShow** (come OBS Virtual Camera) **non** compare nell'app Fotocamera di Windows, nelle app WinRT/UWP e nell'elenco Impostazioni → Fotocamere. Il nuovo Teams è segnalato come inaffidabile con quei filtri. Il filtro DirectShow serve solo come strada di riserva per Windows 10.
5. **Windows 10**: `MFCreateVirtualCamera` non esiste: `mfsensorgroup.dll` non esporta la funzione. Il supporto di Windows 10 è finito il 14 ottobre 2025 (ESU consumer fino al 13 ottobre 2026, forse esteso: vedi sotto). Consiglio: Windows 10 solo con un filtro DirectShow e un avviso chiaro, mai con un driver kernel.
6. **Audio**: né la Camera Extension né `MFCreateVirtualCamera` portano audio. Il microfono virtuale è un lavoro separato. Sul Mac basta un Audio Server Plug-in, senza estensione di sistema. Su Windows serve un driver audio in modalità kernel firmato da Microsoft: è la parte più costosa di tutto il progetto.

## 1. Come cercano le fotocamere i browser

| Browser | Windows | Mac | Vede una camera MF (`MFCreateVirtualCamera`) | Vede un filtro DirectShow |
|---|---|---|---|---|
| **Chrome / Edge / Opera / Brave** (Chromium) | Media Foundation predefinito, più i dispositivi solo DirectShow | AVFoundation | **Sì** | **Sì** (aggiunto in coda) |
| **WebView2** (nuovo Teams per l'interfaccia, WhatsApp Windows dal 2025, molte app) | come Chromium | — | Sì | Sì, se l'app usa `getUserMedia` (vedi Teams) |
| **Firefox** | DirectShow (libwebrtc) | AVFoundation | Sì su Windows 11 (provato con VCamSample, dedotto via Frame Server) | **Sì** |
| **Safari** | — | AVFoundation | — | — |

**Chromium, verificato nel codice.** `media/base/media_switches.cc` ha `BASE_FEATURE(kMediaFoundationVideoCapture, base::FEATURE_ENABLED_BY_DEFAULT)`. `video_capture_device_factory_win.cc` contiene la funzione `AugmentDevicesListWithDirectShowOnlyDevices` con il commento: «DirectShow virtual cameras are not supported by MediaFoundation. To overcome this, based on device name and model, we append missing DirectShow device descriptor to full devices list» ([media_switches.cc](https://github.com/chromium/chromium/blob/main/media/base/media_switches.cc); [video_capture_device_factory_win.cc](https://github.com/chromium/chromium/blob/main/media/capture/video/win/video_capture_device_factory_win.cc)). Per un dispositivo che elenca formati solo in DirectShow, Chromium passa a DirectShow ([commit Chromium](https://chromium.googlesource.com/chromium/src.git/+/3772661191b045df5ed2df7aa6fde0a787967fae)). **Conseguenza: Google Meet, Teams nel browser, Zoom web, Discord web, webcamtests.com e qualsiasi sito vedono la webcam di WebcamLR in Chrome ed Edge, che sia MF o DirectShow.**

Un'eccezione da conoscere: in un caso segnalato su VCamSample, webcamtests.com dava «busy or blocked» in Chrome finché non si disattivava la cattura Media Foundation di Chrome. L'autore non è riuscito a riprodurlo né in Chrome, né in Edge, né in Firefox ([VCamSample #13](https://github.com/smourier/VCamSample/issues/13)). Va nella procedura di prova.

**Firefox su Windows** usa il modulo di cattura DirectShow di libwebrtc. L'autore di VCamSample l'ha provato con la sua camera MF senza problemi ([VCamSample #13](https://github.com/smourier/VCamSample/issues/13)). Che una camera del Frame Server compaia anche in DirectShow lo conferma anche OBS: la sua sorgente «Dispositivo di acquisizione video» è DirectShow e vede VCamSample ([README VCamSample](https://github.com/smourier/VCamSample)). È una deduzione, non una garanzia scritta da Microsoft: **va provata con Firefox e OBS**.

**Su Mac** tutti i browser usano AVFoundation, che elenca le Camera Extension come camere normali: niente differenze tra Chrome, Firefox e Safari.

## 2. App per app

Legenda: ✅ funziona per costruzione o da prove documentate · 🟡 probabile, da provare · ⚠️ problemi noti · ❌ non funziona.

| App | Mac (Camera Extension) | Windows 11 (MF, Frame Server) | Windows 10 (filtro DirectShow) | Note e fonti |
|---|---|---|---|---|
| **Google Meet e siti web** (Chrome, Edge) | ✅ | ✅ | ✅ | Chromium unisce MF e DirectShow (sopra) |
| **Siti in Firefox** | ✅ | 🟡 (provato da VCamSample) | ✅ | |
| **Siti in Safari** | ✅ | — | — | |
| **Zoom** | ✅ | 🟡 | ✅ | Sul Mac Zoom bloccava i plug-in DAL non firmati ([UCLA](https://dts.ucla.edu/news/virtual-camera-support-zoom-macos)); con le Camera Extension il problema non c'è più. Su Windows OBS (DirectShow) funziona; per le camere MF non ho trovato prove dirette su Zoom |
| **Microsoft Teams (nuovo)** | 🟡 | 🟡 ⚠️ | ⚠️ | Il nuovo Teams ha l'interfaccia in WebView2, ma per le chiamate usa un motore multimediale proprio (SlimCore, documentato per il VDI) ([Microsoft Learn](https://learn.microsoft.com/azure/virtual-desktop/teams-on-avd)). Filtri DirectShow: un solo fotogramma o niente ([forum OBS](https://obsproject.com/forum/threads/new-teams-cant-capture-the-virtual-camera.171102/)). Camera MF: in VCamSample visibile in anteprima ma «non arriva all'altra persona», causa ignota ([README VCamSample](https://github.com/smourier/VCamSample)). NVIDIA Broadcast ha dovuto aggiungere una «compatibilità Teams» specifica ([NVIDIA](https://www.nvidia.com/en-gb/geforce/broadcasting/broadcast-app/release-notes/)). **È la prova più importante** |
| **Teams nel browser** | ✅ | ✅ | ✅ | ripiego affidabile se l'app desktop fa capricci |
| **WhatsApp desktop** | 🟡 | 🟡 → ✅ con la versione WebView2 | ⚠️ | La vecchia app UWP non vedeva OBS Virtual Camera (DirectShow) ma vedeva DroidCam (driver) ([forum OBS](https://obsproject.com/forum/threads/obs-virtual-cam-is-not-working-with-whatsapp-desktop-app.144629/)). Da luglio 2025 WhatsApp per Windows passa a WebView2 ([Neowin](https://www.neowin.net/news/whatsapp-for-windows-is-ditching-uwp-for-a-web-app/); [Notebookcheck](https://www.notebookcheck.net/WhatsApp-ditches-native-Windows-11-app-in-favor-of-Microsoft-WebView2.1063682.0.html)), quindi dovrebbe comportarsi come Chromium (deduzione). Mac: app nativa AVFoundation, da provare |
| **FaceTime, Photo Booth, QuickTime** | ✅ | — | — | Con i DAL FaceTime e Photo Booth non funzionavano ([VDO.Ninja](https://docs.vdo.ninja/common-errors-and-known-issues/virtual-cam-not-working-on-mac); [OBS #3967](https://github.com/obsproject/obs-studio/issues/3967)). Le Camera Extension sono state create proprio per essere «compatibili con qualsiasi app che usa una fotocamera» ([WWDC22 10022](https://developer.apple.com/videos/play/wwdc2022/10022/)); con OBS 30+ FaceTime e QuickTime funzionano ([forum OBS](https://obsproject.com/forum/threads/no-virtual-cam-obs-30-0-0-or-30-0-2-with-final-cut-pro-on-mac-14-2-1.172385/)) |
| **Final Cut Pro** | ⚠️ | — | — | Non elenca OBS Virtual Camera nemmeno con la Camera Extension (segnalazione di un utente, causa non confermata) |
| **Discord** | 🟡 | 🟡 | ✅ ⚠️ | Desktop a volte non vede camere che il web vede ([forum OBS](https://obsproject.com/forum/threads/discord-desktop-app-completely-refusing-to-pick-up-obs-virtual-cam.187674)); casi di crash con OBS VirtualCam ([forum OBS](https://obsproject.com/forum/threads/using-the-virtual-camera-makes-programs-like-discord-crash.136606/)) |
| **Skype** | — | — | — | Chiuso il 5 maggio 2025, sostituito da Teams Free ([Microsoft](https://support.microsoft.com/skype/)) |
| **Webex** | ⚠️ dipende dall'amministratore | ✅ | ✅ | Sul Mac le camere virtuali di terze parti si possono disattivare da Control Hub; su Windows sono sempre permesse ([Webex Help](https://help.webex.com/en-us/article/njflt38/Configure-Virtual-Cameras-for-Calls-and-Meetings-in-Webex-Control-Hub)). Da verificare se Webex tratta una Camera Extension come «virtuale» |
| **Slack (huddle)** | ✅ (Electron/Chromium) | ✅ | ✅ | stesso motore di Chrome (deduzione) |
| **OBS Studio** | ✅ | ✅ | ✅ | provato con VCamSample (sorgente DirectShow di OBS) |
| **App Fotocamera di Windows** | — | ✅ | ❌ | usa solo MF/WinRT: vede VCamSample ([README](https://github.com/smourier/VCamSample)) ma non i filtri DirectShow ([AlterCam](https://altercam.com/articles/obs-virtual-camera.html)) |
| **Snap Camera** | — | — | — | Chiusa il 25 gennaio 2023; resta Snapchat per il Web, che usa la camera del browser ([TechCrunch](https://techcrunch.com/2023/01/05/snap-is-shutting-down-its-desktop-camera-app-that-allows-users-to-apply-filters-during-video-calls)) → come un sito |
| **TikTok LIVE Studio** (Windows) | — | 🟡 | ✅ | aggiunge una sorgente «Fotocamera» e vede OBS Virtual Camera ([guida Tiktory](https://help.tiktory.com/en/pages/how-to-setup-obs-virtual-camera-with-tiktok-live-studio); [ManyCam](https://help.manycam.com/knowledge-base/tiktokstudio/)) |
| **Instagram Live** | — | — | — | Non esiste uno studio desktop: da computer si trasmette con chiave RTMP da OBS, quindi WebcamLR va in OBS |

## 3. Mac: Camera Extension

### DAL e Camera Extension

- Le Camera Extension (CoreMediaIO Extensions) sono arrivate con macOS 12.3 e sostituiscono i plug-in DAL. I DAL caricavano codice non fidato dentro il processo dell'app, «rendendola vulnerabile ai crash» ([WWDC22 10022](https://developer.apple.com/videos/play/wwdc2022/10022/)). Per lo stesso motivo le app con hardened runtime o library validation (FaceTime, Teams, Zoom per un periodo) li rifiutavano.
- **Dal macOS Sonoma 14.1 «sono supportate solo le camere e le uscite video che usano estensioni di sistema moderne»**. I DAL si riattivano solo dalla modalità di recupero con `system-override legacy-camera-plugins-without-sw-camera-indication=on`, e allora sparisce l'indicatore della camera nella barra dei menu ([Apple HT213969](https://support.apple.com/HT213969)). La rimozione era prevista per il 14.0 ed è stata rinviata al 14.1 ([Eclectic Light](https://eclecticlight.co/2023/10/27/how-sonoma-14-1-could-stop-your-camera-working/)).
- WebcamLR fa già la cosa giusta (`Mac/FotocameraVirtuale/`, `CMIOExtensionProvider`). Non c'è alcun motivo di scrivere un DAL.

### Firma, account e approvazione

- **Serve l'account sviluppatore a pagamento.** L'app contenitore deve dichiarare `com.apple.developer.system-extension.install`, un diritto «riservato» che va autorizzato da un profilo di provisioning ([Apple DTS](https://developer.apple.com/forums/thread/710046); [Apple Forums](https://developer.apple.com/forums/thread/793731)). La capability «System Extension» è dei membri del programma a pagamento ([tabella capability Apple](https://developer.apple.com/help/account/reference/supported-capabilities-macos)). Coincide con quanto già scritto nel CLAUDE.md: con l'Apple ID gratuito niente webcam virtuale.
- **Distribuzione fuori dall'App Store**: firma Developer ID e notarizzazione. Per attivare l'estensione **l'app deve trovarsi nella cartella Applicazioni** ([mimoLive](https://mimolive.com/user-manual/playout-output-destinations/virtual-camera/installing-and-activating-virtual-camera-extension)). Esiste `systemextensionsctl developer on` per caricarla da altre cartelle, ma richiede di disattivare SIP: non va proposto a Ledion.
- **Approvazione dell'utente** (una volta sola): da macOS 15 si trova in Impostazioni di Sistema → Generali → Elementi di login ed estensioni → Estensioni videocamera (ⓘ) → interruttore WebcamLR → Fine ([Meld Studio](https://meldstudio.co/docs/outputs/virtual-camera/macos/); [forum OBS](https://obsproject.com/forum/threads/macos-15-sequoia-beta-system-extensions-settings-moved.176958/)). Su macOS 13–14 passa da Privacy e sicurezza → «Consenti». La voce compare solo dopo che l'app ha chiesto l'attivazione ([forum OBS](https://obsproject.com/forum/threads/sequoia-15-0-and-obs.179883/)).
- **Per l'app**: un pulsante «Attiva la webcam virtuale» che chiama `OSSystemExtensionRequest.activationRequest`, intercetta `requestNeedsUserApproval` e apre direttamente quel pannello con una figura dei tre passi. Se l'app non è in Applicazioni, deve dirlo prima di tentare.
- **Disinstallazione**: per OBS gli utenti segnalano camere virtuali che restano negli elenchi dopo la disinstallazione ([forum OBS](https://obsproject.com/forum/threads/virtual-camera-still-showing-in-apps-even-after-uninstalling-plugins.174245/)). Serve un pulsante «Rimuovi la webcam virtuale» (`deactivationRequest`) prima di cestinare l'app.

### Effetti di sistema del Mac

Su Mac con Apple silicon il menu Effetti video (Ritratto, Luce studio, Reazioni) compare per molte camere. Da provare: se compare anche per «WebcamLR», chi usa il Mac li ha gratis e WebcamLR non li deve rifare (vedi `Idee nuove funzioni.md`).

## 4. Windows 11: `MFCreateVirtualCamera`

### Requisiti

| Requisito | Dettaglio | Fonte |
|---|---|---|
| Sistema | Windows 11, build 22000 o successiva. Le «sorgenti associate» richiedono la 22621 | [MFCreateVirtualCamera](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera); [Windows-Camera VirtualCamera](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera) |
| Media source COM | DLL registrata **in HKLM** (non HKCU, perché la caricano più processi), quindi installazione da amministratore | [README VCamSample](https://github.com/smourier/VCamSample) |
| Dove gira il codice | La DLL è caricata da **FrameServerMonitor** alla creazione e da **FrameServer** durante l'uso. Sono servizi di sistema (Local Service / Local System, sessione 0), **non** nel processo dell'app WebcamLR | [Windows-Camera](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera); [README VCamSample](https://github.com/smourier/VCamSample) |
| Permessi sui file | La DLL e le sue dipendenze devono essere leggibili da quei servizi. Una DLL in `C:\Users\…` dà «Access denied» su `IMFVirtualCamera::Start`. Va installata in `Program Files` e va tolto il «Mark of the Web» | [README VCamSample](https://github.com/smourier/VCamSample) |
| Dipendenze | Ogni DLL mancante fa fallire `CoCreateInstance` (MOD_NOT_FOUND). Microsoft consiglia il runtime C++ statico (`dumpbin /DEPENDENTS`) | [Windows-Camera](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera) |
| Durata | `Session`: sparisce quando l'oggetto viene rilasciato. `System`: resta fino al riavvio o alla rimozione (serve l'amministratore per tutti gli utenti); va ricreata all'avvio | [MFCreateVirtualCamera](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera) |
| Consenso | Creare la camera richiede il consenso fotocamera dell'app. Si può provocare prima con `MediaCapture`, e mai sul thread dell'interfaccia | [Windows-Camera](https://github.com/microsoft/Windows-Camera/tree/master/Samples/VirtualCamera) |
| App non pacchettizzata | VCamSample è un'app desktop normale e funziona: non serve MSIX | [README VCamSample](https://github.com/smourier/VCamSample) |
| Solo video | La camera virtuale MF non porta audio | [neon](https://github.com/newdee/neon) |

### Cosa cambia per l'architettura di WebcamLR

`Windows/FotocameraVirtuale/LEGGIMI.md` prevede che l'app passi i fotogrammi alla sorgente «tramite memoria condivisa». È corretto, con due attenzioni che vengono dalla sessione 0:

- La memoria condivisa va creata **con un descrittore di sicurezza che dia accesso a LOCAL SERVICE**, nel namespace `Global\` (che richiede SeCreateGlobalPrivilege, presente per i servizi ma non per l'utente normale). In alternativa la crea il lato servizio, oppure si usa una named pipe con ACL esplicita. Un oggetto con nome creato dall'app utente in `Local\` non è visibile dal FrameServer. È una deduzione dal modello di Windows: va verificato al primo prototipo.
- La sorgente deve **mostrare sempre qualcosa**, anche senza telefono collegato: un'immagine di attesa con «Apri WebcamLR sull'iPhone». Così l'ordine di avvio non conta, e Teams e Zoom vedono la camera anche se partono prima. Il progetto neon fa lo stesso con un riquadro grigio quando il produttore non c'è ([neon](https://github.com/newdee/neon)), e NVIDIA Broadcast mostra un'icona «camera in uso» invece del grigio ([NVIDIA](https://www.nvidia.com/en-gb/geforce/broadcasting/broadcast-app/release-notes/)).
- Formati da esporre: **NV12** (obbligatorio per molte app) e RGB32, a 1280×720 e 1920×1080, 30 e 60 fps. VCamSample espone NV12 e RGB32 ([README](https://github.com/smourier/VCamSample)).
- Durata `System` e ricreazione all'avvio di Windows (con l'opzione «Avvia con Windows», già prevista alla 0.8): la camera esiste sempre, anche prima che l'utente apra WebcamLR.

### Insidie note su Windows

1. **Privacy della fotocamera**: Impostazioni → Privacy e sicurezza → Fotocamera → «Accesso alla fotocamera», «Consenti alle app di accedere alla fotocamera» e soprattutto **«Consenti alle app desktop di accedere alla fotocamera»**. Se è spento, Zoom, Teams e Chrome non vedono niente ([UWaterloo](https://uwaterloo.atlassian.net/wiki/spaces/ISTKB/pages/44815942372/Fix+camera+and+microphone+not+working+in+Windows+11)). WebcamLR può leggere lo stato (`AppCapability` per la webcam, o le chiavi `HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam`) e mostrare il pulsante che apre `ms-settings:privacy-webcam`. Va nella diagnosi automatica (1.3).
2. **Elenchi in cache**: le app di chiamata elencano le camere all'avvio. Una camera che compare dopo resta invisibile finché l'app non viene chiusa del tutto, anche dalla barra di sistema ([CiCi Cam](https://cici-cam.com/blog/virtual-camera-not-showing-up/)). Contromisura: camera `System` sempre registrata. Se WebcamLR vede processi `ms-teams.exe`, `Zoom.exe` o `Discord.exe` avviati prima della registrazione, dice «Riavvia Teams per vedere WebcamLR».
3. **Nuovo Teams**: è la prova da fare per prima (sopra). Se la camera MF compare in anteprima ma l'altra persona non vede niente, bisogna controllare i formati (NV12 a 30 fps, timestamp monotoni, `MF_MT_FRAME_RATE` coerente). È l'ipotesi più probabile, non verificata.
4. **Camera condivisa tra più app**: dipende soprattutto da come l'app apre la camera ([VCamSample #13](https://github.com/smourier/VCamSample/issues/13)). Windows 11 24H2 aggiunge «Consenti a più app di usare la fotocamera contemporaneamente», disattivato per impostazione predefinita, in Impostazioni → Bluetooth e dispositivi → Fotocamere → Opzioni avanzate ([Windows Latest](https://www.windowslatest.com/2024/08/21/windows-11-24h2-will-finally-allow-multiple-apps-to-use-your-camera-at-the-same-time/)). Da provare con OBS e Meet aperti insieme.
5. **Aggiornamenti di Windows**: NVIDIA ha dovuto correggere la sua camera virtuale dopo il 24H2 ([NVIDIA](https://www.nvidia.com/en-gb/geforce/broadcasting/broadcast-app/release-notes/)). Ogni aggiornamento importante di Windows va ripassato con la procedura di prova.
6. **Crash del Frame Server** con due camere aperte: segnalato raramente su VCamSample ([VCamSample #4](https://github.com/smourier/VCamSample/issues)). Una sorgente che va in crash fa cadere il servizio per tutte le camere: il codice della media source deve essere minimo e robusto, senza decodifica dentro (la decodifica resta nell'app).
7. **Effetto specchio**: Zoom e Meet specchiano solo l'anteprima locale, mentre l'altra persona vede l'immagine giusta. Molti utenti credono che il video sia invertito ([forum OBS](https://obsproject.com/forum/threads/using-the-virtual-camera-makes-programs-like-discord-crash.136606/)). Basta una riga nelle domande frequenti.
8. **Disinstallazione pulita**: togliere la camera (`IMFVirtualCamera::Remove`) e poi la registrazione COM. Mai toccare la camera integrata: è la lamentela su Iriun già documentata.

### Come fanno i concorrenti su Windows

| Prodotto | Tecnica | Visibilità | Fonte |
|---|---|---|---|
| **OBS Virtual Camera** | Filtro DirectShow (user mode) | Non compare nell'app Fotocamera né in Impostazioni; Teams e Zoom di solito sì; nuovo Teams inaffidabile | [AlterCam](https://altercam.com/articles/obs-virtual-camera.html); [OBS #13439](https://obs-versions.com/community/issues/13439) |
| **DroidCam** | Driver kernel (AVStream/WDM) visto da Media Foundation | Anche le app dello Store e WhatsApp UWP | [forum OBS](https://obsproject.com/forum/resources/droidcam-virtual-output.1580/) |
| **iVCam / e2eSoft VCam** | Driver di camera virtuale (kernel); i problemi tipici sono la firma del driver e gli antivirus, fino a chiedere di disattivare l'Isolamento core | [e2eSoft](https://www.e2esoft.com/?p=126572) |
| **Iriun** | Driver proprio che può restare dopo la disinstallazione | [Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/4317114/laptop-camera-app-shows-please-turn-on-iriun-camer) |
| **Camo** | «Ultime API Microsoft», tecnica non dichiarata; dal 2025 anche nel Microsoft Store | [PR Newswire](https://prnewswire.co.uk/news-releases/camo-arrives-at-the-microsoft-store-on-windows-301942118.html) |
| **SplitCam** | Camere virtuali Media Foundation su Windows 11, anche verticali | [changelog SplitCam](https://splitcam.com/hi/changelog) |
| **NVIDIA Broadcast** | Camera, microfono e altoparlante virtuali; correzioni specifiche per Teams e per il 24H2 | [NVIDIA](https://www.nvidia.com/en-gb/geforce/broadcasting/broadcast-app/release-notes/) |
| **Elgato EpocCam** | Driver separati per video e audio, oggi abbandonato | [Elgato](https://help.elgato.com/hc/en-us/articles/10030520975757-EpocCam-Microphone-Not-Appearing) |

La strada di WebcamLR (MF per Windows 11) è la stessa di SplitCam e probabilmente di Camo. È l'unica che non richiede un driver kernel.

## 5. Windows 10: le opzioni

- **Stato**: supporto terminato il 14 ottobre 2025; ESU per i privati fino al 13 ottobre 2026 ([Microsoft Q&A](https://learn.microsoft.com/en-ca/answers/questions/5805066/windows-esu-does-enrollment-end-on-13-oct-2026-or)). Pureinfotech riporta un'estensione al 12 ottobre 2027 ([Pureinfotech](https://pureinfotech.com/windows-10-esu-extended-2027-microsoft-update/)): da verificare sulla pagina Microsoft.
- **A. Filtro DirectShow** (come OBS): user mode, nessuna firma Microsoft, si registra con `regsvr32` da amministratore. Lo vedono Chromium (quindi Meet e WhatsApp nuovo), Firefox, Zoom, OBS, Discord e i vecchi Teams; non lo vedono l'app Fotocamera, le app WinRT e forse il nuovo Teams. Costo M. **È la scelta consigliata per la 1.25.**
- **B. Driver kernel AVStream** (come DroidCam e iVCam): lo vede tutto, anche su Windows 10. Servono però un certificato EV, la firma di attestazione Microsoft tramite il Partner Center, la compatibilità con HVCI/Isolamento core e un debug kernel; un bug fa una schermata blu. Costo L, rischio alto. **Sconsigliato.**
- **C. Nessun supporto**: WebcamLR su Windows 10 mostra il video in finestra e lo manda in OBS (finestra o «cattura finestra»). Rimane il ripiego se la A dà problemi.
- Su Windows 11 **non** conviene registrare anche il filtro DirectShow: Chromium vedrebbe due «WebcamLR». Se servirà, va registrato solo sotto la build 22000.

## 6. Audio: un microfono virtuale, più avanti

| | Mac | Windows |
|---|---|---|
| Tecnica | **Audio Server Plug-in** (HAL) in `/Library/Audio/Plug-Ins/HAL`, caricato da `coreaudiod` | **Driver audio kernel** (PortCls/WaveRT, sul modello del campione SysVAD) |
| Estensione di sistema | No: basta installarlo con i permessi di amministratore e riavviare `coreaudiod` | Sì, è un driver |
| Firma | Developer ID e notarizzazione per distribuirlo. In locale, con l'Apple ID gratuito, funziona probabilmente con firma ad hoc (da verificare) | Firma Microsoft obbligatoria (attestazione o WHQL) con certificato EV ([OSR](https://community.osr.com/discussion/comment/297624/); [SysVAD](https://learn.microsoft.com/en-us/samples/microsoft/windows-driver-samples/sysvad-virtual-audio-device-driver-sample/)) |
| Codice di partenza senza GPL | Esempio Apple «Creating an Audio Server Driver Plug-in» (NullAudio); libASPL (MIT, [libASPL](https://github.com/gavv/libASPL)). **BlackHole è GPL-3.0: non usarlo** ([BlackHole](https://github.com/ExistentialAudio/BlackHole)) | SysVAD (licenza MS-PL dei campioni Microsoft, permissiva e non GPL: [Windows-driver-samples](https://github.com/microsoft/Windows-driver-samples)) |
| Alternativa | — | Chiedere di installare un cavo audio virtuale di terzi. Distribuirlo insieme all'app richiede una licenza |
| Costo | M | L (firma, EV, test su molti PC) |

Un filtro DirectShow audio non basta: Zoom e Discord non lo vedono come microfono ([OSR](https://community.osr.com/t/microphone-virtual-driver/16610)). Consiglio: sul Mac il microfono virtuale insieme alla webcam virtuale (2.x). Su Windows rimandarlo finché non c'è un'entità con certificato EV. Nel frattempo l'audio del telefono si può offrire in OBS, dove WebcamLR può fornire una sorgente audio propria.

## 7. Matrice di compatibilità attesa

Per WebcamLR com'è progettata: Camera Extension sul Mac, MF su Windows 11, filtro DirectShow su Windows 10.

| App | Mac 13–26 | Win 11 | Win 10 | Da fare se fallisce |
|---|---|---|---|---|
| Meet / siti in Chrome-Edge | ✅ | ✅ | ✅ | ricaricare la pagina |
| Siti in Firefox | ✅ | 🟡 | ✅ | — |
| Siti in Safari | ✅ | — | — | — |
| Zoom | ✅ | 🟡 | ✅ | chiudere Zoom dalla barra di sistema e riaprirlo |
| Teams nuovo | 🟡 | 🟡 ⚠️ | ⚠️ | Teams nel browser |
| WhatsApp | 🟡 | ✅ (WebView2) | ⚠️ | WhatsApp Web nel browser |
| FaceTime / Photo Booth | ✅ | — | — | — |
| Discord | 🟡 | 🟡 | ✅ | Discord nel browser |
| Webex | ⚠️ (Control Hub) | ✅ | ✅ | chiedere all'amministratore |
| Slack | ✅ | ✅ | ✅ | — |
| OBS Studio | ✅ | ✅ | ✅ | — |
| App Fotocamera | — | ✅ | ❌ | — |
| TikTok LIVE Studio | — | 🟡 | ✅ | sorgente OBS |
| Instagram Live | via OBS | via OBS | via OBS | — |
| Final Cut Pro | ⚠️ | — | — | registrare sull'iPhone |

## 8. Procedura di prova per Ledion

Da fare quando ogni webcam virtuale è pronta: Mac alla 1.23, Windows 11 alla 1.24, Windows 10 alla 1.25. Circa 30 minuti. Per ogni riga: ✅/❌ e uno screenshot se c'è un problema.

**Preparazione**
1. Mac: WebcamLR in Applicazioni → «Attiva la webcam virtuale» → approva in Impostazioni → Generali → Elementi di login ed estensioni → Estensioni videocamera. Annota quanti passi e quanti secondi ci sono voluti.
2. Windows: installa come amministratore. Controlla che «WebcamLR» compaia in Impostazioni → Bluetooth e dispositivi → Fotocamere e che «Consenti alle app desktop di accedere alla fotocamera» sia acceso.
3. Telefono **non ancora collegato**: tutte le app devono già vedere «WebcamLR» con l'immagine di attesa.

**Browser** (con il telefono collegato)
4. https://webcamtests.com in Chrome, Edge, Firefox (e Safari sul Mac): il nome «WebcamLR» compare? Risoluzione e fps riportati? Annota se compare «busy or blocked».
5. https://meet.google.com → «Controlla audio e video» (o una riunione con un secondo account dal telefono di qualcun altro): l'altra persona vede il video? È fluido?

**App** (ognuna: si vede in elenco? anteprima? l'altra persona vede il video?)
6. Zoom: impostazioni → Video, poi la riunione di prova https://zoom.us/test.
7. Teams nuovo: Impostazioni → Dispositivi, poi una «riunione immediata» con un secondo account. **Controlla che l'altra persona veda il video**, non solo l'anteprima.
8. WhatsApp desktop: videochiamata a un contatto di prova.
9. FaceTime e Photo Booth (Mac); app Fotocamera (Windows 11).
10. Discord: Impostazioni utente → Voce e video → Prova video.
11. OBS: sorgente «Dispositivo di acquisizione video» (Windows) o «Dispositivo di cattura video» (Mac).

**Insidie**
12. Apri Zoom **prima** di WebcamLR: compare comunque?
13. Stacca il telefono durante una chiamata: l'app di chiamata mostra l'immagine di attesa (non nero, non errore)? Ricollegandolo, il video torna senza riavviare l'app?
14. Meet e OBS aperti insieme sulla camera: funziona? (Windows 11 24H2: prova con «più app» acceso e spento.)
15. Disinstalla: «WebcamLR» sparisce dagli elenchi? La camera integrata funziona ancora?

Esito atteso da mandare: la matrice della sezione 7 compilata con ✅/❌, più gli screenshot delle righe ❌.
