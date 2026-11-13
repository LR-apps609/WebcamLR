# Funzioni per i copioni di collaudo Android di WebcamLR (si carica con `source`, non si esegue).
# Le usa esegui.sh, che apre l'emulatore, installa l'APK e prepara USCITA (la cartella dei risultati del copione).
# Ogni funzione scrive il suo passo in $USCITA/passi.log; le funzioni che cercano qualcosa rendono 1 se non lo
# trovano, senza fermare il copione: decide il copione (per esempio `tocca_testo "Avanti" || fallisci "manca Avanti"`).

PACCHETTO="${PACCHETTO:-it.lrapps.webcamlr.android}"
ATTIVITA="$PACCHETTO/.MainActivity"
USCITA="${USCITA:-$PWD/risultati/prova}"
# La lingua dell'app: l'emulatore è in inglese, quindi senza questa scelta l'app sarebbe in inglese.
LINGUA_APP="${LINGUA_APP:-it}"
_CARTELLA_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_NODO="$_CARTELLA_LIB/nodo.py"
_numero=0
_rotazione=0

mkdir -p "$USCITA/schermate" "$USCITA/albero"

# ---------------------------------------------------------------- registro e attese

passo() {
    printf '%s  %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$USCITA/passi.log" >&2
}

attendi() { sleep "${1:-1}"; }

# Il numero del passo in $_n (niente $(...): in una sottoshell il contatore non crescerebbe).
_prossimo() {
    _numero=$((_numero + 1))
    printf -v _n '%03d' "$_numero"
}

_nome_file() {
    # Solo lettere, cifre, - e _: il nome resta leggibile anche negli artifact.
    printf '%s' "$1" | tr ' /' '--' | tr -cd 'A-Za-z0-9._-' | cut -c1-60
}

adb_sh() { adb shell "$@" </dev/null; }

