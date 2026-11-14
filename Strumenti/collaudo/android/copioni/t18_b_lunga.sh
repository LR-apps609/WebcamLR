# Copione t18 «giornata lunga», seconda parte (~18 minuti): continua la sessione di t18_a_lunga senza scollegare.
# Seconda telefonata (persa), batteria al 5%, ritorno del caricatore e del fresco, sottofondo e schermo spento lunghi.
source "$(dirname "${BASH_SOURCE[0]}")/t18_comune.inc"
[ -s "$T18_PASSAGGIO/cf" ] || fallisci "manca la prima parte (lanciare t18_a_lunga prima)"
CF=$(cat "$T18_PASSAGGIO/cf")
ONDA=$(cat "$T18_PASSAGGIO/onda")
cp "$T18_PASSAGGIO/pid" "$CF/pid"
passo "SECONDA PARTE: in onda da $(( $(date +%s) - ONDA )) s, computer «$(stato_computer)»"
t18_campiona_sempre 30
t18_guarda "inizio-seconda-parte"; t18_video_ok "inizio seconda parte"
b() { while [ $(( $(date +%s) - T18_INIZIO )) -lt "$1" ]; do sleep 1; done; passo "--- in onda da $(( ($(date +%s) - ONDA) / 60 )) min"; }

b 180; t18_guarda "idle-3min"

# --- Telefonata persa (squilla 25 s, poi chi chiama riattacca).
b 240
t18_emu gsm call 3339876543
attendi 6; t18_guarda "chiamata2-squilla"; t18_video_ok "seconda chiamata squilla"
attendi 19
t18_emu gsm cancel 3339876543
attendi 8; t18_guarda "chiamata2-persa"; t18_video_ok "dopo la chiamata persa"

# --- Batteria al 5%.
b 330
adb_sh dumpsys battery set level 5; passo "BATTERIA: 5%"
attendi 25; t18_guarda "batteria-5"; t18_video_ok "batteria 5%"
adb_sh dumpsys battery set level 2; passo "BATTERIA: 2%"
attendi 25; t18_guarda "batteria-2"; t18_video_ok "batteria 2%"

# --- Caricatore di nuovo, risparmio spento, telefono che si raffredda.
b 420
adb_sh dumpsys battery set ac 1; adb_sh dumpsys battery set status 2; adb_sh dumpsys battery set level 40; adb_sh dumpsys battery set temp 300
adb_sh settings put global low_power 0
adb_sh cmd thermalservice override-status 0
passo "CARICATORE collegato (40%), risparmio spento, 30 °C, stato termico 0"
attendi 45; t18_guarda "fresco-in-carica"; t18_video_ok "fresco e in carica"
tocca_due_volte; attendi 2; t18_guarda "fresco-in-carica-acceso"

# --- App in sottofondo 3 minuti (Andrea controlla la posta sul telefono).
b 520
home
attendi 60; t18_video_ok "sottofondo 1 min"
attendi 110; t18_guarda "sottofondo-3min"; t18_video_ok "sottofondo 3 min"
avvia_app
attendi 5; t18_guarda "ritorno-dopo-3min"; t18_video_ok "ritorno dopo 3 min"

# --- Schermo spento 3 minuti.
b 740
adb_sh input keyevent KEYCODE_SLEEP; passo "SCHERMO SPENTO"
attendi 90; t18_video_ok "schermo spento 90 s"
attendi 90; t18_video_ok "schermo spento 3 min"
adb_sh input keyevent KEYCODE_WAKEUP; adb_sh wm dismiss-keyguard; passo "SCHERMO ACCESO"
attendi 5; t18_guarda "schermo-riacceso-3min"; t18_video_ok "schermo riacceso dopo 3 min"

# --- Fine: memoria, registro, Scollega.
b 980
t18_campiona_ferma
adb_sh dumpsys meminfo "$PACCHETTO" > "$USCITA/meminfo-fine.txt"
passo "FINE: in onda da $(( $(date +%s) - ONDA )) s"
statistiche_computer 3
registro_telefono
attendi 2
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
if tocca_testo "Scollega"; then
    schermata "domanda-scollega"; tocca_testo "Scollega"; attendi 3; schermata "dopo-scollega"
else
    nota "in onda non trovo «Scollega»"; schermata "senza-scollega"
fi
adb_sh dumpsys battery reset
ferma_computer_finto
