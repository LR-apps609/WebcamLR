# Ritocco della pelle e luce sul volto · banco (Qualità 11)

Ramo `ritocco-pelle` (da `prestazioni`), novembre 2026. **Protocollo: non cambia** (stessi campi `pelle` e `luceVolto`).
Obiettivo della lista qualità 1.0, punto 11: «Ritocco della pelle e luce: qualità pari al "beauty" di iVCam, controllata
sul banco». Riguarda il motore degli effetti del computer: Windows (`WebcamLR.Effetti`, `RicettePersona`) e Mac
(`RicetteEffetti.pelle` e `luceVolto`). Il ritocco fatto dall'iPhone (`EffettoPelle.swift`) non cambia.

## Com'era e che difetti aveva

- **Windows**: una sfocatura di tutti e tre i canali (due medie quadrate a metà risoluzione, raggio dallo 0,8% all'1,8%
  dell'altezza del volto), mescolata dove l'immagine differiva poco dalla sfocata; ai livelli leggeri **senza** quella
  maschera dei dettagli. Difetti: ai livelli leggeri occhi, labbra, capelli e contorno impastati (gradiente al 65–75%);
  colore spalmato tra pelle e labbra; un disco largo quanto il lato del volto che arrivava allo sfondo accanto alle
  guance (alone fino a 1,7 livelli sul legno).
- **Mac**: una gaussiana piccolissima (σ ≤ 3 px) dove la differenza dalla sfocata era sotto 1/25, al massimo a metà
  forza. Sicura ma quasi senza effetto: la rugosità della pelle scendeva dell'1–3%.
- **Luce sul volto** (tutti e due): una curva di tono **canale per canale** su un'ellisse grande (2 × la larghezza del
  volto). Una curva per canale cambia i rapporti tra i canali: sulla pelle chiara la saturazione scendeva del 18% e la
  tinta girava di 2,6°, sulla scura il contrario; la parete accanto al viso si schiariva di 10–11 livelli.
- **Sfarfallio**: non era un problema (la ricetta è deterministica e il disco è morbido): resta sotto 0,03 livelli tra
  fotogrammi con il rettangolo del volto che trema.

## La tecnica (Mac e Windows uguali)

I numeri stanno in un posto solo per piattaforma, con gli stessi valori: `RegolePelle` in
`Windows/WebcamLR.Effetti/Motore/RicettePersona.cs` e `RicetteEffetti.RegolePelle` in `Mac/Sorgenti/RicetteEffetti.swift`.

1. **Filtro guidato della luma con sé stessa** (He, Sun e Tang, lo stesso filtro del bordo della persona): in ogni
   finestra a = var / (var + ε), b = (1 − a)·media, poi Ys = media(a)·Y + media(b). Dove la luma varia poco (pori,
   macchie: deviazione 0,02–0,035) a ≈ 0 e il punto prende la media; dove varia molto (occhi, sopracciglia, labbra,
   capelli: 0,1 e oltre) a ≈ 1 e il punto resta com'è. Luma sRGB (Rec. 709, 0…1), raggio delle medie 2% dell'altezza
   del volto (8 px per un volto di 400 px), ε = (0,015 + 0,025·forza)². Medie su una griglia a metà della zona del
   volto (a un quarto ai livelli leggeri), applicazione alla luma piena (filtro guidato «veloce»).
2. **Ritorno della grana**: il 35% della parte più fine (pixel meno la binomiale 3×3; sul Mac la gaussiana di 0,7 px),
   pesato con 1 − media(a), cioè solo dove il filtro ha levigato. Senza, la pelle sembra plastica (nel test `NonEPlastica`, senza il ritorno
   e senza il peso dei bordi, la grana scende al 14% invece del 39%).
