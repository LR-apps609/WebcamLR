# Funzioni comuni dei copioni t13 (Elena, input sbagliati). Si carica con «source».

# Primo avvio pulito fino alla schermata principale.
t13_prepara() {
    cancella_dati_app
    lingua_italiana
    permessi_concedi
    avvia_app
    attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
    # Il tocco su «Salta» a volte si perde (dialogo ANR del Pixel Launcher appena acceso): si riprova.
    local i
    for i in 1 2 3 4 5; do
        c_e_testo "Inizia" && break
        tocca_testo "Salta"
        attendi 2
    done
    tocca_testo "Inizia" || fallisci "manca «Inizia»"
    attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
}

# Torna alla schermata principale (quella con «Collega a mano (indirizzo)») da qualunque punto.
t13_torna() {
    local i
    for i in 1 2 3 4 5; do
        c_e_testo "Collega a mano (indirizzo)" && return 0
        if c_e_testo "Tocca due volte per riaccendere lo schermo"; then tocca_due_volte; continue; fi
        if c_e_testo "Torna ai computer"; then tocca_testo "Torna ai computer"; attendi 2; continue; fi
        if c_e_testo "Scollegare il telefono?"; then tocca_testo "Scollega"; attendi 2; continue; fi
        if c_e_testo "Annulla"; then tocca_testo "Annulla"; attendi 2; continue; fi
        if c_e_testo "Scollega"; then tocca_testo "Scollega"; attendi 2; continue; fi
        indietro
    done
    c_e_testo "Collega a mano (indirizzo)"
}

# Prova un indirizzo nel dialogo «Collega a mano»: $1 testo (può essere vuoto), $2 nome della schermata.
# Scrive in passi.log cosa succede: messaggio d'errore, dialogo chiuso (si collega) o altro.
t13_prova_indirizzo() {
    local testo="$1" nome="$2"
    passo "=== ELENA PROVA L'INDIRIZZO «$testo» ($nome)"
    if ! c_e_testo "Indirizzo del computer"; then
        tocca_testo "Collega a mano (indirizzo)" || { nota "$nome: non trovo «Collega a mano»"; return 1; }
        attendi 1
    fi
    tocca_classe android.widget.EditText
    svuota_campo
    [ -n "$testo" ] && scrivi "$testo"
    albero "$nome-scritto"
    tocca_testo "Collega" || invio
    attendi 2
    schermata "$nome"
    if c_e_testo "Scrivi quattro numeri"; then
        passo "ESITO «$testo»: rifiutato con «Scrivi quattro numeri separati da punti…»"
    elif c_e_testo "Indirizzo del computer"; then
        passo "ESITO «$testo»: il dialogo resta aperto SENZA messaggio"
    else
        passo "ESITO «$testo»: il dialogo si è chiuso (accettato, prova a collegarsi)"
        testi_visibili
    fi
}

# Coordinate «x y» del nodo con quel testo adesso (vuoto se non c'è).
t13_xy() {
    local f="$USCITA/.t13.xml"
    _dump "$f" || return 1
    python3 -I "$_NODO" "$f" testo "$1" 2>/dev/null
}

# Tocchi rapidi ripetuti sullo stesso punto: $1 testo, $2 quante volte, $3 pausa in secondi.
t13_tocchi_rapidi() {
    local xy comandi i
    xy=$(t13_xy "$1") || { passo "TOCCHI RAPIDI: «$1» non trovato"; return 1; }
    comandi="input tap $xy"
    for i in $(seq 2 "${2:-3}"); do comandi="$comandi; sleep ${3:-0.12}; input tap $xy"; done
    adb_sh "$comandi"
    passo "TOCCHI RAPIDI su «$1» in $xy: ${2:-3} volte a ${3:-0.12} s"
}
