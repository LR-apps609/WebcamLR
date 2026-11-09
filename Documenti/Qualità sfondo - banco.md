# Qualità dello sfondo · banco di prova

Primo giro del banco `Strumenti/banco_sfondo` (come si esegue, dati, licenze e tabella completa nel suo README):
le varianti A–E della rifinitura della maschera misurate su clip con l'alfa vera, qui su Linux, con gli stessi conti
del motore effetti di Windows. Ramo `banco-qualita`, 7 novembre 2026. Le prove sui dispositivi di Ledion restano
necessarie: questo dice **cosa provare**, non come si vede sul suo video.

## In breve

- **Consigliata per Windows: «D\*»** = il bordo e la sfocatura di oggi (A) + una **media nel tempo della maschera
  che dipende dal movimento** + la **soglia smoothstep 0,3–0,7** (centro 0,5) al posto di 0,17–0,67 (centro 0,42).
  Rispetto a oggi, modello pieno, media di 5 clip: errore sul bordo (MAD) **−14%** (137 → 118), gradiente −10%,
  **tremolio del bordo −31%** (22,5 → 15,5), dtSSD −9% (3,36 → 3,06), IoU 0,958 → 0,964, alone uguale
  (1,01 → 0,94). Costa meno di 1 ms in più (l'EMA lavora sulla maschera 256×256). Migliora tutte e 5 le clip sul
  bordo e sul tremolio; la giacca scura su fondo scuro (`vm0003_studio`) passa da MAD 178 a 149 e da tremolio 22 a
  14. Unico prezzo: l'errore dell'immagine nella fascia ±10 px sale un poco (2,53 → 2,75 livelli su 255), perché il
  bordo è più netto dove l'alfa vera è sfumata (capelli).
- **B (filtro guidato più fine, come il Mac) non serve su Windows**: A ha già un filtro guidato con raggio ≈ 8 px a
  1080p, e farlo a metà misura con la luminanza piena non cambia i numeri (MAD 137 → 138) ma in C# costa 27 ms invece
  di 7. Un eps più grande (1e-2) peggiora sempre.
- **La sfocatura di oggi è già senza alone** (è già normalizzata). La versione del Mac (persona allargata 12 px,
  2,5m − 0,25) con la maschera già rifinita peggiora: alone da 1,0 a 2,5, perché vicino alla testa prende colore da
  troppo lontano (si vede come una zona piatta e spalmata attorno ai capelli). Va bene sul Mac, dove Vision sta
  qualche pixel dentro il bordo; su Windows no.
- **Il filtro nel tempo del Mac (Cm) sulla maschera di MediaPipe peggiora** (IoU 0,958 → 0,938, MAD 190): la sua
  media lenta (0,3), l'isteresi 0,3/0,7 e la spinta di ±0,15 sono tarate su Vision; sulla libreria che scorre
  l'errore sul bordo raddoppia (MAD 111 → 291), mentre sulla giacca scura aiuta (178 → 156). Non portarlo su Windows
  così com'è.
- **MODNet è nettamente migliore come maschera** (MAD 61 contro 118, tremolio 7 contro 16, IoU 0,986), ma: costa
  81 ms sul processore a 512×288 (il pieno 38), il modello «webcam» non si è potuto convertire qui, e queste clip
  (studio, luce buona, persona centrata) sono proprio il suo terreno. Da provare sulla scheda video e sul video di
  Ledion prima di decidere: se tiene i numeri, diventa la modalità «alta qualità» (vedi sotto).
- **Leggero (Android e ripiego di Windows)**: la stessa D\* aiuta anche lui (MAD 235 → 222, tremolio 32 → 23,
  dtSSD 4,31 → 3,89); resta molto sotto il pieno (IoU 0,911).

## Varianti

Tutte con la sfocatura «Medio» (0,55), a 1080p, livello Pieno del Compositore.

| | Cosa |
|---|---|
| A0 | grezza: maschera ingrandita, nessuna rifinitura |
| A | oggi su Windows: filtro guidato veloce (a, b al quarto, raggio 2 = ≈ 8 px, eps 1e-3, applicati a metà), soglia 0,17–0,67, sfocatura normalizzata con la persona del modello (2m − 0,3) |
| B | a, b a metà misura, applicati alla luminanza piena; raggio 4/8 px, eps 1e-3/3e-3/1e-2 (scelto 8 px, 1e-3) |
| C | B + EMA della maschera: peso della nuova 0,35 + 12·\|ΔY\| (ΔY = differenza di luminanza tra due fotogrammi, media 5×5 alla misura della maschera), tra 0,35 e 1; dopo il FiltroTemporale di oggi |
| Cm | B con il filtro nel tempo del Mac al posto di quello di Windows |
| D | C + soglia 0,3–0,7 + sfocatura del Mac (maschera rifinita, allargata 12 px, 2,5m − 0,25, divisione sempre) |
| D\* | A + EMA di C + soglia 0,3–0,7 |
| E, E\* | MODNet fotografico 512×288 con la rifinitura di D / di D\* |

## Numeri

Media su 5 clip × 120 fotogrammi (tabella completa e per clip nel README del banco). Più basso è meglio, tranne IoU.

| | IoU | MAD bordo ×10⁻³ | Grad bordo ×10⁻³ | dtSSD ×10⁻² | Tremolio ×10⁻³ | Alone | Errore immagine |
|---|---|---|---|---|---|---|---|
| A0 | 0,9577 | 213,7 | 338,3 | 3,32 | 26,6 | 1,24 | 5,25 |
| **A (oggi)** | 0,9582 | 137,4 | 247,1 | 3,36 | 22,5 | 1,01 | 2,53 |
| B | 0,9588 | 138,2 | 248,9 | 3,49 | 22,5 | 1,01 | 2,65 |
| C | 0,9595 | 141,9 | 253,3 | 3,16 | 18,3 | 1,03 | 2,71 |
| Cm | 0,9380 | 190,3 | 303,3 | 4,75 | 22,0 | 1,71 | 4,30 |
| D | 0,9639 | 120,8 | 229,1 | 3,27 | 15,5 | 2,49 | 3,89 |
| **D\*** | 0,9635 | 118,0 | 223,0 | 3,06 | 15,5 | 0,94 | 2,75 |
| E (MODNet + D) | 0,9870 | 64,7 | 162,9 | 2,95 | 6,2 | 2,34 | 3,32 |
| E\* (MODNet + D\*) | 0,9862 | 60,9 | 157,7 | 2,58 | 7,0 | 0,52 | 1,76 |
| leggero A | 0,9061 | 234,5 | 316,0 | 4,31 | 32,0 | 1,78 | 3,78 |
| leggero D\* | 0,9110 | 221,7 | 302,5 | 3,89 | 23,1 | 1,63 | 3,98 |

A contro D\* per clip (pieno):

| Clip | IoU | MAD bordo | Tremolio | dtSSD |
|---|---|---|---|---|
| libreria (molti bordi) | 0,987 → 0,987 | 111 → 103 | 29 → 23 | 4,69 → 4,88 |
| ufficio (figura intera, piccola) | 0,908 → 0,914 | 175 → 165 | 37 → 27 | 5,58 → 4,92 |
| soggiorno | 0,995 → 0,996 | 59 → 47 | 5,8 → 3,2 | 1,22 → 1,17 |
| studio (scuro su scuro) | 0,970 → 0,976 | 178 → 149 | 22 → 14 | 2,65 → 1,91 |
| cemento | 0,931 → 0,945 | 165 → 126 | 18 → 10 | 2,66 → 2,44 |

Sulla libreria il dtSSD sale un poco (4,69 → 4,88): con lo sfondo pieno di bordi che scorre l'EMA trattiene per un
fotogramma un errore del modello che A lascerebbe sparire subito. Il tremolio (zone ferme) scende comunque.

### Tempi (1080p, processore; Xeon 2,3 GHz, 4 processori virtuali, macchina condivisa)

- C# vero (`verifica_cs.py`): maschera pieno 38–47 ms, leggero 5,2–5,5 ms; resa A completa (`Compositore.Rendi`,
  sfocatura Medio) 26–27 ms, di cui il bordo 7,2 ms; il bordo di B 26,8 ms.
