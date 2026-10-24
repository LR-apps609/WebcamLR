# Pipeline degli effetti sull'iPhone (P02, B2)

File: `iPhone/Sorgenti/PipelineEffetti.swift`. Vive in `SessioneTelefono.effetti`, creato una volta per sessione.

**Percorso di un fotogramma**: `Cattura.suFotogramma` → `effetti.elabora(buffer, istante:)` → `codificatore.codifica(buffer, istante:)`. Formato di cattura 420v; rotazione e specchio li fa ancora la connessione di cattura (prima degli effetti); i tempi passano invariati. Prima del `benvenuto` gira `effetti.osserva(...)`: solo analisi, oppure, se un effetto è acceso, la stessa elaborazione di `elabora` solo per l'anteprima del telefono.

**Senza effetti attivi** `elabora` restituisce lo stesso buffer: costo quasi nullo. **Con effetti**: un solo `CIContext` Metal, uscita in un `CVPixelBufferPool` (stesso formato, IOSurface), allegati di colore copiati. Se il render è lento la qualità scende a `.ridotta` (gli effetti usano la via leggera); se resta lento gli effetti si sospendono 3 s.

## Ordine degli effetti

`FaseEffetto` decide l'ordine, in un punto solo (`PipelineEffetti.aggiungi(_:fase:)`): chi aggiunge un effetto dice la sua fase e finisce prima del primo effetto di una fase successiva, qualunque sia l'ordine delle chiamate.

| Fase | Effetto | File | Aggiunto da |
| --- | --- | --- | --- |
| `.sfondo` (10) | sfondo sfocato o sostituito (P14) | `EffettoSfondo.swift` | `EffettiVisivi.collega` |
| `.pelle` (20) | ritocco della pelle (P15) | `EffettoPelle.swift` | `EffettiVisivi.collega` |
| `.inquadratura` (25) | inquadratura automatica (P04) | `InquadraturaAutomatica.swift` | `FunzioniVolto.collega` |
| `.filtro` (30) | filtro (P13) | `EffettoFiltro.swift` | `EffettiVisivi.collega` |
| `.regolazioni` (35) | `RegolazioniBase` (P13) | `PipelineEffetti.swift` | sempre nell'elenco |
| `.scritta` (40) | sottopancia e logo (P17) | `EffettoScritta.swift` | `EffettiVisivi.collega` |

Perché così: sfondo e pelle usano maschera e volti nelle coordinate del fotogramma intero, quindi vanno prima dello zoom dell'inquadratura; il filtro colora l'immagine già inquadrata e le regolazioni dell'utente correggono il risultato del filtro; la scritta va per ultima, così non si ritaglia, non si sfoca e non prende il colore del filtro.

