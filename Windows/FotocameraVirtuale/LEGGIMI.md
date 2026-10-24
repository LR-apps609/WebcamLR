# Webcam virtuale per Windows (1.24–1.26)

Con la webcam installata, l'iPhone compare come fotocamera «WebcamLR» in tutte le app di Windows 11: Fotocamera di Windows, Zoom, Teams (nuovo), Meet e ogni sito in Chrome, Edge e Firefox, WhatsApp, Discord, OBS.

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
| `WebcamLR.Webcam` | server COM .NET 8 (`comhost`) | La sorgente Media Foundation: `IMFActivate` → `IMFMediaSource2`/`IMFMediaSourceEx` con un flusso `IMFMediaStream2`, `IKsControl` vuoto. NV12 1920×1080, 1280×720, 960×540, 640×360 a 30 fps |
| `WebcamLR.Webcam.Installa` | exe, da amministratore | `installa`: copia in `C:\Program Files\WebcamLR\Webcam`, registra il CLSID in HKLM, `MFCreateVirtualCamera` (durata System, tutti gli utenti). `rimuovi`: toglie webcam, registrazione e file, senza riavvio |
| `WebcamLR.App` | l'app | Scheda «Webcam per le altre app» (stato, installa, ripara, rimuovi, inquadratura, specchio) e `UscitaWebcam`, che manda il video alla sorgente |

Perché C# e non C++: si compila con il solo .NET 8 SDK (lo script `Strumenti/Costruisci e avvia.bat` non cambia, niente strumenti C++). Il codice dentro Frame Server è piccolo: nessuna decodifica, nessuna eccezione verso Windows (ogni metodo COM restituisce un HRESULT), memoria preparata una volta. Il prezzo: Frame Server carica il runtime .NET 8 (`C:\Program Files\dotnet`, già installato con l'SDK).

### Memoria condivisa e permessi

