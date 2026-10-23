#!/bin/bash
# Doppio clic dal Finder sul Mac.
# Rigenera i progetti Xcode, prova il protocollo, compila il ricevitore Mac e lo copia
# in Applicazioni (la webcam virtuale si attiva solo da lì), poi apre il progetto iPhone.
# Con l'Apple ID gratuito il Mac si costruisce senza webcam virtuale (Strumenti/account.txt).
set -euo pipefail
cd "$(dirname "$0")/.."
REGISTRO="Strumenti/ultima-build.log"
# I prodotti della build stanno fuori dalla repository: se la repository è in Documenti
# o Scrivania sincronizzati con iCloud, la firma rifiuta i file ("detritus not allowed").
CARTELLA_BUILD="$HOME/Library/Developer/WebcamLR"

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

if [ ! -s Strumenti/account.txt ]; then
  read -r -p "Hai l'account sviluppatore Apple a pagamento (99 $/anno)? [s/N] " RISPOSTA
  case "$RISPOSTA" in
    [sS]*) echo completo > Strumenti/account.txt ;;
    *) echo gratuito > Strumenti/account.txt ;;
  esac
fi
if [ "$(tr -d '[:space:]' < Strumenti/account.txt)" = "completo" ]; then
  PROGETTO_MAC=project.yml
  echo "Account a pagamento: il Mac avrà la webcam virtuale."
else
  PROGETTO_MAC=project-senza-account.yml
  echo "Apple ID gratuito: il Mac si costruisce senza webcam virtuale."
  echo "(Quando avrai l'account, scrivi «completo» in Strumenti/account.txt.)"
fi

echo "1/4 · Test del protocollo"
(cd Protocollo && swift test --scratch-path "$CARTELLA_BUILD/Protocollo") > "$REGISTRO" 2>&1 || { tail -30 "$REGISTRO"; false; }

echo "2/4 · Progetti Xcode"
(cd iPhone && xcodegen generate --quiet)
(cd Mac && xcodegen generate --quiet --spec "$PROGETTO_MAC")

echo "3/4 · Compilo WebcamLR per Mac"
xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme WebcamLR -configuration Debug \
  -derivedDataPath "$CARTELLA_BUILD/Mac" -allowProvisioningUpdates build >> "$REGISTRO" 2>&1 \
  || { grep -E "error:|warning: .*entitlement" "$REGISTRO" | head -30; false; }

echo "4/4 · Copio in Applicazioni"
osascript -e 'quit app "WebcamLR"' 2>/dev/null || true
rm -rf /Applications/WebcamLR.app
cp -R "$CARTELLA_BUILD/Mac/Build/Products/Debug/WebcamLR.app" /Applications/
open /Applications/WebcamLR.app
open iPhone/WebcamLR-iPhone.xcodeproj

echo
echo "Fatto. Mac: WebcamLR è aperta. iPhone: in Xcode scegli il tuo iPhone in alto e premi ▶."
read -r -p "Premi Invio per chiudere."
