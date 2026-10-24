#!/bin/bash
# Doppio clic dal Finder sul Mac (oppure: bash "Strumenti/Nuova versione.command" 1.1).
# Cambia la versione di WebcamLR in Strumenti/Versione.xcconfig, l'unica fonte per Mac e iPhone,
# e fa salire di uno il numero di build (App Store Connect rifiuta un numero già usato).
# Con Invio senza scrivere niente la versione resta uguale e sale solo il numero di build (per un nuovo invio a TestFlight).
set -euo pipefail
cd "$(dirname "$0")/.."
FILE="Strumenti/Versione.xcconfig"

leggi() { sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p" "$FILE" | head -1; }
VERSIONE="$(leggi MARKETING_VERSION)"
BUILD="$(leggi CURRENT_PROJECT_VERSION)"
if [ -z "$VERSIONE" ] || ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Non leggo versione e numero di build in $FILE: servono le righe «MARKETING_VERSION = 1.0» e «CURRENT_PROJECT_VERSION = 2»."
  [ -t 0 ] && read -r -p "Premi Invio per chiudere."
  exit 1
fi

echo "Versione attuale: $VERSIONE (build $BUILD)"
NUOVA="${1:-}"
if [ -z "$NUOVA" ]; then
  read -r -p "Nuova versione (per esempio 1.1 o 1.0.1; Invio = resta $VERSIONE): " NUOVA
fi
NUOVA="${NUOVA:-$VERSIONE}"
if ! [[ "$NUOVA" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "«$NUOVA» non va bene: scrivi due o tre numeri separati da punti, come 1.1 o 1.0.1."
  [ -t 0 ] && read -r -p "Premi Invio per chiudere."
  exit 1
fi
NUOVA_BUILD=$((BUILD + 1))

TEMPORANEO="$(mktemp)"
sed -E -e "s/^([[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*).*/\1$NUOVA/" \
       -e "s/^([[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*).*/\1$NUOVA_BUILD/" "$FILE" > "$TEMPORANEO"
cat "$TEMPORANEO" > "$FILE"
rm -f "$TEMPORANEO"

echo "Fatto: WebcamLR $NUOVA (build $NUOVA_BUILD)."
echo "Vale per Mac e iPhone alla prossima generazione dei progetti (gli script la fanno da soli)."
echo "Ricordati di fare il commit di $FILE."
[ -t 0 ] && [ -z "${1:-}" ] && read -r -p "Premi Invio per chiudere."
exit 0
