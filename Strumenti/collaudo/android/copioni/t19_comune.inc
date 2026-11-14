# Funzioni comuni dei copioni t19 (Emma: telefono in inglese, lingua di sistema). Si carica con «source».
source "$_CARTELLA_LIB/t09_comune.sh"   # giro

# Lingua dell'app = lingua di sistema (nessuna lingua per app): l'emulatore è in inglese (en-US).
t19_lingua_sistema() {
    LINGUA_APP=""
    adb_sh cmd locale set-app-locales "$PACCHETTO" --locales "" >/dev/null 2>&1
    passo "LINGUA APP: quella di sistema ($(adb_sh getprop persist.sys.locale)$(adb_sh getprop ro.product.locale)); per app: $(adb_sh cmd locale get-app-locales "$PACCHETTO" 2>&1 | tr -d '\r')"
    sleep 2
}

# Primo avvio pulito in inglese fino alla schermata principale.
t19_prepara() {
    cancella_dati_app
    t19_lingua_sistema
    permessi_concedi
    avvia_app
    attendi_testo "Skip" 30 || fallisci "la presentazione non compare (in inglese)"
    local i
    for i in 1 2 3 4 5; do c_e_testo "Start" && break; tocca_testo "Skip"; attendi 2; done
    tocca_testo "Start" || fallisci "manca «Start»"
    attendi_testo "Settings" 20 || fallisci "la schermata principale non compare"
}

t19_torna() {
    local i
    for i in 1 2 3 4 5; do
        c_e_testo "Connect manually (address)" && return 0
        if c_e_testo "Double-tap to turn the screen back on"; then tocca_due_volte; continue; fi
        if c_e_testo "Cancel"; then tocca_testo "Cancel"; attendi 2; continue; fi
        indietro
    done
    avvia_app
}

# tendina: apre le notifiche di sistema e le fotografa.
t19_tendina() {
    adb_sh cmd statusbar expand-notifications; sleep 2
    schermata "$1"
    testi_visibili
    adb_sh cmd statusbar collapse; sleep 1
}