- Nome `Global\WebcamLR.Video` (anello: intestazione di 4 KB e tre posti NV12 da 1920×1080) ed evento `Global\WebcamLR.Video.Nuovo`. La disposizione byte per byte è nel commento di `AnelloFotogrammi.cs`.
- Frame Server gira come **LocalService nella sessione 0**, l'app nella sessione dell'utente: serve `Global\`. Un processo normale non può *creare* oggetti in `Global\` (manca `SeCreateGlobalPrivilege`), quindi **li crea la sorgente** e l'app li apre (ci riprova ogni secondo).
- Permessi (SDDL in `NomiWebcam.cs`): `D:P(A;;GA;;;SY)(A;;GA;;;LS)(A;;GA;;;BA)(A;;GRGW;;;IU)`: sistema, LocalService e amministratori tutto; utenti collegati al PC (INTERACTIVE, anche da Desktop remoto) lettura e scrittura. L'evento dà `GA` anche a IU per poterlo segnalare. Senza etichetta d'integrità l'oggetto vale «media»: l'app normale ci scrive.
- Ogni posto ha un numero di versione scritto prima (−1) e dopo i dati: la sorgente lo rilegge dopo la copia e non usa mai un fotogramma scritto a metà.
- La sorgente segna nell'intestazione il formato scelto dall'app e il suo «battito» a ogni fotogramma: l'app accende il secondo decodificatore solo quando una app usa la webcam (meno di 2 s fa) e lo spegne dopo 5 s di inattività.
- Senza fotogrammi nuovi da più di 1 s la sorgente mostra l'immagine di attesa: «WebcamLR · in attesa del telefono · Apri WebcamLR sul telefono», con i colori di `App.xaml` (un test controlla che restino uguali). Le app non si bloccano e non danno errore, in qualunque ordine si aprano.

### Installazione

- HKCU non basta: Frame Server (LocalService) non vede il registro dell'utente. Serve HKLM, quindi l'amministratore: lo chiede Windows quando si preme «Installa la webcam WebcamLR».
- La sorgente va in `C:\Program Files\WebcamLR\Webcam`: Frame Server non può leggere `C:\Users\…`, dove viene compilata l'app. Si toglie anche il «Mark of the Web».
- Reinstallare con la webcam aperta in un'app: il file in uso viene rinominato e cancellato al riavvio, quello nuovo vale subito per le app che aprono la webcam dopo.
- Registri: `C:\ProgramData\WebcamLR\Installazione webcam.txt` (installatore) e `C:\ProgramData\WebcamLR\Registro webcam.txt` (sorgente, dentro Frame Server). Nel registro del collegamento dell'app (modalità avanzata) compaiono le righe «Webcam: …».
- Windows 10: la scheda dice che non è ancora supportata; il filtro DirectShow arriverà con la 1.25.

## Cosa si è provato qui e cosa solo su Windows 11

Provato su Linux: compilazione di tutti i progetti (`WebcamLR.Webcam` con `comhost` e CLSID incluso, installatore, app con il banco di prova), 50 test della parte senza Windows (anello, conversione, inquadrature, immagine di attesa, testi), i test di protocollo e ricevitore.

Verificato contro gli header (revisione delle interfacce COM): IID, ordine dei metodi e parametri di tutte le interfacce in `InterfacceMF.cs` (header mingw-w64 `mfobjects.h`, `mfidl.h`, `ks.h`; `IMFMediaSource2`, `IMFMediaStream2` e `IMFVirtualCamera` con le dichiarazioni generate dall'SDK di DirectN), i GUID degli attributi `MF_MT_*` e `MF_DEVICESTREAM_*`, `PINNAME_VIDEO_CAPTURE`, gli eventi e gli HRESULT, i valori di `MFVirtualCameraLifetime`/`Access` e gli indici 36/38/43 di Start/Remove/Shutdown (3 di IUnknown + 30 di IMFAttributes + i metodi di IMFVirtualCamera). Il comportamento (ordine degli eventi, valori VT_I8, Pause, SetStreamState) segue i due esempi di riferimento, Windows-Camera VirtualCamera di Microsoft e VCamSample.

Solo su un PC Windows 11 vero: che Frame Server carichi la sorgente .NET, `MFCreateVirtualCamera`, i permessi della memoria condivisa tra sessione 0 e utente, la decodifica per la webcam (`IsVideoFrameServerEnabled`, `CopyFrameToVideoSurface`), e tutte le app.

## Procedura di prova (Windows 11)

Prima: `Strumenti\Costruisci e avvia.bat`. Nella cartella `Windows\WebcamLR.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\Webcam` devono esserci `WebcamLR.Webcam.comhost.dll` e `WebcamLR.Webcam.Installa.exe`.

1. **Installazione**: scheda «Webcam per le altre app» → «Installa la webcam WebcamLR» → Sì alla domanda di Windows. Attesi: avviso verde «Webcam installata», stato INSTALLATA (punto verde). In Impostazioni → Bluetooth e dispositivi → Fotocamere compare «WebcamLR (Windows Virtual Camera)»: la parte tra parentesi la aggiunge Windows a ogni webcam virtuale, ed è normale che le app la mostrino così.
2. **Senza telefono**: Fotocamera di Windows → cambia fotocamera fino a «WebcamLR». Attesa: l'immagine scura con «WebcamLR · in attesa del telefono», fluida, senza errori. Nell'app lo stato diventa IN ONDA (punto rosso) entro 2 secondi.
3. **Con il telefono**: collega l'iPhone (Wi-Fi, poi cavo USB). Entro 2 secondi la Fotocamera di Windows mostra il video. Stacca il telefono: dopo circa 1 secondo torna l'immagine di attesa, l'app di prova non si blocca. Ricollega: il video torna.
4. **Meet in Chrome e in Edge**: meet.google.com → nuova riunione → impostazioni → Video → «WebcamLR». Anche webcamtests.com: deve dire 1280×720 o 1920×1080 a 30 fps. Se dice «busy or blocked», prova chrome://flags → «MediaFoundation video capture» disattivato e annota il risultato.
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
