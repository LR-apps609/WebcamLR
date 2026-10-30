# Webcam virtuale per Windows (1.24–1.26)

Con la webcam installata, l'iPhone compare come fotocamera «WebcamLR» in tutte le app di Windows 11: Fotocamera di Windows, Zoom, Teams (nuovo), Meet e ogni sito in Chrome, Edge e Firefox, WhatsApp, Discord, OBS.

Su Windows 10 (1.25, P23) la stessa scheda installa un filtro DirectShow: «WebcamLR» compare in Zoom, Meet e i siti in Chrome, Edge e Firefox, OBS, Discord e nelle altre app DirectShow, ma non nell'app Fotocamera di Windows né nelle app WinRT. Dettagli nella sezione [Windows 10](#windows-10-filtro-directshow-125-p23).

## Come funziona

```
iPhone ──H.264/HEVC──► WebcamLR.exe ──NV12──► memoria condivisa ──► sorgente WebcamLR ──► Frame Server ──► Zoom, Teams, Chrome…
                       (decodifica hardware,     «Global\WebcamLR.Video»   (dentro Frame Server,
                        conversione fuori dal                               LocalService, sessione 0)
                        thread dell'interfaccia)
```

| Parte | Dove | Cosa fa |
| --- | --- | --- |
| `WebcamLR.Webcam.Logica` | net8.0, provata su Linux | Anello di fotogrammi nella memoria condivisa, conversione BGRA → NV12 (BT.709, 16–235) con bande nere, taglio e specchio, scalatura NV12, immagine di attesa, formati, stati e testi |
| `WebcamLR.Webcam` | server COM .NET 8 (`comhost`) | La sorgente Media Foundation: `IMFActivate` → `IMFMediaSource2`/`IMFMediaSourceEx` con un flusso `IMFMediaStream2`, `IKsControl` vuoto. NV12 1920×1080, 1280×720, 960×540, 640×360 a 30 fps; 1920×1080 e 1280×720 anche a 60 fps; 3840×2160 a 30 fps (P12) |
| `WebcamLR.Webcam.Installa` | exe, da amministratore | `installa`: copia in `C:\Program Files\WebcamLR\Webcam`, registra il CLSID in HKLM, `MFCreateVirtualCamera` (durata System, tutti gli utenti). `rimuovi`: toglie webcam, registrazione e file, senza riavvio |
| `WebcamLR.App` | l'app | Scheda «Webcam per le altre app» (stato, installa, ripara, rimuovi, inquadratura, specchio) e `UscitaWebcam`, che manda il video alla sorgente |

Perché C# e non C++: si compila con il solo .NET 8 SDK (lo script `Strumenti/Costruisci e avvia.bat` non cambia, niente strumenti C++). Il codice dentro Frame Server è piccolo: nessuna decodifica, nessuna eccezione verso Windows (ogni metodo COM restituisce un HRESULT), memoria preparata una volta. Il prezzo: Frame Server carica il runtime .NET 8 (`C:\Program Files\dotnet`, già installato con l'SDK).

### Memoria condivisa e permessi

