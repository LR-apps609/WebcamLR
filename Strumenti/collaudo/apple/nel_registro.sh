#!/bin/bash
# Stampa i risultati del collaudo Apple nel registro del lavoro, come tar.gz in base64 tra due righe di confine,
# per chi non può scaricare gli artifact (dominio di Azure bloccato da alcune reti). Lo legge scarica.sh.
# Schermate in JPEG a metà larghezza (sips, sul Mac); alberi, note, esiti e la coda di log-app.txt; niente xcodebuild.log.
set -u
sorgente="${1:-collaudo-apple}"
[ -d "$sorgente" ] || { echo "nessuna cartella $sorgente"; exit 0; }
lavoro=$(mktemp -d)
copia="$lavoro/collaudo-apple"
cp -R "$sorgente" "$copia"
find "$copia" \( -name 'xcodebuild.log' -o -name 'compilazione.log' -o -name '*.ips' \) -delete
find "$copia" -name 'log-app.txt' | while IFS= read -r f; do tail -n 300 "$f" > "$f.coda" && mv "$f.coda" "$f"; done
find "$copia" -name '*.png' | while IFS= read -r png; do
  larghezza=$(sips -g pixelWidth "$png" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  meta=$(( ${larghezza:-1200} / 2 ))
  sips -s format jpeg -s formatOptions 60 --resampleWidth "$meta" "$png" --out "${png%.png}.jpg" >/dev/null 2>&1 \
    && rm -f "$png"
done
tar -C "$lavoro" -czf "$lavoro/risultati.tar.gz" collaudo-apple
echo "Dimensione del pacchetto: $(du -h "$lavoro/risultati.tar.gz" | cut -f1)"
echo "=====COLLAUDO-INIZIO====="
base64 -i "$lavoro/risultati.tar.gz" | fold -w 120
echo "=====COLLAUDO-FINE====="
rm -rf "$lavoro"
