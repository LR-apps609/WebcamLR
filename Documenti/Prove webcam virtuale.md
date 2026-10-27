# Prove della webcam virtuale · app per app, Mac e Windows

Una lista da seguire con il telefono collegato e WebcamLR aperta sul computer, per ogni app di chiamata o di ripresa.
Su **Windows** si può fare subito. Sul **Mac** serve la webcam virtuale, quindi l'account sviluppatore a pagamento
(`Mac/project.yml`, attivazione in `Documenti/Webcam virtuale Mac.md`): con l'Apple ID gratuito la webcam non c'è e le prove
MC si saltano.

Ogni prova ha un codice breve (**MC** = Mac, **W** = Windows, **R** = ritardo e audio, uguali sui due computer).
Per ogni prova scrivi a Claude solo il codice e l'esito: `W7 ok`, `MC4 no: schermo nero dopo 3 s` e simili. Se qualcosa non va,
manda anche quello che c'è scritto nella colonna «Cosa mandare».

## Prima di cominciare

1. Telefono collegato (il cavo è meglio: le misure del ritardo sono più pulite), video in arrivo nella finestra di WebcamLR.
2. Apri i numeri (clic sul chip della qualità sotto il video). Dalla versione del 27 ottobre ci sono:
   - **Latenza**: il ritardo «da vetro a uscita», dalla luce che entra nel telefono all'immagine che esce. È la webcam
     se un'app la sta usando, altrimenti la finestra. È lo stesso numero che il telefono mostra nei Dettagli.
   - **Tappe**: arrivo (soprattutto la rete), finestra (o anteprima su Windows) e webcam.
3. Nel **Registro del collegamento** ogni 30 secondi compare una riga «Da vetro a uscita: arrivo … · finestra … · webcam …
   (attesa nella webcam …) · audio …». Su Windows c'è anche «recuperati … ms»: quanto il lettore di Windows ha tolto di attesa
   inutile. È la riga più utile da mandare.
4. Obiettivi: **sotto i 100 ms con il cavo, sotto i 150 ms in Wi-Fi** per la webcam; l'audio entro ±20 ms dal video.

### Formati che la webcam offre

| | Mac | Windows 11 e 10 |
|---|---|---|
| 16:9 a 30 fps | 1920×1080, 1280×720 | 1920×1080, 1280×720, 960×540, 640×360 |
| 16:9 a 60 fps | 1920×1080, 1280×720 | 1920×1080, 1280×720 |
| 4K | 3840×2160 a 30 fps | 3840×2160 a 30 fps |
| 4:3, 15 fps | non offerti | non offerti |

Un'app che vuole il **4:3** (640×480, 1280×960) o i **15 fps** non trova quel formato e deve prenderne uno 16:9 e adattarlo da sé
(ritaglio ai lati o bande, fotogrammi saltati). È il comportamento atteso, ma va verificato: se un'app mostra un errore o
uno schermo nero invece di adattarsi, è un caso da segnalare (prove W13 e MC12).

Il formato scelto dall'app si legge così:
- **Mac**: nel registro di WebcamLR, «Un'app usa la webcam a 60 fps…» quando chiede 60 fps; il formato esatto con il comando
  `log stream` in fondo a questo documento (riga «Formato 1920×1080 a 60 fps»).
