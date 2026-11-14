# Copione t18 «giornata lunga», prima parte (~18 minuti): Andrea, formatore, ore in onda con il telefono che riceve
# telefonate e notifiche, la batteria che scende e il telefono che si scalda. Misura memoria, CPU, thread, fd,
# batteria e stato termico ogni 30 s (misure.csv). La sessione continua in t18_b_lunga (lanciare tutti e due, in ordine).
source "$(dirname "${BASH_SOURCE[0]}")/t18_comune.inc"
rm -rf "$T18_PASSAGGIO"; mkdir -p "$T18_PASSAGGIO"

avvia_computer_finto --nome "PC di Andrea" --ogni 300 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
adb_sh dumpsys battery reset
adb_sh settings put global low_power 0
adb_sh cmd thermalservice reset 2>/dev/null
avvia_app
sistema_calmo 60
for i in 1 2 3 4 5 6; do
    if c_e_testo "Cerco il tuo computer" || c_e_testo "Non trovo nessun computer" || c_e_testo "Collega a mano"; then break; fi
    if c_e_testo "Inizia"; then tocca_testo "Inizia"; sleep 3; continue; fi
    if c_e_testo "Salta"; then tocca_testo "Salta"; sleep 3; continue; fi
    sleep 3
done
collega_qr || fallisci "link del QR code non aperto"
attendi_computer video 60 || { schermata "senza-video"; testi_visibili; registro_telefono; fallisci "niente video al computer"; }
ONDA=$(date +%s)
passo "IN ONDA dopo $(( ONDA - T18_INIZIO )) s dall'inizio del copione"
echo "$ONDA" > "$T18_PASSAGGIO/onda"
attendi 3
adb_sh dumpsys meminfo "$PACCHETTO" > "$USCITA/meminfo-inizio.txt"
t18_campiona_sempre 30
t18_guarda "in-onda-inizio"
# a <s>: secondi dall'inizio dell'onda.
a() { while [ $(( $(date +%s) - ONDA )) -lt "$1" ]; do sleep 1; done; passo "--- minuto $(( $1 / 60 )):$(printf %02d $(( $1 % 60 )))"; }

a 150; t18_guarda "in-onda-2min30"

# --- Batteria che scende: scollegato dal caricatore, 15% e poi 10%.
a 240
adb_sh dumpsys battery unplug; adb_sh dumpsys battery set status 3; adb_sh dumpsys battery set level 15; passo "BATTERIA: scollegata (in scarica), 15%"
attendi 25; t18_guarda "batteria-15"; t18_video_ok "batteria 15%"
adb_sh dumpsys battery set level 10; passo "BATTERIA: 10%"
attendi 25; t18_guarda "batteria-10"; t18_video_ok "batteria 10%"
tocca_due_volte; attendi 2; t18_guarda "batteria-10-acceso"

# --- Risparmio energetico di sistema.
a 330
adb_sh settings put global low_power 1; passo "RISPARMIO ENERGETICO acceso (low_power 1)"
attendi 25; t18_guarda "risparmio-energetico"; t18_video_ok "risparmio energetico"

# --- Calore: batteria a 47 °C e stato termico «severe» (3).
a 400
adb_sh dumpsys battery set temp 470
adb_sh cmd thermalservice override-status 3; passo "CALORE: batteria 47 °C, stato termico 3 (severe)"
attendi 30; t18_guarda "caldo-severe"; t18_video_ok "caldo severe"
adb_sh cmd thermalservice override-status 4; passo "CALORE: stato termico 4 (critical)"
attendi 30; t18_guarda "caldo-critical"; t18_video_ok "caldo critical"
tocca_due_volte; attendi 2; t18_guarda "caldo-critical-acceso"

# --- Telefonata in arrivo, risposta, 40 s di conversazione, chiusa.
a 520
t18_emu gsm call 3331234567
attendi 4; t18_guarda "chiamata-squilla"; t18_video_ok "chiamata che squilla"
attendi 10; t18_guarda "chiamata-squilla-14s"
t18_emu gsm accept 3331234567
attendi 15; t18_guarda "chiamata-in-corso"; t18_video_ok "chiamata in corso"
attendi 25; t18_video_ok "chiamata in corso 40 s"
t18_emu gsm cancel 3331234567
attendi 5; t18_guarda "chiamata-finita-5s"; t18_video_ok "chiamata finita"
attendi 15; t18_guarda "chiamata-finita-20s"

# --- Notifiche: cinque di fila.
a 630
for k in 1 2 3 4 5; do
    adb_sh cmd notification post -S bigtext -t "Messaggio $k" "t18-$k" "Andrea, la riunione delle 15 e spostata" >/dev/null
    attendi 1
done
passo "NOTIFICHE: 5 messaggi"
attendi 2; t18_guarda "notifiche"; t18_video_ok "notifiche"

# --- App in sottofondo (Home) per 90 s e ritorno.
a 680
home
attendi 20; t18_guarda "sottofondo-20s"; t18_video_ok "sottofondo 20 s"
attendi 70; t18_video_ok "sottofondo 90 s"
avvia_app
attendi 5; t18_guarda "ritorno-dal-sottofondo"; t18_video_ok "ritorno dal sottofondo"

# --- Schermo spento per 2 minuti e riacceso.
a 820
adb_sh input keyevent KEYCODE_SLEEP; passo "SCHERMO SPENTO"
attendi 30; t18_video_ok "schermo spento 30 s"
attendi 90; t18_video_ok "schermo spento 2 min"
adb_sh input keyevent KEYCODE_WAKEUP; adb_sh wm dismiss-keyguard; passo "SCHERMO ACCESO"
attendi 5; t18_guarda "schermo-riacceso"; t18_video_ok "schermo riacceso"

# --- Fine della prima parte: entro 18 minuti e mezzo dall'inizio del copione (il tetto è 20).
while [ $(( $(date +%s) - T18_INIZIO )) -lt 1080 ] && [ $(( $(date +%s) - ONDA )) -lt 1000 ]; do sleep 5; done
t18_guarda "fine-prima-parte"
t18_campiona_ferma
statistiche_computer 3
# Il computer finto resta acceso per la seconda parte: esegui.sh non lo deve fermare.
echo "$CF" > "$T18_PASSAGGIO/cf"
mv "$CF/pid" "$T18_PASSAGGIO/pid"
passo "PRIMA PARTE finita dopo $(( $(date +%s) - ONDA )) s in onda; il computer finto resta acceso per t18_b_lunga"
