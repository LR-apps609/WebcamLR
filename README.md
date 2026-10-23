# WebcamLR

Trasforma l'iPhone (e poi Android) in una webcam professionale per Mac e Windows: video fino a 4K, audio e controlli da videocamera.

- Documento di progetto, funzioni 1–40 e piano a round: [WebcamLR — Documento di progetto](https://claude.ai/artifact/Q8YwdzFh4KapYADzhfZpU5)
- Bozza grafica delle tre app: [WebcamLR · prima bozza grafica](https://claude.ai/artifact/HetVjQiw1JxPxpwUXsiDW6)
- Protocollo comune: [Documenti/Protocollo.md](Documenti/Protocollo.md)

## Cartelle

```
WebcamLR/
├── Protocollo/   pacchetto Swift del protocollo + test (usato da iPhone e Mac)
├── iPhone/       app iOS · Swift, SwiftUI, XcodeGen
├── Mac/          ricevitore macOS · SwiftUI + webcam virtuale (Camera Extension)
├── Windows/      ricevitore Windows · WinUI 3 (C#), protocollo C# + test; webcam virtuale C++ dal round 3
├── Android/      app Android, dal round 10
├── Strumenti/    script di build a doppio clic
└── Documenti/    protocollo, note e risultati dei test
```

## Costruire

**Mac e iPhone** — doppio clic su `Strumenti/Costruisci e installa.command`.
La prima volta chiede il Team ID Apple e installa XcodeGen con Homebrew. Prova il protocollo, compila il ricevitore Mac, lo copia in Applicazioni e apre il progetto iPhone in Xcode: scegli l'iPhone in alto e premi ▶.

**Windows** — doppio clic su `Strumenti/Costruisci e avvia.bat` (serve .NET 8 SDK).

I progetti Xcode non sono nella repository: si rigenerano da `iPhone/project.yml` e `Mac/project.yml`.

## Stato

Round 0 · fondamenta. Cosa c'è oggi:

- protocollo v1 in Swift e C#, con gli stessi test
- iPhone: schermata «Scegli il computer» che trova davvero i computer in rete, impostazioni
- Mac: si fa trovare in rete, finestra e menu nella barra, webcam virtuale con immagine di prova
- Windows: finestra del ricevitore, ancora senza rete né webcam virtuale

Interfaccia solo in italiano per ora.
