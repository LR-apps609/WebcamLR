# Sito di WebcamLR

HTML e CSS statici, senza strumenti di build: si apre `index.html` e basta. Indirizzo: https://lr-apps609.github.io/WebcamLR/

- `index.html`: presentazione (cosa risolve, come funziona, collegamenti, funzioni, prezzo, a che punto siamo).
- `download.html` + `download.js`: download per iPhone, Android, Mac, Windows e Linux. **I link veri si scrivono in cima a `download.js`** (`url: null` = «presto»). Senza JavaScript la pagina mostra i testi scritti nell'HTML: quando un link diventa vero, aggiorna anche lo `<span data-download="…">` corrispondente.
- `aiuto.html` + `aiuto.js`: le domande frequenti dell'app e le guide. Le domande sono copiate da `Stile/Sources/Stile/DomandeFrequenti.swift` (stessi testi, id `d-<id>`, parole della ricerca in `data-parole`): se cambiano lì, vanno cambiate anche qui.
- `privacy.html`: bozza da far verificare.
- `404.html`: usa indirizzi assoluti (`/WebcamLR/…`) perché GitHub Pages la mostra a qualsiasi profondità; in locale i link di questa pagina non funzionano.
- `stile.css`: colori e caratteri, gli stessi delle app (pacchetto `Stile/`).
- `caratteri/`: Barlow Condensed, IBM Plex Sans e IBM Plex Mono, licenza SIL OFL. Sono qui e non su Google Fonts, così il sito non manda dati a terzi (vedi `privacy.html`).
- `anteprima.png`: l'immagine che compare quando si condivide un link (Open Graph, 1200×630).
- Tra parentesi quadre le decisioni ancora aperte: email, titolare, data della privacy.

Per provarlo in locale: `python3 -m http.server` dentro questa cartella, poi http://localhost:8000.

Pubblicazione: `.github/workflows/sito.yml` lo mette su GitHub Pages a ogni modifica su `main` (da attivare una volta in Settings › Pages › Source: «GitHub Actions»).

## versione.json

Lo leggono le app Mac e iPhone all'avvio (e ogni 6 ore) per mostrare «Aggiornamento disponibile». A ogni nuova versione aggiorna `versione`, `build`, `data` e `novita`, con gli stessi valori di `Strumenti/Versione.xcconfig`.