3. **Solo sulla pelle**:
   - **peso dal colore**: la crominanza (Cb, Cr) ruotata verso la tinta della pelle (130°). Tutte le pelli, dalla più
     chiara alla più scura, hanno quella tinta (cambia solo la quantità di colore): peso 1 entro circa ±12°, 0 oltre
     ±24°, e solo con un po' di colore (il bianco degli occhi, i capelli neri e i grigi restano fuori). Labbra a 106°:
     0,1–0,4. Il legno e i capelli castani hanno la tinta della pelle: lì lavorano il filtro guidato e il punto sotto;
   - **vicino ai bordi veri si ferma**: con la varianza locale della luma da 0,0016 a 0,0064 il peso scende a 0
     (smoothstep). Il filtro guidato da solo lascia un velo sui bordi medi (labbra, contorno su un fondo color legno);
   - **ellisse** attorno a ogni volto (piena fino al rettangolo del volto, niente oltre 1,4 volte), non più un disco
     largo quanto il lato più lungo;
   - **occhi e bocca protetti (Mac)**: con la pelle accesa il Mac cerca i volti con `VNDetectFaceLandmarksRequest`
     invece di `VNDetectFaceRectanglesRequest`; occhio + sopracciglio e labbra diventano ellissi dove il ritocco è zero
     (fino a 0,75 del raggio, pieno da 1,1). Windows non ha i punti del volto (il volto viene dalla maschera della
     persona): la stessa funzione accetta le zone (`protette`), ma oggi riceve null.
4. **Luma e colore separati**: la differenza di luma va uguale su rosso, verde e blu (il colore non cambia); il colore
   va del 50% verso quello medio della pelle attorno (media pesata con il peso del colore, raggio doppio: labbra, occhi
   e sfondo non entrano), a luma ferma. I rossori e le macchie colorate si attenuano, la tinta della pelle resta.

**Luce sul volto**: la stessa curva di prima (+0,4 EV su ombre e mezzitoni, il bianco al suo posto) ma sulla **luma**: il
guadagno curva(Y) / Y uguale sui tre canali (tinta e saturazione restano); il canale più alto si prende al più metà
dello spazio fino a 254 (niente bianco bruciato). Ellisse più stretta (0,8 della larghezza e 1 dell'altezza del volto
come semiassi, centro 6% più in basso) con il bordo smoothstep dal 30% del raggio. Su Windows una tabella del guadagno
per la luma; sul Mac una tabella 3D (`CIColorCube`, 32³) con la stessa formula, mescolata in sRGB come su Windows.

**Mac, come è fatto**: solo filtri di sistema di Core Image, come il bordo della persona: il filtro guidato riusa
`coefficientiGuida` (con sigma ed ε propri: la sigma è quella con la stessa varianza della media quadrata di Windows), il
peso del colore è una tabella 3D 64³ di `pesoColore`, la media pesata del colore passa da `dividi` con un piccolo peso
neutro (0,01, uguale su Windows) che tiene la divisione tra 0 e 1. Se `verificaAritmetica` non torna (il guided filter
del bordo è già spento in quel caso), il ritocco non si fa.

**Windows, processore e scheda video**: il ritocco e la luce restano sul processore in tutti e due i percorsi. Con la
pelle o la luce accese la composizione sulla scheda video (Qualità 5 e 12) compone solo lo sfondo e il ritocco viene
dopo, sui colori veri, uguale per i due percorsi: lo shader (`Composizione.hlsl`) non cambia e il confronto
`SchedaVideoVeraComeIlProcessore` / `IlProcessoreFaIContiDelloShader` resta quello di prima.

## Il banco

`Strumenti/banco_pelle` (C#, .NET 8): `dotnet run -c Release --project Strumenti/banco_pelle` (circa un minuto e mezzo con
4 processori). Con `-p:Effetti=<altra copia>/Windows/WebcamLR.Effetti -p:Prima=true` prova la libreria di un'altra copia
(i numeri «prima» qui sotto vengono da 7e5dd09); con `-- --immagini <cartella>` scrive anche i ritagli in PPM.

**Nessun volto vero.** Nel banco della Qualità 4 (VideoMatte240K) le persone sono lontane e piccole, e foto di volti
scaricate senza licenza chiara non vanno usate: i tre volti sono **sintetici**, disegnati dal banco (`Volto.cs`), pelle
chiara, media e scura a 1920×1080 con un volto di 340×405 px: ombreggiatura di una sfera, macchie (σ 5 px, 4%), pori
(σ 1,2 px, 3%), grana fine (σ 0,6 px, 2%), 14 brufoli rossi, due riflessi; occhi con palpebre e ciglia, sopracciglia a
peli, labbra, narici, frangia a ciocche; dietro un pannello di legno (colore simile alla pelle) e una parete grigia;
rumore del sensore σ = 2/255. «Pulito» è lo stesso volto senza macchie, pori e brufoli. Sono volti disegnati, non foto:
le misure dicono se una modifica va nella direzione giusta, non quanto è bella su una persona vera.

Misure (luma Rec. 709, 0–255; medie sui tre volti):

