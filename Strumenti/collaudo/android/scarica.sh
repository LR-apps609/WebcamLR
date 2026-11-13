#!/usr/bin/env bash
# scarica.sh <id-del-run> [cartella]: scarica i risultati di un run del collaudo Android.
# Prima prova l'artifact «collaudo-android» (gh run download, schermate PNG piene); se la rete lo blocca, li
# ricostruisce dal registro del lavoro (schermate JPEG a metà risoluzione, senza il logcat completo).
set -u
id="${1:?uso: scarica.sh <id-del-run> [cartella]}"
repo="${REPO:-LR-apps609/WebcamLR}"
cartella="${2:-risultati-$id}"
mkdir -p "$cartella"
if gh run download "$id" -R "$repo" -n collaudo-android -D "$cartella" 2>/dev/null; then
    echo "Artifact scaricato in $cartella"
    exit 0
fi
echo "Artifact non raggiungibile: ricostruisco dal registro del lavoro"
lavoro=$(gh run view "$id" -R "$repo" --json jobs --jq '.jobs[0].databaseId')
registro=$(mktemp)
curl -sL -H "Authorization: Bearer $(gh auth token)" \
    "https://api.github.com/repos/$repo/actions/jobs/$lavoro/logs" -o "$registro"
# Ogni riga del registro comincia con l'ora: si toglie il primo campo.
cut -d' ' -f2- "$registro" | tr -d '\r' \
    | sed -n '/^=====COLLAUDO-INIZIO=====$/,/^=====COLLAUDO-FINE=====$/p' \
    | sed '1d;$d' | base64 -d > "$registro.tar.gz" \
    && tar -C "$cartella" --strip-components=1 -xzf "$registro.tar.gz" \
    && echo "Risultati in $cartella" || echo "Nessun pacchetto nel registro del lavoro $lavoro"
rm -f "$registro" "$registro.tar.gz"
