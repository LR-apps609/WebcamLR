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
    attendi_testo "Salta" 30 || { nota "giro $n: niente presentazione"; return; }
    tocca_testo "Salta"
    tocca_testo "Inizia"
    attendi_testo "Impostazioni" 20 || { nota "giro $n: niente schermata principale"; return; }
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
    if [ "$visto_errore" = si ] || [ "$(stato_computer)" != video ]; then
        nota "giro $n (attesa $attesa s): NON in onda; codice visto $visto_codice, «non confermato» $visto_errore"
        schermata "giro$n-errore"
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

t08_giro 1 10
t08_giro 2 10
t08_giro 3 6
t08_giro 4 15
t08_giro 5 10
