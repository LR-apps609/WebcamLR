#!/bin/bash
# Doppio clic dal Finder sul Mac.
# Rigenera i progetti Xcode, prova il protocollo, compila il ricevitore Mac e lo copia
# in Applicazioni (la webcam virtuale si attiva solo da lì), poi apre il progetto iPhone.
set -euo pipefail
cd "$(dirname "$0")/.."
REGISTRO="Strumenti/ultima-build.log"

fallito() {
  echo
  echo "Qualcosa non va. Manda a Claude il file $REGISTRO o le righe qui sopra."
  read -r -p "Premi Invio per chiudere."
  exit 1
}
trap fallito ERR

if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    echo "Installo XcodeGen…"
    brew install xcodegen
  else
    echo "Serve XcodeGen: installa Homebrew da https://brew.sh e riprova."
    false
  fi
fi

if [ ! -s Strumenti/team.txt ]; then
  echo "Scrivi il tuo Team ID Apple (Xcode › Impostazioni › Account › il tuo team, 10 caratteri) e premi Invio:"
  read -r TEAM
  echo "$TEAM" > Strumenti/team.txt
fi
export WEBCAMLR_TEAM="$(tr -d '[:space:]' < Strumenti/team.txt)"

echo "1/4 · Test del protocollo"
(cd Protocollo && swift test) > "$REGISTRO" 2>&1 || { tail -30 "$REGISTRO"; false; }

echo "2/4 · Progetti Xcode"
(cd iPhone && xcodegen generate --quiet)
(cd Mac && xcodegen generate --quiet)

echo "3/4 · Compilo WebcamLR per Mac"
xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme WebcamLR -configuration Debug \
  -derivedDataPath build/Mac -allowProvisioningUpdates build >> "$REGISTRO" 2>&1 \
  || { grep -E "error:|warning: .*entitlement" "$REGISTRO" | head -30; false; }

echo "4/4 · Copio in Applicazioni"
osascript -e 'quit app "WebcamLR"' 2>/dev/null || true
rm -rf /Applications/WebcamLR.app
cp -R build/Mac/Build/Products/Debug/WebcamLR.app /Applications/
open /Applications/WebcamLR.app
open iPhone/WebcamLR-iPhone.xcodeproj

echo
echo "Fatto. Mac: WebcamLR è aperta. iPhone: in Xcode scegli il tuo iPhone in alto e premi ▶."
read -r -p "Premi Invio per chiudere."