- **Rugosità**: scarto quadratico dalla pelle pulita nel nucleo della pelle (lontano dai lineamenti). Comprende il
  rumore del sensore (circa 1,5), quindi lo zero non si raggiunge.
- **Rossori**: lo stesso per Cr.
- **Grana**: deviazione della parte più fine, uscita / ingresso (1 = intatta, 0 = plastica).
- **Bordi**: gradiente di Sobel uscita / ingresso **sui bordi veri** (dove il volto pulito ha un gradino oltre circa 12
  livelli) di occhi e sopracciglia, bocca, capelli e contorno del viso.
- **Alone**: differenza media sullo sfondo da 6 a 30 px fuori dal viso.
- **Sfarfallio**: differenza media tra fotogrammi successivi (30), con il rettangolo del volto che trema (1,5% in
  posizione, 2% in misura, come la stima dalla maschera); senza rumore tutto quello che cambia lo fa il ritocco.

### Numeri, prima e dopo

| Ritocco | Forza | Rugosità | Riduzione | Rossori | Grana | Occhi | Bocca | Capelli | Contorno | Alone |
|---|---|---|---|---|---|---|---|---|---|---|
| ingresso | | 6,64 | | 2,10 | 1 | 1 | 1 | 1 | 1 | 0 |
| Windows prima, pieno | 0,5 | 5,84 | 12% | 1,72 | 0,78 | 1,00 | 0,94 | 0,98 | 0,94 | 0,77 |
| **Windows dopo, pieno** | 0,5 | **5,53** | **17%** | **1,67** | 0,78 | 1,00 | **0,96** | 0,97 | **0,95** | **0,46** |
| Windows prima, leggero | 0,5 | 5,92 | 11% | 1,83 | 0,82 | 0,83 | 0,83 | 0,88 | 0,86 | 0,63 |
| **Windows dopo, leggero** | 0,5 | 5,62 | 15% | 1,77 | 0,75 | **0,99** | **0,94** | **0,95** | **0,96** | 0,40 |
| Windows prima, pieno | 1 | 5,09 | 23% | 1,35 | 0,60 | 0,99 | 0,89 | 0,97 | 0,88 | 1,69 |
| **Windows dopo, pieno** | 1 | **4,25** | **36%** | **1,27** | 0,46 | 0,99 | 0,88 | 0,91 | 0,86 | **1,37** |
| Windows prima, leggero | 1 | 5,09 | 23% | 1,53 | 0,63 | 0,65 | 0,65 | 0,75 | 0,71 | 1,61 |
| **Windows dopo, leggero** | 1 | 4,44 | 33% | 1,45 | 0,41 | **0,98** | **0,83** | **0,87** | **0,88** | 1,18 |
| Mac prima (modello in C#) | 0,5 | 6,57 | 1% | 2,01 | 0,93 | 1,00 | 0,99 | 1,00 | 0,99 | 0,07 |
| Mac prima (modello in C#) | 1 | 6,47 | 3% | 1,94 | 0,86 | 1,00 | 0,99 | 1,00 | 0,99 | 0,30 |
| **dopo, con occhi e bocca protetti (come il Mac)** | 0,5 | 5,53 | 17% | 1,67 | 0,78 | **1,00** | **1,00** | 0,97 | 0,95 | 0,46 |
| **dopo, con occhi e bocca protetti (come il Mac)** | 1 | 4,25 | 36% | 1,27 | 0,46 | **1,00** | **1,00** | 0,91 | 0,86 | 1,37 |

Sfarfallio (forza 0,5, volto medio):

| | Solo il rettangolo che trema: pelle / bordi | Con il rumore: pelle / bordi (ingresso 1,71 / 1,71) |
|---|---|---|
| Windows prima, pieno | 0,004 / 0,032 | 1,32 / 1,59 |
| Windows dopo, pieno | 0,005 / 0,022 | 1,37 / 1,65 |
| Windows prima, leggero | 0,003 / 0,127 | 1,41 / 1,48 |
| Windows dopo, leggero | 0,019 / 0,096 | 1,33 / 1,65 |

Luce sul volto (presenza piena):

| | ΔY pelle (chiara / media / scura) | Saturazione uscita / ingresso | Tinta | Riflessi ΔY | Bruciati | Parete accanto ΔY |
|---|---|---|---|---|---|---|
| prima | +14,4 / +16,1 / +10,0 | 0,82 / 0,90 / 0,98 | +2,6° / +1,3° / +0,3° | +7,8 (chiara) | 0% | +10,7 |
| **dopo** | +11,5 / +16,0 / +9,8 | **1,00 / 1,00 / 1,00** | **0°** | **+0,2** | 0% | **+6,9** |

Come si leggono:

- **A forza media** (0,5) il ritocco nuovo toglie di più (17% contro 12%) senza perdere nulla sui bordi (tutti uguali o
  meglio) e con meno alone; la grana resta la stessa. Ai **livelli leggeri** la differenza è grande: prima occhi,
  bocca e contorno perdevano un sesto del gradiente anche a metà forza, ora restano al 94–99%.
- **A forza piena** toglie molto di più (36% contro 23%, rossori 1,27 contro 1,35). Sui capelli (frangia sulla fronte,
  0,91 contro 0,97) e sul contorno contro il legno (0,86 contro 0,88) perde un poco: sono i bordi deboli, con una luma
  simile ai due lati, che il peso dei bordi non vede. Con i punti del volto (Mac) occhi e bocca restano al 100%.
- La **grana** a forza piena scende a 0,46 (ritocco più forte, era 0,60): sui ritagli non sembra plastica, la trama fine
  resta visibile; è il numero da guardare se Ledion la trova «finta».
- **Sfarfallio**: trascurabile prima e dopo (sotto 0,1 livelli); con il rumore del sensore l'uscita sfarfalla meno
  dell'ingresso perché la pelle levigata ha meno rumore.
- **Luce**: la saturazione e la tinta non cambiano più, i riflessi non salgono (+0,2 invece di +7,8) e la parete
  accanto al viso si schiarisce di un terzo in meno. La pelle chiara si schiarisce un poco meno (+11,5 invece di +14,4)
  perché il tetto protegge i suoi chiari.
- **Mac prima** era quasi spento (1–3%): il Mac nuovo usa la stessa ricetta di Windows, quindi dovrebbe dare i numeri
  di «dopo, con occhi e bocca protetti». Non è misurato: Core Image qui non c'è.

## Costo e livelli

| | Pieno | Leggero |
|---|---|---|
| Windows prima, solo il ritocco, volto alto 405 px a 1080p | 4,9 ms | 5,4 ms |
| **Windows dopo** | **3,9 ms** | **2,6 ms** |

(Mediana di 30 chiamate, 4 processori virtuali condivisi: ±30%.) Il test `MisuraTempi` («pelle + luce + specchio», volto
piccolo) resta tra 20 e 32 ms qui prima e dopo, come la variabilità della macchina. Ai livelli della Qualità 6 il
ritocco segue il bordo: **pieno** al livello Pieno; **leggero** (griglia a un quarto, niente grana, tre quarti della
forza) da Bordo leggero in giù sul PC, con il bordo bilineare sul Mac. Sul Mac costa qualche passaggio in più nel grafo
Core Image (una ventina di filtri sulla zona del volto, sulla scheda video) e, con la pelle accesa, i punti del volto
invece dei soli rettangoli: qualche millisecondo sulla coda di analisi, 10 volte al secondo, fuori dal tempo di Vision
misurato per i livelli.

## Non verificato qui

- **Swift** (Mac): niente compilatore su Linux. Riletto con cura: i filtri usati (`CIColorCube`, `CIRadialGradient`,
  `CIColorPolynomial`, `CIMaximumCompositing`, `CIMinimumCompositing`, `CIBlendWithMask`), `VNDetectFaceLandmarksRequest`
  e i punti normalizzati al riquadro del volto. Da provare: la build, l'aspetto, il costo (riga «Effetti sul Mac»).
- La resa vera su **volti veri** e la luce di una stanza vera: il banco usa volti disegnati.
- I punti del volto di Vision con occhiali, barba, volto di profilo: le zone protette potrebbero essere piccole o
  mancare (allora il ritocco si regola solo con il colore e i bordi, come su Windows).
- iVCam: nessun confronto diretto (serve un PC con iVCam e la stessa scena).

## Dubbi e idee

- Su Windows il modello pieno ha la classe «pelle del volto»: sarebbe una maschera della pelle migliore del colore
  (esclude capelli castani e legno), ma oggi la maschera arriva alla resa solo con lo sfondo acceso.
- Il raggio del 2% e il ritorno della grana del 35% sono scelti sul banco: da regolare con le prove di Ledion.
- Il ritocco del telefono (iPhone, `EffettoPelle.swift`) è ancora quello di prima.
