#!/usr/bin/env bash
# Stampa i risultati nel registro del lavoro, come tar.gz in base64 tra due righe di confine, per chi non può
# scaricare gli artifact (gli artifact stanno su un dominio di Azure che alcune reti bloccano). Le schermate
# diventano JPEG a metà risoluzione; il logcat completo resta solo nell'artifact. Lo legge scarica.sh.
set -u
sorgente="${1:-risultati}"
[ -d "$sorgente" ] || { echo "nessuna cartella $sorgente"; exit 0; }
lavoro=$(mktemp -d)
copia="$lavoro/risultati"
cp -r "$sorgente" "$copia"
find "$copia" -name 'logcat-completo.txt.gz' -delete
find "$copia" -name 'gradle-*.log' -delete
if command -v convert >/dev/null 2>&1; then
    find "$copia" -name '*.png' | while IFS= read -r png; do
        convert "$png" -resize 50% -quality 72 "${png%.png}.jpg" && rm -f "$png"
    done
fi
tar -C "$lavoro" -czf "$lavoro/risultati.tar.gz" risultati
echo "Dimensione del pacchetto: $(du -h "$lavoro/risultati.tar.gz" | cut -f1)"
echo "=====COLLAUDO-INIZIO====="
base64 -w 120 "$lavoro/risultati.tar.gz"
echo "=====COLLAUDO-FINE====="
rm -rf "$lavoro"
