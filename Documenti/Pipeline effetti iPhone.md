# Pipeline degli effetti sull'iPhone (P02)

File: `iPhone/Sorgenti/PipelineEffetti.swift`. Vive in `SessioneTelefono.effetti`, creato una volta per sessione.

**Percorso di un fotogramma**: `Cattura.suFotogramma` → `effetti.elabora(buffer, istante:)` → `codificatore.codifica(buffer, istante:)`. Formato di cattura 420v; rotazione e specchio li fa ancora la connessione di cattura; i tempi passano invariati. Prima del `benvenuto` gira solo `effetti.osserva(...)` (solo analisi).

**Senza effetti attivi** `elabora` restituisce lo stesso buffer: costo quasi nullo. **Con effetti**: un solo `CIContext` Metal, uscita in un `CVPixelBufferPool` (stesso formato, IOSurface), allegati di colore copiati. Se il render è lento la qualità scende a `.ridotta`; se resta lento gli effetti si sospendono 3 s. Anteprima del telefono ancora grezza (`anteprimaConEffetti = false`, TODO in `Cattura.swift`).

**Aggiungere un effetto**
```swift
final class MioEffetto: Effetto, @unchecked Sendable {
    let nome = "…"
    var attivo: Bool { /* letto con un blocco */ }
    var analisiNecessarie: Set<TipoAnalisi> { [.volti] }   // facoltativo
    func applica(_ immagine: CIImage, contesto: InfoFotogramma) -> CIImage { … }
}
sessione.effetti.aggiungi(effetto)   // oppure aggiungi(_:in: posizione)
sessione.effetti.rimuovi(effetto)
```
Gli effetti girano in ordine sulla coda di cattura: devono essere veloci; i valori cambiati dall'interfaccia vanno protetti con un blocco dentro l'effetto. L'uscita si ritaglia alla misura dell'ingresso. `InfoFotogramma`: `istante`, `larghezza`, `altezza`, `qualita`, `volti`, `maschera`.

`effetti.regolazioni` (`RegolazioniBase`) è già nella lista: `.valori = .init(luminosita:contrasto:saturazione:)`, ciascuno -1…1; spento se tutti a 0.

**Analisi** (`effetti.analisi: AnalisiFotogramma`): `richiedi(.volti, per: "nome")` / `rinuncia(.volti, per: "nome")`; un effetto attivo con `analisiNecessarie` la riceve da solo. Gira ogni `passo` fotogrammi (3) su una coda propria, mai se nessuno la chiede. `ultimiVolti: VoltiRilevati?` (rettangoli normalizzati, origine in basso a sinistra come Vision/CIImage, nel fotogramma già dritto; `istante`, `quando`). `ultimaMaschera: MascheraPersona?` (maschera della persona OneComponent8, `VNGeneratePersonSegmentationRequest` `.balanced`, da scalare all'immagine).
