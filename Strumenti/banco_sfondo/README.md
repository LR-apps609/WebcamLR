# Banco di prova della qualità dello sfondo

Misura con i numeri, qui su Linux, quanto è buono il ritaglio della persona del motore effetti di Windows (e del
modello leggero, lo stesso di Android): maschera, bordo, tremolio nel tempo, alone della sfocatura e tempi. Serve a
scegliere le modifiche prima di provarle sui dispositivi di Ledion, non a sostituire quelle prove.
Conclusioni e numeri commentati: `Documenti/Qualità sfondo - banco.md`.

## Cosa fa

1. **Clip di prova** (`clip.py`): le 5 clip di prova di VideoMatte240K (persona + alfa vera, 4K ridotto a 1920×1080),
   120 fotogrammi ciascuna (4 s a 30 fps), composte su sfondi **nitidi** che si muovono come davanti a un telefono in
   mano (panoramica lenta + tremolio, che muove anche la persona) con il rumore del sensore (σ = 2/255). Gli sfondi sono
   le scene di `Strumenti/genera_sfondi.py` senza la sfocatura finale: disegnate da noi, nessuna licenza di terzi.

   | Clip | Persona | Sfondo |
   |---|---|---|
   | vm0000_libreria | uomo, primo piano | libri colorati (molti bordi) |
   | vm0001_ufficio | due persone a figura intera, piccole | ufficio chiaro |
   | vm0002_soggiorno | mezzo busto | parete calda, divano |
   | vm0003_studio | donna con giacca scura | studio scuro (scuro su scuro) |
   | vm0004_cemento | mezzo busto | cemento grigio |

2. **Modelli** (gli stessi file di `Windows/WebcamLR.Effetti/Modelli`): pieno (Selfie Multiclass 256×256) e leggero
   (Selfie Segmenter landscape 144×256, anche su Android), più MODNet per la variante E. Preparazione e filtro nel tempo
   sono quelli di `Preparazione.cs` e `FiltroTemporale.cs`, riscritti in numpy in `ricette_windows.py` insieme al bordo
   e alla sfocatura del `Compositore` (stessi conti, stessi arrotondamenti).
3. **Varianti** (`varianti.py`), tutte con la sfocatura «Medio» (0,55):

   | | Cosa cambia |
   |---|---|
   | A0 | grezza: maschera ingrandita bilineare, nessuna rifinitura (riferimento) |
   | **A** | **come oggi su Windows**: filtro guidato veloce (a, b al quarto, raggio ≈ 8 px a 1080p, eps 1e-3, applicati a metà), soglia smoothstep 0,17–0,67, sfocatura normalizzata con la persona del modello allargata (2m − 0,3) |
   | B | filtro guidato più fine, come il Mac: a, b a metà misura, applicati alla luminanza piena; raggio 4–8 px, eps 1e-3–1e-2 (la migliore: 8 px, 1e-3) |
   | C | B + EMA della maschera che dipende dal movimento: peso della nuova 0,35 dove l'immagine è ferma, fino a 1 dove si muove (0,35 + 12·\|ΔY\| medio 5×5) |
   | Cm | B con il filtro nel tempo del Mac (media 0,3, isteresi 0,3/0,7, spinta 0,15) |
   | D | C + soglia smoothstep 0,3–0,7 + sfocatura normalizzata dalla maschera rifinita, allargata 12 px, come il Mac (2,5m − 0,25) |
   | **D\*** | **consigliata**: A + EMA dal movimento + soglia 0,3–0,7 (bordo e sfocatura di oggi). Nel banco: `pieno/D:fondo_modello=1:fine=0` |
   | E0 / E / E\* | MODNet fotografico 512×288: grezzo / con la rifinitura di D / con quella di D\* |

4. **Misure** (`misure.py`), per fotogramma a 1920×1080 e poi in media (ogni clip pesa uguale):
   IoU (alfa ≥ 0,5); **MAD bordo** = errore medio |alfa − vera| nella fascia ±10 px dal contorno vero (×10⁻³);
   **Grad bordo** = errore sul gradiente nella stessa fascia (×10⁻³); **dtSSD** come Robust Video Matting (×10⁻²);
   **tremolio bordo** = variazione media dell'alfa dove la verità non cambia, entro 20 px dal contorno (×10⁻³);
   **alone** = errore di colore (0–255) dell'immagine sfocata, nell'anello 0–40 px fuori dalla persona, rispetto
   all'ideale (sfocatura normalizzata con la persona vera); **errore immagine bordo** = lo stesso nella fascia ±10 px.
