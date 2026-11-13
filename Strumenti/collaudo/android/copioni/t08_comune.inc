# Funzioni comuni dei copioni t08 (si carica con `source` dai copioni t08_*).

# t08_in_onda: primo avvio pulito, collegamento con il link del QR code (niente codice), aspetta il video.
t08_in_onda() {
    cancella_dati_app
    lingua_italiana
    permessi_concedi
    avvia_app
    attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
    tocca_testo "Salta"
    tocca_testo "Inizia" || fallisci "manca «Inizia»"
    attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
    collega_qr || fallisci "link del QR code non aperto"
    attendi_computer video 60 || { schermata "senza-video"; testi_visibili; registro_telefono; fallisci "niente video al computer"; }
    attendi 3
}

# t08_guarda <etichetta> <secondi>: per <secondi> fotografa e scrive i testi ogni ~10 s (cosa vede Luca).
t08_guarda() {
    local et="$1" fine=$(( $(date +%s) + $2 )) k=0
    while [ "$(date +%s)" -lt "$fine" ]; do
        k=$((k + 1))
        schermata "$et-$k"
        testi_visibili
        sleep 6
    done
}

# t08_ritorno <collegamenti-prima> <massimo> <etichetta>: secondi fino al ricollegamento con video (scritti in
# passi.log e note.txt); fotografa ogni ~8 s mentre aspetta.
t08_ritorno() {
    local prima="$1" massimo="$2" et="$3" inizio=$(date +%s) ultimo=0 ora
    while :; do
        ora=$(date +%s)
        if [ "$(collegamenti_computer)" -gt "$prima" ] && [ "$(stato_computer)" = video ]; then
            nota "$et: video di nuovo al computer $(( ora - inizio )) s dopo il ritorno della rete"
            return 0
        fi
        if [ $(( ora - inizio )) -ge "$massimo" ]; then
            nota "$et: NESSUN ritorno del video in $massimo s (computer «$(stato_computer)», collegamenti $(collegamenti_computer))"
            schermata "$et-senza-ritorno"; testi_visibili
            return 1
        fi
        if [ $(( ora - ultimo )) -ge 8 ]; then schermata "$et-attesa"; ultimo=$ora; fi
        sleep 1
    done
}

# t08_risveglia: se «In onda» è oscurato, doppio tocco per vedere i pulsanti.
t08_risveglia() { c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte; return 0; }
