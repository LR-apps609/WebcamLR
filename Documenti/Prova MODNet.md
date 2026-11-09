# Prova MODNet

Punto 9 della lista qualità 1.0: «Prova di MODNet per i capelli: confrontarlo sul banco con Vision e MediaPipe; si tiene
solo se vince». Ramo `prova-modnet` (da `prestazioni`), 9 novembre 2026. Banco: `Strumenti/banco_sfondo` (README per
come si esegue; primo giro in `Qualità sfondo - banco.md`).

## In breve

- **Licenza: va bene.** Codice, modelli e demo di MODNet sono Apache-2.0 per dichiarazione esplicita degli autori.
  Resta un dubbio che da qui non si chiude: con quali dati sono stati addestrati i pesi (vedi «Licenze»).
- **Qualità: MODNet vince chiaramente, ma solo a 512×288 o più.** Con la nostra rifinitura di oggi (variante Q, uguale
  al C# di `prestazioni`) il modello webcam a 512×288, contro il pieno di oggi: errore sui capelli **−34%** (146 → 96),
  errore sul bordo −47%, tremolio −54%, dtSSD −21%, IoU 0,964 → 0,987, alone −44%. Vince in tutte e 5 le clip e su
  tutte le misure, anche scuro su scuro (capelli 211 → 115). A 256×160, dove costa meno del pieno, non vince in modo
  chiaro (capelli −7%, peggio nella libreria; dtSSD e tremolio uguali).
- **Costo: non entra nei livelli di oggi.** A 512×288 la rete costa **2,1–2,4 volte il pieno** (8,7 contro 4,1 GMAC;
  70 contro 30 ms sul processore qui), alla misura nativa 896×512 sei-sette volte (27 GMAC, 218 ms). Il pieno è già il
  livello più alto della scala del punto 6 e sta sulla scheda video; MODNet a 512×288 ci starebbe solo come livello in
  più sopra il pieno, sulle schede video veloci, e il tempo con DirectML non è misurato (stima 6–45 ms, il limite è
  28 ms a 30 fps).
- **Decisione: per ora non si integra. Nessun codice nell'app.** Vince sulla qualità ma non sul costo: dove costa come
  il pieno non vince, e dove vince costa più del doppio del livello più alto. Si riapre con una misura vera: se sul PC
  di Ledion MODNet 512×288 con DirectML resta sotto **12 ms**, si aggiunge un livello «Alta» sopra il pieno (sezione
  «Se si riapre»). Lo strumento per la misura c'è già: `VerificaCs --tempi-modelli`.
- **Vision di Apple non è nel confronto**: qui non gira e nel banco non ci sono numeri del Mac.

## Licenze e fonti

### MODNet

- Repository ufficiale: https://github.com/ZHKKKe/MODNet. README, sezione «License» (letta alla fonte il 9 novembre,
  `raw.githubusercontent.com/ZHKKKe/MODNet/master/README.md`): «The code, models, and demos in this repository
  (excluding GIF files under the folder `doc/gif`) are released under the Apache License 2.0». Il file `LICENSE` è il
  testo dell'Apache License 2.0 (SHA-256 c71d239d…0dab4). Quindi **codice e pesi Apache-2.0**, uso commerciale
  permesso, con avviso e testo della licenza da distribuire.
- I pesi ufficiali stanno su Google Drive (link nel README e in `onnx/README.md`), che da qui non si raggiunge. Si sono
  usate le copie di Hugging Face https://huggingface.co/DavG25/modnet-pretrained-models (Apache-2.0, dichiara di
  ricopiare la cartella `pretrained` del repository ufficiale):
  - `modnet_photographic_portrait_matting.onnx`, l'export ONNX ufficiale (fatto da @manthan3C273 con `onnx/export_onnx.py`
    del repository): SHA-256 07c308cf0fc7e6e8b2065a12ed7fc07e1de8febb7dc7839d7b7f15dd66584df9, uguale bit per bit a
    Xenova/modnet;
  - `modnet_photographic_portrait_matting.ckpt`: 7c22235f0925deba15d4d63e53afcb654c47055bbcd98f56e393ab2584007ed8;
  - `modnet_webcam_portrait_matting.ckpt`: 913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b.
  Che il checkpoint fotografico combaci peso per peso (scarto 0) con l'export ufficiale dice che la copia del
  fotografico è quella vera; per il webcam non c'è un confronto possibile da qui.
