# Sito di WebcamLR

HTML e CSS statici, senza strumenti di build: si apre `index.html` e basta.

- `stile.css`: colori e caratteri, gli stessi delle app (pacchetto `Stile/`).
- `caratteri/`: Barlow Condensed, IBM Plex Sans e IBM Plex Mono, licenza SIL OFL. Sono qui e non su Google Fonts, così il sito non manda dati a terzi (vedi `privacy.html`).
- `download.js`: mette in evidenza la piattaforma di chi visita; la pagina funziona anche senza.
- Tra parentesi quadre le decisioni ancora aperte: prezzo, versione gratuita, data di uscita, email, titolare.

Per provarlo in locale: `python3 -m http.server` dentro questa cartella, poi http://localhost:8000.

Pubblicazione: `.github/workflows/sito.yml` lo mette su GitHub Pages a ogni modifica su `main` (da attivare una volta in Settings › Pages › Source: «GitHub Actions»).
