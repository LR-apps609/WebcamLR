# WebcamLR

Trasforma l'iPhone (e poi Android) in una webcam professionale per Mac e Windows: video fino a 4K, audio e controlli da videocamera.

- Documento di progetto, funzioni 1–40 e piano a round: [WebcamLR — Documento di progetto](https://claude.ai/artifact/Q8YwdzFh4KapYADzhfZpU5)
- Bozza grafica delle tre app: [WebcamLR · prima bozza grafica](https://claude.ai/artifact/HetVjQiw1JxPxpwUXsiDW6)
- Protocollo comune: [Documenti/Protocollo.md](Documenti/Protocollo.md)

## Cartelle

```
WebcamLR/
├── Protocollo/   pacchetto Swift del protocollo + test (usato da iPhone e Mac)
├── Stile/        pacchetto Swift della grafica: colori, caratteri, logo, pillole di stato
├── iPhone/       app iOS · Swift, SwiftUI, XcodeGen
├── Mac/          ricevitore macOS · SwiftUI + webcam virtuale (Camera Extension)
├── Windows/      ricevitore Windows · WinUI 3 (C#); protocollo e sessione in C# con test (iPhone simulato); webcam virtuale C++ dal round 3
├── Android/      app Android, dal round 10
├── Strumenti/    script di build a doppio clic
└── Documenti/    protocollo, note e risultati dei test
```

## Costruire

**Mac e iPhone** — doppio clic su `Strumenti/Costruisci e installa.command`.
La prima volta chiede il Team ID Apple e se hai l'account sviluppatore a pagamento, e installa XcodeGen con Homebrew. Con l'Apple ID gratuito il Mac si costruisce senza webcam virtuale (`Mac/project-senza-account.yml`); con l'account, completo (`Mac/project.yml`). La scelta resta in `Strumenti/account.txt`. Prova il protocollo, compila il ricevitore Mac, lo copia in Applicazioni e apre il progetto iPhone in Xcode: scegli l'iPhone in alto e premi ▶.

**Windows** — doppio clic su `Strumenti/Costruisci e avvia.bat` (serve .NET 8 SDK).

I progetti Xcode non sono nella repository: si rigenerano da `iPhone/project.yml` e `Mac/project.yml`.

## Rami

| Ramo | Cosa contiene | Stato |
| --- | --- | --- |
| `main` | Round 0: fondamenta, modalità senza account | in prova |
| `round-1` | Round 1 e anticipi dei round 2, 3, 4, 8 (vedi sotto) | da provare dopo il round 0 |
| `sito` | Sito web in `Sito/` e pubblicazione su GitHub Pages | da rivedere |

## Stato del ramo `round-1`

Funzioni della lista 1–40 già scritte (da provare con la checklist):

- **1–6** ricerca in rete, QR code e indirizzo scritto, video H.264, anteprima, latenza visibile, riconnessione automatica
- **10** HEVC, a scelta nelle impostazioni dell'iPhone (su Windows serve l'estensione di Microsoft Store)
- **11** webcam virtuale Mac con il video dell'iPhone, con la spia «in onda» (serve l'account sviluppatore a pagamento)
- **17, 19–22, 26** obiettivi, esposizione, ISO e tempo manuali, bianco, fuoco con tocco, zoom, torcia — anche comandati dal Mac e da Windows
- **25, 27–28** immagine specchiata, effetti video di Apple (Ritratto, Luce da studio)
- **31–35** qualità ridotta se fa caldo, schermo oscurato, avviso batteria, aiuto «Non trovi il computer?», foto e registrazione dal Mac
- **Windows** (anticipo del round 3): annuncio in rete, QR code, video in finestra, latenza, comandi della fotocamera; manca la webcam virtuale

Protocollo e ricevitore Windows hanno test automatici (`dotnet test`), compreso un iPhone simulato. Il codice Swift è stato riletto da revisori indipendenti ma si compila solo sul Mac.

Checklist: [Documenti/Round 1 - test.md](Documenti/Round%201%20-%20test.md)

Interfaccia solo in italiano per ora.