- **Il modello webcam in ONNX** non esiste ufficialmente: l'ha fatto `Strumenti/banco_sfondo/converti_modnet_webcam.py`
  senza PyTorch (non si installa qui). La rete è la stessa del fotografico: lo script mette i pesi del checkpoint
  webcam nel grafo dell'export ufficiale, con le BatchNorm del backbone fuse come nell'export. La corrispondenza tra
  pesi del grafo e chiavi del checkpoint si trova confrontando il checkpoint fotografico con il suo ONNX ufficiale:
  tutti i 204 pesi combaciano con scarto 0. Il checkpoint si legge senza eseguire codice (Unpickler che accetta solo
  le classi dei tensori). Il risultato non è nella repository.
- **Dati di addestramento: non verificati.** L'articolo (Ke et al., «MODNet: Real-Time Trimap-Free Portrait Matting via
  Objective Decomposition», AAAI 2022, https://arxiv.org/abs/2011.11961) da qui non si apre (arxiv.org bloccato), e
  il README non dice su quali dati sono stati addestrati i pesi pubblicati. Se ci fossero dati con licenza solo di
  ricerca (succede spesso nel matting), la licenza Apache degli autori sui pesi resta quella dichiarata, ma è un
  rischio da far guardare prima di distribuire il modello. **Da controllare prima di un'eventuale integrazione.**

### Dati del banco

- **VideoMatte240K** (Lin et al., «Real-Time High-Resolution Background Matting», CVPR 2021): pagina ufficiale
  https://grail.cs.washington.edu/projects/background-matting-v2/#/datasets, **anche oggi non raggiungibile da qui**.
  Il codice di BackgroundMattingV2 è MIT (https://github.com/PeterL1n/BackgroundMattingV2, `LICENSE` letto alla
  fonte), ma il README non dà una licenza per il dataset; i filmati vengono da Storyblocks. La copia usata
  (Hugging Face `datasets/geyongtao/video_matting`) non dichiara nessuna licenza. Uso: solo misure interne, niente
  ridistribuzione, niente addestramento, niente immagini nei documenti. Prima di qualsiasi altro uso Ledion legga i
  termini sulla pagina ufficiale.
- **Sfondi** delle clip: `Strumenti/genera_sfondi.py`, disegnati da noi.
- **MediaPipe** (pieno e leggero): Apache-2.0, già nella repository (`Windows/WebcamLR.Effetti/Licenze`).

## Come si è misurato

Stesse 5 clip del banco (VideoMatte240K, 120 fotogrammi a 1080p su sfondi nitidi che si muovono, rumore del sensore),
stesse misure del giro di MediaPipe, più tre misure nuove sui capelli.

- **Oggi su Windows = variante Q**: il ritaglio e la resa del ramo `prestazioni` riscritti in numpy: filtro nel tempo,
  media dal movimento, isteresi (Qualità 4), filtro guidato veloce al quarto → metà, soglia 0,3–0,7, sfocatura «Medio»
  senza alone. `verifica_cs.py` la confronta con la libreria C# vera: maschere del pieno identiche (0 punti diversi),
  leggero al massimo 1/255 su 0,0002% dei punti, immagine al massimo 1/255.
- **MODNet** entra nella stessa catena (Q): la sua alfa al posto della persona di MediaPipe. In più la variante **M**
  (matting diretto): filtro nel tempo e media dal movimento, poi l'alfa ingrandita senza filtro guidato né soglia, per
  vedere se l'alfa morbida dei capelli aiuta.
