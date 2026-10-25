# Microfono del telefono sul Mac · P20

Il microfono del telefono compare sul Mac come un ingresso audio chiamato **«WebcamLR (microfono)»**. Lo vedono tutte le app: Zoom, Meet, Teams, FaceTime, OBS, QuickTime. L'audio è allineato al video della webcam virtuale.

Funziona con l'**Apple ID gratuito**: non servono il gruppo d'app né un'estensione di sistema. Serve la **password del Mac** una volta, per l'installazione.

## Come è fatto

```
telefono ──(pacchetti tipo 3, AAC-LC, cifrati)──▶ WebcamLR.app
                                                    │ decodifica AAC → Float32 48 kHz mono
                                                    │ mette ogni campione nel momento in cui va ascoltato
                                                    ▼
                                          memoria condivisa (128 KB)  ◀── la crea l'aiutante (LaunchDaemon)
                                                    ▲                      e la passa a tutti e due con XPC
                                                    │ legge il tratto del suo ciclo
                                    coreaudiod ── «WebcamLR Microfono.driver» ──▶ Zoom, Meet, FaceTime…
```

Tre pezzi, tutti in `Mac/Microfono/`:

| Pezzo | Dove | Cosa fa |
|---|---|---|
| Driver audio | `Driver/Microfono.c` → `/Library/Audio/Plug-Ins/HAL/WebcamLR Microfono.driver` | Audio Server Plug-in (driver HAL) in C, caricato da coreaudiod. Un dispositivo con un solo flusso d'ingresso: 48 kHz, mono, Float32. È anche la propria sorgente di orologio |
| Aiutante | `Aiuto/main.c` → `/Library/Application Support/WebcamLR/webcamlr-microfono-aiuto`, avviato da `/Library/LaunchDaemons/it.lrapps.webcamlr.microfono.plist` | Crea la memoria condivisa e la consegna con XPC sul servizio Mach `it.lrapps.webcamlr.microfono`. L'audio non passa da qui |
| Lato app | `App/CollegamentoMicrofono.c` (C) e `Sorgenti/MicrofonoTelefono.swift` | Riceve i pacchetti dalla sessione, decodifica con AudioConverter e scrive nella memoria |

La forma della memoria è in `Comune/AnelloMicrofono.h`, l'unico file incluso da tutti e tre.

Il driver è scritto da noi. Segue la struttura dell'esempio Apple «NullAudio» (*Creating an Audio Server Driver Plug-in*): un plug-in, un dispositivo, un flusso. **Nessuna riga viene da BlackHole**, che è GPL-3.0. Non usiamo nemmeno libASPL (MIT): con un solo dispositivo e un solo flusso il C diretto resta corto (circa 750 righe con i commenti) e non porta dipendenze.

## Perché un aiutante (la comunicazione tra app e driver)

La difficoltà vera è far parlare l'app con il driver. Tutti e due sono chiusi in un sandbox, e i due sandbox sono diversi.

**Il driver** gira dentro coreaudiod, che è nel sandbox. L'header di Apple `AudioServerPlugIn.h` dice che un plug-in:
- può leggere solo i file del proprio bundle e le librerie di sistema;
- può scrivere solo nelle cartelle temporanee e nella cache di sistema;
- non può parlare con altri processi, **tranne** i servizi Mach scritti nel suo Info.plist sotto `AudioServerPlugIn_MachServices` (ci sono anche `AudioServerPlugIn_Network` e `AudioServerPlugIn_IOKitUserClients`).