- Nome `Global\WebcamLR.Video` (anello: intestazione di 4 KB, tre posti NV12 da 3840×2160 e l'immagine personale della schermata di attesa fino a 1920×1080, circa 40 MB; Windows dà le pagine solo quando si scrivono) ed evento `Global\WebcamLR.Video.Nuovo`. La disposizione byte per byte è nel commento di `AnelloFotogrammi.cs`. Versione 2 dalla P12 (posti da 4K e fps chiesti), versione 3 dalla W1 (stato, stile e lingua della schermata di attesa, immagine personale): dopo ogni aggiornamento della versione va **reinstallata la webcam** (l'installatore lo fa da solo; dalla build di sviluppo «Ripara» o «Rimuovi» e «Installa»), altrimenti sorgente e app non si riconoscono e la webcam mostra solo «La webcam non è collegata».
- Frame Server gira come **LocalService nella sessione 0**, l'app nella sessione dell'utente: serve `Global\`. Un processo normale non può *creare* oggetti in `Global\` (manca `SeCreateGlobalPrivilege`), quindi **li crea la sorgente** e l'app li apre (ci riprova ogni secondo).
- Permessi (SDDL in `NomiWebcam.cs`): `D:P(A;;GA;;;SY)(A;;GA;;;LS)(A;;GA;;;BA)(A;;GRGW;;;IU)`: sistema, LocalService e amministratori tutto; utenti collegati al PC (INTERACTIVE, anche da Desktop remoto) lettura e scrittura. L'evento dà `GA` anche a IU per poterlo segnalare. Senza etichetta d'integrità l'oggetto vale «media»: l'app normale ci scrive.
- Ogni posto ha un numero di versione scritto prima (−1) e dopo i dati: la sorgente lo rilegge dopo la copia e non usa mai un fotogramma scritto a metà.
- La sorgente segna nell'intestazione il formato scelto dall'app (misura e fps) e il suo «battito» a ogni fotogramma: l'app accende il secondo decodificatore solo quando una app usa la webcam (meno di 2 s fa) e lo spegne dopo 5 s di inattività.
- Il ritmo segue il formato scelto (`RitmoWebcam`): a 30 fps un fotogramma ogni 33,3 ms (con il video dell'app: appena arriva, tra 28 e 38 ms), a 60 fps ogni 16,7 ms (tra 14 e 19 ms). Con il telefono a 30 fps e l'app a 60 ogni fotogramma esce due volte, a ritmo regolare. L'app converte già alla misura scelta, anche il 4K: la sorgente scala solo se le misure non coincidono.
- Senza video la sorgente mostra la schermata di attesa (sotto, «Schermata di attesa»). Le app non si bloccano e non danno errore, in qualunque ordine si aprano.

### Installazione

- HKCU non basta: Frame Server (LocalService) non vede il registro dell'utente. Serve HKLM, quindi l'amministratore: lo chiede Windows quando si preme «Installa la webcam WebcamLR».
- La sorgente va in `C:\Program Files\WebcamLR\Webcam`: Frame Server non può leggere `C:\Users\…`, dove viene compilata l'app. Si toglie anche il «Mark of the Web».
- Reinstallare con la webcam aperta in un'app: il file in uso viene rinominato e cancellato al riavvio, quello nuovo vale subito per le app che aprono la webcam dopo.
- Registri: `C:\ProgramData\WebcamLR\Installazione webcam.txt` (installatore) e `C:\ProgramData\WebcamLR\Registro webcam.txt` (sorgente, dentro Frame Server). Nel registro del collegamento dell'app (modalità avanzata) compaiono le righe «Webcam: …».
- Windows 10: lo stesso pulsante installa il filtro DirectShow (sotto, «Windows 10»).
- L'installatore di WebcamLR (`Windows/WebcamLR.Setup`, W1) installa l'app per l'utente e chiama, con un solo permesso
  dell'amministratore, `WebcamLR.Webcam.Installa.exe configura "<WebcamLR.exe>" [webcam]`: regola del firewall
  «WebcamLR» (in ingresso, solo reti private, solo quel programma) più la webcam, se chiesta o se c'era già.
  Il disinstallatore chiama `… disinstalla "<WebcamLR.exe>"` (webcam e regola). A mano ci sono anche `firewall` e
  `rimuovi-firewall` con lo stesso argomento. Guida: `Documenti/Windows - installazione e prova.md`.

## Schermata di attesa (W1)

Come sul Mac (`Mac/Sorgenti/AttesaWebcam.swift`, `Mac/FotocameraVirtuale/Fotocamera.swift`): fondo quasi nero con la sfumatura
verde del logo (#30453E → #0D1B18, scurita della metà e più scura ai bordi), il logo piccolo, il titolo in Barlow Condensed
Bold e la riga sotto in Barlow Medium, con le stesse misure (per 1080 righe: logo 120, titolo 84, riga 34).

| Stato (`StatoAttesa`) | Titolo · riga sotto (inglese) |
| --- | --- |
| `NonCollegata` | «La webcam non è collegata» · «Apri WebcamLR sul telefono» (The webcam is not connected · Open WebcamLR on your phone) |
| `AppChiusa` (WebcamLR chiusa: lo decide la webcam, l'app non lo scrive) | «WebcamLR è chiusa» · «Apri WebcamLR sul computer» (WebcamLR is closed · Open WebcamLR on the computer) |
| `Interrotta` | «Collegamento interrotto» · «Riconnessione in corso…» (Connection lost · Reconnecting…) |
| `Pausa` | «Webcam in pausa» (Webcam paused) |

- **Chi fa cosa**: la sorgente di Windows 11 (`FlussoWebcam`) e il filtro DirectShow (`FonteFotogrammi`) chiamano lo stesso
  `CompositoreWebcam` (in `WebcamLR.Webcam.Logica`, provato su Linux): legge video e stato dall'anello, decide con
  `ProgrammaAttesa` (le regole del Mac) e disegna con `DisegnoAttesa`. Diversamente dal Mac, l'app **non** disegna nulla:
  scrive solo stato, stile, lingua e l'eventuale immagine personale; la webcam disegna da sé, anche quando l'app è chiusa.
- **Tempi**: interruzione e app chiusa: l'ultima immagine resta 2 s, poi mezzo secondo di dissolvenza (16 passi, ognuno
  calcolato una volta). Pausa e «non collegata» decise dall'app: subito, con la stessa dissolvenza. Ritorno del video:
  la schermata svanisce sopra il video in 0,3 s. Un fotogramma rimasto nella memoria da più di 1 s non conta come video.
- **Disegnata una volta** per stato, stile, lingua e misura (al massimo 6 tenute; 1080p circa 40 ms, 4K circa 300 ms, una
  volta); a ogni fotogramma si consegna la stessa memoria.
- **Testi**: la sorgente gira in un servizio senza caratteri installati, quindi i 10 testi (5 italiani, 5 inglesi) sono
  disegnati prima con i caratteri di Stile da `Strumenti/genera_testi_attesa.py` (maschere a 2160 righe, 67 KB compressi,
  risorsa della DLL) e rimpiccioliti alla misura giusta. Testi nuovi: aggiungerli lì, in `TestiAttesa.cs` e nel catalogo
  del Mac (un test controlla che siano uguali), poi rilanciare lo script.
- **Lingua**: quella scritta dall'app (`LinguaAttesa.Italiano`/`Inglese`); se l'app non la scrive, quella di Windows:
  dentro Frame Server la lingua del sistema, nel filtro DirectShow quella dell'utente. Italiano se è italiano, altrimenti inglese.
- **Colori**: da Stile (`Tema.swift`, `LogoWebcamLR.celle`), non da `App.xaml`; un test li confronta con Stile.
- **Stili di WebcamLR Pro** (`StileAttesa`): `WebcamLR`, `Nero` (solo nero), `Immagine` (l'immagine personale che riempie
  il riquadro, senza scritte), `Sfocata` (l'ultima immagine del telefono sfocata e scurita, con le scritte). Senza immagine
  personale o senza un'ultima immagine vale `WebcamLR`, come sul Mac. Pro lo controlla l'app: senza Pro scrive `WebcamLR`.

### Come l'app imposta la schermata (per chi scrive l'app)

Tutto su `MemoriaCondivisa.Anello` (`AnelloFotogrammi`), la stessa memoria dei fotogrammi, da qualsiasi thread:

```csharp
// Almeno una volta al secondo (fa da battito) e subito a ogni cambio. Per esempio in UscitaWebcam.Controlla,
// che gira già ogni secondo, più una chiamata quando cambia il collegamento del telefono.
memoria.Anello.ImpostaAttesa(
    stato,   // StatoAttesa: Nessuna se il telefono manda video; NonCollegata senza telefono;
             // Interrotta durante la riconnessione; Pausa se il telefono è in pausa (stato.pausa)
    stile,   // StileAttesa scelto in Impostazioni se Pro è attivo, altrimenti StileAttesa.WebcamLR
    Lingue.DaCultura(CultureInfo.CurrentUICulture),   // o LinguaAttesa.Automatica
    Environment.TickCount64);

