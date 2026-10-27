# Modelli per il ritaglio della persona

Ricerca del 27 ottobre 2026 (lavoro 4 di «Qualità ed efficienza»). Obiettivo: la maschera della persona migliore per
sfondo sfocato e sostituito, sul telefono, senza rete, con licenza permissiva (Apache, MIT, BSD: niente GPL, niente
licenze non commerciali), per codice **e** pesi.

## In breve

- **Android (fatto):** il modello **MediaPipe Selfie Multiclass 256×256** sulla GPU, con persona = 1 − sfondo. Se il
  telefono non lo regge, l'app torna da sola al **Selfie Segmenter** leggero (quello di prima). Dettagli più sotto.
- **iPhone:** la scelta migliore resta di sistema: «Ritratto» di Apple (lavoro 2) e, per la nostra pipeline, Vision
  `VNGeneratePersonSegmentationRequest` (`.balanced` a ogni fotogramma). Un modello nostro con Core ML è possibile solo
  convertendolo su un Mac (vedi «iPhone»); i modelli MediaPipe non si convertono in Core ML in modo pratico.
- **Esclusi:** Robust Video Matting (il migliore nel tempo, ma GPL-3.0).

## Confronto

| Modello | Bordo e capelli | Stabilità nel tempo | Velocità su telefono | Dimensione | Licenza (codice / pesi) | iPhone (Core ML) | Android |
|---|---|---|---|---|---|---|---|
| MediaPipe Selfie Segmenter (quadrato 256×256 e «landscape» 144×256) | Buono sul corpo, capelli impastati; IoU medio 96,5 % (quadrato) e 96,0 % (landscape) sulla scheda | Nessuna memoria tra fotogrammi: tremolio del bordo, si corregge con un filtro (c'è già) | Pixel 6: 33–34 ms CPU e GPU (tutta la pipeline) | 249 KB / 244 KB | Apache 2.0 / Apache 2.0 (scheda del modello) | Solo con MediaPipe per iOS (CocoaPods); Core ML: no conversione pratica da .tflite | Già usato: ora è il ripiego |
| **MediaPipe Selfie Multiclass 256×256** | Il migliore dei MediaPipe sui capelli: classi sfondo, capelli, pelle del corpo, pelle del volto, vestiti, accessori; IoU medio 77,2 % sulle 6 classi (non confrontabile con il 96 % a 2 classi) | Nessuna memoria tra fotogrammi (come sopra) | Pixel 6: **71 ms GPU**, 218 ms CPU (tutta la pipeline) | 16,4 MB (float32; non esiste float16 o int8 ufficiale) | Apache 2.0 / Apache 2.0 (scheda del modello) | Come sopra | **Integrato** (GPU, con prova di velocità) |
| MediaPipe Selfie Multiclass 512×512 | Ancora migliore (IoU 81,1 %) | Come sopra | Più lento del 256 (non c'è il dato ufficiale) | non trovato tra i file scaricabili | Apache 2.0 | — | Troppo lento per il video |
| Vision `VNGeneratePersonSegmentationRequest` (iOS 15+) | `.accurate` molto buono sui capelli; `.balanced` buono; `.fast` grossolano | Richiesta «stateful» da riusare tra i fotogrammi: Apple dice che aiuta a smussare nel tempo con `.fast` | `.balanced` consigliato da Apple per il video fotogramma per fotogramma | di sistema (0 MB) | di sistema | Sì, è già usato | — |
| «Ritratto» di Apple (Effetti video, iOS 15+) | Il migliore che abbiamo sull'iPhone (profondità + segmentazione di sistema) | Ottima | Ottimizzato da Apple | di sistema | di sistema | Sì, lo accende l'utente (lavoro 2) | — |
| MODNet (matting, alfa vera) | Alfa morbida sui capelli, migliore di una segmentazione | Tremolio nel video; la correzione proposta nel lavoro (OFD) aggiunge un fotogramma di ritardo | Nessun dato ufficiale su telefono; il modello pubblicato lavora a 512 px ed è molto più pesante dei MediaPipe; il modello «7 MB» della demo non è pubblicato | circa 25 MB in float32 (stima da 6,5 M parametri) | **Apache 2.0 / Apache 2.0** (README: «The code, models, and demos … are released under the Apache License 2.0»). Prima era CC BY-NC-SA: controllare la data della versione dei pesi scaricati | Conversione PyTorch → Core ML con coremltools su un Mac: fattibile | PyTorch → ONNX → TFLite: fattibile fuori da qui, non con l'ImageSegmenter di MediaPipe senza metadati |
| PP-HumanSegV2-Lite (PaddleSeg) | Buono (mIoU 96,63 % sul loro insieme ritratti, 256×144) | Nessuna memoria tra fotogrammi | 15,86 ms su Snapdragon 855, un solo core (Paddle Lite) | 5,4 MB | Apache 2.0 (repository); per i pesi nessuna dichiarazione separata | Paddle → ONNX → Core ML: coremltools non legge più ONNX, poco pratico | Paddle → ONNX → TFLite: fattibile fuori da qui; serve un interprete TFLite nostro (non l'ImageSegmenter) |
| Robust Video Matting | Il migliore nel video (ricorrente, alfa) | Ottima (memoria tra fotogrammi) | Ha già i modelli Core ML | non controllata | **GPL-3.0**: escluso | — | — |

Nota sulle velocità: i numeri MediaPipe sono della pagina ufficiale (Pixel 6, tutta la pipeline); quelli di PaddleSeg
sono loro, su un altro telefono e un altro motore: non si confrontano alla pari.

## Perché il Multiclass su Android, e con quale cautela

- **Qualità:** è il solo modello MediaPipe che distingue i capelli e gli accessori (occhiali, cappelli). Sommando tutte
  le classi tranne lo sfondo (persona = 1 − sfondo) il bordo dei capelli è più fine e meno «a casco» del Selfie
  Segmenter.
- **Combinazione delle classi:** le maschere di confidenza escono già passate per softmax (nei metadati del modello
  l'attivazione è SOFTMAX), quindi la somma delle sei classi in ogni punto fa 1 e la persona è esattamente
  `1 − maschera[0]`. L'ordine delle classi è quello di `labels.txt` nel modello: background, hair, body-skin, face-skin,
  clothes, others. Le maschere arrivano grandi come l'immagine data (384×216), in qualunque proporzione.
- **Velocità, il punto debole:** 71 ms sulla GPU del Pixel 6 vuol dire 14 maschere al secondo, cioè la maschera resta
  indietro rispetto al video e torna il difetto delle scie (terza prova di Ledion). Per questo l'app lo **prova**: le
  prime 5 maschere non contano (la GPU compila), poi su 20 maschere se la media supera **45 ms** (meno di circa 22 al
  secondo) passa al Selfie Segmenter leggero sul processore per il resto della sessione. Stessa cosa se la GPU non si
  apre o il calcolo dà errore. Sui telefoni di fascia alta recenti ci si aspetta che regga; su quelli medi resta il
  modello di prima. Nel registro (logcat, etichetta `WebcamLR`) si legge quale modello è in uso e perché è stato
  lasciato.
- **Dimensione:** +16 MB nell'APK (solo float32 è pubblicato). Accettabile per la qualità; se diventa un problema, si
  può spostare in un pacchetto di risorse scaricato dal Play Store.

Codice: `Android/app/src/main/kotlin/it/lrapps/webcamlr/android/effetti/AnalisiImmagine.kt`. Modello:
`Android/app/src/main/assets/modelli/selfie_multiclass_256x256.tflite` (scaricato da
`storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/`, SHA-256
`c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0`). Licenza in `assets/licenze/Apache-MediaPipe.txt`.

Da guardare alla prova vera: un crash nativo del delegato GPU non si può intercettare dal Kotlin; sui telefoni dove la
GPU di MediaPipe non funziona di solito la creazione fallisce in modo pulito, ma va provato almeno su un telefono medio
e su uno di fascia alta.

## iPhone: cosa resta possibile oltre a «Ritratto»

1. **Vision, già in uso:** `.balanced` a ogni fotogramma con lo stesso oggetto richiesta riusato (Apple lo chiama
   «stateful» e consiglia `.balanced` per il video), `.accurate` solo per le foto o a frequenza ridotta. È la base
   giusta per sfondo sostituito, dove Ritratto non serve.
2. **MediaPipe per iOS** (lo stesso Multiclass): funziona con il motore TFLite e la GPU Metal, ma si installa **solo con
   CocoaPods** (guida ufficiale), da affiancare a XcodeGen. Possibile, ma è una dipendenza pesante per un guadagno
   incerto rispetto a Vision `.balanced`.
3. **Core ML con un modello nostro:** i .tflite di MediaPipe non si convertono in Core ML in modo pratico (coremltools
   parte da PyTorch o TensorFlow, non da TFLite, e non legge più ONNX). Candidato realistico: **MODNet** (Apache 2.0
   per codice e pesi secondo il README attuale), convertito da PyTorch con coremltools su un Mac, a 256–384 px per stare
   nei tempi, con l'Apple Neural Engine. Va misurato su un iPhone vero: senza un filtro nel tempo tremola, e il suo
   filtro proposto aggiunge un fotogramma di ritardo. Non si può fare qui (niente Mac, niente Swift).
4. **Robust Video Matting** avrebbe già i Core ML pronti ed è il migliore nel video, ma è GPL-3.0: escluso.

## Fonti

- MediaPipe, guida Image Segmenter (modelli, classi, tempi sul Pixel 6):
  https://ai.google.dev/edge/mediapipe/solutions/vision/image_segmenter
- Scheda del modello Multiclass (Apache 2.0, classi, IoU, 256 e 512):
  https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf
- Scheda del modello Selfie Segmentation (Apache 2.0, 249/244 KB, ingressi 256×256 e 144×256, IoU):
  https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Selfie%20Segmentation.pdf
- MediaPipe, licenza del codice (Apache 2.0): https://github.com/google-ai-edge/mediapipe/blob/master/LICENSE
- MediaPipe 0.10.14, API Java (`BaseOptions.setDelegate`, `Delegate.GPU`, maschere di confidenza come float):
  https://github.com/google-ai-edge/mediapipe/tree/v0.10.14/mediapipe/tasks/java/com/google/mediapipe/tasks
- MediaPipe per iOS, solo CocoaPods: https://ai.google.dev/edge/mediapipe/solutions/setup_ios
- Apple, WWDC21 «Detect people, faces, and poses using Vision» (livelli di qualità, richiesta stateful):
  https://developer.apple.com/videos/play/wwdc2021/10040/
- MODNet, README e licenza (Apache 2.0 per codice, modelli e demo): https://github.com/ZHKKKe/MODNet
- PaddleSeg, licenza Apache 2.0: https://github.com/PaddlePaddle/PaddleSeg ; PP-HumanSeg (tabelle dei modelli):
  https://github.com/PaddlePaddle/PaddleSeg/blob/release/2.9/contrib/PP-HumanSeg/README.md
- Robust Video Matting (GPL-3.0, modelli Core ML): https://github.com/PeterL1n/RobustVideoMatting

Non verificato qui: la pagina di Google (ai.google.dev) è bloccata dalla rete di questo ambiente; i tempi del Pixel 6
vengono dalle copie della stessa pagina trovate con la ricerca. Le dimensioni di MODNet (6,5 M parametri) vengono dal
lavoro scientifico, non da una misura del file.
