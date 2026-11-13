# Collaudo t02 (Giorgio, 62 anni, poco pratico): primo avvio letto con calma, i permessi RIFIUTATI per paura,
# poi l'app chiusa e riaperta per tornare indietro e consentirli. Carattere un po' più grande (1.3), come su molti
# telefoni di chi ha più di 60 anni.

cancella_dati_app
lingua_italiana
carattere_grande 1.3
avvia_app

# --- Presentazione: Giorgio legge ogni pagina e tocca «Avanti».
attendi_testo "Il tuo telefono diventa la webcam" 30 || fallisci "la presentazione non compare al primo avvio"
schermata "pres-1"
testi_visibili
scorri_giu
schermata "pres-1-in-fondo"
tocca_testo "Avanti" || fallisci "manca «Avanti» nella pagina 1"
attendi 2
schermata "pres-2"
testi_visibili
scorri_giu
schermata "pres-2-in-fondo"
tocca_testo "Avanti" || fallisci "manca «Avanti» nella pagina 2"
attendi 2
schermata "pres-3"
testi_visibili
scorri_giu
schermata "pres-3-in-fondo"
tocca_testo "Avanti" || fallisci "manca «Avanti» nella pagina 3"
attendi_testo "Goditi l'esperienza" 10 || nota "pagina dei permessi: titolo non trovato"
schermata "pres-4-permessi"
testi_visibili
scorri_giu
schermata "pres-4-in-fondo"
testi_visibili

# --- «Inizia»: Giorgio ha paura e risponde «Non consentire» a tutto.
tocca_testo "Inizia" || fallisci "manca «Inizia»"
n=0
while attendi_id "permission_message" 8; do
    n=$((n + 1))
    schermata "dialogo-sistema-$n"
    testi_visibili
    rifiuta_dialogo || break
    [ "$n" -ge 4 ] && break
done
nota "dialoghi di sistema rifiutati al primo giro: $n"
attendi 3
schermata "dopo-rifiuti"
testi_visibili
scorri_giu
schermata "dopo-rifiuti-in-fondo"
testi_visibili
scorri_su

# --- Giorgio prova lo stesso a inquadrare il QR code (la cosa che gli dice lo schermo).
if tocca_testo "Inquadra il QR code del computer"; then
    attendi 3
    schermata "qr-senza-fotocamera"
    testi_visibili
    # Un eventuale dialogo di sistema che chiede di nuovo la fotocamera: lo rifiuta ancora.
    if attendi_id "permission_message" 5; then
        schermata "qr-dialogo-sistema"
        rifiuta_dialogo
        attendi 2
        schermata "qr-dopo-secondo-rifiuto"
        testi_visibili
    fi
    indietro
    attendi 2
fi
schermata "principale-dopo-qr"
testi_visibili

# --- Si spaventa, chiude l'app (dalle app recenti: qui force-stop) e la riapre.
chiudi_app
avvia_app
attendi 4
schermata "riaperta-1"
testi_visibili
n=0
while attendi_id "permission_message" 6; do
    n=$((n + 1))
    schermata "riaperta-dialogo-$n"
    testi_visibili
    consenti_dialogo || break
    [ "$n" -ge 4 ] && break
done
nota "dialoghi di sistema alla riapertura (consentiti): $n"
attendi 3
schermata "riaperta-dopo-dialoghi"
testi_visibili

# --- Se l'app non li ha richiesti, prova dal QR: ora la fotocamera serve davvero.
if tocca_testo "Inquadra il QR code del computer"; then
    attendi 3
    schermata "qr-seconda-volta"
    testi_visibili
    if attendi_id "permission_message" 5; then
        schermata "qr-seconda-volta-dialogo"
        consenti_dialogo
        attendi 3
        schermata "qr-seconda-volta-consentito"
    fi
    # Cerca un pulsante che porti alle impostazioni di sistema.
    for t in "Apri le impostazioni" "Impostazioni" "Consenti" "Autorizzazioni"; do
        c_e_testo "$t" && nota "nel lettore QR c'è il testo «$t»"
    done
    indietro
    attendi 2
fi
schermata "fine-permessi"
testi_visibili
adb_sh dumpsys package "$PACCHETTO" 2>/dev/null | grep -E 'permission.(CAMERA|RECORD_AUDIO|POST_NOTIFICATIONS): granted' | while read -r r; do nota "permesso: $r"; done
