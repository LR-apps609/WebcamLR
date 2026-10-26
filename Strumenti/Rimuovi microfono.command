#!/bin/bash
# Doppio clic dal Finder sul Mac.
# Toglie «WebcamLR (microphone)» (P20): il driver audio, l'aiutante e i suoi due LaunchDaemon.
# Lo stesso si fa dall'app: Impostazioni › Microfono del telefono › «Rimuovi il microfono…» (senza password).
# Da fare prima di cestinare WebcamLR, oppure se l'audio del Mac si comporta in modo strano.
# Chiede la password del Mac. Spiegazioni: Documenti/Microfono Mac.md.
set -uo pipefail
ETICHETTA="it.lrapps.webcamlr.microfono"
RIMOZIONE="it.lrapps.webcamlr.microfono.rimozione"

echo "Tolgo il microfono virtuale di WebcamLR (serve la password del Mac)."
sudo -v || exit 1
sudo launchctl bootout "system/$ETICHETTA" 2>/dev/null
sudo launchctl bootout "system/$RIMOZIONE" 2>/dev/null
sudo rm -f "/Library/LaunchDaemons/$ETICHETTA.plist" "/Library/LaunchDaemons/$RIMOZIONE.plist"
sudo rm -rf "/Library/Audio/Plug-Ins/HAL/WebcamLR Microfono.driver"
sudo rm -f "/Library/Application Support/WebcamLR/webcamlr-microfono-aiuto"
sudo rmdir "/Library/Application Support/WebcamLR" 2>/dev/null
echo "Riavvio l'audio del Mac (per un attimo i suoni si fermano)."
sudo killall coreaudiod 2>/dev/null || sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
echo
echo "Fatto. «WebcamLR (microphone)» non c'è più."
read -r -p "Premi Invio per chiudere."
