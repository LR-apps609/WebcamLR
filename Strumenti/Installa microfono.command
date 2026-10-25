#!/bin/bash
# Doppio clic dal Finder sul Mac.
# Microfono del telefono (P20): costruisce e installa «WebcamLR», il microfono virtuale
# che Zoom, Meet, Teams, FaceTime e OBS vedono come un microfono qualsiasi.
# Va rifatto solo quando cambia il codice in Mac/Microfono (non a ogni build dell'app).
# Funziona con l'Apple ID gratuito. Chiede la password del Mac: scrive in /Library e riavvia l'audio.
# Per toglierlo: Strumenti/Rimuovi microfono.command. Spiegazioni: Documenti/Microfono Mac.md.
set -euo pipefail
cd "$(dirname "$0")/.."
# Lo stesso registro di «Costruisci e installa» (già escluso dalla repository).
REGISTRO="Strumenti/ultima-build.log"
# Come in «Costruisci e installa»: i prodotti stanno fuori dalla repository (cartelle iCloud).
CARTELLA_BUILD="$HOME/Library/Developer/WebcamLR"
PRODOTTI="$CARTELLA_BUILD/Mac/Build/Products/Debug"
DRIVER="WebcamLR Microfono.driver"
AIUTO="webcamlr-microfono-aiuto"
ETICHETTA="it.lrapps.webcamlr.microfono"
CARTELLA_AIUTO="/Library/Application Support/WebcamLR"

fallito() {
  echo
  echo "Qualcosa non va. Manda a Claude il file $REGISTRO o le righe qui sopra."
  read -r -p "Premi Invio per chiudere."
  exit 1
}
trap fallito ERR

if ! command -v xcodegen >/dev/null; then
  echo "Serve XcodeGen: fai prima doppio clic su «Costruisci e installa.command», che lo installa."
  false
fi

# Il progetto Mac si rigenera come in «Costruisci e installa» (il microfono c'è in tutti e due).
export WEBCAMLR_TEAM="$( [ -s Strumenti/team.txt ] && tr -d '[:space:]' < Strumenti/team.txt || true)"
if [ -s Strumenti/account.txt ] && [ "$(tr -d '[:space:]' < Strumenti/account.txt)" = "completo" ]; then
  PROGETTO_MAC=project.yml
else
  PROGETTO_MAC=project-senza-account.yml
fi

echo "1/3 · Compilo il driver e l'aiutante"
(cd Mac && xcodegen generate --quiet --spec "$PROGETTO_MAC")
xcodebuild -project Mac/WebcamLR-Mac.xcodeproj -scheme "WebcamLR Microfono" -configuration Debug \
  -derivedDataPath "$CARTELLA_BUILD/Mac" build > "$REGISTRO" 2>&1 \
  || { grep -i -E "error|failed" "$REGISTRO" | grep -v -E "^\s*$" | tail -25 || tail -30 "$REGISTRO"; false; }

echo "2/3 · Copio in /Library (serve la password del Mac)"
sudo -v
sudo mkdir -p /Library/Audio/Plug-Ins/HAL "$CARTELLA_AIUTO"
# L'aiutante vecchio si ferma prima di sostituirlo (se non c'era, va bene lo stesso).
sudo launchctl bootout "system/$ETICHETTA" 2>/dev/null || true
sudo rm -rf "/Library/Audio/Plug-Ins/HAL/$DRIVER"
sudo cp -R "$PRODOTTI/$DRIVER" /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel "/Library/Audio/Plug-Ins/HAL/$DRIVER"
sudo install -m 755 -o root -g wheel "$PRODOTTI/$AIUTO" "$CARTELLA_AIUTO/$AIUTO"
sudo install -m 644 -o root -g wheel "Mac/Microfono/Aiuto/$ETICHETTA.plist" "/Library/LaunchDaemons/$ETICHETTA.plist"
sudo xattr -dr com.apple.quarantine "/Library/Audio/Plug-Ins/HAL/$DRIVER" "$CARTELLA_AIUTO/$AIUTO" 2>/dev/null || true
sudo launchctl bootstrap system "/Library/LaunchDaemons/$ETICHETTA.plist"

echo "3/3 · Riavvio l'audio del Mac (per un attimo i suoni si fermano)"
# coreaudiod carica i driver solo all'avvio. launchd lo fa ripartire da solo.
sudo killall coreaudiod 2>/dev/null || sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
sleep 3

# Il dispositivo compare come titolo «WebcamLR:» (la camera ha lo stesso nome, ma qui ci sono solo dispositivi audio).
if system_profiler SPAudioDataType 2>/dev/null | grep -qE "^[[:space:]]*WebcamLR:[[:space:]]*$"; then
  echo
  echo "Fatto. «WebcamLR» è tra i microfoni del Mac."
  echo "Chiudi (⌘Q) e riapri le app di chiamata già aperte: molte leggono l'elenco solo all'avvio."
else
  echo
  echo "⚠️  Installato, ma macOS non mostra ancora «WebcamLR»."
  echo "   Riavvia il Mac e guarda in Impostazioni di Sistema › Suono › Ingresso."
  echo "   Se non c'è, manda a Claude il risultato di questo comando nel Terminale:"
  echo "   log show --last 5m --predicate 'process == \"coreaudiod\"' | grep -i webcamlr"
fi
read -r -p "Premi Invio per chiudere."
