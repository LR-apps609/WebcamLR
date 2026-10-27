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
| `.doppiaVista` (24) | volto e scrivania (P09) | `DoppiaVista.swift` | `SessioneTelefono.init` |
| `.inquadratura` (25) | inquadratura automatica (P04) | `InquadraturaAutomatica.swift` | `FunzioniVolto.collega` |
| `.filtro` (30) | filtro (P13) | `EffettoFiltro.swift` | `EffettiVisivi.collega` |
| `.regolazioni` (35) | `RegolazioniBase` (P13) | `PipelineEffetti.swift` | sempre nell'elenco |
| `.scritta` (40) | sottopancia e logo (P17) | `EffettoScritta.swift` | `EffettiVisivi.collega` |

Perché così: sfondo e pelle usano maschera e volti nelle coordinate del fotogramma intero, quindi vanno prima dello zoom dell'inquadratura e della doppia vista (che così li trova già fatti nei due ritagli); la doppia vista ricompone tutto il fotogramma, quindi l'inquadratura resta sospesa mentre è accesa; il filtro colora l'immagine già inquadrata e le regolazioni dell'utente correggono il risultato del filtro; la scritta va per ultima, così non si ritaglia, non si sfoca e non prende il colore del filtro.

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
- **Sfondo** (rifatto dopo la terza prova, 27 ottobre): chiede `.persona`, che con lo sfondo acceso si analizza a ogni fotogramma (al massimo 32 al secondo; `.fast` e 15 al secondo con il telefono molto caldo); la pipeline aspetta pochi millisecondi la maschera del fotogramma stesso (`aspettaMaschera`, al massimo il 45% di un fotogramma e 18 ms, solo con la qualità piena). Filtro nel tempo senza ritardo alla risoluzione della maschera (due buffer BGRA a turno): peso della nuova 0,6 + 4 × |nuova − vecchia|, quindi dove la persona si muove vale la nuova. Bordo: `CIEdgePreserveUpsampleFilter` guidato dal video (lato corto al massimo 1080), piuma fissa di 1 px e soglia morbida smoothstep (`CIColorPolynomial`); con la qualità ridotta ingrandimento bilineare a metà risoluzione, piuma e poi soglia. Sfocatura senza alone: la persona (allargata) esce dall'immagine come alfa, si sfoca e si divide per l'alfa sfocato; raggio fisso di 2,5 px nell'immagine ridotta, l'intensità cambia solo la riduzione (sigma a 1080p = 32 × intensità^1,6: 3,5 / 12 / 32 px per Poco / Medio / Tanto). Sfondi sostituiti disegnati una volta in un buffer IOSurface. Con una fotocamera posteriore lo sfondo è spento e lo `stato` dice `nessuno`. Con «Ritratto» di iOS acceso (`AVCaptureDevice.isPortraitEffectEnabled`, letto ogni 2 s) «sfocato» resta in pausa.
- **Pelle**: chiede `.volti`. Sfocatura piccola a metà risoluzione solo attorno ai volti, mescolata dove differisce poco dall'originale, al massimo al 75%.
- **Scritta**: disegnata con UIKit e tenuta come `CIImage` finché testo, logo o misura non cambiano. Si aggiunge dopo lo specchio della cattura: chi guarda la legge sempre dritta.

## Volto e scrivania (P09)

`EffettoDoppiaVista` (`DoppiaVista.swift`), comandato da `SessioneTelefono.impostaDoppiaVista` (foglio «Assistente» o `comando.doppiaVista`; `stato.doppiaVista`, `capacita.doppiaVista`).

- **Niente multicamera.** Sul supporto la fotocamera rivolta verso l'utente è una sola: la frontale non vede la scrivania e la posteriore guarda dall'altra parte. Come «Vista scrivania» di Continuity si usa un solo obiettivo, il **Grandangolo 0,5× posteriore rivolto verso l'utente** (il modo consigliato), e dallo stesso fotogramma si ritagliano due zone. Funziona su ogni iPhone con il grandangolo; senza, `capacita.doppiaVista` è falso.
- **Volto**: riquadro nella metà alta (altezza ½ del fotogramma), centrato sul volto più grande (`.volti`, centro levigato all'8% per fotogramma); senza volti torna piano al centro.
- **Scrivania**: trapezio in basso (largo 76% in basso, 40% in alto, alto 34%), raddrizzato con `CIPerspectiveCorrection`, allungato 2× in verticale (la prospettiva schiaccia la profondità) e girato di 180° (i fogli sono girati verso chi parla); con lo specchio acceso solo il capovolgimento verticale. Valori da tarare con le prove.
- **Composizione**: «Affiancate» (volto a sinistra, scrivania a destra, metà e metà) o «Scrivania e riquadro» (scrivania a tutto schermo, volto in alto a destra con un bordo scuro). La disposizione si salva (`doppiaVista.disposizione`); l'accensione no, perché cambia l'obiettivo.
- **Obiettivo**: accesa passa al grandangolo senza salvarlo come obiettivo di serie; spenta rimette quello di prima. Un altro obiettivo scelto mentre è accesa la spegne.
- **Costo**: due ritagli scalati e una correzione prospettica, in un solo render; spenta non c'è nell'elenco degli effetti attivi.

## Anteprima con effetti

`effetti.anteprima` (`AnteprimaEffetti.swift`): con almeno un effetto attivo ogni buffer elaborato (lo stesso che va al codificatore) va subito in un `AVSampleBufferDisplayLayer` sopra l'anteprima grezza, in `SchermataInOnda`; senza effetti il livello si nasconde e resta l'`AVCaptureVideoPreviewLayer` (costo zero). L'anteprima con effetti è il video **come lo riceve il computer**: mostra l'inquadratura automatica e non è specchiata come l'anteprima grezza della frontale (così scritta e logo si leggono dritti). Il tocco per il fuoco usa ancora il livello grezzo. `anteprima.istantanea()` dà un fotogramma piccolo per le miniature dei filtri.

## Analisi

`effetti.analisi: AnalisiFotogramma`: `richiedi(.volti, per: "nome")` / `rinuncia(.volti, per: "nome")`; un effetto attivo con `analisiNecessarie` la riceve da solo. Gira ogni `passo` fotogrammi (3) su una coda propria, mai se nessuno la chiede. `ultimiVolti: VoltiRilevati?` (rettangoli normalizzati, origine in basso a sinistra come Vision/CIImage, nel fotogramma già dritto; `istante`, `quando`). `ultimaMaschera: MascheraPersona?` (maschera della persona OneComponent8, `VNGeneratePersonSegmentationRequest` `.balanced`, da scalare all'immagine). La pelle ignora risultati più vecchi di 1 s, lo sfondo di 0,5 s.

## Costi (obiettivo: 1080p a 30 fps su un iPhone 12)

Filtro e regolazioni: un passaggio per pixel. Sfondo: sfocatura su ¼ dei lati (1/16 dei pixel) più una fusione; maschera nuova a ogni fotogramma (Vision, in parallelo), filtrata in piccolo e rifinita alla risoluzione del video (al massimo 1080 di lato corto). Pelle: solo la zona dei volti, a metà risoluzione. Scritta: una sovrapposizione di un'immagine piccola. Il ridisegno di uno sfondo sostituito o della scritta costa una volta sola, quando cambiano.
