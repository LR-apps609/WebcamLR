# Copione t11 (Marta, cieca, usa TalkBack): ogni schermata letta come la leggerebbe un lettore di schermo (nomi dei
# pulsanti, immagini annunciate, stati), la navigazione con la tastiera (Tab, frecce, Invio: il fuoco «focused») e,
# se l'emulatore ha TalkBack, l'accensione di TalkBack. Poi in onda con il computer finto (link del QR code).

T11_PY="$(dirname "$_NODO")/t11_accessibilita.py"
t11_controlla() {
    local f="$USCITA/.t11.xml"
    schermata "$1"
    _dump "$f" || { passo "CONTROLLO $1: dump non riuscito"; return; }
    passo "CONTROLLO $1:"
    python3 -I "$T11_PY" "$f" controlla | tee -a "$USCITA/passi.log" >&2
}
t11_fuoco() {
    local f="$USCITA/.t11.xml"
    _dump "$f" && printf '%s' "$(python3 -I "$T11_PY" "$f" fuoco)" || printf 'dump non riuscito'
}
# t11_tasti <nome> <tasto> <volte> [fotografa-ogni]: preme un tasto (KEYCODE_…) e annota dove va il fuoco.
t11_tasti() {
    local nome="$1" tasto="$2" volte="$3" ogni="${4:-0}" i
    passo "GIRO $tasto «$nome» · inizio: $(t11_fuoco)"
    for i in $(seq 1 "$volte"); do
        adb_sh input keyevent "$tasto"
        sleep 0.6
        passo "  $tasto $i: $(t11_fuoco)"
        if [ "$ogni" -gt 0 ] && [ $((i % ogni)) -eq 0 ]; then schermata "fuoco-$nome-$i"; fi
    done
}

cancella_dati_app
lingua_italiana
if adb_sh pm list packages | grep -qi talkback; then
    nota "TalkBack è installato sull'emulatore"
    T11_TALKBACK=1
else
    nota "TalkBack non è installato sull'emulatore (immagine google_apis): niente prova con TalkBack acceso"
    T11_TALKBACK=0
fi
passo "Servizi di accessibilità installati: $(adb_sh settings get secure enabled_accessibility_services)"

avvia_app
attendi_testo "Il tuo telefono diventa la webcam" 30 || fallisci "la presentazione non compare"
t11_controlla "presentazione-1"
t11_tasti "presentazione" KEYCODE_TAB 8 4
tocca_testo "Avanti"; attendi 1; t11_controlla "presentazione-2"
tocca_testo "Avanti"; attendi 1; t11_controlla "presentazione-3"
tocca_testo "Avanti"; attendi 1; t11_controlla "presentazione-4"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
for permesso in 1 2 3; do
    attendi_id "permission_message" 8 || break
    consenti_dialogo || break
done
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
t11_controlla "principale-cerco"
attendi_testo "Non trovo nessun computer" 40 && t11_controlla "principale-non-trovo"
t11_tasti "principale" KEYCODE_TAB 16 4
t11_tasti "principale-frecce" KEYCODE_DPAD_DOWN 6 3
adb_sh input keyevent KEYCODE_ENTER; attendi 1.5
passo "Dopo Invio sul fuoco: $(t11_fuoco)"
schermata "dopo-invio-principale"
indietro

if tocca_testo "Collega a mano (indirizzo)"; then
    t11_controlla "dialogo-indirizzo"
    t11_tasti "dialogo-indirizzo" KEYCODE_TAB 5 1
    adb_sh input keyevent KEYCODE_ESCAPE; attendi 1
    passo "Dopo Esc nel dialogo: $(t11_fuoco)"
    c_e_testo "Annulla" && { nota "Esc (tastiera) non chiude il dialogo «Collega a mano»"; tocca_testo "Annulla"; }
fi
if tocca_testo "Usa il cavo USB"; then
    t11_controlla "dialogo-cavo"
    tocca_testo "Chiudi" || indietro
fi
if tocca_testo "Inquadra il QR code del computer"; then
    attendi 3
    t11_controlla "lettore-qr"
    indietro
fi
attendi_testo "Impostazioni" 10
tocca_testo "Impostazioni" && {
    t11_controlla "impostazioni-1"
    t11_tasti "impostazioni" KEYCODE_TAB 12 6
    scorri_giu; t11_controlla "impostazioni-2"
    scorri_giu; t11_controlla "impostazioni-3"
    indietro
}
tocca_testo "App e assistenza" && {
    t11_controlla "app-assistenza"
    tocca_testo "Segnala un bug" && { t11_controlla "segnala-bug"; indietro; }
    indietro
}

# --- In onda con il link del QR code.
avvia_computer_finto --nome "PC di Marta" || fallisci "il computer finto non parte"
attendi_testo "Impostazioni" 10
collega_qr || fallisci "nessun link del QR code"
attendi_computer video 45 || nota "il computer finto non riceve il video"
attendi 3
t11_controlla "in-onda"
t11_tasti "in-onda" KEYCODE_TAB 12 4
passo "Aspetto 35 s senza tocchi: lo schermo si oscura"
attendi 35
t11_controlla "in-onda-oscurato"
t11_tasti "oscurato" KEYCODE_TAB 3
adb_sh input keyevent KEYCODE_ENTER; attendi 1.5
t11_controlla "oscurato-dopo-invio"

if [ "$T11_TALKBACK" = 1 ]; then
    servizio=$(adb_sh pm list packages | grep -i talkback | head -1 | sed 's/package://' | tr -d '\r')
    adb_sh settings put secure enabled_accessibility_services "$servizio/com.google.android.marvin.talkback.TalkBackService"
    adb_sh settings put secure accessibility_enabled 1
    attendi 4
    t11_controlla "talkback-acceso"
    adb_sh settings put secure enabled_accessibility_services ""
fi
statistiche_computer 2
ferma_computer_finto
attendi 3
t11_controlla "dopo-computer-spento"
