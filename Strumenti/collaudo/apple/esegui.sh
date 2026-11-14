#!/bin/bash
# Banco di prova di WebcamLR (collaudo-20): compila i copioni e li esegue uno per uno, ognuno da uno stato pulito.
# Lo usa .github/workflows/collaudo-apple.yml su una macchina macOS (serve Xcode con XcodeGen già fatto girare).
#
#   Strumenti/collaudo/apple/esegui.sh iphone "<copioni>" "<simulatore>"
#   Strumenti/collaudo/apple/esegui.sh mac "<copioni>"
#
# Copioni: vuoto = tutti; altrimenti «CopioneFumo», «CopioneFumo/test02_impostazioni», «iPhone:…», «Mac:…»
# (separati da spazi o virgole). Risultati in collaudo-apple/<piattaforma>/<Classe>/<metodo>/.
# Non esce mai con un errore per un copione rosso: l'esito è in collaudo-apple/esito.txt.

set -u
piattaforma="$1"
filtro="${2:-}"
dispositivo="${3:-iPhone 16}"

radice="$(cd "$(dirname "$0")/../../.." && pwd)"
banco="$radice/Strumenti/collaudo/apple/banco.py"
uscita="$radice/collaudo-apple"
registri="$uscita/$piattaforma/_banco"
mkdir -p "$registri"
cd "$radice" || exit 0

abbellisci() {
  if command -v xcbeautify >/dev/null; then xcbeautify --renderer github-actions; else cat; fi
}

case "$piattaforma" in
  iphone)
    progetto=iPhone/WebcamLR-iPhone.xcodeproj
    cartella=iPhone/CollaudoUI
    target=CollaudoUI-iPhone
    derivati=build/collaudo-iphone
    udid="$(python3 -I "$banco" simulatore "$dispositivo" 2>>"$registri/simulatore.txt")"
    cat "$registri/simulatore.txt"
    if [ -z "$udid" ]; then
      echo "NESSUN SIMULATORE: vedi _banco/simulatore.txt" > "$registri/esito-compilazione.txt"
      exit 0
    fi
    xcrun simctl boot "$udid" 2>/dev/null
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
    destinazione="id=$udid"
    # Firma locale («-»), senza account: senza firma l'app non ha i diritti (entitlements) e sul simulatore il
    # Portachiavi non salva (avviso «L'iPhone non riesce a ricordare questo collegamento»).
    firma=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
    ;;
  mac)
    progetto=Mac/WebcamLR-Mac.xcodeproj
    cartella=Mac/CollaudoUI
    target=CollaudoUI-Mac
    derivati=build/collaudo-mac
    destinazione="platform=macOS"
    # Firma locale («-»): senza firma il sandbox dell'app e il programma dei test UI non partono. Nessun account.
    firma=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
    ;;
  *)
    echo "Piattaforma sconosciuta: $piattaforma (iphone o mac)"; exit 0 ;;
esac

# I dati dell'app sul Mac (preferenze nel contenitore del sandbox, finestre da riaprire): via prima di ogni test.
pulisci_mac() {
  pkill -x WebcamLR 2>/dev/null
  sleep 1
  defaults delete it.lrapps.webcamlr.mac >/dev/null 2>&1
  contenitore="$HOME/Library/Containers/it.lrapps.webcamlr.mac/Data/Library"
  rm -f "$contenitore/Preferences/it.lrapps.webcamlr.mac.plist" 2>/dev/null
  rm -rf "$contenitore/Saved Application State/it.lrapps.webcamlr.mac.savedState" 2>/dev/null
  killall cfprefsd 2>/dev/null
  true
}