5. **Immagini di confronto** (fotogramma 60 di ogni clip, per ogni variante): originale | maschera (verde = persona
   persa, rosso = sfondo preso per persona) | sfocatura, e sotto l'ingrandimento del bordo della testa.

`verifica_cs.py` + `VerificaCs/` passano gli stessi fotogrammi nella libreria C# vera (`RitaglioPersona`,
`Compositore.Rendi`) e la confrontano con D* (`D:fondo_modello=1:fine=0`, maschere con il filtro nel tempo e la media
dal movimento di `varianti.C`). Con la libreria del ramo prestazioni (30 fotogrammi di vm0003_studio): maschere del
pieno identiche (0 punti diversi), leggero al massimo 1/255 su 0,0002% dei punti, immagine di D* al massimo 1/255
(nessun punto oltre 2). Danno anche i tempi veri di C#. Con una libreria di prima di D* le maschere differiscono
(fino a 93/255 sul 13% dei punti): la verifica se ne accorge. `--effetti <cartella di WebcamLR.Effetti>` prova la
libreria di un'altra copia, per esempio di un altro ramo.

## Come si esegue

Serve Python 3.11+ con un ambiente virtuale, e il .NET 8 SDK solo per la verifica con C#.

```bash
python3 -m venv ~/banco-venv
~/banco-venv/bin/pip install onnxruntime numpy opencv-python-headless pillow
cd Strumenti/banco_sfondo
# 1. Dati (fuori dalla repository, ~200 MB): VideoMatte240K (solo i file che servono) e MODNet
~/banco-venv/bin/python -I scarica_dati.py ~/banco-dati
# 2. Tutte le varianti predefinite (5 clip in parallelo; circa 40 minuti con 4 processori)
~/banco-venv/bin/python -I banco.py --dati ~/banco-dati/vm240k --modnet ~/banco-dati/modnet --uscita ~/banco-risultati
#    solo alcune varianti o clip, meno fotogrammi:
~/banco-venv/bin/python -I banco.py ... --varianti pieno/A pieno/B:raggio=4:eps=0.01 --clip vm0003_studio --fotogrammi 30
# 3. Tempi per fotogramma (la rete; la rifinitura in numpy vale solo come rapporto tra varianti)
~/banco-venv/bin/python -I banco.py ... --tempi
# 4. Stessi conti della libreria C# (D*) e tempi veri di C#
~/banco-venv/bin/python -I verifica_cs.py --dati ~/banco-dati/vm240k --lavoro /tmp/banco-cs [--effetti <altra copia>/Windows/WebcamLR.Effetti]
```

`banco.py` scrive in `--uscita`: `risultati.json` (si aggiorna a ogni esecuzione, variante per variante),
`risultati.md` (tabelle per clip e media) e `confronti/*.jpg`. Le immagini contengono le persone di VideoMatte240K:
non vanno nella repository.

## Dati e licenze (niente di questo nella repository)

- **VideoMatte240K** (Lin, Ryabtsev, Sengupta, Curless, Seitz, Kemelmacher-Shlizerman, «Real-Time High-Resolution
  Background Matting», CVPR 2021): 484 clip da green screen (filmati di Storyblocks) con l'alfa estratta. Usiamo le
  5 clip di prova, primi 120 fotogrammi, dalla versione «JPEG HD» preparata per Robust Video Matting.
  - Fonte ufficiale: https://grail.cs.washington.edu/projects/background-matting-v2/#/datasets (link nel README di
    PeterL1n/BackgroundMattingV2). **Da qui non è raggiungibile**: i termini d'uso del dataset non si sono potuti
    leggere. Il codice di BGMv2 è MIT, ma non c'è una licenza scritta per il dataset nella repository; i filmati
    sono di Storyblocks e il dataset è distribuito per la ricerca. Va bene per prove interne di misura (niente
    ridistribuzione, niente addestramento, niente immagini nei documenti pubblici); **prima di qualsiasi altro uso
    Ledion controlli i termini sulla pagina ufficiale**.
  - Copia usata: Hugging Face `datasets/geyongtao/video_matting`, file `videomatte.zip` (23,7 GB, copia di terzi
    senza licenza dichiarata). `scarica_dati.py` legge l'indice dello zip e scarica solo i 1200 file che servono
    (~170 MB) con richieste a intervalli. Con l'archivio ufficiale si può puntare `--dati` alla cartella che contiene
    `VideoMatte240K_JPEG_HD/test`.