Chi ha provato ad aprire un file da un driver HAL riceve «Operation not permitted», anche in `/tmp` ([forum Apple 129737](https://developer.apple.com/forums/thread/129737)).

**L'app** è nel sandbox delle app. Una memoria POSIX (`shm_open`) può crearla solo con un nome che comincia con il gruppo d'app. Il gruppo d'app richiede l'account a pagamento, come la webcam virtuale.

Strade considerate:

| Strada | Funziona? |
|---|---|
| File mappato in memoria in `/tmp`, `/Users/Shared` o nel contenitore dell'app | **No.** coreaudiod non legge fuori dal bundle del driver |
| Memoria POSIX con il nome del gruppo d'app (account a pagamento) | **No**, nemmeno con l'account a pagamento: il sandbox di coreaudiod non apre memorie POSIX altrui. Il gruppo d'app risolve solo il lato dell'app |
| L'app pubblica un servizio Mach | **No.** Un'app nel sandbox può pubblicare solo nomi del gruppo d'app, e solo nella sessione dell'utente: coreaudiod, che è un servizio di sistema, non li vede |
| Il driver pubblica un servizio Mach | **No.** Un plug-in non può registrare servizi |
| **Un LaunchDaemon pubblica il servizio, app e driver lo cercano** | **Sì.** Il driver lo dichiara in `AudioServerPlugIn_MachServices`. L'app usa l'eccezione `com.apple.security.temporary-exception.mach-lookup.global-name`, che non richiede l'account a pagamento, come quella per `usbmuxd` già usata per il cavo USB |

La stessa architettura (driver ↔ servizio Mach di un LaunchDaemon) è quella di progetti noti come Background Music. Qui l'abbiamo **ricostruita da zero**: Background Music è GPL e non abbiamo copiato codice.

Per non far passare l'audio da un terzo processo, l'aiutante crea una sola memoria (`mmap` condivisa e anonima) e manda a chi la chiede un `xpc_shmem` della stessa memoria. Dopo la consegna l'app scrive e il driver legge direttamente, senza copie e senza messaggi. L'aiutante gira come utente `nobody` e non tocca l'audio.

**Conclusione:** l'account a pagamento **non serve** e non aiuterebbe. La strada è la stessa con i due account. Per la distribuzione al pubblico servirà invece la firma Developer ID (vedi *Distribuzione*).

## Sincronia con il video

- Ogni pacchetto audio porta il timestamp del primo campione sull'orologio dei fotogrammi del telefono (Protocollo.md, *Audio*).
- La sessione passa al microfono la **stessa differenza di orologi del video**, cioè il `pong` più rapido degli ultimi 10. Così si ottiene l'istante di cattura sul Mac.
- Il frame va ascoltato a **cattura + ritardo**. Il ritardo è la latenza del video dell'ultimo secondo, tenuta fra **60 e 300 ms**: voce e labbra arrivano insieme. Il ritardo cambia solo se la differenza supera 20 ms, perché ogni cambio è un piccolo salto. Il minimo di 60 ms fa da riserva contro i salti della rete (il buffer anti-jitter).
- **Linea del tempo comune**: l'indice di ogni campione nella memoria è il tempo di sistema dall'avvio (`CLOCK_UPTIME_RAW`, lo stesso di `Orologio`) in campioni a 48 kHz. Anche l'orologio del driver è il tempo di sistema. Il driver legge il tratto che corrisponde al suo ciclo e non deve decidere niente.
- Un frame che arriva entro 10 ms dal punto atteso si attacca al precedente. Così non ci sono buchi dovuti agli arrotondamenti né alle piccole derive dell'orologio del microfono.
- **In ritardo**: la parte già passata si scarta; un frame passato del tutto si butta.
- **Niente clic**:
  - prima di un buco la coda già scritta scende a zero in 2,7 ms (128 campioni) e il frame dopo il buco entra con una dissolvenza;
  - una sovrapposizione, quando il ritardo cambia, diventa una dissolvenza incrociata;
  - quando l'audio manca del tutto (telefono spento, rete caduta) il driver porta il volume a zero in 64 campioni e lo riporta su quando l'audio torna.

Da verificare sul Mac: il decodificatore AAC di Apple può aggiungere un ritardo fisso, il «priming» del codec. Se la prova del battito di mani mostra la voce sempre in ritardo sulle labbra, si corregge `MicrofonoTelefono.correzioneDecodifica`.

## Interfaccia

Colonna **Uscite** → riga **Microfono del telefono**:

- **Stato**:
  - *non installato*: il driver non è nel sistema;
  - *spento*: l'interruttore è spento;
  - *attivo*: arriva l'audio;
  - *in uso*: un'app sta usando «WebcamLR (microfono)».
  Il verde compare solo quando l'audio arriva davvero; il rosso resta per «in onda» e la registrazione.
- **Interruttore**: manda `comando.audio` vero o falso. La scelta resta salvata: a ogni telefono che si collega e dichiara `capacita.audio` l'audio si richiede da solo.
- **Livello**: una barra ciano mentre l'audio arriva (ambra vicino alla saturazione).
- Senza telefono la riga è grigia: «Collega un telefono per usarlo.» Se il telefono non dichiara `capacita.audio`: «Il telefono non manda l'audio.»

L'app capisce se il driver è installato cercando il dispositivo con l'UID `it.lrapps.webcamlr.microfono.dispositivo`. Capisce se è in uso dalla proprietà `DeviceIsRunningSomewhere`. Controlla ogni 2 secondi.

## Installazione per le prove (Apple ID gratuito)

1. Doppio clic su `Strumenti/Costruisci e installa.command`, come sempre. Lo script compila anche il microfono. Se il microfono non compila lo segnala, ma l'app si installa lo stesso.
2. Doppio clic su **`Strumenti/Installa microfono.command`**.
   - Lo script compila il driver e l'aiutante con la firma locale («-»), poi chiede la **password del Mac**.
   - Copia il driver in `/Library/Audio/Plug-Ins/HAL`, l'aiutante in `/Library/Application Support/WebcamLR` e il suo plist in `/Library/LaunchDaemons`, poi avvia l'aiutante.
   - Infine riavvia coreaudiod: per un attimo i suoni del Mac si fermano.
3. Lo script controlla che «WebcamLR (microfono)» compaia tra i dispositivi audio.
4. **Chiudi (⌘Q) e riapri le app di chiamata** già aperte: molte leggono l'elenco dei microfoni solo all'avvio.

Il microfono va reinstallato solo quando cambia il codice in `Mac/Microfono/`, non a ogni build dell'app.

**Per toglierlo**: `Strumenti/Rimuovi microfono.command` (chiede la password). Da fare prima di cestinare WebcamLR.

Comandi utili nel Terminale, se qualcosa non va:

```
system_profiler SPAudioDataType | grep -A3 WebcamLR          # il dispositivo c'è?
sudo launchctl print system/it.lrapps.webcamlr.microfono     # l'aiutante è caricato?
log show --last 5m --predicate 'process == "coreaudiod"' | grep -i webcamlr
```

## Distribuzione (più avanti, account a pagamento)

Per chi scarica WebcamLR dal sito non si possono usare gli script: serve un **pacchetto .pkg firmato e notarizzato**.

1. Il driver e l'aiutante si firmano con **Developer ID Application**, con il runtime protetto.
2. Si prepara una cartella con la struttura di destinazione:
   - `/Library/Audio/Plug-Ins/HAL/WebcamLR Microfono.driver`
   - `/Library/Application Support/WebcamLR/webcamlr-microfono-aiuto`
   - `/Library/LaunchDaemons/it.lrapps.webcamlr.microfono.plist`
3. Si costruisce il pacchetto con `pkgbuild --root … --scripts … --identifier it.lrapps.webcamlr.microfono`, poi `productbuild` con la firma **Developer ID Installer**.
4. Lo script `postinstall` esegue `launchctl bootstrap system /Library/LaunchDaemons/it.lrapps.webcamlr.microfono.plist`, poi `killall coreaudiod`.
5. Si notarizza con `xcrun notarytool submit … --wait`, poi `xcrun stapler staple`.
6. Nell'app, la nota «non installato» diventa un pulsante «Installa il microfono» che apre il .pkg incluso nell'app con `NSWorkspace.open`. Il sandbox lo permette e l'Installer di macOS chiede la password.
7. Per la disinstallazione: un secondo pkg, oppure le stesse righe di `Rimuovi microfono.command` dentro uno script firmato.

Alternative scartate:

- **SMAppService.daemon** (macOS 13+). Registrerebbe l'aiutante dall'app, con l'approvazione in Impostazioni › Elementi di login. Però il driver deve stare comunque in `/Library/Audio/Plug-Ins/HAL`, e lì serve un amministratore: il pkg resta necessario.
- **AuthorizationExecuteWithPrivileges**: deprecata e non disponibile nel sandbox.

Da decidere per il **Mac App Store**: l'eccezione `mach-lookup.global-name` non è accettata, come quella di `usbmuxd`. Vale la stessa decisione in sospeso: per ora la distribuzione è dal sito (Piano aggiornamenti, 1.8).

## Sicurezza

- Qualsiasi processo del Mac può chiedere la memoria all'aiutante e quindi scrivere nel microfono virtuale. Per le prove va bene.
- Prima della distribuzione l'aiutante dovrebbe controllare la firma di chi chiede: dal token di audit del collegamento XPC (`xpc_connection_get_audit_token` → `SecCodeCopyGuestWithAttributes`) si accettano solo l'app WebcamLR con il nostro Team ID e coreaudiod.
- Il driver legge la memoria e non la scrive (tranne l'istante dell'ultima lettura, per la diagnosi). I dati vanno solo dall'app alle app di chiamata.

## Limiti noti e cose da verificare

- **Firma locale**: coreaudiod deve caricare un driver firmato «-» su Apple Silicon. Ci aspettiamo di sì, perché i driver compilati da sé funzionano così, ma non l'abbiamo provato. Se non compare, si prova la firma «Apple Development» togliendo `CODE_SIGN_IDENTITY: "-"` in `base.yml`.
- **macOS 14 e successivi**: i plug-in di terzi possono girare in un processo separato di coreaudiod (*Core Audio Driver Service*). Le regole del sandbox dovrebbero essere le stesse (Info.plist), ma va verificato.
- Se l'aiutante si chiude per un errore, ne riparte uno nuovo con una memoria nuova. Il driver se ne accorge e si ricollega dopo 2 secondi; l'app al frame successivo.
- Non c'è ricampionamento contro la deriva tra l'orologio del microfono del telefono e quello del Mac. Ogni pochi minuti può esserci un salto di qualche millisecondo, coperto da una dissolvenza.
- Il codice C e Swift è stato scritto senza un compilatore macOS (ambiente Linux). Il C ha superato solo un controllo di sintassi con header finti, non quelli di Apple. Il primo giro di build sul Mac potrebbe segnalare errori da correggere.

## Checklist P20 (sul Mac)

1. `Costruisci e installa.command`: l'app parte. Nel registro non c'è «Il microfono virtuale non compila».
2. Nella colonna Uscite, senza telefono: la riga «Microfono del telefono» è grigia, con «Collega un telefono per usarlo.» e lo stato «non installato».
3. `Installa microfono.command`: alla fine dice «Fatto». In Impostazioni di Sistema › Suono › Ingresso c'è **WebcamLR (microfono)**.
4. Senza riaprire l'app, entro 2 secondi lo stato diventa «spento».
5. Collega il telefono e accendi l'interruttore: lo stato diventa «attivo» e la barra del livello si muove quando parli. Con un telefono senza audio compare «Il telefono non manda l'audio.» e l'interruttore resta grigio.
6. QuickTime › Nuova registrazione audio › microfono «WebcamLR (microfono)»: registra 20 secondi parlando. Non devono sentirsi clic né buchi. Su WebcamLR lo stato è «in uso».
7. Prova del battito di mani: FaceTime o Photo Booth con la webcam virtuale **e** il microfono WebcamLR, registra un video battendo le mani davanti al telefono. Il suono è sul fotogramma delle mani che si toccano? Annota se è in anticipo o in ritardo e di quanto (un fotogramma = 33 ms).
8. Zoom (zoom.us/test), Meet e Teams: scegli «WebcamLR (microfono)», poi spegni l'interruttore. Il microfono resta nell'elenco ma tace, senza clic. Riaccendi: la voce torna.
9. Allontanati con il telefono finché il Wi-Fi peggiora: la voce può interrompersi, ma senza scoppi.
10. Scollega il telefono e ricollegalo: con l'interruttore acceso l'audio riparte da solo.
11. `Rimuovi microfono.command`: «WebcamLR (microfono)» sparisce e lo stato torna «non installato».

Se qualcosa non va, manda a Claude: `Strumenti/ultima-build.log`, il risultato dei comandi della sezione *Installazione* e uno screenshot della colonna Uscite.