- **Windows 11**: in `C:\ProgramData\WebcamLR\Registro webcam.txt`, riga «Video dall'app: 1920×1080 → 1280×720 a 30 fps»
  (misura che arriva dal telefono → formato scelto dall'app). **Windows 10**: `%LOCALAPPDATA%\WebcamLR\Registro webcam DirectShow.txt`.
  Nel registro di WebcamLR: «Un'app usa la webcam (1280×720 a 30 fps)».

## Le prove comuni a ogni app

Per ogni app qui sotto si fanno gli stessi passi; nella tabella dell'app c'è solo ciò che cambia.

| Passo | Cosa fare | Cosa deve succedere |
|---|---|---|
| a | Apri l'app e scegli la fotocamera «WebcamLR» | Compare nell'elenco con il nome «WebcamLR»; l'anteprima mostra il telefono entro 2 secondi |
| b | Guarda il telefono | Il rosso **IN ONDA** si accende; nel computer la scheda del telefono dice «In onda» con il nome dell'app |
| c | Chiudi l'app (o cambia fotocamera) | IN ONDA si spegne entro 2–3 secondi |
| d | Durante l'uso, spegni il Wi-Fi o stacca il cavo per 5 secondi | Nell'app: l'ultima immagine per 2 secondi, poi «Collegamento interrotto»; quando torna, il video riprende da solo, senza richiamare |
| e | Chiudi WebcamLR sul computer con l'app ancora aperta | Nell'app: «La webcam non è collegata» dopo circa 2 secondi, nessun blocco dell'app |
| f | Batti le mani davanti al telefono, guardando l'anteprima dell'app (o registra con l'app, se può) | Il suono del battito arriva insieme all'immagine delle mani (prova R2) |
| g | Copri e scopri l'obiettivo, guardando insieme il telefono e l'app | Il ritardo a occhio è sotto un decimo di secondo con il cavo; il numero «webcam» nei numeri è sotto i 100 ms |

## Mac (serve l'account a pagamento)

| Codice | App | Formato da provare | Cosa deve succedere in più | Errori tipici |
|---|---|---|---|---|
| MC1 | **FaceTime** | quello che sceglie FaceTime (di solito 1280×720 a 30) | passi a–g; FaceTime non mostra avvisi | FaceTime non elenca WebcamLR: estensione non attiva (`systemextensionsctl list`) |
| MC2 | **Photo Booth** | 1280×720 | anteprima fluida, foto scattata con l'immagine del telefono | immagine specchiata: Photo Booth specchia l'anteprima di suo, la foto salvata è dritta |
| MC3 | **QuickTime Player** → Archivio → Nuova registrazione filmato | 1920×1080 (Qualità massima) | registra 30 secondi con il microfono «WebcamLR (microphone)»; nel file voce e labbra insieme (R2) | il file a 1080p ha bande: WebcamLR adatta senza tagliare, è giusto con il telefono in verticale |
| MC4 | **Zoom** (app) | Impostazioni → Video: «HD» acceso (1280×720 o 1920×1080) | passi a–g in una riunione di prova (zoom.us/test) | Zoom chiede il permesso della Fotocamera la prima volta: senza, schermo nero |
| MC5 | **Microsoft Teams** (app nuova) | quello che sceglie Teams | **la prova più importante**: in una chiamata vera l'altra persona deve vederti, non solo l'anteprima | anteprima sì, altra persona no: annota la versione di Teams e manda il `log stream` |
| MC6 | **Google Meet in Safari** | meet.google.com/landing → «Controlla audio e video» | passi a–g | Safari chiede il permesso per il sito: «Consenti» |
| MC7 | **Google Meet in Chrome** | come MC6 | passi a–g | in Chrome: Impostazioni di Sistema → Privacy → Fotocamera → Chrome acceso |
| MC8 | **Google Meet in Edge** | come MC6 | passi a–g | come MC7, per Edge |
| MC9 | **OBS Studio** | Sorgente «Dispositivo di cattura video», preimpostazione 1920×1080 e poi 1280×720; poi **60 fps** | a 60 fps WebcamLR chiede 60 fps al telefono (riga nel registro); immagine fluida | a 60 fps con il telefono a 30 ogni immagine esce due volte: va bene, niente scatti |
| MC10 | **OBS Studio**, 4K | Risoluzione 3840×2160 | con il telefono in 4K l'immagine è nitida; con il telefono a 1080p l'estensione ingrandisce | 4K a scatti: annota il Mac (Intel o Apple) e gli fps nei numeri |
| MC11 | **Discord** (app) | Impostazioni → Voce e video → Fotocamera | anteprima e videochiamata | Discord non elenca la webcam: chiudilo del tutto (anche dalla barra in alto) e riaprilo |
| MC12 | **WhatsApp desktop** | videochiamata | passi a, b, c, g; se WhatsApp chiede 4:3 l'immagine è ritagliata ai lati, senza errori | nessuna fotocamera: permesso della Fotocamera per WhatsApp |
| MC13 | **Zoom** con due telefoni (Pro) | come MC4 | «Usa prospettiva» sul secondo telefono: in Zoom l'immagine cambia senza richiamare | per un attimo l'immagine di attesa: segnalalo con i secondi |

## Windows (si può fare subito)

Prima: in WebcamLR, colonna Uscite, la webcam è «installata». Su Windows 11 la webcam è quella del Frame Server; su Windows 10
è il filtro DirectShow (alcune app non la vedono: vedi la tabella).

| Codice | App | Formato da provare | Cosa deve succedere in più | Errori tipici |
|---|---|---|---|---|
| W1 | **Fotocamera di Windows** (solo Windows 11) | Impostazioni dell'app → Qualità video: 1080p 30 fps, poi 720p | anteprima e un video di 10 secondi registrato | su Windows 10 WebcamLR non compare: è previsto (filtro DirectShow) |
| W2 | **Zoom** (app) | Impostazioni → Video: «HD» acceso | passi a–g in zoom.us/test | Zoom vede «WebcamLR» ma è nero: manda il `Registro webcam.txt` |
| W3 | **Microsoft Teams** (app nuova) | quello che sceglie Teams | **la prova più importante**: in una chiamata vera l'altra persona deve vederti | anteprima sì, altra persona no (problema noto delle webcam virtuali): annota la versione di Teams, prova anche Teams nel browser (W4) |
| W4 | **Teams nel browser** (Edge) | teams.microsoft.com | passi a–g | è il ripiego se W3 non va |
| W5 | **Google Meet in Chrome** | meet.google.com/landing | passi a–g | «Fotocamera occupata»: un'altra app la sta già usando con un formato diverso; chiudila |
| W6 | **Google Meet in Edge** | come W5 | passi a–g | come W5 |
| W7 | **Discord** (app) | Impostazioni → Voce e video | anteprima e videochiamata | Discord desktop a volte non vede webcam che il browser vede: prova discord.com nel browser e scrivi quale va |
| W8 | **WhatsApp desktop** | videochiamata | passi a, b, c, g | la versione vecchia (UWP) non vede il filtro DirectShow di Windows 10: annota la versione |
| W9 | **OBS Studio** | Sorgente «Dispositivo di acquisizione video», Risoluzione 1920×1080, poi 1280×720 | immagine fluida; nel `Registro webcam.txt` la riga «Video dall'app» con il formato scelto | OBS mostra 640×360: hai lasciato la risoluzione «Predefinita del dispositivo»; scegli quella personalizzata |
| W10 | **OBS Studio a 60 fps** | FPS 60, 1280×720 | WebcamLR chiede 60 fps al telefono (riga nel registro), immagine fluida | a scatti: manda la riga «Da vetro a uscita» e gli fps dei numeri |
| W11 | **OBS Studio in 4K** | 3840×2160 a 30 | immagine nitida con il telefono in 4K | il PC fatica: guarda «Fotogrammi» nei numeri e manda il registro |
| W12 | **Zoom** (app) a 540p o 360p | Zoom senza «HD», rete lenta | l'immagine resta nitida in proporzione, nessun errore | — |
| W13 | Un'app che vuole **4:3 o 15 fps** (per esempio webcamtests.com in Chrome, che prova i formati) | lascia che il sito provi i formati | il sito sceglie un formato 16:9 e adatta; nessun «busy or blocked» | «busy or blocked» in Chrome: segnalato anche con altre webcam virtuali; prova in Edge e scrivi se cambia |
| W14 | **Due app insieme** (Zoom e Fotocamera di Windows) | uguale nelle due | su Windows 11 le due app vedono la webcam insieme (Frame Server la condivide) | la seconda dice «in uso»: annota quale app hai aperto per prima |

## Ritardo e audio (su tutti e due i computer)

| Codice | Cosa fare | Cosa deve succedere | Cosa mandare se non va |
|---|---|---|---|
| R1 | Con un'app che usa la webcam, lascia andare 2 minuti e guarda i numeri | «webcam» sotto 100 ms con il cavo, sotto 150 ms in Wi-Fi; «finestra»/«anteprima» poco sotto «webcam» | due righe «Da vetro a uscita» del registro, a un minuto di distanza |
| R2 | Microfono del telefono acceso, uscita audio verso «WebcamLR (microphone)» (Mac) o VB-CABLE (Windows). Batti le mani davanti al telefono e registra con l'app (QuickTime sul Mac, OBS o Fotocamera di Windows) | nel video registrato il suono e le mani coincidono (entro un fotogramma) | il file registrato (o i secondi di scarto a occhio) e la riga «Da vetro a uscita», che contiene anche il ritardo dell'audio |
| R3 | Come R2, ma muovi il telefono in Wi-Fi lontano dal router per un minuto e poi torna vicino | la voce non fa salti né eco; il ritardo dell'audio nella riga del registro cambia al massimo una volta ogni 5 secondi | le righe «Da vetro a uscita» di quel minuto |
| R4 | Su Windows, con OBS o Zoom aperti da 5 minuti | «recuperati» nella riga del registro resta piccolo (0–100 ms) e il numero «webcam» non sale col tempo | le righe «Da vetro a uscita» all'inizio e dopo 5 minuti |
| R5 | Su Mac, con un'app a 60 fps e il telefono a 30 (o il contrario) | movimento regolare, nessun «saltello» ogni qualche secondo | un video fatto col telefono dello schermo, se riesci, e il `log stream` |

## Cosa mandare a Claude

Sempre: il codice della prova, l'esito, il sistema (macOS 15.x, Windows 11 24H2…) e la versione dell'app provata.

- **Mac**: la riga «Da vetro a uscita» del Registro del collegamento (colonna Dispositivi → «Registro del collegamento»), e se
  la webcam non va, in **Terminale**:
  ```
  systemextensionsctl list
  log stream --predicate 'subsystem BEGINSWITH "it.lrapps.webcamlr.mac"' --level info
  ```
  (la seconda mentre provi; poi copia le righe).
- **Windows**: il Registro del collegamento (pulsante «Copia»), e i file
  `C:\ProgramData\WebcamLR\Registro webcam.txt` (Windows 11) o `%LOCALAPPDATA%\WebcamLR\Registro webcam DirectShow.txt` (Windows 10).
- Uno **screenshot** dell'app con la scelta della fotocamera, se WebcamLR non compare o l'immagine è sbagliata (nera, verde,
  a righe, tagliata).

## Errori tipici e cosa vogliono dire

| Cosa vedi | Probabile causa | Cosa fare |
|---|---|---|
| WebcamLR non è nell'elenco | Mac: estensione non attiva o app non riavviata. Windows: webcam non installata, o filtro DirectShow con un'app che usa solo Media Foundation | Mac: `systemextensionsctl list`, chiudi l'app con ⌘Q. Windows: colonna Uscite → stato della webcam |
| Immagine di attesa anche con il telefono collegato | WebcamLR sul computer non manda il video alla webcam (Mac: manca il permesso della Fotocamera per WebcamLR) | chiudi e riapri WebcamLR; manda il registro |
| Immagine verde o a righe | formato dei pixel letto male dall'app | screenshot e il formato scelto (riga «Video dall'app» o «Formato…») |
| Immagine schiacciata o allungata | l'app ha chiesto un formato non 16:9 e lo stira invece di ritagliare | screenshot e nome dell'app: è un caso per la prova W13/MC12 |
| A scatti ogni qualche secondo | ritmo dell'uscita diverso da quello del telefono | gli fps nei numeri, il formato dell'app, il `log stream` (Mac) o il `Registro webcam.txt` (Windows) |
| La voce arriva prima o dopo le labbra | ritardo dell'audio non allineato | la riga «Da vetro a uscita» e quanto è lo scarto a occhio (prova R2) |
| L'altra persona non ti vede, l'anteprima sì (Teams) | motore multimediale di Teams | versione di Teams, prova nel browser, manda i registri |
