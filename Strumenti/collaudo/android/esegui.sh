#!/usr/bin/env bash
# Esegue i copioni di collaudo sull'emulatore già acceso (lo chiama .github/workflows/collaudo-android.yml).
# Variabili: APK (l'APK di debug), COMPUTER_FINTO (la DLL del computer finto, facoltativa), RISULTATI (cartella, predefinita «risultati»), COPIONI (nomi separati da spazi,
# vuoto = tutti quelli in copioni/), TEMPO_COPIONE (secondi, predefinito 1200).
# Finisce sempre con 0: un copione che trova un bug scrive FALLITO nel suo esito.txt, non ferma il lavoro.
set -u
QUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RISULTATI="${RISULTATI:-risultati}"
mkdir -p "$RISULTATI"
RISULTATI="$(cd "$RISULTATI" && pwd)"
PACCHETTO="it.lrapps.webcamlr.android"
riepilogo="$RISULTATI/riepilogo.txt"
: > "$riepilogo"

annota() { echo "$*" | tee -a "$riepilogo"; }

adb wait-for-device
for _ in $(seq 1 120); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
    sleep 2
done
adb shell svc power stayon true
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard 2>/dev/null || adb shell input keyevent 82
adb shell settings put secure show_ime_with_hard_keyboard 1
adb logcat -G 16M 2>/dev/null || true
annota "Emulatore: $(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r')), schermo $(adb shell wm size | tail -1 | tr -d '\r')"

if [ -z "${APK:-}" ] || [ ! -f "$APK" ]; then
    annota "APK non trovato (${APK:-vuoto}): niente collaudo"
    exit 0
fi
if ! adb install -r "$APK" > "$RISULTATI/installazione.txt" 2>&1; then
    annota "Installazione non riuscita: vedi installazione.txt"
    exit 0
fi
annota "APK installato: $(basename "$APK")"

nomi="${COPIONI:-}"
if [ -z "${nomi// /}" ]; then
    nomi=$(cd "$QUI/copioni" && ls ./*.sh 2>/dev/null | sed 's#^\./##; s#\.sh$##' | tr '\n' ' ')
fi

# Le righe del logcat dell'app: i processi del pacchetto (anche dopo un riavvio), crash e ANR.
filtra_logcat() {
    awk -v pac="$PACCHETTO" '
        NR == FNR {
            if (match($0, "Start proc [0-9]+:" pac)) { split(substr($0, RSTART + 11), a, ":"); pid[a[1]] = 1 }
            if (match($0, "pid=[0-9]+") && index($0, pac)) { pid[substr($0, RSTART + 4, RLENGTH - 4)] = 1 }
            next
        }
        ($3 in pid) || index($0, pac) || /FATAL EXCEPTION|AndroidRuntime|ANR in|WebcamLR/ { print }
    ' "$1" "$1"
}

for nome in $nomi; do
    copione="$QUI/copioni/$nome.sh"
    uscita="$RISULTATI/$nome"
    mkdir -p "$uscita"
    if [ ! -f "$copione" ]; then
        printf 'FALLITO\ncopione %s non trovato\n' "$nome" > "$uscita/esito.txt"
        annota "$nome: FALLITO (copione non trovato)"
        continue
    fi
    echo "::group::Copione $nome"
    adb logcat -c 2>/dev/null; adb logcat -b crash -c 2>/dev/null
    adb logcat -v threadtime > "$uscita/logcat-completo.txt" 2>/dev/null &
    lettore=$!
    inizio=$(date +%s)
    USCITA="$uscita" timeout --kill-after=30 "${TEMPO_COPIONE:-1200}" \
        bash -c 'source "$1"; source "$2"' copione "$QUI/lib.sh" "$copione" </dev/null
    codice=$?
    durata=$(( $(date +%s) - inizio ))
    # Il computer finto lasciato acceso dal copione si ferma qui (con «arrivederci»), e la sua chiave di prova sparisce.
    if [ -f "$uscita/computer-finto/pid" ]; then
        USCITA="$uscita" bash -c 'source "$1"; ferma_computer_finto' ferma "$QUI/lib.sh" >/dev/null 2>&1 </dev/null
    fi
    rm -f "$uscita/computer-finto/identita.key" "$uscita/computer-finto/pid"
    adb forward --remove-all >/dev/null 2>&1
    sleep 2
    kill "$lettore" 2>/dev/null; wait "$lettore" 2>/dev/null
    adb logcat -b crash -d -v threadtime > "$uscita/crash.txt" 2>/dev/null
    filtra_logcat "$uscita/logcat-completo.txt" > "$uscita/logcat-app.txt"
    gzip -f "$uscita/logcat-completo.txt"
    rm -f "$uscita/.finestra.xml" "$uscita/.attesa.xml"

    # L'esito: quello scritto dal copione (fallisci), poi l'uscita, poi crash e ANR dell'app.
    if [ ! -s "$uscita/esito.txt" ]; then
        if [ "$codice" = 124 ] || [ "$codice" = 137 ]; then
            printf 'FALLITO\ncopione fermato dopo %s secondi (tempo scaduto)\n' "${TEMPO_COPIONE:-1200}" > "$uscita/esito.txt"
        elif [ "$codice" != 0 ]; then
            printf 'FALLITO\ncopione uscito con codice %s; ultimo passo: %s\n' "$codice" "$(tail -1 "$uscita/passi.log" 2>/dev/null)" > "$uscita/esito.txt"
        else
            printf 'OK\n' > "$uscita/esito.txt"
        fi
    fi
    problemi=""
    grep -q "Process: $PACCHETTO" "$uscita/crash.txt" 2>/dev/null && problemi="crash dell'app (vedi crash.txt)"
    grep -q "ANR in $PACCHETTO" "$uscita/logcat-app.txt" 2>/dev/null && problemi="${problemi:+$problemi; }ANR dell'app (vedi logcat-app.txt)"
    if [ -n "$problemi" ]; then
        primo=$(head -1 "$uscita/esito.txt")
        resto=$(tail -n +2 "$uscita/esito.txt")
        printf 'FALLITO\n%s\n%s\n' "$problemi" "$([ "$primo" = FALLITO ] && echo "$resto")" > "$uscita/esito.txt"
    fi
    annota "$nome: $(head -1 "$uscita/esito.txt") in ${durata}s, $(ls "$uscita/schermate" 2>/dev/null | wc -l) schermate$(sed -n '2p' "$uscita/esito.txt" | sed 's/^./ — &/')"
    echo "::endgroup::"

    # Il copione successivo parte dal telefono com'era: schermo, carattere, rotazione, rete, lingua.
    USCITA="$uscita" bash -c 'source "$1"; ripristina' ripristino "$QUI/lib.sh" >/dev/null 2>&1 </dev/null
done

exit 0
