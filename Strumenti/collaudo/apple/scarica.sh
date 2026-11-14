#!/usr/bin/env bash
# scarica.sh <id-del-run> [cartella] [filtro]: i risultati di un run di «Collaudo Apple».
# Prima prova l'artifact «collaudo-apple»; se la rete lo blocca li ricostruisce dal registro del lavoro
# (schermate JPEG a metà larghezza). Filtro facoltativo (per esempio «iphone/CopioneFumo»): estrae solo quella parte.
set -u
id="${1:?uso: scarica.sh <id-del-run> [cartella] [filtro]}"
repo="${REPO:-LR-apps609/WebcamLR}"
cartella="${2:-risultati-apple-$id}"
filtro="${3:-}"
mkdir -p "$cartella"
if [ -z "$filtro" ] && gh run download "$id" -R "$repo" -n collaudo-apple -D "$cartella" 2>/dev/null; then
  echo "Artifact scaricato in $cartella"; exit 0
fi
echo "Ricostruisco dal registro del lavoro"
lavoro=$(gh run view "$id" -R "$repo" --json jobs --jq '.jobs[0].databaseId')
registro=$(mktemp)
curl -sL -H "Authorization: Bearer $(gh auth token)" \
  "https://api.github.com/repos/$repo/actions/jobs/$lavoro/logs" -o "$registro"
cut -d' ' -f2- "$registro" | tr -d '\r' \
  | sed -n '/^=====COLLAUDO-INIZIO=====$/,/^=====COLLAUDO-FINE=====$/p' \
  | sed '1d;$d' | base64 -d > "$registro.tar.gz"
rm -f "$registro"
if [ -n "$filtro" ]; then
  tar -C "$cartella" --strip-components=1 -xzf "$registro.tar.gz" --wildcards "collaudo-apple/esito.txt" "collaudo-apple/$filtro*"
else
  tar -C "$cartella" --strip-components=1 -xzf "$registro.tar.gz"
fi && echo "Risultati in $cartella" || echo "Nessun pacchetto nel registro del lavoro $lavoro"
rm -f "$registro.tar.gz"