- **Sfondi**: `Strumenti/genera_sfondi.py`, disegnati da noi (nessuna licenza di terzi).
- **MODNet** (ZHKKKe/MODNet): codice, modelli e demo Apache-2.0 per dichiarazione esplicita del README ufficiale.
  Usiamo `modnet_photographic_portrait_matting.onnx` (export ufficiale; SHA-256 07c308cf…584df9, uguale a
  Xenova/modnet e alla copia DavG25/modnet-pretrained-models da cui si scarica). Il modello «webcam» esiste solo come
  checkpoint PyTorch: per convertirlo serve PyTorch, che qui non si installa (download.pytorch.org bloccato).
  Restano da verificare le licenze dei dati con cui sono stati addestrati i pesi.
- **Modelli MediaPipe**: quelli della repository (Apache-2.0, `Windows/WebcamLR.Effetti/Licenze`).

## Risultati (7 novembre 2026, 5 clip × 120 fotogrammi)

Media sulle 5 clip. In grassetto oggi e la consigliata. Più basso è meglio, tranne IoU.

| Modello / variante | IoU | MAD bordo | Grad bordo | dtSSD | Tremolio bordo | Alone | Errore immagine bordo |
|---|---|---|---|---|---|---|---|
| pieno A0 (grezza) | 0,9577 | 213,7 | 338,3 | 3,32 | 26,6 | 1,24 | 5,25 |
| **pieno A (oggi)** | **0,9582** | **137,4** | **247,1** | **3,36** | **22,5** | **1,01** | **2,53** |
| pieno B (r 8 px, eps 1e-3) | 0,9588 | 138,2 | 248,9 | 3,49 | 22,5 | 1,01 | 2,65 |
| pieno C | 0,9595 | 141,9 | 253,3 | 3,16 | 18,3 | 1,03 | 2,71 |
| pieno Cm (filtro del Mac) | 0,9380 | 190,3 | 303,3 | 4,75 | 22,0 | 1,71 | 4,30 |
| pieno D | 0,9639 | 120,8 | 229,1 | 3,27 | 15,5 | 2,49 | 3,89 |
| **pieno D\* (consigliata)** | **0,9635** | **118,0** | **223,0** | **3,06** | **15,5** | **0,94** | **2,75** |
| leggero A0 | 0,9040 | 275,5 | 383,6 | 4,20 | 38,8 | 1,65 | 5,29 |
| leggero A (oggi) | 0,9061 | 234,5 | 316,0 | 4,31 | 32,0 | 1,78 | 3,78 |
| leggero D\* | 0,9110 | 221,7 | 302,5 | 3,89 | 23,1 | 1,63 | 3,98 |
| MODNet E0 (grezzo) | 0,9871 | 75,8 | 198,4 | 2,48 | 11,5 | 0,49 | 2,29 |
| MODNet E | 0,9870 | 64,7 | 162,9 | 2,95 | 6,2 | 2,34 | 3,32 |
| MODNet E\* | 0,9862 | 60,9 | 157,7 | 2,58 | 7,0 | 0,52 | 1,76 |

Unità: MAD e Grad ×10⁻³, dtSSD ×10⁻², tremolio ×10⁻³, alone ed errore immagine in livelli 0–255.

Prova del filtro guidato (B, pieno, stessa media): raggio 4 px / eps 1e-3: MAD 136,9, Grad 264,0; 4 px / 1e-2: 147,4 /
292,4; 8 px / 1e-3: 138,2 / 248,9; 8 px / 3e-3: 145,7 / 263,1; 8 px / 1e-2: 158,4 / 288,8. Nessuno batte A in modo
chiaro, e un eps più grande peggiora sempre.

### Tempi per fotogramma (1080p, processore, Xeon 2,3 GHz, 4 processori virtuali, macchina condivisa)

| | ms (mediana) |
|---|---|
| Pieno, libreria C# `RitaglioPersona.Calcola` (preparazione + rete + filtro) | 38–47 |
| Leggero, libreria C# | 5,2–5,5 |
| Resa A completa, C# `Compositore.Rendi` (bordo + sfocatura Medio + composizione) | 26–27 |
| di cui bordo A (filtro guidato al quarto → metà + soglia), C# | 7,2 |
| bordo B (a, b a metà → misura piena), C# | 26,8 |
| EMA dal movimento (C e D\*), numpy su 256×256 | 1,9 (in C# stimato sotto 0,5) |
| Rete pieno / leggero / MODNet 512×288, onnxruntime Python, 4 fili | 38 / 2,9 / 81 |

La rifinitura in numpy è 10–15 volte più lenta del C# e conta solo come rapporto: D\* costa come A (321 contro
352 ms in numpy), B, C e D circa +30%.
