# Banco di prova iPhone e Mac (collaudo)

I copioni sono test XCUITest che usano le app vere: l'iPhone sul simulatore, il Mac sulla macchina macOS di GitHub.
Si eseguono solo su GitHub (`.github/workflows/collaudo-apple.yml`): su Linux non c'è Swift.

## Dove stanno

| Cosa | Dove |
|---|---|
| Copioni iPhone | `iPhone/CollaudoUI/Copione<Nome>.swift` (target `CollaudoUI-iPhone`, schema `CollaudoUI`) |
| Copioni Mac | `Mac/CollaudoUI/Copione<Nome>.swift` (target `CollaudoUI-Mac` in `project-senza-account.yml`) |
| Libreria comune | `Strumenti/collaudo/apple/Collaudo.swift` (+ `iPhone/CollaudoUI/AiutiIPhone.swift`) |
| Esempio completo | `CopioneFumo.swift`, uno per piattaforma |
| Banco | `esegui.sh` (compila, pulisce, esegue un test alla volta), `banco.py` (filtro, simulatore, estrazione) |

## Scrivere un copione

Un file per tester, una classe figlia di `CopioneCollaudo`, un metodo `@MainActor func testNN_qualcosa()` per prova.
Prima di **ogni metodo** il banco cancella il simulatore (iPhone) o i dati dell'app (Mac): ogni metodo parte pulito.

```swift
import XCTest

final class CopioneMario: CopioneCollaudo {
    @MainActor func test01_impostazioni() {
        avviaPulito()                  // lingua italiana; avviaPulito(lingua: .inglese, caratteriGrandi: true)
        superaPresentazione()          // solo iPhone: Salta, Inizia, «Consenti» a fotocamera e microfono
        tocca("Impostazioni")          // etichetta o identificatore (anche «contiene»)
        fotografa("impostazioni")      // schermata + albero degli elementi
        nota("La riga Pro dice «Sblocca»")
    }
}
```

| Funzione | Cosa fa |
|---|---|
| `avvia(...)`, `avviaPulito(...)` | apre l'app; `lingua: .italiano/.inglese`, `caratteriGrandi:` (iPhone XXXL), `argomenti:` |
| `schermata("n")`, `albero("n")`, `fotografa("n")` | immagine dello schermo, `app.debugDescription`, tutte e due |
| `nota("…")` | un'osservazione: finisce in `note.txt` |
| `tocca("…")`, `toccaSePresente("…")` | tocca/clic; il primo segna errore se non trova (il copione continua) |
| `scrivi("testo", nelCampo: "…")` | scrive in un campo (etichetta, segnaposto o identificatore) |
| `attendi("testo", secondi: 10)`, `esiste("testo")` | aspetta un testo (errore se non arriva) / dice se c'è |
| `indietro()`, `chiudiFoglio()`, `scorri(giu:volte:)` | navigazione; sul Mac anche `tasto(",", con: .command)` |
| `permessi = .concedi / .nega / .nonRispondere` | come rispondere alle domande di sistema (fotocamera, microfono) |
| `attendiDomandaDiSistema()`, `rispondiAlleDomandeDiSistema(.nega)` | per fotografare la domanda prima di rispondere |

Per trovare etichette e identificatori: guarda i file `*.albero.txt` del fumo. In tearDown il banco salva
sempre l'ultima schermata («fine»).

## Lanciare

```sh
gh workflow run collaudo-apple.yml -R LR-apps609/WebcamLR --ref collaudo-20-apple -f copioni="CopioneMario"
gh workflow run collaudo-apple.yml -R LR-apps609/WebcamLR --ref collaudo-20-apple \
   -f copioni="iPhone:CopioneMario/test01_impostazioni" -f dispositivo="iPhone SE (3rd generation)" -f piattaforme=iphone
```

`copioni`: vuoto = tutti; voci separate da spazi o virgole: `Classe`, `Classe/metodo`, con `iPhone:` o `Mac:`
davanti per una piattaforma sola. `piattaforme`: `entrambe`, `iphone`, `mac`. Anche un push sui rami `collaudo-20*`
che tocca iPhone/, Mac/, Stile/, Protocollo/ o questa cartella esegue tutto.

## Risultati

```sh
gh run list -R LR-apps609/WebcamLR -w collaudo-apple.yml -L 5
gh run download <id> -R LR-apps609/WebcamLR -n collaudo-apple -D risultati
```

`esito.txt` (VERDE/ROSSO per test, con i messaggi d'errore) e, per ogni test,
`<iphone|mac>/<Classe>/<metodo>/`: le schermate numerate `NN nome.png`, gli alberi `NN nome.albero.txt`, `note.txt`,
`log-app.txt` (registro di sistema del processo WebcamLR), `xcodebuild.log`, eventuali rapporti di crash.
Errori di compilazione: `<piattaforma>/_banco/esito-compilazione.txt` e `compilazione.log`.

## Tempi tipici

Preparazione e generazione ~3 min; compilazione ~6–10 min per piattaforma; poi ~1–2 min per metodo
(cancellare e riaccendere il simulatore costa ~30 s). Il fumo completo (4 + 4 metodi) ~35 min.
Le macchine macOS di GitHub a volte non partono: si rilancia.

## Limiti

- Niente fotocamera, telefoni o computer veri: niente «In onda», nessun collegamento.
- Acquisti: niente configurazione StoreKit nei test, la pagina Pro mostra quello che dà l'App Store del simulatore.
- Rete locale: il simulatore non chiede il permesso; sul Mac la domanda di macOS può comparire o no.
- Sul Mac «caratteri grandi» non esiste; la lingua si cambia con gli argomenti di avvio (`-AppleLanguages`).
- `avviaPulito()` è davvero pulito solo la prima volta in un metodo: le volte dopo azzera solo i permessi (iPhone).
- I copioni non possono uscire dall'app (Impostazioni di iOS, Impostazioni di Sistema).
