# Effetti su Windows

Studio di fattibilità e base del «motore effetti» sul PC (decisione del 27 ottobre: gli effetti pesanti si fanno sul
computer, come iVCam; il telefono fa solo fotocamera e codifica). Questo documento copre **Windows**: il modello che
ritaglia la persona, le licenze, i tempi, la libreria (`Windows/WebcamLR.Effetti`) e il **motore effetti collegato alla
finestra** (ramo `effetti-windows`, sezione «Motore effetti» qui sotto). Dalla lista qualità 1.0: la rifinitura del
bordo come il Mac (Qualità 4) e la composizione dello sfondo sulla scheda video (Qualità 5), sezione «Qualità 4 e 5»;
bokeh, mosaico e schermo verde, su Mac e Windows (Qualità 7 e 8), sezione «Qualità 7 e 8».

## In breve

- **Modello:** MediaPipe **Selfie Multiclass 256×256** convertito in ONNX (`ritaglio_persona.onnx`, 16 MB), persona =
  1 − sfondo, sulla scheda video con **ONNX Runtime + DirectML**. Ripiego: MediaPipe **Selfie Segmenter landscape
  144×256** (`ritaglio_persona_leggero.onnx`, 0,4 MB) sul processore. Sono gli stessi due modelli dell'app Android
  (Documenti/Modelli ritaglio.md), quindi stessa resa sulle due piattaforme.
- **Licenze:** modelli Apache 2.0 (Google), ONNX Runtime MIT (Microsoft), DirectML licenza Microsoft ridistribuibile solo
  per Windows. Niente GPL, niente clausole non commerciali.
- **Conversione verificata:** il modello ONNX dà gli stessi numeri del .tflite originale (differenza massima 4·10⁻⁵ sulle
  uscite grezze); la libreria C# dà la stessa maschera di onnxruntime in Python (differenza 0/255).
- **Tempi su CPU misurati qui** (Xeon a 2,8 GHz, 4 processori virtuali, Linux): pieno 53 ms, leggero 5 ms per maschera
  dalla libreria C#. Il pieno sul processore è troppo lento per 30 fps: serve la scheda video. Sulla GPU con DirectML ci
  si aspettano 3–20 ms secondo la scheda (stima, **da misurare sul PC di Ledion**).
- **API:** `RitaglioPersona.Crea(opzioni)` e `Calcola(ReadOnlySpan<byte> bgra, larghezza, altezza, passo) →
  MascheraPersona` (byte 0–255 alla misura del modello, da usare come texture R8 stirata sul fotogramma).

## Motore effetti (collegato, prima versione sul processore)

Stesso disegno e stessi nomi del Mac (`Mac/Sorgenti/MotoreEffetti.swift`, ramo `effetti-mac`): `EffettiSulComputer`
(vero di serie), `ImpostazioniMotore`, `StatoEffettiComputer`, `MotoreEffetti` con le sue `Misure` e `Note`,
`MollaInquadratura`, livelli che scendono presto e risalgono piano da soli (Qualità 6, «Qualità che si adatta al PC»).

### Architettura

```
telefono ──H.264/HEVC──▶ MotoreVideo (WebcamLR.App)
                          decodificatore hardware «frame server» (uno solo per il telefono nella webcam)
                          CopyFrameToVideoSurface (la scheda video scala: oltre il 1080p si lavora a 1080p)
                          → memoria BGRA ─▶ MotoreEffetti.Elabora (WebcamLR.Effetti, non aspetta mai)
                                             coda di analisi: metà e quarto della misura, maschera dal quarto
                                                              (RitaglioPersona: DirectML o processore), volto dalla maschera
                                             coda di resa:    Compositore con la maschera DELLO STESSO fotogramma: le cose
                                                              piccole sul processore, il passo a piena risoluzione dello
                                                              sfondo sulla scheda video (Direct3D 11) o sul processore
                                                              → giro di 16 immagini di uscita
                          ─▶ Fotogramma(immagine, elaborata) ─┬▶ anteprima e finestra mini (VideoElaborato, WriteableBitmap
                                                              │   sopra il MediaPlayerElement)
                                                              ├▶ webcam virtuale (UscitaWebcam.Scrivi → NV12, memoria condivisa)
                                                              ├▶ registrazione (RegistrazioneElaborata: MediaTranscoder H.264 hardware)
                                                              └▶ foto e «Copia il fotogramma» (MotoreVideo.PrendiAsync)
```

- **Un punto unico**: con `EffettiSulComputer` la webcam non usa più il suo decodificatore e le istantanee nemmeno; tutte
  le uscite prendono da `MotoreVideo`. Con gli effetti spenti l'anteprima resta il `MediaPlayerElement` hardware di
  sempre (costo zero) e le altre uscite ricevono il fotogramma com'è, copiato solo se serve (webcam in uso, registrazione,
  foto chiesta).
- **Niente attese nel fotogramma**: il fotogramma N si compone con la maschera di N; se l'analisi è occupata ne aspetta
  al massimo uno, un terzo fa scartare il più vecchio (come il Mac). Ritardo aggiunto = maschera + resa.
- **Riservatezza** (lezione del Mac): con lo sfondo acceso un fotogramma senza maschera usa l'ultima maschera buona, se
  non ha più di 0,5 s (`EtaMassimaMaschera`); se è più vecchia o non ce n'è nessuna non si consegna niente (anteprima e
  webcam tengono l'ultima immagine elaborata). Mai lo sfondo vero.
- **Scheda video persa** (driver aggiornato, sospensione, TDR): dopo 3 errori della maschera di fila la fonte si chiude e
  il fotogramma dopo la riapre; la prima volta come prima, dalla seconda solo sul processore. Al massimo 3 riaperture,
  il conto si azzera dopo 300 maschere buone di fila. Nel registro: «il ritaglio si chiude e si riapre».
  Un errore di resa non consegna l'originale. Dopo `Ferma`/`Azzera` (telefono via, cambio di telefono o di formato) i
  fotogrammi ancora in lavorazione non arrivano più alle uscite (generazione).
- **Specchio e sfondo solo con la fotocamera frontale** (`stato.obiettivo`), come oggi: con la posteriore i pulsanti
  restano grigi e il motore non specchia e non cambia lo sfondo.
