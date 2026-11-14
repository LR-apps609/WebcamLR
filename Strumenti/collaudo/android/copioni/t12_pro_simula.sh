# t12 (Roberto): «Simula Pro» (solo APK di debug) acceso e spento: pillola, righe, pagina Pro, «Ripristina acquisti»
# con Pro attivo, cosa cambia in onda con il computer finto e cosa succede togliendo Pro (anche in onda) e riaprendo.
source "$(dirname "${BASH_SOURCE[0]}")/t12_comune.inc"

avvia_computer_finto --nome "PC di Roberto" --attesa-conferma 6 || fallisci "il computer finto non parte"
t12_prepara

passo "=== APP E ASSISTENZA › Simula Pro"
tocca_testo "App e assistenza" || fallisci "manca «App e assistenza»"
attendi 1
t12_pagina "app-assistenza-prima" 2
t12_stato_pulsanti
tocca_testo "Simula Pro" || fallisci "manca «Simula Pro»"
attendi 2
schermata "app-assistenza-simula-acceso"
testi_visibili
t12_stato_pulsanti
if tocca_testo "Pro attivo: grazie"; then
    attendi 2
    t12_pagina "pro-attivo" 3
    t12_stato_pulsanti
    passo "=== «Ripristina acquisti» con Pro simulato"
    if tocca_testo "Ripristina acquisti"; then
        schermata "pro-attivo-ripristina-subito"; attendi 10
        schermata "pro-attivo-ripristina-10s"; testi_visibili
    fi
fi
t12_principale
schermata "principale-con-pro"
testi_visibili
tocca_testo "Impostazioni"; attendi 1
schermata "impostazioni-con-pro"; testi_visibili
t12_principale

# --- In onda con Pro.
passo "=== IN ONDA CON PRO"
collega_indirizzo || fallisci "non riesco a scrivere l'indirizzo"
attendi_testo "Conferma sul computer" 15 && schermata "conferma"
attendi_computer video 45 || { schermata "senza-video"; testi_visibili; fallisci "niente video al computer"; }
attendi 5
schermata "in-onda-con-pro"
testi_visibili
statistiche_computer 3
if tocca_testo "Impostazioni"; then
    attendi 1
    t12_pagina "in-onda-impostazioni-con-pro" 3
    if tocca_testo "WebcamLR Pro"; then attendi 1; schermata "in-onda-foglio-pro-con-pro"; testi_visibili; indietro; attendi 1; fi
    indietro; attendi 1
fi
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
if tocca_testo "Dettagli"; then attendi 1; schermata "in-onda-dettagli-con-pro"; testi_visibili; indietro; attendi 1; fi

# --- Tolgo Pro mentre sono in onda (Impostazioni in onda › App e assistenza).
passo "=== TOLGO PRO IN ONDA"
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
tocca_testo "Impostazioni"; attendi 1
if tocca_testo "App e assistenza"; then
    attendi 2
    schermata "in-onda-app-assistenza"
    tocca_testo "Simula Pro"; attendi 2
    schermata "in-onda-simula-spento"; t12_stato_pulsanti
    indietro; attendi 2
else
    nota "da «In onda» non trovo «App e assistenza» per togliere Pro"
    indietro
fi
attendi 5
schermata "in-onda-senza-pro"
testi_visibili
statistiche_computer 3
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
if tocca_testo "Impostazioni"; then
    attendi 1; schermata "in-onda-impostazioni-senza-pro"; testi_visibili
    if tocca_testo "WebcamLR Pro"; then attendi 3; t12_pagina "in-onda-foglio-pro-senza-pro" 3; indietro; attendi 1; fi
    indietro; attendi 1
fi
registro_telefono
c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
tocca_testo "Scollega"; attendi 2
c_e_testo "Scollegare il telefono?" && tocca_testo "Scollega"
attendi 3
t12_principale
schermata "principale-dopo-in-onda"
testi_visibili

# --- Simula Pro acceso, app chiusa e riaperta: resta? Poi «Torna all'acquisto vero».
passo "=== SIMULA PRO E RIAPERTURA"
tocca_testo "App e assistenza"; attendi 1
tocca_testo "Simula Pro"; attendi 1
schermata "simula-riacceso"; t12_stato_pulsanti
chiudi_app
avvia_app
attendi_testo "Impostazioni" 20; attendi 3
schermata "riaperta-dopo-simula"
testi_visibili
tocca_testo "App e assistenza"; attendi 1
schermata "riaperta-app-assistenza"; t12_stato_pulsanti
tocca_testo "Torna all"; attendi 2
schermata "acquisto-vero"; testi_visibili; t12_stato_pulsanti
t12_principale
schermata "principale-acquisto-vero"; testi_visibili
chiudi_app
avvia_app
attendi_testo "Impostazioni" 20; attendi 3
schermata "riaperta-dopo-acquisto-vero"; testi_visibili