- Misure d'ingresso di MODNet: **256×160** (la più vicina a 256×144 con i lati multipli di 32 che MODNet vuole; il
  fotogramma si stira, come con MediaPipe), **512×288** e **896×512**, la nativa (lato corto 512, come la demo webcam
  ufficiale e `ref_size = 512` dell'inferenza ufficiale).
- **Capelli**: dove l'alfa vera è sfumata (0,02–0,98, allargata di 3 px) nel 35% più alto della persona: testa e capelli
  (nella libreria e nell'ufficio anche la mano alzata). MAD e gradiente ×10⁻³, errore dell'immagine sfocata in livelli.
- **Scuro su scuro**: la clip `vm0003_studio` (giacca e capelli scuri su fondo scuro).

## Numeri

Media su 5 clip × 120 fotogrammi. Più basso è meglio, tranne IoU. MAD, Grad e tremolio ×10⁻³, dtSSD ×10⁻², alone ed
errori dell'immagine in livelli 0–255. «webcam» e «foto» sono i due modelli MODNet.

| | IoU | MAD bordo | Grad bordo | dtSSD | Tremolio | Alone | Errore immagine | MAD capelli | Grad capelli | Immagine capelli |
|---|---|---|---|---|---|---|---|---|---|---|
| **pieno, oggi (Q)** | 0,964 | 115,4 | 223,6 | 3,12 | 14,4 | 0,93 | 2,78 | 145,6 | 314,2 | 3,53 |
| leggero, oggi (Q) | 0,911 | 221,1 | 305,2 | 3,92 | 21,4 | 1,63 | 4,00 | 267,9 | 436,7 | 5,37 |
| webcam 256×160, Q | 0,968 | 109,7 | 218,4 | 3,23 | 14,7 | 0,92 | 2,46 | 135,2 | 304,2 | 3,21 |
| webcam 256×160, M | 0,965 | 188,6 | 356,9 | 3,20 | 25,1 | 0,93 | 4,75 | 230,8 | 448,2 | 6,46 |
| **webcam 512×288, Q** | **0,987** | **61,7** | **159,9** | **2,47** | **6,6** | **0,52** | **1,78** | **95,6** | **248,2** | **2,44** |
| webcam 512×288, M | 0,987 | 90,0 | 224,3 | 2,34 | 12,0 | 0,53 | 2,66 | 133,1 | 313,4 | 3,85 |
| foto 512×288, Q | 0,986 | 60,6 | 157,6 | 2,60 | 6,7 | 0,52 | 1,76 | 95,1 | 246,9 | 2,46 |
| foto 512×288, M | 0,986 | 85,6 | 214,8 | 2,42 | 11,4 | 0,52 | 2,53 | 127,3 | 303,5 | 3,60 |
| foto 512×288, grezzo (E0) | 0,987 | 75,8 | 198,4 | 2,48 | 11,5 | 0,49 | 2,29 | 117,3 | 288,3 | 3,40 |
| webcam 896×512, Q | 0,989 | 51,8 | 142,1 | 2,20 | 4,9 | 0,41 | 1,53 | 83,3 | 227,3 | 2,18 |
| webcam 896×512, M | 0,990 | 70,2 | 163,5 | 1,86 | 7,4 | 0,43 | 1,91 | 106,6 | 243,1 | 2,78 |

Webcam 512×288 con Q contro il pieno di oggi: IoU +0,023, MAD bordo −47%, Grad −28%, dtSSD −21%, tremolio −54%,
alone −44%, errore immagine −36%, **capelli: MAD −34%, Grad −21%, immagine −31%**.

Capelli (MAD ×10⁻³) e dtSSD per clip:

| Clip | pieno Q | webcam 256×160 Q | webcam 512×288 Q | webcam 896×512 Q | dtSSD pieno → webcam 512 |
|---|---|---|---|---|---|
| libreria (molti bordi) | 162,5 | 178,2 | 115,1 | 97,3 | 5,05 → 4,26 |
| ufficio (figura intera, piccola) | 150,3 | 149,0 | 98,0 | 77,0 | 4,91 → 3,51 |
| soggiorno | 56,3 | 53,2 | 47,8 | 45,2 | 1,23 → 1,17 |
| studio (scuro su scuro) | 211,0 | 164,1 | 115,1 | 115,4 | 1,95 → 1,26 |
| cemento | 148,0 | 131,6 | 101,8 | 81,5 | 2,47 → 2,13 |

Scuro su scuro (`vm0003_studio`), pieno Q → webcam 512×288 Q: MAD bordo 141 → 67, capelli 211 → 115, tremolio
12,7 → 5,0, IoU 0,977 → 0,994.

Cosa dicono:

- **La rete conta più dell'alfa morbida.** Con la nostra soglia (Q) MODNet va meglio che con la sua alfa così com'è
  (M) anche sui capelli (96 contro 133): sul bordo l'alfa di MODNet sbaglia di più di quanto guadagni a essere sfumata.
  Il guadagno viene dalla segmentazione migliore (più capelli presi, meno sfondo preso), non dal matting. Quindi, se
  si integra, MODNet entra nella catena di oggi come terza fonte della maschera, senza un bordo nuovo.
- **Webcam e fotografico sono quasi uguali**; il webcam trema un po' meno nel tempo (dtSSD 2,47 contro 2,60) e va
  meglio scuro su scuro: è lui il candidato.
- **A 256×160 MODNet non vince chiaramente**: in media capelli −7% e bordo −5%, ma nella libreria peggio del pieno
  (178 contro 162), dtSSD e tremolio uguali. Sotto i 512 px perde i dettagli che lo fanno vincere.
- **896×512** è il migliore su quasi tutto (capelli −43%), ma costa più di sei volte il pieno.

Limiti (gli stessi del primo giro, `Qualità sfondo - banco.md`): clip da studio con luce buona, persone centrate,
nessuna compressione H.264 e nessuna stanza vera: è il terreno di MODNet, e i numeri assoluti sono ottimisti. La zona
«capelli» è approssimata (alfa sfumata nella parte alta). Il video di Ledion (felpa scura, mensola con il peluche)
non è stato provato.

## Tempi

Solo la rete, mediana per fotogramma. Xeon 2,3 GHz con 4 processori virtuali, macchina condivisa (±30%). C# =
ONNX Runtime 1.24.4 della libreria (`VerificaCs --tempi-modelli`, due giri); Python = onnxruntime 1.31.1
(`banco.py --tempi`). Il rapporto con il pieno è dalla colonna Python a 4 fili, la più stabile.

| Modello | GMAC | C#, 4 fili | Python, 4 fili | Python, 1 filo | Rispetto al pieno |
|---|---|---|---|---|---|
| pieno 256×256 | 4,13 | 30–50 ms | 33,1 ms | 77,9 ms | 1 |
| leggero 256×144 | 0,03 | 2,4 ms | 2,4 ms | 2,5 ms | 0,08 |
| MODNet 256×160 | 2,42 | 19–21 ms | 22,9 ms | 51,5 ms | 0,7 |
| MODNet 512×288 | 8,70 | 67–70 ms | 78,1 ms | 189,6 ms | 2,3 |
| MODNet 896×512 (nativa) | 27,06 | 218–225 ms | 236,7 ms | 624,4 ms | 7,3 |

GMAC contati con le forme vere (ogni uscita delle convoluzioni misurata con onnxruntime). Il resto della catena (filtro
nel tempo, media dal movimento e isteresi su 147 456 punti a 512×288 invece di 65 536) costa meno di 1 ms in più; il
bordo e la sfocatura non cambiano, perché la maschera si porta comunque al quarto del fotogramma.

### Stima con DirectML (Windows)

Non misurato: qui non c'è una scheda video. Per il pieno `Effetti su Windows.md` stima 3–20 ms secondo la scheda (anche
quello da misurare sul PC di Ledion). Con il rapporto dei GMAC (le reti piccole sulla scheda video scalano un po' meno
del conto):

| | pieno | MODNet 256×160 | MODNet 512×288 | MODNet 896×512 |
|---|---|---|---|---|
| Stima DirectML | 3–20 ms | 2–12 ms | 6–45 ms | 20–130 ms |

Il limite della scala (punto 6) a 30 fps è 28 ms per la coda della maschera (85% di 33 ms). MODNet 512×288 ci sta
sulle schede video dedicate di fascia media e alta; sulle integrate (Intel UHD, dove già il pieno fatica) no.

### Stima con Core ML (Mac)

Non misurato (qui non c'è un Mac). Sul Neural Engine di un M1 una rete da 8,7 GMAC dovrebbe stare sui 5–15 ms; la
normalizzazione per istanza e i ridimensionamenti bilineari di MODNet possono finire sulla scheda video e allungare.
Il confronto vero sul Mac è con Vision (`VNGeneratePersonSegmentationRequest`, `.balanced`), che fa parte del sistema e
non costa spazio: i suoi numeri nel banco non ci sono.

## Decisione

**Non si integra adesso.** Le due condizioni non sono tutte e due vere:

1. Vince chiaramente sui capelli senza peggiorare il resto? **Sì a 512×288** (e a 896×512): meglio su tutte le misure e
   in tutte le clip. **No a 256×160**.
2. Il costo entra nei livelli del punto 6? **No.** Il livello più alto (`Pieno`) è già il modello pieno sulla scheda
   video, tarato per stare nel fotogramma sui PC di fascia media. MODNet 512×288 costa 2,1–2,4 volte tanto: non
   sostituisce nessun livello, starebbe solo in un sesto livello sopra il pieno, e solo sulle schede video veloci. Il
   suo tempo con DirectML è una stima (6–45 ms), non una misura. Dove costa come il pieno (256×160) non vince.

In più restano aperti: i dati di addestramento dei pesi (articolo non raggiungibile da qui), il modello webcam
convertito da noi e non dagli autori, e la prova sul video vero di Ledion (il banco è il terreno di MODNet).

Nessun codice nell'app. Nel banco restano gli strumenti per rifare la prova: la variante Q (uguale al C# di oggi),
le misure sui capelli, la conversione del modello webcam e la misura dei tempi in C# con DirectML.

### Se si riapre

Condizioni: (a) sul PC di Ledion `VerificaCs --tempi-modelli` dà MODNet 512×288 sotto **12 ms** con DirectML (così il
livello in più ha margine anche con la resa in parallelo e non oscilla); (b) sul suo video il bordo dei capelli si
vede meglio e la mensola non entra nella persona; (c) i dati di addestramento sono chiari. Allora:

- **Windows**: terza fonte in `RitaglioPersona` (`ModelloRitaglio.Alta`: ingresso NCHW 1×3×288×512 in [−1, 1], uscita
  1×1×288×512), con la stessa catena di oggi (filtro nel tempo, media dal movimento, isteresi, bordo, soglia). Un
  livello `Alta` sopra `Pieno` in `SceltaLivello`, raggiunto solo salendo e solo se il tempo misurato del pieno lascia
  spazio a 2,5 volte tanto; da `Alta` si scende a `Pieno` come oggi. Senza la classe «pelle del volto», il volto si
  prende come con il leggero. Test in `WebcamLR.Effetti.Test` come per il pieno e il leggero.
- **Pacchetto**: il modello nel pacchetto, in float16 (circa 13 MB invece di 26), non scaricato all'installazione:
  l'installatore resta autonomo e senza rete, e oggi contiene già il pieno da 16,5 MB. Licenza Apache-2.0 in
  `Licenze/`.
- **Mac**: conversione in Core ML su un Mac con `coremltools` dal checkpoint webcam (PyTorch → `ct.convert`, ingresso
  immagine 512×288, `compute_units = ALL`, float16), da confrontare con Vision `.balanced` sullo stesso video. Va fatta
  solo se MODNet resta su Windows.

## Da provare (Ledion, solo se si vuole riaprire)

1. In `Strumenti\banco_sfondo` su Windows: scarica `modnet_photographic_portrait_matting.onnx` da
   https://huggingface.co/DavG25/modnet-pretrained-models (cartella `models`) in una cartella a parte, poi
   `dotnet run -c Release --project VerificaCs -- --tempi-modelli <quella cartella>`. **Manda** le cinque righe
   (scheda video) e, con `processore` in fondo, le cinque del processore.
2. Il fotografico e il webcam hanno la stessa rete: il tempo vale per tutti e due.