- D\* = A + l'EMA (un giro su 65 536 punti: 1,9 ms in numpy, in C# sotto 0,5 ms) + una soglia diversa (stesso
  costo): **circa 27 ms**, come oggi.
- Reti in onnxruntime (4 fili): pieno 38 ms, leggero 2,9 ms, MODNet 512×288 81 ms (sul processore troppo lento per
  30 fps; sulla scheda video da misurare).

## Proposta per il prossimo round (Windows)

1. In `Compositore`/`RitaglioPersona`: l'EMA dal movimento dopo il `FiltroTemporale` (serve la luminanza ridotta del
   fotogramma precedente alla misura della maschera: l'analisi ha già il quarto) e `SogliaMorbida` con centro 0,5 e
   larghezza 0,4 per lo sfocato. Lasciare filtro guidato e sfocatura come sono. Rifare il banco dopo la modifica
   (`verifica_cs.py` deve tornare a 0 differenze con la variante D\* portata in C#).
2. Per «sostituito» la soglia ha già la larghezza che scende con l'intensità (0,8 → 0,2): da misurare a parte (il
   banco oggi misura solo lo sfocato).
3. MODNet come «alta qualità» solo dopo: (a) tempo con DirectML sul PC di Ledion; (b) prova sul suo video (felpa
   scura, mensola con peluche); (c) licenze dei dati di addestramento dei pesi.
4. Android: la stessa D\* vale per il leggero (Android usa lo stesso modello e lo stesso filtro nel tempo).

Da provare sui dispositivi: il tremolio del bordo con il telefono fermo e in mano (dove D\* deve vedersi meglio), e la
scia quando ci si muove in fretta (l'EMA non deve trattenere la persona: il peso sale a 1 dove l'immagine cambia).

## Limiti del banco

- **Dati non di webcam**: VideoMatte240K è girato in studio con luce buona e green screen; due clip sono a figura
  intera. Mancano controluce, stanza vera con oggetti (il peluche), compressione H.264 del telefono, scarsa luce. I
  numeri assoluti sono ottimisti, conta il confronto tra varianti.
- **Sfondi disegnati**: nitidi e mossi, ma sintetici; persona e sfondo sono composti (niente ombre né luce comune).
  Il movimento della fotocamera è simulato.
- **Pochi dati**: 5 clip × 4 s. Le differenze piccole (B contro A, ±1–2%) sono dentro il rumore.
- **La verità dei capelli è sfumata**, le maschere di MediaPipe no: MAD e Grad sul bordo premiano un modello di matting
  (MODNet) più di quanto si veda a occhio.
- **Licenza di VideoMatte240K non verificata** (pagina ufficiale non raggiungibile da qui; copia di terzi su Hugging
  Face): solo per prove interne, niente immagini fuori.
- **Tempi**: processore condiviso a 4 fili; niente DirectML, niente GPU. La rifinitura in numpy vale solo come
  rapporto; i ms veri sono quelli di C# per la variante A e per il bordo di B.
- MODNet è il modello «fotografico»: quello «webcam» non si è potuto convertire (serve PyTorch).
- Solo «sfocato Medio»; lo sfondo sostituito, il light wrap e i livelli più bassi del Compositore non sono misurati.