# Il dump dell'interfaccia in un file locale. uiautomator a volte risponde «could not get idle state»: si riprova.
_dump() {
    local destinazione="$1" prova
    for prova in 1 2 3 4; do
        rm -f "$destinazione"
        if adb_sh uiautomator dump /sdcard/finestra.xml >/dev/null 2>&1 \
            && adb pull /sdcard/finestra.xml "$destinazione" >/dev/null 2>&1 \
            && grep -q '<hierarchy' "$destinazione"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# ---------------------------------------------------------------- fotografie

# schermata <nome>: PNG e albero dell'interfaccia con lo stesso numero.
schermata() {
    local n nome
    _prossimo; n=$_n; nome="$n-$(_nome_file "${1:-schermata}")"
    adb exec-out screencap -p > "$USCITA/schermate/$nome.png" 2>/dev/null
    _dump "$USCITA/albero/$nome.xml" || echo "dump non riuscito" > "$USCITA/albero/$nome.xml.errore"
    passo "SCHERMATA $nome"
}

# albero <nome>: solo il dump XML dell'interfaccia.
albero() {
    local n nome
    _prossimo; n=$_n; nome="$n-$(_nome_file "${1:-albero}")"
    _dump "$USCITA/albero/$nome.xml" || echo "dump non riuscito" > "$USCITA/albero/$nome.xml.errore"
    passo "ALBERO $nome"
}

# testi_visibili: scrive nel registro i testi e le descrizioni che si vedono adesso (utile per scrivere i copioni).
testi_visibili() {
    local f="$USCITA/.finestra.xml"
    _dump "$f" || { passo "testi visibili: dump non riuscito"; return 1; }
    passo "TESTI VISIBILI:"
    python3 -I "$_NODO" "$f" elenca | sed 's/^/        · /' | tee -a "$USCITA/passi.log" >&2
}

# ---------------------------------------------------------------- tocchi e tasti

tocca_xy() {
    adb_sh input tap "$1" "$2"
    sleep "${ATTESA_DOPO_TOCCO:-1.2}"
}

# Il dump «prima del tocco» resta in albero/ con il numero del passo: è l'albero a ogni passo.
_tocca() {
    local modo="$1" valore="$2" indice="${3:-1}" prova n nome f centro
    _prossimo; n=$_n; nome="$n-prima-di-tocca-$(_nome_file "$valore")"
    f="$USCITA/albero/$nome.xml"
    for prova in 0 1 2 3 4; do
        if _dump "$f" && centro=$(python3 -I "$_NODO" "$f" "$modo" "$valore" "$indice"); then
            [ "$prova" -gt 0 ] && passo "  (trovato dopo $prova scorrimenti)"
            passo "TOCCA $modo «$valore» in $centro"
            # shellcheck disable=SC2086
            tocca_xy $centro
            return 0
        fi
        # Non c'è: forse è più in basso. Si scorre e si riprova (al massimo 4 volte).
        [ "$prova" -lt 4 ] && _scorri giu
    done
    passo "NON TROVATO: $modo «$valore» (dopo 4 scorrimenti)"
    schermata "non-trovato-$valore"
    return 1
}

# tocca_testo "<testo>" [indice]: cerca per text o content-desc (prima uguale, poi «contiene»), tocca il centro.
tocca_testo() { _tocca testo "$1" "${2:-1}"; }

# tocca_id <resource-id>: per esempio permission_allow_button (va bene anche il nome completo con il pacchetto).
tocca_id() { _tocca id "$1" "${2:-1}"; }

# scrivi "<testo>": nel campo che ha il fuoco (prima toccalo). Solo caratteri ASCII: `input text` non scrive accenti.
scrivi() {
    local testo="$1" sicuro
    if printf '%s' "$testo" | LC_ALL=C grep -q '[^ -~]'; then
        passo "ATTENZIONE: «$testo» ha caratteri non ASCII che adb input text non sa scrivere"
    fi
    sicuro=$(printf '%s' "$testo" | sed -e 's/[\\"'"'"'`$&|;<>()*?#~!]/\\&/g' -e 's/ /%s/g')
    adb_sh "input text $sicuro"
    passo "SCRIVI «$testo»"
    sleep 0.8
}

indietro() { adb_sh input keyevent KEYCODE_BACK; passo "INDIETRO"; sleep 1.2; }
home() { adb_sh input keyevent KEYCODE_HOME; passo "HOME"; sleep 1.2; }
invio() { adb_sh input keyevent KEYCODE_ENTER; passo "INVIO"; sleep 1; }

_dimensioni() {
    # «Override size» se c'è (schermo_piccolo), altrimenti «Physical size».
    adb_sh wm size | awk -F': ' '{d=$2} END {print d}' | tr -d '\r'
}

_scorri() {
    local d l a x
    d=$(_dimensioni); l=${d%x*}; a=${d#*x}; x=$((l / 2))
    if [ "$1" = giu ]; then
        adb_sh input swipe "$x" $((a * 3 / 4)) "$x" $((a / 4)) 350
    else
        adb_sh input swipe "$x" $((a / 4)) "$x" $((a * 3 / 4)) 350
    fi
    sleep 1
}

scorri_giu() { passo "SCORRI GIÙ"; _scorri giu; }
scorri_su() { passo "SCORRI SU"; _scorri su; }

# attendi_testo "<testo>" [secondi=10]: 0 appena compare, 1 se non compare in tempo (nessuno scorrimento).
attendi_testo() {
    local testo="$1" secondi="${2:-10}" f="$USCITA/.attesa.xml" fine
    fine=$(( $(date +%s) + secondi ))
    while :; do
        if _dump "$f" && python3 -I "$_NODO" "$f" testo "$testo" >/dev/null; then
            passo "VISTO «$testo»"
            return 0
        fi
        [ "$(date +%s)" -ge "$fine" ] && break
        sleep 1
    done
    passo "NON COMPARE «$testo» in ${secondi}s"
    return 1
}

# attendi_id <resource-id> [secondi=10]
attendi_id() {
    local voluto="$1" secondi="${2:-10}" f="$USCITA/.attesa.xml" fine
    fine=$(( $(date +%s) + secondi ))
    while :; do
        if _dump "$f" && python3 -I "$_NODO" "$f" id "$voluto" >/dev/null; then
            passo "VISTO id $voluto"
            return 0
        fi
        [ "$(date +%s)" -ge "$fine" ] && break
        sleep 1
    done
    passo "NON COMPARE id $voluto in ${secondi}s"
    return 1
}

# c_e_testo "<testo>": vero se il testo si vede adesso (un dump solo, nessun registro).
c_e_testo() {
    local f="$USCITA/.attesa.xml"
    _dump "$f" && python3 -I "$_NODO" "$f" testo "$1" >/dev/null
}

# ---------------------------------------------------------------- esito

# fallisci "<motivo>": fotografa, scrive FALLITO in esito.txt e chiude il copione.
fallisci() {
    passo "FALLITO: $*"
    schermata "fallito"
    printf 'FALLITO\n%s\n' "$*" > "$USCITA/esito.txt"
    exit 1
}

# nota "<testo>": un'osservazione del tester (finisce in passi.log e in note.txt).
nota() {
    passo "NOTA: $*"
    printf '%s\n' "$*" >> "$USCITA/note.txt"
}

# ---------------------------------------------------------------- app

avvia_app() {
    passo "AVVIA APP"
    adb_sh am start -W -n "$ATTIVITA" >/dev/null 2>&1
    sleep 2
}

chiudi_app() { passo "CHIUDI APP (force-stop)"; adb_sh am force-stop "$PACCHETTO"; sleep 1; }

# cancella_dati_app: come appena installata (pm clear), con la lingua scelta e i permessi da chiedere di nuovo.
cancella_dati_app() {
    passo "CANCELLA DATI APP (primo avvio pulito)"
    adb_sh pm clear "$PACCHETTO" >/dev/null
    _applica_lingua
    sleep 1
}

_applica_lingua() { adb_sh cmd locale set-app-locales "$PACCHETTO" --locales "$LINGUA_APP" >/dev/null 2>&1; }

# Lingua dell'app di Android 13+ (la stessa di Impostazioni › App › Lingua): nessun riavvio del telefono, l'app si
# ricrea da sola. I dialoghi di sistema (permessi) restano in inglese, la lingua dell'emulatore.
lingua_inglese() { LINGUA_APP=en; _applica_lingua; passo "LINGUA APP: inglese"; sleep 2; }
lingua_italiana() { LINGUA_APP=it; _applica_lingua; passo "LINGUA APP: italiano"; sleep 2; }

# ---------------------------------------------------------------- permessi

_permessi_app="android.permission.CAMERA android.permission.RECORD_AUDIO"

# permessi_nega: toglie fotocamera e microfono (Android chiude l'app se è aperta).
permessi_nega() {
    local p
    for p in $_permessi_app; do adb_sh pm revoke "$PACCHETTO" "$p" 2>/dev/null; done
    passo "PERMESSI NEGATI: fotocamera, microfono"
}

# permessi_concedi: fotocamera, microfono e notifiche, senza dialoghi.
permessi_concedi() {
    local p
    for p in $_permessi_app android.permission.POST_NOTIFICATIONS; do adb_sh pm grant "$PACCHETTO" "$p" 2>/dev/null; done
    passo "PERMESSI CONCESSI: fotocamera, microfono, notifiche"
}

# consenti_dialogo / rifiuta_dialogo [secondi=8]: rispondono a UN dialogo di permesso di sistema, se compare (1 se no).
# «Consenti» tocca «While using the app» se c'è (fotocamera, microfono), altrimenti «Allow» (notifiche).
_dialogo() {
    local fine id
    fine=$(( $(date +%s) + ${2:-8} ))
    while [ "$(date +%s)" -lt "$fine" ]; do
        for id in $1; do
            if c_e_id "$id"; then tocca_id "$id"; return 0; fi
        done
        sleep 1
    done
    passo "NESSUN DIALOGO DI PERMESSO"
    return 1
}
consenti_dialogo() { _dialogo "permission_allow_foreground_only_button permission_allow_button" "${1:-8}"; }
rifiuta_dialogo() { _dialogo "permission_deny_button permission_deny_and_dont_ask_again_button" "${1:-8}"; }

c_e_id() {
    local f="$USCITA/.attesa.xml"
    _dump "$f" && python3 -I "$_NODO" "$f" id "$1" >/dev/null
}

# ---------------------------------------------------------------- rete

rete_spenta() { adb_sh svc wifi disable; adb_sh svc data disable; passo "RETE SPENTA (Wi-Fi e dati)"; sleep 2; }
rete_accesa() {
    adb_sh cmd connectivity airplane-mode disable 2>/dev/null
    adb_sh svc wifi enable; adb_sh svc data enable
    passo "RETE ACCESA"; sleep 3
}
aereo() { adb_sh cmd connectivity airplane-mode enable; passo "MODALITÀ AEREO"; sleep 2; }

# ---------------------------------------------------------------- schermo

# schermo_piccolo: 480x800 a 240 dpi, cioè 320x533 dp (un telefono piccolo e vecchio).
schermo_piccolo() { adb_sh wm size 480x800; adb_sh wm density 240; passo "SCHERMO PICCOLO 480x800 @240dpi"; sleep 2; }

# carattere_grande [scala=2.0]: il carattere più grande di Android 14.
carattere_grande() { adb_sh settings put system font_scale "${1:-2.0}"; passo "CARATTERE ${1:-2.0}x"; sleep 2; }

# ruota [orizzontale|verticale]: senza argomento passa all'altra.
ruota() {
    local verso="${1:-}"
    if [ -z "$verso" ]; then [ "$_rotazione" = 0 ] && verso=orizzontale || verso=verticale; fi
    [ "$verso" = orizzontale ] && _rotazione=1 || _rotazione=0
    adb_sh settings put system accelerometer_rotation 0
    adb_sh settings put system user_rotation "$_rotazione"
    passo "RUOTA $verso"
    sleep 2
}

# ripristina: schermo, carattere, rotazione, rete e lingua come all'inizio.
ripristina() {
    adb_sh wm size reset; adb_sh wm density reset
    adb_sh settings put system font_scale 1.0
    adb_sh settings put system user_rotation 0; _rotazione=0
    rete_accesa >/dev/null 2>&1
    LINGUA_APP=it; _applica_lingua
    passo "RIPRISTINA (schermo, carattere, rotazione, rete, lingua italiana)"
    sleep 2
}
