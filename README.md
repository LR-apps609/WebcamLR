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

## Stato

Round 1 · video dall'iPhone al Mac (ramo `round-1`, da provare). Cosa c'è:

- protocollo v1 in Swift e C#, con gli stessi test
- iPhone: trova i computer in rete, si collega, cattura con l'obiettivo scelto, comprime in H.264 hardware e invia; schermata «In onda» come la bozza, torcia, schermo oscurato
- Mac: riceve e mostra il video, misura la latenza (anche sull'iPhone), statistiche, menu nella barra; webcam virtuale con immagine di prova (solo con l'account a pagamento)
- Windows: finestra del ricevitore, ancora senza rete né webcam virtuale (round 3)
- caratteri e colori della bozza grafica in tutte le app

Checklist: [Documenti/Round 1 - test.md](Documenti/Round%201%20-%20test.md)

Interfaccia solo in italiano per ora.
