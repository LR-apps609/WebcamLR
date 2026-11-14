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
Prima di **ogni metodo** il banco toglie l'app dal simulatore con i suoi dati, permessi e Portachiavi (iPhone;
`COLLAUDO_CANCELLA=1` in esegui.sh cancella invece tutto il simulatore) o cancella i dati dell'app (Mac): ogni metodo
parte pulito.

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
| `tocca("…")`, `toccaSePresente("…")` | tocca/clic; il primo segna errore se non trova (il copione continua) e scorre per cercare |
| `tocca("Sfondo", dentro: "Impostazioni")` | cerca solo dentro un contenitore (gruppo, elenco, finestra) con quell'etichetta |
| `scrivi("testo", nelCampo: "…")` | scrive in un campo (etichetta, segnaposto o identificatore) |
| `attendi("testo", secondi: 10)`, `esiste("testo")` | aspetta un testo (errore se non arriva) / dice se c'è |
| `indietro()`, `chiudiFoglio()`, `scorri(giu:volte:dentro:)` | navigazione; sul Mac anche `tasto(",", con: .command)` |
| `permessi = .concedi / .nega / .nonRispondere` | come rispondere alle domande di sistema (fotocamera, microfono) |
| `attendiDomandaDiSistema()`, `rispondiAlleDomandeDiSistema(.nega)` | per fotografare la domanda prima di rispondere |

Per trovare etichette e identificatori: guarda i file `*.albero.txt` del fumo. In tearDown il banco salva
sempre l'ultima schermata («fine»). Attenzione: sull'iPhone i testi hanno l'etichetta (`label`), sul Mac solo il valore
(`value`); `tocca`, `attendi` ed `esiste` guardano tutti e due.

Etichette utili (dal fumo):
- iPhone, presentazione: `presentazione.avanti.webcam`, `presentazione.avanti.computer`, `presentazione.avanti.impostazioni`,
  `presentazione.salta`, `presentazione.inizia`, `presentazione.permesso.fotocamera|microfono|rete`, `presentazione.mandaLink`.
- iPhone, principale: «Impostazioni» (ingranaggio; in inglese «Settings»), «Sblocca WebcamLR Pro» (pillola), «Inquadra il QR
  code del computer», «Usa il cavo USB», «Collega a mano (indirizzo)», «Mandami il link per il computer»; nelle Impostazioni
  «WebcamLR Pro», «App e assistenza» › «Guida», «Domande frequenti», «Segnala un bug», «Registro del collegamento», «Fine».
- Mac: «Impostazioni», «Aiuto» (menu: «Guida», «Domande frequenti», «Segnala un bug»), «WebcamLR» (menu); nel pannello
  (`dentro: "Impostazioni"`) le 14 pagine per titolo, «Indietro», «Chiudi le impostazioni»; nella finestra «App e
  assistenza» le schede `dentro: "Barra laterale"`.

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
gh run download <id> -R LR-apps609/WebcamLR -n collaudo-apple -D risultati      # l'artifact (PNG, video)
Strumenti/collaudo/apple/scarica.sh <id> risultati [iphone/CopioneMario]          # se l'artifact è bloccato
```

`scarica.sh` prova l'artifact e, se la rete lo blocca, ricostruisce i risultati dal registro del lavoro (il passo
«Risultati nel registro» stampa un tar.gz in base64, con `nel_registro.sh`): schermate JPEG a metà larghezza, alberi,
note, esiti, le ultime 300 righe di log-app.txt; niente video né xcodebuild.log. Con il terzo argomento estrae solo una
parte. Il pacchetto del fumo intero pesa qualche decina di MB: con poco disco, estrai solo quello che serve.

`esito.txt` (VERDE/ROSSO per test, con i messaggi d'errore) e, per ogni test,
`<iphone|mac>/<Classe>/<metodo>/`: le schermate numerate `NN nome.png`, gli alberi `NN nome.albero.txt`, `note.txt`,
`log-app.txt` (registro di sistema del processo WebcamLR), `xcodebuild.log`, eventuali rapporti di crash, e in
`video/` la registrazione dello schermo che Xcode fa da solo (solo nell'artifact).
Errori di compilazione: `<piattaforma>/_banco/esito-compilazione.txt` e `compilazione.log`.

## Tempi (misurati, 13–14 novembre 2026, Xcode 26.6, macOS 26.7)

| Fase | Tempo |
|---|---|
| Attesa della macchina macOS | da 0 a ore: a volte GitHub non la dà (annullata dopo ~15 min, 0 passi) e va rilanciato |
| Preparazione (checkout, Xcode, XcodeGen, progetti) | ~20 s |
| Simulatore pronto + compilazione iPhone | ~2,5 min + ~6 min |
| Un metodo iPhone | 1,5–4 min di test, più ~1 min di installazione |
| Compilazione Mac | ~2 min |
| Un metodo Mac | 0,5–2 min (con lo scorrimento del pannello fino a ~7 min) |
| Fumo completo (4 + 4 metodi), con «Risultati nel registro» | ~45–55 min |

## Limiti

- Niente fotocamera, telefoni o computer veri: niente «In onda», nessun collegamento.
- Acquisti: niente configurazione StoreKit nei test: la pagina Pro dice «L'App Store non risponde» (normale qui).
- Rete locale: il simulatore non chiede il permesso; sul Mac la domanda di macOS può comparire o no.
- Sul Mac «caratteri grandi» non esiste; la lingua si cambia con gli argomenti di avvio (`-AppleLanguages`).
- `avviaPulito()` è davvero pulito solo la prima volta in un metodo: le volte dopo azzera solo i permessi (iPhone).
- Raramente l'iPhone risponde «Timed out while evaluating UI query» durante la presentazione animata: il metodo finisce
  rosso senza altro. Rilancia quel metodo prima di segnalarlo come bug.
- I copioni non possono uscire dall'app (Impostazioni di iOS, Impostazioni di Sistema).
