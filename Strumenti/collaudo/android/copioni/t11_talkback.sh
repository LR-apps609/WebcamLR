# Copione t11 (Marta) secondo giro: TalkBack acceso davvero (schermate con il riquadro verde del fuoco di TalkBack dopo
# ogni «scorri a destra»), la tastiera in onda subito dopo il collegamento (prima che lo schermo si oscuri) e lo schermo
# che si oscura mentre si naviga solo con TalkBack o con la tastiera (senza tocchi sullo schermo).

T11_PY="$(dirname "$_NODO")/t11_accessibilita.py"
t11_fuoco() {
    local f="$USCITA/.t11.xml"
    _dump "$f" && printf '%s' "$(python3 -I "$T11_PY" "$f" fuoco)" || printf 'dump non riuscito'
}
TB_PACCHETTO=$(adb_sh pm list packages | grep -i talkback | head -1 | sed 's/package://' | tr -d '\r')
TB_SERVIZIO=$(adb_sh dumpsys package "$TB_PACCHETTO" | grep -o "$TB_PACCHETTO/[A-Za-z0-9_.]*TalkBackService" | head -1 | tr -d '\r')
passo "TalkBack: pacchetto «$TB_PACCHETTO», servizio «$TB_SERVIZIO»"
talkback_acceso() {
    adb_sh settings put secure enabled_accessibility_services "$TB_SERVIZIO"
    adb_sh settings put secure accessibility_enabled 1
    attendi 6
    passo "TalkBack acceso: $(adb_sh dumpsys accessibility | grep -ci 'talkback') righe in dumpsys accessibility; servizi: $(adb_sh settings get secure enabled_accessibility_services)"
    # La prima volta TalkBack può mostrare un tutorial o un avviso: lo fotografiamo.
    schermata "talkback-appena-acceso"
}
talkback_spento() { adb_sh settings put secure enabled_accessibility_services '""'; adb_sh settings put secure accessibility_enabled 0; passo "TalkBack spento"; attendi 2; }
# Gesto di TalkBack «scorri a destra con un dito» = elemento successivo.
avanti_tb() { adb_sh input swipe 250 1300 850 1300 120; sleep 1.5; }

cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
for permesso in 1 2 3; do attendi_id "permission_message" 6 || break; consenti_dialogo || break; done
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"

# --- In onda con la sola tastiera, subito.
avvia_computer_finto --nome "PC di Marta" || fallisci "il computer finto non parte"
collega_qr || fallisci "nessun link del QR code"
attendi_computer video 45 || nota "il computer finto non riceve il video"
attendi 2
passo "TAB in onda subito dopo il collegamento:"
for i in $(seq 1 10); do adb_sh input keyevent KEYCODE_TAB; sleep 0.4; passo "  TAB $i: $(t11_fuoco)"; done
schermata "in-onda-dopo-10-tab"
passo "Continuo a premere Tab ogni 4 s per 40 s: lo schermo si oscura lo stesso?"
for i in $(seq 1 10); do adb_sh input keyevent KEYCODE_TAB; sleep 4; done
schermata "in-onda-tastiera-40s"
c_e_testo "Tocca due volte per riaccendere lo schermo" && nota "In onda lo schermo si oscura anche mentre si usa la tastiera (Tab ogni 4 s)"
tocca_due_volte
attendi 2

# --- TalkBack acceso in onda.
talkback_acceso
for i in $(seq 1 8); do avanti_tb; schermata "tb-in-onda-$i"; done
passo "Con TalkBack: scorro avanti ogni 5 s per 40 s"
for i in $(seq 1 8); do avanti_tb; sleep 3.5; done
schermata "tb-in-onda-40s"
c_e_testo "Tocca due volte per riaccendere lo schermo" && nota "Con TalkBack lo schermo in onda si oscura anche mentre Marta scorre gli elementi"
# Doppio tocco di TalkBack: attiva l'elemento con il fuoco (sullo schermo oscurato: riaccende).
adb_sh "input tap 540 1200; input tap 540 1200"; sleep 2
schermata "tb-dopo-doppio-tocco"
talkback_spento
statistiche_computer 1
ferma_computer_finto
attendi 3

# --- TalkBack sulla schermata principale.
attendi_testo "Impostazioni" 15
talkback_acceso
for i in $(seq 1 10); do avanti_tb; schermata "tb-principale-$i"; done
talkback_spento