# L'app tolta dal simulatore (con i suoi dati), permessi e Portachiavi azzerati: come appena installata.
# Più veloce di «simctl erase» (che costava ~5 minuti a test tra cancellazione, avvio e prima installazione).
# Con COLLAUDO_CANCELLA=1 si cancella invece tutto il simulatore.
pulisci_iphone() {
  if [ "${COLLAUDO_CANCELLA:-0}" = 1 ]; then
    xcrun simctl shutdown "$udid" >/dev/null 2>&1
    xcrun simctl erase "$udid" || echo "simctl erase non riuscito"
    xcrun simctl boot "$udid" >/dev/null 2>&1
  else
    xcrun simctl terminate "$udid" it.lrapps.webcamlr.iphone >/dev/null 2>&1
    xcrun simctl uninstall "$udid" it.lrapps.webcamlr.iphone >/dev/null 2>&1
    xcrun simctl privacy "$udid" reset all it.lrapps.webcamlr.iphone >/dev/null 2>&1
    xcrun simctl keychain "$udid" reset >/dev/null 2>&1
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
}

echo "::group::Compilazione ($piattaforma)"
set -o pipefail
xcodebuild build-for-testing -project "$progetto" -scheme CollaudoUI -configuration Debug \
  -destination "$destinazione" -derivedDataPath "$derivati" "${firma[@]}" 2>&1 \
  | tee "$registri/compilazione.log" | abbellisci
esito_compilazione=$?
set +o pipefail
echo "::endgroup::"
if [ $esito_compilazione -ne 0 ]; then
  {
    echo "COMPILAZIONE FALLITA ($piattaforma): nessun copione eseguito. Errori:"
    grep -E "error:|\*\* .* FAILED \*\*" "$registri/compilazione.log" | sort -u | head -60
  } > "$registri/esito-compilazione.txt"
  cat "$registri/esito-compilazione.txt"
  exit 0
fi
echo "Compilazione riuscita" > "$registri/esito-compilazione.txt"

elenco="$(python3 -I "$banco" elenca "$cartella" "$piattaforma" "$filtro")"
echo "$elenco" > "$registri/test-scelti.txt"
if [ -z "$(echo "$elenco" | tr -d '[:space:]')" ]; then
  echo "Nessun copione per $piattaforma con il filtro «$filtro»" >> "$registri/esito-compilazione.txt"
  exit 0
fi

while IFS= read -r prova; do
  [ -z "$prova" ] && continue
  classe="${prova%%/*}"
  metodo="${prova#*/}"
  qui="$uscita/$piattaforma/$classe/$metodo"
  mkdir -p "$qui"
  echo "::group::$piattaforma $prova"
  if [ "$piattaforma" = iphone ]; then pulisci_iphone < /dev/null; else pulisci_mac < /dev/null; fi
  inizio="$(date '+%Y-%m-%d %H:%M:%S')"
  segno="$registri/.inizio"
  touch "$segno"
  risultato="${RUNNER_TEMP:-/tmp}/$piattaforma-$classe-$metodo.xcresult"
  rm -rf "$risultato"
  xcodebuild test-without-building -project "$progetto" -scheme CollaudoUI -configuration Debug \
    -destination "$destinazione" -derivedDataPath "$derivati" "${firma[@]}" \
    -only-testing:"$target/$classe/$metodo" -resultBundlePath "$risultato" \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 900 < /dev/null 2>&1 \
    | tee "$qui/xcodebuild.log" | abbellisci
  python3 -I "$banco" estrai "$risultato" "$qui"
  # I registri dell'app (os_log/Logger e print) dall'inizio di questo test.
  if [ "$piattaforma" = iphone ]; then
    xcrun simctl spawn "$udid" log show --style compact --info --debug --start "$inizio" \
      --predicate 'process == "WebcamLR"' < /dev/null > "$qui/log-app.txt" 2>&1
  else
    log show --style compact --info --debug --start "$inizio" \
      --predicate 'process == "WebcamLR"' < /dev/null > "$qui/log-app.txt" 2>&1
  fi
  # Rapporti di arresto anomalo dell'app, se ce ne sono.
  find "$HOME/Library/Logs/DiagnosticReports" -newer "$segno" -name 'WebcamLR*' -exec cp {} "$qui/" \; 2>/dev/null
  cat "$qui/esito.txt"
  echo "::endgroup::"
done <<< "$elenco"

exit 0