// Lo stile «Immagine»: dopo che l'utente la sceglie, e di nuovo ogni volta che l'app apre la memoria condivisa
// (la webcam la crea vuota quando Windows la carica). BGRA come SoftwareBitmap; viene rimpicciolita a 1920×1080 al massimo.
memoria.Anello.ScriviImmaginePersonaleBgra(bgra, larghezza, altezza, passo);
memoria.Anello.TogliImmaginePersonale();   // se l'utente la toglie

// Alla chiusura di WebcamLR (prima di Dispose della memoria): la webcam tiene l'ultima immagine 2 s e poi
// mostra «La webcam non è collegata».
memoria.Anello.SegnalaChiusura();
```

Se l'app non chiama nulla (versione di prima) la webcam funziona lo stesso: il video passa, e quando si ferma, dopo 2 s,
mostra «La webcam non è collegata» (mai «Collegamento interrotto» né «Webcam in pausa»). Se l'app smette di scrivere per più
di 2,5 s (`NomiWebcam.StatoAppMs`, per esempio se si chiude di colpo) vale chiusa. Su Windows 10 la memoria è quella locale
(`NomiAnello.Locale`), con le stesse chiamate.

## Cosa si è provato qui e cosa solo su Windows 11

Provato su Linux: compilazione di tutti i progetti (`WebcamLR.Webcam` con `comhost` e CLSID incluso, installatore, app con il banco di prova), 50 test della parte senza Windows (anello, conversione, inquadrature, immagine di attesa, testi), i test di protocollo e ricevitore.
Dalla W1: 142 test di `WebcamLR.Webcam.Logica.Test` (schermata di attesa, regole delle dissolvenze, compositore con un anello
in memoria, anello versione 3, regola del firewall), 36 di `WebcamLR.Setup.Logica.Test`, le schermate guardate come immagini,
e `Pacchetto.proj` provato con un'app finta (disinstallatore, zip e installatore autonomo costruiti).

Verificato contro gli header (revisione delle interfacce COM): IID, ordine dei metodi e parametri di tutte le interfacce in `InterfacceMF.cs` (header mingw-w64 `mfobjects.h`, `mfidl.h`, `ks.h`; `IMFMediaSource2`, `IMFMediaStream2` e `IMFVirtualCamera` con le dichiarazioni generate dall'SDK di DirectN), i GUID degli attributi `MF_MT_*` e `MF_DEVICESTREAM_*`, `PINNAME_VIDEO_CAPTURE`, gli eventi e gli HRESULT, i valori di `MFVirtualCameraLifetime`/`Access` e gli indici 36/38/43 di Start/Remove/Shutdown (3 di IUnknown + 30 di IMFAttributes + i metodi di IMFVirtualCamera). Il comportamento (ordine degli eventi, valori VT_I8, Pause, SetStreamState) segue i due esempi di riferimento, Windows-Camera VirtualCamera di Microsoft e VCamSample.

Solo su un PC Windows 11 vero: che Frame Server carichi la sorgente .NET, `MFCreateVirtualCamera`, i permessi della memoria condivisa tra sessione 0 e utente, la decodifica per la webcam (`IsVideoFrameServerEnabled`, `CopyFrameToVideoSurface`), e tutte le app.

## Procedura di prova (Windows 11)

Prima: `Strumenti\Costruisci e avvia.bat`. Nella cartella `Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\Webcam` devono esserci `WebcamLR.Webcam.comhost.dll` e `WebcamLR.Webcam.Installa.exe`.

1. **Installazione**: scheda «Webcam per le altre app» → «Installa la webcam WebcamLR» → Sì alla domanda di Windows. Attesi: avviso verde «Webcam installata», stato INSTALLATA (punto verde). In Impostazioni → Bluetooth e dispositivi → Fotocamere compare «WebcamLR (Windows Virtual Camera)»: la parte tra parentesi la aggiunge Windows a ogni webcam virtuale, ed è normale che le app la mostrino così.
2. **Senza telefono**: Fotocamera di Windows → cambia fotocamera fino a «WebcamLR». Attesa: la schermata verde scura con il logo, «La webcam non è collegata» e «Apri WebcamLR sul telefono», fluida, senza errori. Nell'app lo stato diventa IN ONDA (punto rosso) entro 2 secondi.
3. **Con il telefono**: collega l'iPhone (Wi-Fi, poi cavo USB). Entro 2 secondi la Fotocamera di Windows mostra il video. Stacca il telefono: l'ultima immagine resta 2 secondi, poi in mezzo secondo la schermata di attesa; l'app di prova non si blocca. Ricollega: il video torna.
4. **Meet in Chrome e in Edge**: meet.google.com → nuova riunione → impostazioni → Video → «WebcamLR». Anche webcamtests.com: deve dire 1280×720 o 1920×1080 a 30 fps. Se dice «busy or blocked», prova chrome://flags → «MediaFoundation video capture» disattivato e annota il risultato.
   - **60 fps e 4K (P12)**: Fotocamera di Windows → impostazioni (ingranaggio) → Qualità video: devono comparire 1080p e 720p a 60 fps e 2160p (4K) a 30 fps. Scegli 1080p 60 fps e muovi la mano davanti al telefono: movimento fluido, nessuno scatto regolare. In OBS («Dispositivo di acquisizione video» → Proprietà → Risoluzione/FPS personalizzati) prova 1920×1080 a 60 e 3840×2160 a 30: nelle statistiche di OBS nessun fotogramma perso per la sorgente. Nel registro del collegamento (modalità avanzata) la riga «Webcam: un'app la sta usando (1920×1080 a 60 fps)».
5. **Firefox**: webcamtests.com e Meet in Firefox.
6. **Zoom**: chiudi Zoom del tutto (anche dalla barra accanto all'orologio), riaprilo → Impostazioni → Video → «WebcamLR». Fai una riunione di prova con un secondo dispositivo: l'altro deve vederti.
7. **Teams nuovo** (la prova più importante): Impostazioni → Dispositivi → Fotocamera «WebcamLR», poi una chiamata vera con un'altra persona o un altro account. Annota se **l'altra persona** vede il video, non solo l'anteprima (problema noto di altre webcam Media Foundation).
8. **WhatsApp desktop**: videochiamata, cambia fotocamera in «WebcamLR».
9. **Discord**: Impostazioni → Voce e video → Fotocamera «WebcamLR» → Prova video.
10. **OBS**: Sorgente «Dispositivo di acquisizione video» → «WebcamLR». Poi Meet nel browser aperto **insieme** a OBS: annota se tutte e due vedono il video.
11. **Verticale e specchio**: in WebcamLR scegli «Riempi, tagliando i bordi» con il telefono in verticale: niente bande nere. Il pulsante «Specchia» sotto l'anteprima non cambia la webcam; l'interruttore «Specchia anche per chi guarda» sì. (Zoom e Meet specchiano solo la tua anteprima: chi ti guarda ti vede dritto.)
12. **Latenza dell'anteprima**: con la webcam in uso la finestra di WebcamLR deve restare fluida come prima (latenza nelle statistiche simile).
13. **Rimozione (1.26)**: «Rimuovi la webcam» → Sì. Attesi: avviso «Webcam rimossa», «WebcamLR» sparisce dalla Fotocamera di Windows e da Impostazioni → Fotocamere senza riavviare; la fotocamera integrata funziona ancora. Poi reinstalla (punto 1).
14. **Riavvio del PC**: dopo il riavvio «WebcamLR» c'è ancora, anche prima di aprire l'app (mostra l'immagine di attesa). Se manca, la scheda dice DA RIPARARE: annotalo e premi «Ripara la webcam» (vorrà dire che Windows non conserva la webcam al riavvio e l'app la dovrà ricreare all'avvio).

Se nel registro della sorgente c'è «Memoria condivisa non disponibile» (la webcam mostra solo l'immagine di attesa anche con il telefono collegato), manda anche l'uscita di `sc qprivs FrameServer` e `sc qsidtype FrameServer` (Prompt dei comandi): la sorgente crea gli oggetti `Global\` e per farlo Frame Server deve avere `SeCreateGlobalPrivilege`.

Se qualcosa non va, manda: lo stato nella scheda, il messaggio dell'avviso, i due file in `C:\ProgramData\WebcamLR\` e la versione di Windows (Impostazioni → Sistema → Informazioni).

## Windows 10: filtro DirectShow (1.25, P23)

`MFCreateVirtualCamera` su Windows 10 non esiste. Come consiglia `Documenti/Compatibilità webcam.md` (sezione 5) c'è un filtro DirectShow in modalità utente, come OBS Virtual Camera, e mai un driver kernel.

```
iPhone ──► WebcamLR.exe ──NV12──► memoria condivisa ──► filtro «WebcamLR» dentro Zoom ──YUY2/NV12/RGB24──► Zoom
                                  «Local\WebcamLR.Video»  filtro «WebcamLR» dentro Chrome ─────────────────► Chrome
                                  (la crea l'app)         … uno per ogni app che apre la webcam
```

| Parte | Cosa fa |
| --- | --- |
| `WebcamLR.Webcam.DirectShow` | Server COM .NET 8 (`comhost`), CLSID `{70917e66-b31c-4a4d-b96d-cf8768d7f45b}`. `FiltroWebcam` (`IBaseFilter`, `IMediaFilter`, `IPersist`, `IAMFilterMiscFlags`: «sono una sorgente») con un pin `PinWebcam` («Cattura»: `IPin`, `IAMStreamConfig`, `IKsPropertySet` che risponde `PIN_CATEGORY_CAPTURE`, `IQualityControl`), `IEnumPins`, `IEnumMediaTypes`. Un thread consegna i fotogrammi con l'allocatore concordato con l'app (`IMemInputPin::GetAllocator`, se no `CLSID_MemoryAllocator`) e `IMemInputPin::Receive`, con i tempi dell'orologio del grafo |
| `WebcamLR.Webcam.Logica` | Formati DirectShow, `VIDEOINFOHEADER` e `VIDEO_STREAM_CONFIG_CAPS` scritti byte per byte, conversioni NV12 → YUY2, NV12 con altro passo, RGB24 (BT.709, dal basso in alto), nomi dell'anello locale. Tutto provato su Linux |
| `WebcamLR.Webcam.Installa` | `installa` su Windows 10 registra il filtro (sotto); `directshow` lo registra anche su Windows 11, solo a mano; `rimuovi` toglie sempre anche il filtro |
| `WebcamLR.App` | La scheda «Webcam per le altre app» non dice più «Windows 10 non supportato»: installa il filtro, mostra lo stato e crea l'anello locale |

### Perché C# e non C++

Deciso C#, come la sorgente di Windows 11:

- **Si compila con il solo .NET SDK** (`Strumenti\Costruisci e avvia.bat` non cambia, niente Visual Studio da diversi GB). Anche NativeAOT, che toglierebbe il runtime, su Windows vuole il linker di MSVC.
- **Riusa il codice già provato**: anello e seqlock, immagine di attesa (scritta pixel per pixel), scalatura, ritmo, orologio preciso. In C++ andrebbero riscritti e riprovati senza test qui.
- Il prezzo, da conoscere:
  - **Il filtro carica .NET 8 dentro ogni app che apre la webcam** (circa 50–100 ms la prima volta e qualche decina di MB). In un processo può esserci un solo .NET moderno: un'app che ha già caricato .NET 6 o 7 non potrebbe aprire «WebcamLR». Con `RollForward=Major` va bene invece con .NET 9 o più nuovi. .NET Framework (4.x) convive senza problemi. Zoom, Chrome, Firefox, OBS e Discord sono C++/Electron: nessun conflitto noto.
  - **App a 32 bit**: serve la DLL x86 (la build la mette in `Webcam\x86`) e il **runtime .NET 8 x86**, che l'SDK a 64 bit non installa. Senza runtime x86 l'installatore registra il filtro solo per le app a 64 bit (codice 7, «Fatto per le app a 64 bit…» con il link per scaricarlo) invece di mostrare alle app a 32 bit una webcam che non si apre. Oggi Zoom, Chrome, Edge, Firefox, OBS, Discord e Teams sono a 64 bit.
  - **Chrome ed Edge**: aprono le webcam nel processo «Video Capture», che su Windows non ha sandbox (deve caricare driver e filtri: è così che funziona OBS Virtual Camera). Se una versione futura vi attivasse il blocco del codice dinamico, il JIT di .NET non partirebbe e servirebbe la strada C++. Da provare.
  - Ogni metodo COM cattura tutto e restituisce un HRESULT, il thread di consegna è protetto: un'eccezione .NET non gestita chiuderebbe Zoom o Chrome.
- Se una di queste prove va male, un filtro C++ con un `CMakeLists.txt` (saltato dallo script se manca MSVC) resta la strada di riserva: la parte da riscrivere è il filtro, l'anello resta uguale.

### Memoria condivisa su Windows 10

- Senza Frame Server il filtro gira **dentro l'app, come l'utente, nella sua sessione**: basta lo spazio dei nomi `Local\`, che ogni processo può creare. Su Windows 11 non cambia nulla (`Global\`, creato dalla sorgente).
- Nomi: `Local\WebcamLR.Video` ed evento `Local\WebcamLR.Video.Nuovo` (`NomiAnello.Locale`), stessa disposizione dell'anello globale (versione 2). **Lo crea chi arriva prima**: WebcamLR appena la webcam risulta installata, oppure il filtro se un'app apre la webcam prima di WebcamLR (allora mostra l'immagine di attesa finché l'app non scrive).
- Il filtro prova prima `Global\WebcamLR.Video` (c'è solo su Windows 11 con la sorgente attiva, se qualcuno ha registrato il filtro a mano con `directshow`) e poi `Local\`. L'app sceglie con `NomiWebcam.TipoPer(build)`: Windows 11 apre il globale, Windows 10 crea il locale.
- Permessi (`NomiWebcam.SddlLocale`): `D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;IU)S:(ML;;NW;;;LW)`. Sistema, amministratori e utenti collegati tutto, così un WebcamLR avviato come amministratore e uno Zoom normale si vedono; l'etichetta d'integrità bassa permette di segnare il battito anche a un processo di cattura a integrità bassa.
- Più app insieme (Zoom e OBS): ognuna ha il suo filtro, tutte leggono lo stesso anello. L'app scrive la misura chiesta per ultima; chi ne vuole un'altra scala da sé (`ScalaNv12`). L'evento «fotogramma nuovo» è a reset automatico e sveglia un filtro solo: gli altri consegnano al termine della loro finestra (al massimo 38 ms a 30 fps). Va bene per due app, non è perfetto.

### Formati

18 formati: 1280×720 (il primo e predefinito: leggero anche su un PC vecchio), 1920×1080, 960×540, 640×360 a 30 fps, 1280×720 e 1920×1080 a 60 fps; per ognuno YUY2 (lo accettano tutte le app DirectShow), NV12 (nessuna conversione), RGB24 (app vecchie; righe dal basso, multiple di 4 byte). Niente 4K: lo convertirebbe ogni app per conto suo. `IAMStreamConfig::SetFormat` (Chrome lo chiama prima di collegare, OBS anche dopo, con `IFilterGraph::Reconnect`) sceglie il formato; un renderer che chiede righe più larghe con `IMediaSample::GetMediaType` viene rispettato. Le capacità hanno misura minima = massima e passi di 1 pixel (OBS conta le misure camminando da minima a massima: un passo 0 non finirebbe mai).

### Registrazione (installatore, da amministratore)

1. Copia la cartella `Webcam` (e `Webcam\x86`) in `C:\Program Files\WebcamLR\Webcam` (`…\x86`); i file aperti da un'app vengono rinominati e cancellati al riavvio.
2. Classe COM in HKLM: `CLSID\{70917e66-…}\InprocServer32` → `WebcamLR.Webcam.DirectShow.comhost.dll`, `ThreadingModel=Both`; la x86 nel registro a 32 bit (WOW6432Node) solo se c'è il runtime .NET 8 x86 (`C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App\8.*` o `HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x86`).
3. Categoria video con `IFilterMapper2::RegisterFilter` (merito `MERIT_DO_NOT_USE`, un pin d'uscita di cattura con i tre sottotipi): scrive `CLSID`, `FriendlyName` («WebcamLR») e `FilterData` sotto `CLSID\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\Instance\{70917e66-…}`. Gli stessi tre valori si scrivono poi in tutte e due le viste di HKLM (FilterData non contiene puntatori). Se `IFilterMapper2` fallisce si registra senza FilterData: le app elencano la webcam lo stesso.
4. **Windows 11: il filtro non si registra.** La camera Media Foundation compare già anche in DirectShow tramite Frame Server; con il filtro Chrome vedrebbe due «WebcamLR». `WebcamLR.Webcam.Installa.exe directshow` lo registra comunque, per prove con app che vedono solo DirectShow.
- Lo stato nella scheda (Windows 10): classe COM con file esistente + voce nella categoria → INSTALLATA; una sola delle due → DA RIPARARE. L'avviso sulla privacy della fotocamera non compare: non vale per i filtri DirectShow.
- Registro del filtro: `%LOCALAPPDATA%\WebcamLR\Registro webcam DirectShow.txt` (ogni riga con il nome dell'app e 32/64 bit). Installatore: `C:\ProgramData\WebcamLR\Installazione webcam.txt` come prima.

### Verificato qui e cosa solo su Windows 10

Verificato su Linux: compilazione del filtro x64 e x86 (comhost PE32 per x86, `rollForward: Major`, CLSID nel `clsidmap`), installatore, app con il banco di prova (nessun errore C#), target `CompilaWebcam` (produce `Webcam\x86`), 29 test nuovi su formati, strutture, conversioni e nomi (100 in tutto). IID e ordine dei metodi di tutte le interfacce (`IPin`, `IBaseFilter`, `IMediaFilter`, `IEnumPins`, `IEnumMediaTypes`, `IMemInputPin`, `IMemAllocator`, `IMediaSample`, `IReferenceClock`, `IFilterGraph`, `IAMStreamConfig`, `IKsPropertySet`, `IAMFilterMiscFlags`, `IQualityControl`, `IFilterMapper2`) confrontati con le tabelle `…Vtbl` di `strmif.h` di mingw-w64; strutture (`AM_MEDIA_TYPE`, `PIN_INFO`, `FILTER_INFO`, `ALLOCATOR_PROPERTIES`, `REGFILTER2`, `REGFILTERPINS2`, `REGPINTYPES`, `VIDEO_STREAM_CONFIG_CAPS`, `VIDEOINFOHEADER` da `amvideo.h`), GUID (`uuids.h`) e HRESULT (`vfwmsgs.h`). Nota: `IMediaSample::GetSize` e `IAMFilterMiscFlags::GetMiscFlags` restituiscono un numero, non un HRESULT.

Solo su un PC Windows 10 vero: che le app carichino il filtro .NET, la negoziazione con i pin di Chrome, Firefox, Zoom e OBS, il runtime x86, `IFilterMapper2`, le prestazioni della conversione dentro le app.

## Procedura di prova (Windows 10)

Prima: `Strumenti\Costruisci e avvia.bat`. Accanto a `WebcamLR.exe`, in `Webcam`, devono esserci `WebcamLR.Webcam.DirectShow.comhost.dll` e la cartella `x86` con lo stesso file. Facoltativo: installa «.NET Desktop Runtime 8» **x86** per le app a 32 bit.

1. **Installazione**: scheda «Webcam per le altre app» → la descrizione parla di Windows 10, nessun «non supportato» → «Installa la webcam WebcamLR» → Sì. Attesi: avviso verde «Webcam installata» (giallo con il link per il runtime x86 se manca), stato INSTALLATA. Nell'app Fotocamera di Windows **non** compare: è normale.
2. **Senza telefono**: webcamtests.com in Chrome → «WebcamLR» nell'elenco, schermata di attesa verde scura con il logo, fluida. Nella scheda lo stato passa a IN ONDA entro 2 secondi.
3. **Con il telefono**: collega l'iPhone; entro 2 secondi la pagina mostra il video. Stacca: l'ultima immagine 2 secondi, poi la schermata di attesa, nessun blocco. Ricollega: il video torna.
4. **Chrome ed Edge**: meet.google.com → impostazioni → Video → «WebcamLR»; webcamtests.com deve dire 1280×720 (o 1920×1080) a 30 fps. Annota se compare «busy or blocked».
5. **Firefox**: webcamtests.com e Meet.
6. **Zoom**: chiudi Zoom del tutto, riaprilo → Impostazioni → Video → «WebcamLR», poi https://zoom.us/test con un secondo dispositivo: l'altro ti vede?
7. **OBS**: sorgente «Dispositivo di acquisizione video» → «WebcamLR» → Proprietà → Risoluzione/FPS personalizzati: prova 1280×720 YUY2, 1920×1080 NV12 a 60 fps, 640×360 RGB24. Colori giusti (non verdi o viola), immagine non capovolta.
8. **Due app insieme**: OBS e Meet aperti sulla webcam: tutte e due vedono il video? Annota se una delle due va a scatti.
9. **Discord** (Impostazioni → Voce e video → Prova video) e **Teams nuovo** (Impostazioni → Dispositivi; poi una chiamata vera: l'altra persona vede il video?). Se Teams non la vede, prova Teams nel browser.
10. **Ordine**: apri Zoom **prima** di WebcamLR: la webcam mostra l'immagine di attesa e il video arriva appena WebcamLR parte e il telefono è collegato.
11. **App a 32 bit** (solo con il runtime x86): una qualsiasi app a 32 bit che usa la webcam (per esempio AMCap a 32 bit) vede «WebcamLR».
12. **Rimozione**: «Rimuovi la webcam» → Sì → «WebcamLR» sparisce da Chrome e Zoom (dopo averli riaperti), la fotocamera integrata funziona ancora.

Se qualcosa non va, manda: lo stato nella scheda, il messaggio dell'avviso, `C:\ProgramData\WebcamLR\Installazione webcam.txt`, `%LOCALAPPDATA%\WebcamLR\Registro webcam DirectShow.txt` (incolla il percorso in Esplora file) e la versione di Windows.
