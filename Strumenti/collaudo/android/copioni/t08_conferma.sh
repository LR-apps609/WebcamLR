source "$(dirname "${BASH_SOURCE[0]}")/t08_comune.inc"
# Copione t08 «conferma»: il «Collegamento non confermato» intermittente. Primo collegamento a mano con il codice,
# ripetuto con telefono nuovo (dati cancellati) e attese diverse del computer prima di consentire. A ogni giro: cosa
# mostra il telefono secondo per secondo, cosa scrive il computer finto e, se va male, il registro del telefono.

# t08_giro <n> <attesa-conferma>
t08_giro() {
    local n="$1" attesa="$2" inizio fine stato visto_codice=no visto_errore=no
    passo "===== GIRO $n: attesa della conferma $attesa s ====="
    avvia_computer_finto --nome "PC di Luca" --attesa-conferma "$attesa" || { nota "giro $n: il computer finto non parte"; return; }
    cancella_dati_app
    lingua_italiana
    permessi_concedi
    avvia_app
    t08_salta_presentazione || { nota "giro $n: niente schermata principale"; schermata "giro$n-senza-principale"; chiudi_app; return; }
    # Orologi: quello del telefono (registro del collegamento) e quello del computer finto (eventi.log).
    passo "giro $n: ora del telefono $(adb_sh date +%H:%M:%S.%N | cut -c1-12), ora del computer $(date +%H:%M:%S.%N | cut -c1-12)"
    # Chi chiude la connessione, e quando: i pacchetti con SYN, FIN o RST sulla porta del computer finto.
    sudo -n timeout 120 tcpdump -i any -n -tt -l "tcp port $(cat "$CF/porta.txt") and (tcp[tcpflags] & (tcp-syn|tcp-fin|tcp-rst) != 0)" \
        > "$USCITA/tcp-giro$n.txt" 2>&1 &
    sleep 1
    collega_indirizzo || { nota "giro $n: Collega a mano non riesce"; return; }
    inizio=$(date +%s)
    fine=$(( inizio + attesa + 30 ))
    while [ "$(date +%s)" -lt "$fine" ]; do
        stato=$(stato_computer)
        if c_e_testo "Collegamento non confermato"; then visto_errore=si; break; fi
        if [ "$visto_codice" = no ] && c_e_testo "Conferma sul computer"; then
            visto_codice=si
            passo "giro $n: «Conferma sul computer» dopo $(( $(date +%s) - inizio )) s (computer: $stato, codice $(codice_computer))"
            schermata "giro$n-conferma"
        fi
        [ "$stato" = video ] && break
        sleep 0.5
    done
    passo "giro $n: dopo $(( $(date +%s) - inizio )) s computer «$(stato_computer)», codice visto: $visto_codice, errore: $visto_errore"
    sed 's/^/        computer: /' "$CF/eventi.log" | tail -n 12 | tee -a "$USCITA/passi.log" >&2
    sleep 2
    sudo -n pkill -f "tcpdump -i any" 2>/dev/null
    sed "s/^/        tcp: /" "$USCITA/tcp-giro$n.txt" | head -20 | tee -a "$USCITA/passi.log" >&2
    if [ "$visto_errore" = si ] || [ "$(stato_computer)" != video ]; then
        nota "giro $n (attesa $attesa s): NON in onda; codice visto $visto_codice, «non confermato» $visto_errore"
        schermata "giro$n-errore"
        # Cosa faceva la rete del telefono intanto (il logcat-app.txt tiene solo le righe con il nome dell'app).
        adb logcat -d -v threadtime 2>/dev/null | grep -E -i "ConnectivityService|NetworkMonitor|netd|destroy|WifiClientModeImpl|WifiConnectivityManager|DhcpClient|NetworkAgent|linger|webcamlr" \
            | grep -v -E "BillingClient|EGL_emulation|mediapipe|\tat " | tail -n 400 > "$USCITA/rete-giro$n.txt"
        passo "giro $n: righe di rete del logcat in rete-giro$n.txt ($(wc -l < "$USCITA/rete-giro$n.txt"))"
        testi_visibili
        registro_telefono
    else
        nota "giro $n (attesa $attesa s): in onda; codice visto prima del consenso: $visto_codice"
    fi
    chiudi_app
    ferma_computer_finto
    # Un computer «nuovo» a ogni giro: senza identità il telefono nuovo deve chiedere di nuovo il codice.
    rm -f "$CF/identita.key"
    mv "$CF/eventi.log" "$CF/eventi-giro$n.log" 2>/dev/null
}

for g in 1 2 3 4 5; do t08_giro $g 10; done
t08_giro 6 5
t08_giro 7 20