- **Telefono**: alla prima `capacita` di ogni sessione si decide (`TelecomandoEffetti`, come `decidiEffetti` del Mac;
  Protocollo.md, «Effetti sul computer»). Con `capacita.effettiSulComputer` riceve `comando.effettiSulComputer: true` e poi
  `effetti` (specchio, sfondo, luce sul volto come li fa davvero il motore per lui: `RegoleTelecomando.Stato`), di nuovo a
  ogni cambio; i suoi pulsanti mandano `chiedi-effetto`, che il PC applica come i suoi pulsanti (solo frontale, mai sopra
  Ritratto o Luce da studio, «sfocato» con l'ultimo livello del PC) e a cui risponde sempre con `effetti`. Un telefono di
  prima riceve invece un `comando` che spegne i suoi effetti di immagine (sfondo nessuno, filtro naturale, regolazioni 0,
  pelle 0, calore 0, scritta vuota, `togliLogo`, specchia e inquadratura falsi, luce sul volto spenta). Poi gli vanno solo
  fotocamera, doppia vista e postura (`RegoleEffettiComputer.PerIlTelefono`). Le immagini caricate (sfondo personale,
  logo) restano sul PC.
- **Interfaccia**: colonna «Effetti», «Specchia», «Sfondo» con il suo menu e la pagina «Sfondo» delle impostazioni
  leggono e scrivono `effettiComputer` (un `ControlloEffetti` in modo computer), salvato in `effetti-computer.json`
  (la prima volta calore 0,3). Le capacità degli effetti le dà il PC (`EffettiComputer.CapacitaEffetti`: tutti i filtri,
  gli 8 sfondi pronti, pelle, luce, inquadratura, scritta e logo, calore, specchio) per qualsiasi telefono.
- **Pro** (`RegoleMotore`, da `capacita.pro` del telefono nella webcam): gratis sfocatura, calore, luce sul volto e
  specchio; Pro lo sfondo sostituito, filtri, regolazioni, pelle, inquadratura, scritta e logo. Con «Ritratto» o «Luce da
  studio» del telefono accesi le nostre restano spente (mai due).
- **Sfondi pronti grandi**: `WebcamLR.App/Assets/Sfondi/grandi/<id>.jpg` (1920×1080, gli stessi del telefono; li scrivono
  anche `Strumenti/genera_sfondi.py` e `prepara_sfondi.py`). «La tua immagine» è la copia salvata dall'app.

### Ricette (portate dal Mac e dall'iPhone)

- **Bordo**: maschera dal quarto della misura, filtro guidato «veloce» (coefficienti al quarto, resa a metà risoluzione,
  guida = luminosità del video) = bordo guidato dal colore; soglia morbida smoothstep **0,3–0,7** (centro 0,5, larga
  0,4: variante «D\*» del banco di qualità, `Documenti/Qualità sfondo - banco.md`) con lo sfocato, centrata a 0,42 e
  larga da 0,8 a 0,2 con l'intensità con il sostituito.
- **Nel tempo** (nella maschera, `RitaglioPersona`): filtro senza ritardo, media dal movimento (D\*) e **isteresi** per
  punto (Qualità 4, `IsteresiMaschera`: persona sopra 0,6, sfondo sotto 0,4, spinta 0,1 dove l'immagine è ferma).
- **Sostituito** (Qualità 4, come `personaSuSfondoNuovo` del Mac): **bordo pulito** dal vecchio sfondo (dove la
  maschera è parziale il colore viene dall'interno sicuro della persona) e **light wrap** dello sfondo nuovo sull'orlo.
- **Sfocatura senza alone**: persona allargata (2m − 0,3) tolta come alfa, sfocatura gaussiana di sfondo × alfa e
  dell'alfa, poi divisione: ogni punto prende colore solo dallo sfondo vicino. Sigma a 1080p 32 × intensità^1,6 (Poco
  3,5 px, Medio 12 px, Tanto 32 px), calcolata sul gradino della piramide (1/4…1/32) dove resta sotto i 3 px.
- **Colore**: calore (la stessa diagonale dell'iPhone, 1,0467 / 0,9946 / 0,9158 in lineare), i 10 filtri e le
  regolazioni come catene di tabelle per canale e matrici 3×3 (12 bit), con AVX2 dove c'è. Differenze volute dal Mac:
  vibranza di «Vivido» come saturazione, ombre/luci di «Cinema» pesate col canale, niente riduzione del rumore di «Notte».
- **Pelle** e **luce sul volto** solo attorno al volto; **nitidezza** sulla luminosità; **inquadratura** con la molla del
  Mac (zoom fino a 1,6×); **scritta** disegnata con GDI+ (Barlow Condensed, `DisegnoScritta`) e **logo** in alto a destra.
- **Volto senza rilevatore a parte**: con il modello pieno il riquadro della classe «pelle del volto» del multiclasse;
  con il leggero la testa (cima della persona). Basta per inquadrare e illuminare; nessun modello in più da scaricare.

### GPU o CPU, e perché

La maschera è sulla **scheda video** con DirectML quando c'è; dalla Qualità 5 anche il **passo a piena risoluzione dello
sfondo** (persona sopra il fondo sfocato o sostituito, bordo pulito, light wrap, calore) va sulla scheda video con
Direct3D 11, con il processore come ripiego automatico (sezione «Qualità 4 e 5»). Il resto della resa (filtri, pelle,
luce, inquadratura, scritta) resta sul **processore** (C# con `System.Numerics`/AVX2, cicli paralleli). Le uscite del
motore restano in memoria (webcam, anteprima, registrazione, foto): il fotogramma sale sulla scheda video e torna, il 4K
si elabora a 1080p.

### Tempi misurati qui (resa a 1080p sul processore)

Xeon 2,8 GHz, **4 processori virtuali**, Linux, Release, mediana di 40 rese dopo il riscaldamento (la macchina è condivisa:
le misure ballano del ±30%). Un PC desktop con 6–8 core veri dovrebbe stare a metà o meno.

| Effetti accesi | Resa (ms, mediana) | Minimo |
|---|---|---|
| solo calore | 3,9 | 3,4 |
| filtro Caldo | 8–15 | 6,6 |
| filtro Cinema + regolazioni | 12–17 | 13,7 |
| sfocatura Poco | 21 | 16 |
| sfocatura Medio | 18–22 | 15 |
| sfocatura Tanto + calore | 19–21 | 14 |
| sfocatura Medio, bordo leggero | 13–15 | 11 |
| sfocatura Medio, veloce | 11–12 | 8,3 |
| sfondo sostituito | 12–14 | 10 |
| pelle + luce sul volto + specchio | 8 | 6 |
| tutto insieme (sfocatura, calore, pelle, luce, filtro, contrasto, nitidezza, specchio, inquadratura) | 45–50 | 40 |

Analisi: riduzioni a metà e a un quarto 1,3 ms; maschera dal quarto sul processore 4 ms (leggero) e 52 ms (pieno: per
questo il pieno va sulla scheda video, o si scende al leggero da soli). Analisi e resa lavorano in parallelo: a 30 fps
(33 ms) la sfocatura con un filtro ci sta anche qui; «tutto insieme» no, e allora il livello scende (vedi sotto) e i
fotogrammi in eccesso si saltano. Nel registro ogni 30 secondi: «Effetti sul PC: … ms (maschera …, resa …; livello;
scheda video/processore, modello) · scartati · senza maschera · anteprima»; nei numeri la riga «Effetti».

### Qualità che si adatta al PC (Qualità 6)

Come Google Meet: sui PC deboli lo sfondo non deve far scendere i fotogrammi. Con lo sfondo acceso `SceltaLivello`
(`Motore/SceltaLivello.cs`, senza thread e senza orologio: si prova con tempi finti in `SceltaLivelloTest`) sceglie uno
di cinque livelli (`LivelloResa`; che cosa cambia lo dicono `ConBordoAMeta`, `ConMascheraAlterna`, `ConModelloLeggero`,
`ConBordoBilineare`):

| Livello | Modello | Maschera | Bordo |
|---|---|---|---|
| 1 `Pieno` | pieno | ogni fotogramma | filtro guidato a metà risoluzione |
| 2 `BordoLeggero` | pieno | ogni fotogramma | filtro guidato a un quarto |
| 3 `MascheraAlterna` | pieno | un fotogramma sì e uno no | filtro guidato a un quarto |
| 4 `Veloce` | leggero | ogni fotogramma | bilineare |
| 5 `Minimo` | leggero | un fotogramma sì e uno no | bilineare |

Il filtro nel tempo, la media dal movimento e l'isteresi della maschera restano accesi a tutti i livelli (meno di 1 ms).
Con lo sfondo sostituito il bordo pulito si salta ai livelli `Veloce` e `Minimo` (come il «leggero» del Mac); il light
wrap resta.

- **Misura**: finestre di 2 s (almeno 10 fotogrammi resi) con le medie di maschera e resa: sono due code in parallelo,
  conta la più lenta. Il **tempo di un fotogramma** è la media della metà centrale degli ultimi 30 intervalli d'arrivo,
  mai sotto quello dei fps dichiarati dal telefono nel messaggio `formato` (33 ms a 30 fps, 17 ms a 60;
  `MotoreVideo.Formato` → `MotoreEffetti.Fps`), né sotto 1/60 s se non li dice. I primi 5 fotogrammi dopo un azzeramento
  o una fonte nuova non contano (riscaldamento di DirectML); un buco di più di 1 s apre una finestra nuova.
- **Scende** appena una finestra supera l'**85%** del fotogramma (a 30 fps: 28 ms), di un gradino che alleggerisce la
  coda più lenta: maschera lenta → maschera alterna (o subito il veloce se anche dimezzata non ci starebbe); resa lenta
  → bordo leggero, poi il veloce; dal veloce il minimo; dal minimo niente (si saltano fotogrammi).
- **Risale** di un gradino dopo **5 finestre di fila (circa 10 s) sotto il 50%** del fotogramma. Se ricade dal gradino
  appena preso entro 30 s, la prossima risalita aspetta il doppio (20, 40, 80, al massimo 160 s); tenuto 30 s, si torna a
  10 s. Tra il 50% e l'85% resta dov'è.
- **Maschera alterna**: il fotogramma «in mezzo» passa comunque dalla coda di analisi (l'ordine non cambia, le riduzioni
  a metà e a un quarto si fanno lo stesso) e prende la maschera del precedente se non ha più di 100 ms
  (`EtaMassimaRiuso`); altrimenti la calcola. Non conta come «senza maschera». Niente interpolazione tra due maschere:
  servirebbe la maschera del fotogramma dopo, cioè un fotogramma di ritardo.
- **Cambio di modello** (tra il 3 e il 4): la fonte nuova si apre e si scalda (una maschera su un fotogramma vuoto) su un
  altro thread mentre la vecchia continua; quando è pronta prende il suo posto e la vecchia si chiude. Così la risalita
  al pieno non ferma il video per la compilazione degli shader. Se la fonte nuova non si apre, si resta sulla vecchia
  finché il livello non cambia. Il passaggio al leggero «perché il pieno è lento» dentro `RitaglioPersona`
  (`MisuraVelocita`) nel motore è spento (`RipiegoSeLento = false`): lo decide la scala, che può anche risalire. Senza
  DirectML si parte comunque dal leggero.
- **Registro**: una riga a ogni cambio. Giù: «Effetti: il PC non regge 33 ms a fotogramma (maschera 45 ms, resa 12 ms):
  maschera un fotogramma sì e uno no, bordo rifinito a un quarto». Su: «Effetti: il PC ha margine a 33 ms a fotogramma
  (…): di nuovo bordo rifinito a metà risoluzione». Nessun avviso nuovo per l'utente: Windows non ne ha uno di «resa
  lenta», e il cambio di livello non chiede nulla a chi guarda.
- Dopo un azzeramento (telefono nuovo, sessione nuova, altra misura del video) si riparte dal pieno.

## Qualità 4 e 5: rifinitura come il Mac, composizione sulla scheda video

Ramo `effetti-windows` (da `prestazioni`), novembre 2026.

### Mac e Windows prima di questo giro

| | Mac (`MotoreEffetti.swift`, `RicetteEffetti.swift`) | Windows prima |
|---|---|---|
| Bordo guidato dal colore | filtro guidato sulla luma, a e b a lato corto 540, applicati alla luma piena; soglia 0,55 | filtro guidato veloce: a e b al quarto, applicati a metà; soglia D\* 0,3–0,7 (sfocato) |
| Filtro nel tempo | media 0,3 con **isteresi** 0,3/0,7 e spinta 0,15 | filtro senza ritardo + media dal movimento (D\*), **niente isteresi** |
| Sfocato senza alone | sfocatura normalizzata, persona allargata 12 px (2,5m − 0,25) | sfocatura normalizzata, persona 2m − 0,3 (già senza alone) |
| Sostituito | **bordo pulito** dal vecchio sfondo + **light wrap** | solo la miscela: il vecchio sfondo restava sull'orlo |
| Dove | tutto Core Image sulla scheda video | resa sul processore |

Il bordo guidato e lo sfocato senza alone di Windows restano com'erano: il banco li aveva già confrontati con quelli del
Mac (varianti B e D) e la versione del Mac non migliorava (B) o peggiorava (D: alone 1,0 → 2,5) sulla maschera di
MediaPipe. Mancavano l'isteresi, il bordo pulito e il light wrap.

### Qualità 4: cosa è stato portato

- **Isteresi** (`IsteresiMaschera`, dopo `MediaNelMovimento` in `RitaglioPersona`): ogni punto ricorda se è persona;
  lo diventa sopra **0,6**, torna sfondo sotto **0,4**, e dove l'immagine è ferma il valore si sposta di **0,1** dalla
  parte del suo stato (dove si muove la spinta scende a zero: niente scie). Il filtro del Mac così com'è peggiorava la
  maschera di MediaPipe (variante «Cm»: MAD 137 → 190): questi valori sono tarati con il banco sopra D\*.
  Banco (pieno, 5 clip × 60 fotogrammi), D\* → D\* + isteresi: tremolio del bordo 16,8 → 15,6 (−7%, meno in tutte
  le clip), MAD bordo 124,6 → 122,3 (scuro su scuro 165 → 158), dtSSD 3,30 → 3,38 (+2%), IoU 0,958 → 0,958, alone
  uguale. Varianti provate: spinta 0,05 (metà dell'effetto), soglie 0,3/0,7 (uguale), spinta anche dove l'immagine si
  muove (tremolio −11% ma dtSSD +4%).
- **Bordo pulito** (sostituito, non ai livelli bilineari): fiducia nel pixel 2,5a − 1,5; dove è bassa il colore viene
  dalla media pesata dell'interno sicuro della persona (peso 0 sotto 0,75, 1 da 0,95; sigma 8 px a 1080p, calcolata a un
  quarto). Banco (sostituito «Medio», errore contro la persona vera sullo sfondo nuovo, fascia ±10 px): 12,0 → 11,8
  in media; ufficio chiaro −9%, libreria −2%, soggiorno uguale, studio scuro e cemento +5–10% (lì il vecchio sfondo
  somiglia già alla persona). Da guardare sul video vero: capelli chiari su un muro bianco, poi sfondo scuro.
- **Light wrap** (sostituito): lo sfondo nuovo sfocato (14 px) entra con lo «schermo» sull'orlo interno, peso
  0,3·a·(1 − a sfocata) al massimo 0,15 (i numeri del Mac). È una scelta di resa: nel banco aggiunge 0,3 livelli di
  errore nella fascia del bordo, come atteso.
- Tutti i numeri in un posto (`RegoleBordo`), usati dal processore, dallo shader e dai test.

### Qualità 5: la composizione sulla scheda video

- **Che cosa va sulla scheda video**: il passo a piena risoluzione dello sfondo (`PianoComposizione` → `IComposizione`):
  per ogni pixel alfa (da metà o un quarto), bordo pulito, calore, light wrap e miscela con il fondo (pieno con il
  sostituito, piccolo con lo sfocato). Le cose piccole (filtro guidato e soglia, fondo sfocato, colore della persona,
  sfondo nuovo sfocato, maschera sfocata) restano sul processore, uguali per le due strade.
- **Come**: Direct3D 11 con un compute shader (`SchedaVideo/Composizione.hlsl`, cs_5_0) tramite **Vortice.Windows**
  (MIT). Lo shader è nella libreria come testo e si **compila all'apertura con D3DCompile** (`d3dcompiler_47.dll`,
  presente in Windows 10 e 11): nessun `.cso` da preparare. Per fotogramma: il fotogramma sale (`UpdateSubresource`),
  lo shader compone, il risultato torna in memoria (`CopyResource` + `Map`); l'immagine dello sfondo sostituito e la sua
  versione sfocata salgono solo quando cambiano. La resa resta sincrona sulla coda di resa: `SceltaLivello` (Qualità
  6) misura il tempo vero, scheda video compresa, e la scala dei livelli non cambia.
- **Ripiego automatico** (nel `Compositore`):
  - la scheda video si apre **in sottofondo** alla prima resa con lo sfondo; intanto lavora il processore;
  - non si apre → processore per tutta la sessione, nel registro «Effetti: sfondo composto sul processore (motivo)».
    Motivi: non è Windows; Direct3D 11 livello 11.0 assente; solo il «Microsoft Basic Render Driver» (WARP, cioè il
    processore: più lento del nostro); lo shader non compila; **il risultato su due fotogrammi di prova differisce da
    quello del processore** (più di 4 livelli, o 0,6 in media: `ComposizioneSchedaVideo.Verifica`). Così uno shader
    sbagliato o un driver strano non arrivano mai al video;
  - presa → «Effetti: sfondo composto sulla scheda video (nome della scheda)»;
  - un errore durante il lavoro (driver aggiornato, sospensione, TDR) rifà **lo stesso fotogramma** sul processore
    (nessun fotogramma perso, mai lo sfondo vero); dopo 3 errori di fila la scheda video si chiude e si riapre **una
    volta**; se si perde di nuovo, processore fino alla fine.
- **Interfaccia per la App**: `MotoreEffetti(..., creaComposizione: () => ComposizioneSchedaVideo.Crea())` in
  `MotoreVideo`; la nota `MotoreEffetti.Nota.Composizione` va nel registro (testi in italiano e inglese).
- **Tempi sul processore** (qui, Xeon 4 processori virtuali, Release, mediana; la macchina è condivisa, ±30%): sfocatura
  Medio 10–14 ms come prima; sostituito 10 → 15–21 ms con bordo pulito e light wrap (13 ms al livello veloce). Sulla
  scheda video il passo a piena risoluzione dovrebbe costare 1–3 ms più le copie (8 MB su e giù a 1080p, 1–4 ms):
  **da misurare** (il test `SchedaVideoVeraComeIlProcessore` li scrive su Windows).
- **Non verificato qui**: lo shader non si è potuto né compilare né eseguire (niente Windows né compilatore HLSL); il C#
  di Direct3D 11 compila (Vortice è codice .NET) ma gira solo su Windows. I conti dello shader sono la copia di `RegoleBordo.Canale`, che i test provano contro il processore
  (differenza ≤ 2). La CI su Windows (rami ci, prestazioni, round-2) compila tutto ed esegue
  `SchedaVideoVeraComeIlProcessore` con WARP: è la prima prova vera dello shader.

## Qualità 7 e 8: bokeh, mosaico e schermo verde (Mac e Windows)

Ramo `bokeh-mosaico` (da `prestazioni`), novembre 2026. Tre sfondi nuovi, sul Mac e sul PC, con gli stessi identificativi
e gli stessi numeri (Windows: `Motore/StiliSfondo.cs`, `Motore/RicetteSfondo.cs`; Mac: `StiliSfocatura` e `SfondoVerde`
in `MotoreEffetti.swift`, ricette in `RicetteEffetti.swift`).

| | Che cos'è | Dove si sceglie | Pro |
|---|---|---|---|
| **Obiettivo (bokeh)** | sfocatura come un obiettivo: le luci forti diventano dischi | «Stile» nel menu di «Sfondo» (anche pagina «Sfondo» e colonna «Effetti») | gratis, come la sfocatura |
| **Mosaico** | lo sfondo a quadretti; Poco / Medio / Tanto = 21 / 32 / 48 px a 1080p | come sopra | gratis |
| **Schermo verde** | verde pieno #00B140, bordo netto, niente light wrap: per il chroma key di OBS | voce sotto «Sfondi ›» | Pro, come gli sfondi sostituiti |

Bokeh e mosaico sono uno **stile** dello sfondo sfocato (`ValoriEffetti.Sfocatura` / `Effetti.sfocatura`, salvato con
le scelte; una preferenza di prima o sconosciuta vale «normale»): i livelli Poco, Medio, Tanto restano, e un clic su
«Sfondo» riaccende l'ultimo stile. Lo schermo verde è uno sfondo **sostituito** con un'immagine fissa
(`immagineSfondo` = `verde`, che non si legge da file): segue le regole Pro degli sfondi e si riaccende con il clic come
l'ultimo sfondo scelto.

**Protocollo: non cambia.** Sono scelte del computer: il telefono, con gli effetti sul computer, manda il video com'è e
fa solo da telecomando con un pulsante «Sfoca» acceso/spento. Al telecomando `effetti.sfondo` dice `sfocato` per bokeh
e mosaico e `sostituito` per il verde, e `chiedi-effetto` con `sfocato` riaccende l'ultimo stile scelto sul computer
(Protocollo.md, «Effetti sul computer»). Un campo nuovo servirebbe solo a un telefono che sceglie lo stile da sé, e
nessuna app del telefono ha (o deve avere) quella scelta: le app del telefono non cambiano.

### Come sono fatti

- **Bokeh, Windows** (sul processore, `RicetteSfondo.Bokeh`): in luce lineare (tabella 2,2), luci espanse
  Y / (1 − 0,9·Y) sulla luminanza (il bianco vale 10), persona allargata tolta come peso (come lo sfocato senza alone),
  **disco pieno** di raggio 2σ della sfocatura normale (stessa deviazione standard: lo sfondo è sfocato «quanto» con la
  normale) con le somme cumulate di ogni riga, cioè (2r + 1) letture per punto invece di π r²; poi diviso per il peso e
  compresso con l'inversa esatta Y / (1 + 0,9·Y), così una parete uniforme torna identica e una lampadina diventa un
  disco chiaro e piatto. Il fondo piccolo va alla stessa composizione a piena risoluzione dello sfocato (scheda video o
  processore): lo shader non cambia.
- **Bokeh, Mac**: lo stesso disegno con i filtri di sistema: `CIBokehBlur` (disco morbido con un filo di anello,
  `ringAmount` 0,15) in piccolo perché il disco resti 12 px (al massimo un quarto della misura), luci espanse
  v + 20·(v − 0,6) canale per canale e compresse con l'inversa (matrice, limiti e `somma` del guided filter: nessun
  kernel Metal proprio).
- **Mosaico, Windows**: un pixel per quadretto, media dei colori del quadretto pesata dallo sfondo (un quadretto
  sull'orlo prende il colore dello sfondo, non quello della persona); la composizione lo ingrandisce «al più vicino»
  (`PianoComposizione.FondoAQuadretti`, opzione `QUADRETTI` dello shader con gli stessi interi del processore: quadretto
  ⌊x · colonne / L⌋). La verifica della scheda video all'apertura prova anche il mosaico.
- **Mosaico, Mac**: sfondo senza alone sfocato di un terzo del quadretto (il centro vale la media) e poi `CIPixellate`,
  griglia dall'angolo in alto a sinistra.
- **Schermo verde** (tutti e due): soglia del bordo stretta (0,12 invece di 0,2–0,8), **bordo pulito sì** (toglie il
  vecchio sfondo dai capelli, che il chroma key vedrebbe come un alone), **light wrap no**, intensità nascosta.

### Costo e livelli (Qualità 6)

Il bokeh costa più della sfocatura normale, il mosaico meno; il tempo vero entra nella misura della scala dei livelli,
che scende da sola se serve.

| Livello | Windows | Mac |
|---|---|---|
| pieno | bokeh a un quarto della misura (a un ottavo se il disco supera 10 px: «Tanto» a 1080p) | bokeh |
| bordo leggero, maschera alterna | bokeh a un ottavo | — (`.bordoLeggero`: sfocatura normale) |
| veloce, minimo / `.veloce` | **sfocatura normale** | **sfocatura normale** |
| mosaico, schermo verde | a tutti i livelli | a tutti i livelli |

Tempi del fondo piccolo misurati qui (Windows, Xeon 4 processori virtuali, Release, test
`QuantoCostanoBokehEMosaicoA1080p`): bokeh Medio al quarto **4 ms**, Tanto a un ottavo **1,5 ms** (al quarto sarebbe
8 ms), mosaico **0,3 ms**. Prendono il posto del fondo sfocato normale (che è meno di 1 ms): con la resa dello sfocato a
10–14 ms in tutto, il bokeh aggiunge circa 1–4 ms, il mosaico niente. Sul Mac
`CIBokehBlur` su circa 130 000 pixel con raggio 12 dovrebbe stare sotto i 2 ms su Apple Silicon (stima, **da misurare**:
la riga «Effetti sul Mac» del registro).

### Non verificato qui

- Swift (Mac), WinUI e lo shader non si compilano su Linux: riletti a mano. Il motore di Windows (bokeh, mosaico, verde,
  composizione sul processore) è provato dai test (`SfondiNuoviTest`, `IlProcessoreFaIContiDelloShader` con il mosaico).
- `CIBokehBlur` su un'immagine con l'alfa premoltiplicato (come `CIDiscBlur` nello sfocato di sempre) e la resa esatta
  del verde nel buffer YCbCr di uscita (range e matrice del decodificatore): da vedere sul Mac vero.

## Modello scelto

| | Pieno: Selfie Multiclass 256×256 | Leggero: Selfie Segmenter landscape 144×256 |
|---|---|---|
| File | `Modelli/ritaglio_persona.onnx` (16,5 MB, float32) | `Modelli/ritaglio_persona_leggero.onnx` (0,45 MB) |
| Ingresso `immagine` | [1, 256, 256, 3] RGB in [−1, 1] | [1, 144, 256, 3] RGB in [0, 1] |
| Uscita | `classi` [1, 256, 256, 6] con softmax: sfondo, capelli, pelle del corpo, pelle del volto, vestiti, accessori | `persona` [1, 144, 256, 1] in [0, 1] |
| Persona | 1 − `classi[0]` | `persona` |
| Calcolo | circa 4,2 GMAC (solo convoluzioni), 4,1 M parametri | circa 0,03 GMAC, 0,1 M parametri |
| Qualità | bordo dei capelli e accessori migliori; su una foto vera prende anche qualche oggetto vicino (peluche sulla mensola) | bordo più tondo, «a casco» sui capelli; buono sul corpo |
| Dove | scheda video (DirectML) | processore (o scheda video, se il pieno è troppo lento) |

Perché questi: sono gli unici candidati con licenza Apache chiara **per codice e pesi** già provati da noi (Android), con
un formato convertibile in ONNX qui. Robust Video Matting resta escluso (GPL-3.0); MODNet (Apache 2.0) e
PP-HumanSegV2 sono alternative possibili in futuro (Documenti/Modelli ritaglio.md), ma vanno convertiti da PyTorch/Paddle
fuori da qui e non danno un vantaggio dimostrato. Il Selfie Segmenter quadrato 256×256 non serve: il video del telefono
è sempre orizzontale nel computer o comunque si stira.

Le proporzioni: il fotogramma (16:9) si stira nel quadrato 256×256, come fa MediaPipe con `ImageSegmenter`. La maschera
torna quadrata e si applica con le coordinate normalizzate del fotogramma: nessun ritaglio, nessuna banda.

### Conversione (Strumenti/converti_ritaglio_onnx.py)

1. I `.tflite` si scaricano da `storage.googleapis.com/mediapipe-models/image_segmenter/…/latest/` (raggiungibile da qui;
   SHA-256 del multiclasse uguale a quello dell'app Android, `c6748b12…e0e0`; landscape `490e9ea7…8e`).
2. `tf2onnx` 1.17 (con `tensorflow-cpu` 2.21), opset 17. `tflite2onnx` non va: non conosce `SUM` e `HARD_SWISH`.
3. Ritocchi:
   - multiclasse: softmax aggiunto in uscita (MediaPipe lo applica leggendo i metadati; il modello dà i logit); i tre
     `Resize` «nearest» usavano `tf_half_pixel_for_nn`, deprecato da ONNX e con un avviso di onnxruntime: diventano
     `half_pixel` + `round_prefer_ceil`, equivalente (differenza 3·10⁻⁷ dopo il softmax);
   - leggero: l'operatore personalizzato di MediaPipe `Convolution2DTransposeBias` (che ONNX Runtime non conosce)
     diventa un `ConvTranspose` standard (nucleo 2×2, passo 2) più bias. Qui non c'è un riferimento TFLite (anche
     l'interprete TFLite senza MediaPipe non lo esegue): verificato a occhio sulla maschera (nessuna quadrettatura) e con
     l'accordo col multiclasse sulla foto (IoU 0,94 a soglia 0,5);
   - nomi uguali per i due modelli (`immagine`, `classi`/`persona`). Tutti operatori ONNX standard (Conv, Resize,
     Softmax, ReduceSum, Transpose…), supportati da DirectML.
4. Normalizzazione presa dai metadati dei `.tflite` (media/deviazione 127,5/127,5 per il multiclasse, 0/255 per il
   leggero).

### Prova su immagini

- **Fotogramma vero** (da `video2/v.mp4`, anteprima del Mac, Ledion con la felpa davanti alla mensola): maschera pulita
  su testa, spalle e braccio con entrambi i modelli; il pieno segna come «persona» anche parte dei peluche sulla
  mensola a destra e un pezzo di divano in basso a sinistra (il leggero meno). Immagini nella cartella di lavoro, non
  nella repository (contengono il viso di Ledion).
- **Persona disegnata** (nei test, `WebcamLR.Effetti.Test/Dati/sintetica.ppm.gz`): il leggero la ritaglia
  perfettamente; il **pieno non la riconosce** (è addestrato su foto vere): per il pieno il test controlla solo
  l'uguaglianza numerica con Python, la prova di resa va fatta col video vero.

## Licenze

| Componente | Licenza | Uso commerciale | File in `Windows/WebcamLR.Effetti/Licenze/` |
|---|---|---|---|
| Modelli MediaPipe (pesi), modificati da noi | Apache 2.0 (Google) | Sì; serve la licenza e l'avviso delle modifiche | `Apache-MediaPipe.txt` (testo completo + elenco modifiche, sezione 4 b) |
| ONNX Runtime 1.24.4 (`Microsoft.ML.OnnxRuntime`, `.Managed`, `.DirectML`) | MIT (Microsoft) | Sì | `MIT-OnnxRuntime.txt`, `OnnxRuntime-ThirdPartyNotices.txt` |
| DirectML 1.15.4 (`Microsoft.AI.DirectML`, dipendenza del pacchetto DirectML) | Licenza Microsoft «DirectML»: ridistribuibile dentro le nostre app, **solo su Windows e Xbox** | Sì | `DirectML.txt`, `DirectML-ThirdPartyNotices.txt` |
| Vortice.Windows 3.8.3 (`Vortice.Direct3D11`, `Vortice.D3DCompiler`, con `Vortice.DXGI`, `Vortice.DirectX`, `Vortice.Mathematics` 2.1.0), SharpGen.Runtime 2.4.2-beta (Qualità 5) | MIT (Amer Koleci; SharpGen: Mutel, Koritzinsky, Koleci) | Sì | `MIT-Vortice.txt` |

Le licenze vanno copiate accanto all'exe (lo fa il progetto: `Content` → `Licenze\`) e citate nella finestra «Informazioni»
quando si collega la libreria. Nota: la licenza DirectML dice che il software può raccogliere dati di diagnostica
(sezione 2): da citare nell'informativa privacy di Windows al momento della pubblicazione.

**Pacchetti NuGet.** Su Windows `Microsoft.ML.OnnxRuntime.DirectML` (contiene anche il motore sul processore, x64 e
ARM64); altrove `Microsoft.ML.OnnxRuntime` (solo per i test su Linux). Stessa versione, **1.24.4**: è l'ultima del
pacchetto DirectML (il CPU è già alla 1.31). Microsoft ha messo DirectML in manutenzione e spinge Windows ML
(Windows 11 24H2+, che sceglie da sé GPU/NPU); per ora DirectML è la via che funziona anche su Windows 10 e sulle schede
video non recenti. Da rivedere quando Windows ML è disponibile su tutti i PC che supportiamo.

## Tempi

Misurati qui (Linux, Intel Xeon 2,8 GHz, 4 processori virtuali, AVX-512; nessuna GPU):

| | onnxruntime 1.31, Python, 1 / 2 / 4 fili | Libreria C# (ORT 1.24.4, Release, tutta `Calcola`) |
|---|---|---|
| Pieno 256×256 | 107 / 61–70 / 44–52 ms | 53 ms (71 ms in Debug) |
| Leggero 144×256 | 2,6 ms (con qualunque numero di fili) | 5,2 ms |
| Riduzione di un fotogramma 1920×1080 alla misura del modello (C#) | — | 2,8 ms |

Il leggero in C# include la riduzione, la conversione, il filtro nel tempo e la copia della maschera.

**Attesi sulla scheda video con DirectML** (stima dal calcolo, circa 8,4 GFLOP per il pieno, e dai dati di MediaPipe:
71 ms sulla GPU di un telefono Pixel 6):

| Scheda | Pieno | Leggero |
|---|---|---|
| Integrata recente (Intel Iris Xe, AMD Radeon 680M) | 10–20 ms | 1–3 ms |
| Integrata vecchia (Intel UHD 620) | 25–50 ms → ripiego al leggero | 2–5 ms |
| Dedicata media (GTX 1650, RX 6500) e superiori | 3–8 ms | < 2 ms |

La prima maschera sulla GPU è lenta (compilazione degli shader di DirectML): la libreria non conta le prime 5.
Le stime vanno confermate sul PC di Ledion: è la prima cosa da provare (checklist sotto).

## La libreria `Windows/WebcamLR.Effetti`

net8.0 senza API di Windows, si prova su Linux. Uso:

```csharp
using var ritaglio = RitaglioPersona.Crea();              // DirectML se c'è, altrimenti leggero sul processore
var maschera = ritaglio.Calcola(bgra, 1920, 1080, passo); // bloccante: fuori dal thread dell'interfaccia
// maschera.Valori: byte[Larghezza × Altezza], 0 = sfondo, 255 = persona; maschera.Valore(u, v) in [0, 1]
// ritaglio.InUso (SchedaVideo/Processore), ritaglio.Modello (Pieno/Leggero), ritaglio.MotivoRipiego (per il registro)
```

- `OpzioniRitaglio`: `Modello` (Pieno), `Acceleratore` (Automatico / SchedaVideo / Processore), `RipiegoAutomatico`
  (vero), `FiltroNelTempo` (vero), `CartellaModelli` (`Modelli` accanto all'exe), `SchedaVideo` (indice dell'adattatore
  DirectML), `Fili`.
- **Pre-elaborazione** (`Preparazione.BgraInRgb`): media dei pixel coperti da ogni punto del modello (niente
  scalettature da 1080p a 256), BGRA → RGB, normalizzazione del modello, disposizione NHWC; righe con passo qualsiasi
  (superfici della scheda video).
- **Post-elaborazione** (`Preparazione.Persona`): persona = 1 − sfondo col multiclasse, il canale unico col leggero.
- **Filtro nel tempo senza ritardo** (`FiltroTemporale`): lo stesso di Android, peso della nuova 0,7 + 3 × |differenza|
  (al massimo 1): il tremolio del bordo si smorza, il movimento passa subito. Nessun fotogramma di attesa.
- **Media dal movimento** (`MediaNelMovimento`, dopo il filtro nel tempo; variante «D\*» del banco di qualità): media
  della maschera con peso della nuova 0,35 + 12 × |ΔY| (ΔY = differenza di luminanza tra due fotogrammi alla misura della
  maschera, media 5×5), tra 0,35 e 1: dove l'immagine è ferma il bordo trema un terzo in meno, dove si muove vale subito
  la nuova. Stessi conti di `Strumenti/banco_sfondo/varianti.py` (classe C): `verifica_cs.py` dà 0 punti diversi sul
  modello pieno.
- **Ripiego** (`MisuraVelocita`): senza DirectML si parte dal leggero; col pieno, dopo 5 maschere di riscaldamento e
  20 di prova, se la media supera 25 ms si passa al leggero per il resto della sessione (sulla stessa scheda video). Il
  motivo è in `MotivoRipiego`, per il registro. Nel motore effetti questo secondo passaggio è spento: lo fa la scala dei
  livelli («Qualità che si adatta al PC»).
- **Controlli**: un file modello mancante o con ingresso/uscita diversi è un errore chiaro, non una maschera senza senso.
- Le sessioni ONNX Runtime riusano gli stessi buffer a ogni fotogramma (`OrtValue` su array fissi): nessuna allocazione
  grande per fotogramma, tranne la maschera restituita (64 KB).

Test: `dotnet test Windows/WebcamLR.Effetti.Test` (19 test, anche in `Strumenti/Costruisci e avvia.bat`). Con
`WEBCAMLR_IMMAGINE_PROVA=<foto.ppm o .ppm.gz>` il test `FotoVeraSeIndicata` scrive le maschere in PGM accanto alla foto e
le confronta con i riferimenti Python se ci sono.

## Piano di integrazione nella pipeline video di Windows

Oggi (`Windows/WebcamLR.App`): `AnteprimaVideo` decodifica l'H.264/HEVC del telefono con Media Foundation dentro un
`MediaPlayer`; la finestra lo mostra con `MediaPlayerElement`; `UscitaWebcam` ha un **secondo** decodificatore in modalità
«frame server» (`IsVideoFrameServerEnabled`), copia ogni fotogramma su una superficie D3D11 BGRA
(`CopyFrameToVideoSurface`), lo scarica in memoria e lo converte in NV12 per la webcam virtuale. Gli effetti oggi li fa il
telefono.

Obiettivo (brief del 27 ottobre): effetti applicati **una volta sola dopo la decodifica**, e lo stesso risultato va ad
anteprima, finestra mini, webcam virtuale, foto e registrazione.

1. **Un solo decodificatore in modalità frame server** (`MotoreEffetti`, nuovo, in `WebcamLR.App`): riceve
   `VideoFrameAvailable`, copia il fotogramma in una texture D3D11 BGRA propria (`CopyFrameToVideoSurface`, come oggi in
   `UscitaWebcam`). Il `Direct3D11Device` è quello del `MediaPlayer` (o uno nostro condiviso via
   `IDirect3DDxgiInterfaceAccess`), creato con `D3D11_CREATE_DEVICE_BGRA_SUPPORT`.
2. **Maschera sulla GPU**: compute shader che riduce la texture a 256×256 (o 256×144) e normalizza in un buffer D3D12/
   D3D11 → DirectML lo legge senza passare dalla memoria. Primo passo più semplice e già sufficiente: riduzione sulla GPU
   (shader) in una texture piccola, copia in memoria di soli 256×256×4 byte (≈ 0,1 ms), `RitaglioPersona.Calcola` sul
   piccolo (la libreria accetta già qualsiasi misura e passo). Il passaggio a buffer condivisi D3D12 (interop
   `IDMLDevice`/`OrtDmlApi`) è un'ottimizzazione successiva da misurare.
3. **In parallelo, senza ritardo**: la maschera si calcola su un thread suo per l'ultimo fotogramma arrivato; il
   fotogramma corrente si compone con l'ultima maschera pronta (al massimo un fotogramma più vecchia, con il filtro
   «senza ritardo» non si vede la scia sotto i ~25 ms). Se la maschera è più vecchia di 100 ms (PC in difficoltà)
   l'effetto si ferma a metà intensità invece di sbagliare il bordo.
4. **Shader D3D11 (pixel/compute, HLSL compilato in fase di build con `fxc`/`dxc`)**:
   - ingrandimento della maschera guidato dal colore (filtro guidato «joint bilateral» a 1/2 risoluzione) e soglia
     morbida (smoothstep), come `CIEdgePreserveUpsampleFilter` sul Mac/iPhone;
   - **sfocatura senza alone** come sull'iPhone: persona allargata come alfa, sfondo × (1 − alfa) ridotto a 1/4–1/8,
     sfocatura gaussiana separabile, poi diviso per l'alfa sfocato (niente bordo scuro attorno alla persona); Poco /
     Medio / Tanto cambiano la riduzione (sigma a 1080p 3,5 / 12 / 32 px); bokeh con un nucleo a disco sui punti luce;
   - **sfondo sostituito**: texture dell'immagine (pronta o caricata) ritagliata «a riempire» una volta sola;
   - composizione finale, poi gli altri effetti a colori (filtri, regolazioni, calore, luce sul volto) come LUT 3D e
     operazioni per pixel nello stesso passaggio; specchio come cambio di coordinate;
   - conversione BGRA → NV12 per la webcam con uno shader (oggi la fa il processore in `ConversioneVideo.BgraInNv12`).
5. **Uscite** dalla stessa texture finale: anteprima e finestra mini (una `SwapChainPanel` di WinUI al posto di
   `MediaPlayerElement`), webcam virtuale (`UscitaWebcam` riceve la texture già composta invece di decodificare per
   conto suo: un decodificatore in meno), foto e registrazione (`IMFSinkWriter` con l'encoder hardware, come oggi).
6. **Pro e capacità**: le regole restano quelle del telefono (`capacita.pro`): sfocatura e calore liberi, il resto Pro.
   Il telefono smette di applicare gli effetti quando il computer dichiara di farli (campo nuovo nel protocollo, da
   aggiungere in `Documenti/Protocollo.md` e nelle tre implementazioni al momento dell'integrazione).
7. **Misure**: `MotoreEffetti` scrive nel registro e nelle «Tappe» del Misuratore il tempo della maschera, quello della
   composizione e il modello/acceleratore in uso (`RitaglioPersona.InUso`, `Modello`, `MotivoRipiego`).

Ordine di lavoro proposto: (a) prova dei tempi DirectML sul PC di Ledion con un piccolo comando (vedi checklist);
(b) `MotoreEffetti` con un decodificatore e uscita verso la webcam, sfocatura con maschera calcolata dalla copia piccola;
(c) anteprima con `SwapChainPanel`; (d) sfondi sostituiti e il resto degli effetti; (e) eliminazione del secondo
decodificatore.

## Requisiti minimi del PC e ripiego

- **Pieno con DirectML**: Windows 10 22H2 o Windows 11 (quelli che già supportiamo; DirectML chiede almeno Windows 10
  1709), una scheda video con **DirectX 12** e driver aggiornati: in pratica quasi tutte dal 2015 in poi (Intel HD/UHD
  integrate dei processori Core recenti, AMD GCN e successive, NVIDIA GTX 600 e successive). Con le integrate vecchie (UHD 620) il pieno potrebbe non
  stare nei 25 ms: lo decide la misura automatica.
- **Ripiego automatico**: nessuna DirectX 12 (macchine virtuali, Desktop remoto, driver di base Microsoft), DirectML che
  non si apre, o pieno troppo lento → **modello leggero**: sul processore circa 5 ms anche su un portatile modesto, bordo
  più grossolano sui capelli. Nessuna configurazione richiesta all'utente; nel registro si legge il motivo.
- **Sotto il minimo** (processore a 2 core vecchio, ritaglio oltre 30 ms anche col leggero): il livello `Minimo`, maschera
  a metà frequenza (un fotogramma sì e uno no) con il filtro nel tempo; ci arriva da sola la scala dei livelli.
- Memoria: +17 MB su disco (modelli) e circa 60–120 MB di RAM/VRAM per il pieno con DirectML (stima).
- ARM64 (Snapdragon X): il pacchetto DirectML ha i binari ARM64; la GPU Adreno supporta DirectX 12. Da provare se Ledion
  ha accesso a un PC ARM.

## Cosa non si è potuto fare qui

- DirectML non si prova su Linux: i tempi GPU sono stime. Nessuna misura su Windows.
- L'app WinUI non si compila qui: il C# della finestra è controllato con il banco (compilatore C# con lo XAML simulato),
  ma `MediaTranscoder`, `WriteableBitmap`, GDI+ e la copia dalla scheda video si vedono solo su Windows.
- Lo shader Direct3D 11 della Qualità 5 non si è potuto né compilare né eseguire qui (niente Windows, niente
  compilatore HLSL): è controllato solo a occhio contro `RegoleBordo` (vedi «Qualità 4 e 5»).
- La resa del pieno su una persona vera si è vista su un solo fotogramma; quella in movimento (tremolio, scie) va vista
  dal vivo.

## Checklist di prova (per Ledion, quando si collega)

1. `dotnet test Windows\WebcamLR.Effetti.Test` su Windows: tutti verdi (prova anche che i binari nativi di ONNX Runtime
   DirectML si caricano).
2. Primo collegamento: nel registro deve comparire «ritaglio: scheda video, modello pieno» e il tempo medio per maschera
   dopo 25 maschere. Annota la scheda video del PC e il tempo.
3. Su un PC senza scheda video adatta (o in Desktop remoto): «processore, modello leggero» con il motivo.
4. Video in movimento con sfondo sfocato: bordo dei capelli, mani davanti al corpo, nessuna scia quando ti muovi veloce.

### Motore effetti collegato (ramo `effetti-windows`)

1. All'arrivo del telefono, nel registro: «Effetti di immagine sul PC: spenti sul telefono». Sul telefono gli effetti
   risultano spenti; Specchia, Sfondo ed Effetti sul PC funzionano anche con un telefono senza effetti.
2. Sfondo › Medio: entro 1–2 s l'anteprima diventa sfocata (prima apertura del modello); nel registro «Effetti: ritaglio
   della persona: scheda video, modello pieno» (o il motivo del ripiego). Dopo 30 s la riga «Effetti sul PC: … ms»:
   **mandala**, con il nome del processore e della scheda video.
3. La stessa immagine in: anteprima, finestra mini (Ctrl+Maiusc+M), Zoom/Teams/OBS con la webcam WebcamLR, una foto
   (Ctrl+T) e una registrazione di 10 s (Ctrl+R): tutte sfocate e specchiate allo stesso modo.
4. Riservatezza: con lo sfondo acceso muoviti in fretta, copri l'obiettivo, scollega il telefono: in nessuna uscita deve
   comparire per un attimo la stanza vera. Scollegando, la webcam passa alla schermata di attesa e non torna indietro.
5. Fotocamera posteriore: Specchia e Sfondo grigi, nessuno specchio né sfondo nel video.
6. Telefono gratis: sfocatura, calore, luce sul volto e specchio funzionano; sfondi pronti, filtri, pelle, scritta con
   «PRO» e senza effetto. Con Pro: sfondo «Ufficio», «La tua immagine», filtro Cinema, scritta con logo.
7. Riavvio dell'app: le scelte degli effetti restano.
8. Tempi: con «tutto insieme» il video resta fluido? Se il registro dice «il PC non regge …», annota il livello.

### Qualità che si adatta al PC (Qualità 6)

1. Sfondo › Medio su un PC lento (o con il portatile a batteria in risparmio energetico): entro 2–4 s dal primo
   rallentamento il registro dice «il PC non regge …» con il livello nuovo, e il video torna fluido.
2. Lascia lo sfondo acceso e chiudi ciò che pesa (o attacca l'alimentatore): dopo circa 10 s «il PC ha margine … di
   nuovo …», un gradino alla volta. Alla risalita dal modello leggero al pieno il video **non** si deve fermare.
3. Telefono a 60 fps: il registro, se scende, dice «17 ms a fotogramma».
4. Riservatezza: con «maschera un fotogramma sì e uno no» muoviti in fretta: nessun lampo della stanza vera.
5. Manda le righe «Effetti: …» del registro con il nome del processore e della scheda video.

### Qualità 4 e 5 (ramo `effetti-windows`)

1. `dotnet test Windows\WebcamLR.Effetti.Test`: il test `SchedaVideoVeraComeIlProcessore` deve passare e scrivere il nome
   della scheda video, i ms per fotogramma e la differenza dal processore (sfocato e sostituito). **Mandali.**
2. Sfondo › Medio: entro 1–2 s nel registro «Effetti: sfondo composto sulla scheda video (…)». Se c'è «sul
   processore (…)», manda il motivo.
3. Dopo 30 s la riga «Effetti sul PC: … ms»: la resa deve essere scesa rispetto a prima (con lo sfocato a 1080p prima
   era 10–20 ms). Manda la riga e il livello; con «tutto insieme» il livello dovrebbe scendere meno spesso.
4. Bordo fermo: seduto immobile davanti a un fondo con bordi (libreria, mensola), sfocato Medio: il bordo di spalle e
   felpa scura trema meno di prima? Poi muoviti in fretta: nessuna scia.
5. Sostituito («Ufficio» e un'immagine tua scura): sull'orlo dei capelli e delle spalle non deve restare il colore della
   stanza vera (alone chiaro con il muro bianco); un filo di luce dello sfondo nuovo sull'orlo, non un contorno.
6. Scheda video persa: con lo sfondo acceso metti il PC in sospensione e riaprilo (o aggiorna il driver): il video non
   si ferma e non mostra mai la stanza; nel registro, se succede, «sul processore (scheda video persa…)».
7. PC senza scheda video adatta (Desktop remoto o macchina virtuale): «sul processore (solo il driver di base…)» e lo
   sfondo funziona come prima.

### Qualità 7 e 8: bokeh, mosaico e schermo verde (ramo `bokeh-mosaico`, Mac e Windows)

1. Sfondo › Stile › **Obiettivo (bokeh)**, livello Medio, con una lampada o una finestra luminosa dietro di te (meglio
   delle lucine): dietro devono comparire dischi chiari e tondi, non macchie grigie. Poi Tanto. **Screenshot.**
2. Una parete chiara uniforme con il bokeh: deve restare dello stesso chiaro della sfocatura normale (niente bianco
   bruciato). Confronta Normale e Obiettivo con lo stesso livello.
3. **Mosaico**, Poco / Medio / Tanto: quadretti netti, sempre più grandi; sul bordo della persona i quadretti hanno il
   colore della stanza, non della felpa. Muoviti: la persona resta nitida, i quadretti non «ballano» da fermo.
4. Un clic su «Sfondo» spegne; un altro riaccende **lo stesso stile**. Riavvia l'app: lo stile resta.
5. Dal telefono, il pulsante «Sfoca»: spegne il bokeh e lo riaccende come bokeh (non come sfocatura normale).
6. **Schermo verde** (con Pro): in OBS aggiungi il filtro «Chiave cromatica» (verde) alla webcam WebcamLR: il verde
   sparisce tutto, senza bordo verde sulle spalle né alone della stanza sui capelli. **Screenshot** prima e dopo il filtro.
   Con un telefono gratis la voce ha «PRO» e apre la pagina di Pro.
7. Costo: dopo 30 s con il bokeh Tanto, la riga «Effetti sul PC: … ms» (o «sul Mac»): **mandala**, con quella della
   sfocatura normale. Su un PC lento il registro deve dire «il PC non regge …» e, ai livelli veloci, il bokeh diventa una
   sfocatura normale (senza dischi) senza che il video si fermi.
8. Windows: `dotnet test Windows\WebcamLR.Effetti.Test`: `SchedaVideoVeraComeIlProcessore` ora scrive anche la riga
   «mosaico»: **mandala**.

## Fonti

- MediaPipe Image Segmenter (modelli, classi): https://ai.google.dev/edge/mediapipe/solutions/vision/image_segmenter
- Schede dei modelli (Apache 2.0): Documenti/Modelli ritaglio.md, sezione «Fonti».
- ONNX Runtime, DirectML Execution Provider (requisiti, `EnableMemoryPattern = false`, esecuzione sequenziale):
  https://onnxruntime.ai/docs/execution-providers/DirectML-ExecutionProvider.html
- Pacchetti NuGet e licenze: `microsoft.ml.onnxruntime.directml` 1.24.4 (MIT, dipende da `Microsoft.AI.DirectML`
  1.15.4, licenza nel pacchetto), letti da api.nuget.org il 27 ottobre 2026.
- iVCam, effetti sul PC con DirectML: https://www.e2esoft.com/?p=114452