Un effetto geometrico può dire come ha spostato i pixel con `trasformazione(per:)` (di serie l'identità); gli effetti dopo lo ricevono in `InfoFotogramma.trasformazione` e `inImmagine(_:)` porta un rettangolo di Vision sull'immagine. Oggi nessun effetto dopo l'inquadratura usa coordinate, quindi l'inquadratura non la implementa.

## Aggiungere un effetto

```swift
final class MioEffetto: Effetto, @unchecked Sendable {
    let nome = "…"
    var attivo: Bool { /* letto con un blocco */ }
    var analisiNecessarie: Set<TipoAnalisi> { [.volti] }   // facoltativo
    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage { … }
}
sessione.effetti.aggiungi(effetto, fase: .filtro)   // la fase decide il posto
sessione.effetti.rimuovi(effetto)
```
Gli effetti girano in ordine sulla coda di cattura: devono essere veloci; i valori cambiati dall'interfaccia vanno protetti con un blocco dentro l'effetto. L'uscita si ritaglia alla misura dell'ingresso. `InfoFotogramma`: `istante`, `larghezza`, `altezza`, `qualita`, `volti`, `maschera`, `trasformazione`. C'è ancora `aggiungi(_:in:)` con una posizione esplicita; un effetto aggiunto senza fase non conta per l'ordine delle fasi.

## Effetti visivi (B2)

`SessioneTelefono.visivi` (`EffettiVisivi.swift`, `@MainActor`) tiene i valori mostrati dal foglio «Effetti», li salva in UserDefaults (chiavi `effetti.*`; foto dello sfondo e logo in Application Support), li passa agli effetti e parla il protocollo: `applica(comando)`, `completa(&stato)`, `completa(&capacita)`. Ogni cambiamento, dal telefono o dal computer, chiama `suCambiamento` (al massimo 4 volte al secondo) e la sessione manda uno `stato`.

- **Filtri** (`RicetteFiltri`): solo operazioni per pixel; curve in sRGB dentro lo spazio lineare della pipeline. Vignettatura di «Cinema» e riduzione del rumore di «Notte» saltate con la qualità ridotta. Nitidezza: `CISharpenLuminance` (positiva) o un velo di sfocatura (negativa).
- **Sfondo**: chiede `.persona`. La maschera di Vision si media nel tempo (65% nuova, 35% precedente) alla sua risoluzione, in due buffer BGRA a turno, solo quando ne arriva una nuova; poi sfumata, contrastata e allargata al fotogramma. Sfocatura a ¼ della risoluzione (Lanczos; ⅛ e interpolazione semplice con la qualità ridotta). Sfondi sostituiti disegnati una volta in un buffer IOSurface. Con «Ritratto» di iOS acceso (`AVCaptureDevice.isPortraitEffectEnabled`, letto ogni 2 s) «sfocato» resta in pausa.
- **Pelle**: chiede `.volti`. Sfocatura piccola a metà risoluzione solo attorno ai volti, mescolata dove differisce poco dall'originale, al massimo al 75%.
- **Scritta**: disegnata con UIKit e tenuta come `CIImage` finché testo, logo o misura non cambiano. Si aggiunge dopo lo specchio della cattura: chi guarda la legge sempre dritta.

## Anteprima con effetti

`effetti.anteprima` (`AnteprimaEffetti.swift`): con almeno un effetto attivo ogni buffer elaborato (lo stesso che va al codificatore) va subito in un `AVSampleBufferDisplayLayer` sopra l'anteprima grezza, in `SchermataInOnda`; senza effetti il livello si nasconde e resta l'`AVCaptureVideoPreviewLayer` (costo zero). L'anteprima con effetti è il video **come lo riceve il computer**: mostra l'inquadratura automatica e non è specchiata come l'anteprima grezza della frontale (così scritta e logo si leggono dritti). Il tocco per il fuoco usa ancora il livello grezzo. `anteprima.istantanea()` dà un fotogramma piccolo per le miniature dei filtri.

## Analisi

`effetti.analisi: AnalisiFotogramma`: `richiedi(.volti, per: "nome")` / `rinuncia(.volti, per: "nome")`; un effetto attivo con `analisiNecessarie` la riceve da solo. Gira ogni `passo` fotogrammi (3) su una coda propria, mai se nessuno la chiede. `ultimiVolti: VoltiRilevati?` (rettangoli normalizzati, origine in basso a sinistra come Vision/CIImage, nel fotogramma già dritto; `istante`, `quando`). `ultimaMaschera: MascheraPersona?` (maschera della persona OneComponent8, `VNGeneratePersonSegmentationRequest` `.balanced`, da scalare all'immagine). Sfondo e pelle ignorano risultati più vecchi di 1 s.

## Costi (obiettivo: 1080p a 30 fps su un iPhone 12)

Filtro e regolazioni: un passaggio per pixel. Sfondo: sfocatura su ¼ dei lati (1/16 dei pixel) più una fusione; maschera rifatta circa 10 volte al secondo su un'immagine piccola. Pelle: solo la zona dei volti, a metà risoluzione. Scritta: una sovrapposizione di un'immagine piccola. Il ridisegno di uno sfondo sostituito o della scritta costa una volta sola, quando cambiano.
