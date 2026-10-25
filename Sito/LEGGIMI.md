# Sito di WebcamLR

HTML e CSS statici, senza strumenti di build: si apre `index.html` e basta. Indirizzo: https://lr-apps609.github.io/WebcamLR/

Identità di LR Apps, la stessa delle app (`Stile/Sources/Stile/Tema.swift` sul ramo `round-2`): fondo verde scuro con la sfumatura del logo (#30453E → #0D1B18), toni di salvia, testo quasi bianco, Barlow Condensed per i titoli e Barlow per il testo. Il corallo (`--tally`, #E67A67) solo per «in onda» e registrazione; azioni e selezione nell'accento salvia (`--accento`). Solo tema scuro; i contrasti del testo sono almeno 4,5:1.

- `index.html` + `pagina.js`: presentazione. Disegni in SVG nel file (pezzi in `<defs>`, usati con `<use>`), come la presentazione dell'iPhone: iPhone sul supporto e videochiamata, confronto «Webcam del computer» / «iPhone» (mouse, dito e tastiera), Specchia e Sfoca sfondo, profili. Con «Riduci movimento» niente animazioni. I commenti `SCREENSHOT` dicono dove andranno immagini e video veri dopo le prove.
- `download.html` + `download.js`: download per iPhone, Android, Mac, Windows e Linux, e «Costruiscila dal codice». **I link veri si scrivono in cima a `download.js`** (`url: null` = «in arrivo»). Senza JavaScript la pagina mostra i testi scritti nell'HTML: quando un link diventa vero, aggiorna anche lo `<span data-download="…">` corrispondente.
- `aiuto.html` + `aiuto.js`: le domande frequenti e le guide. Le domande tra i commenti «DALL'APP» vengono da `Stile/Sources/Stile/DomandeFrequenti.swift` (ramo `round-2`) e si rigenerano con `Strumenti/faq_sito.py`: id `d-<id>`, parole della ricerca in `data-parole`. Sotto, cinque risposte **solo sul sito** (Specchia, Sfoca sfondo, profili, microfono, «Aggiornamento disponibile»): quando entrano nell'app, toglierle da qui.
- `privacy.html`: bozza da far verificare.
- `404.html`: usa indirizzi assoluti (`/WebcamLR/…`) perché GitHub Pages la mostra a qualsiasi profondità; in locale i link di questa pagina non funzionano (per provarla, servi una cartella che contiene `WebcamLR` → `Sito`).
- `stile.css`: colori e caratteri, gli stessi delle app.
- `caratteri/`: Barlow, Barlow Condensed e IBM Plex Mono (numeri), licenza SIL OFL. Sono qui e non su Google Fonts, così il sito non manda dati a terzi (vedi `privacy.html`).
- `anteprima.png` (Open Graph, 1200×630) e `apple-touch-icon.png`: si rigenerano con `python3 Strumenti/anteprima_sito.py` (serve Pillow).
- Tra parentesi quadre le decisioni ancora aperte: email, titolare, data della privacy.

Per provarlo in locale: `python3 -m http.server` dentro questa cartella, poi http://localhost:8000.

Pubblicazione: `.github/workflows/sito.yml` lo mette su GitHub Pages a ogni modifica su `main` (da attivare una volta in Settings › Pages › Source: «GitHub Actions»).

## versione.json

Lo legge WebcamLR per Mac all'avvio (e ogni 6 ore) per mostrare «Aggiornamento disponibile». A ogni nuova versione aggiorna `versione`, `build`, `data` e `novita`, con gli stessi valori di `Strumenti/Versione.xcconfig`, e solo dopo aver pubblicato il dmg (`Documenti/Pubblicazione.md`, sul ramo `round-2`).
