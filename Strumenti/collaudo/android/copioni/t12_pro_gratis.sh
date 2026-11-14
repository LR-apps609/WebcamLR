# t12 (Roberto): la pagina WebcamLR Pro senza Pro, sull'emulatore dove Google Play non è pronto: cosa ottiene, quanto
# costa, «Riprova», «Ripristina acquisti», le tre strade per arrivarci e cosa succede senza rete.
source "$(dirname "${BASH_SOURCE[0]}")/t12_comune.inc"

t12_prepara
schermata "principale-senza-pro"
testi_visibili

# --- 1. Dalla pillola in cima.
passo "=== ROBERTO TOCCA LA PILLOLA PRO"
t12_apri_pro_dalla_pillola || nota "la pillola «PRO · Sblocca» non apre la pagina Pro"
schermata "pro-subito"
attendi 10
t12_pagina "pro-dopo-10s" 4
t12_stato_pulsanti

passo "=== «Riprova»"
if tocca_testo "Riprova"; then
    schermata "riprova-subito"
    testi_visibili
    attendi 3
    schermata "riprova-3s"
    attendi 8
    schermata "riprova-11s"
    testi_visibili
else
    nota "nessun «Riprova» nella pagina Pro"
fi

passo "=== «Ripristina acquisti»"
if tocca_testo "Ripristina acquisti"; then
    schermata "ripristina-subito"
    testi_visibili
    attendi 3
    schermata "ripristina-3s"
    testi_visibili
    attendi 8
    schermata "ripristina-11s"
    testi_visibili
    t12_stato_pulsanti
else
    nota "nessun «Ripristina acquisti»"
fi
# Due tocchi di fila: si accavallano?
tocca_testo "Ripristina acquisti"; attendi 1; tocca_testo "Ripristina acquisti"; attendi 10
schermata "ripristina-due-volte"
testi_visibili
t12_principale

# --- 2. Dalle Impostazioni.
passo "=== IMPOSTAZIONI › WebcamLR Pro"
tocca_testo "Impostazioni"
attendi 1
schermata "impostazioni-riga-pro"
testi_visibili
if tocca_testo "WebcamLR Pro"; then attendi 2; schermata "pro-dalle-impostazioni"; testi_visibili; fi
t12_principale

# --- 3. Da App e assistenza.
passo "=== APP E ASSISTENZA › WebcamLR Pro"
tocca_testo "App e assistenza"
attendi 1
schermata "app-assistenza-riga-pro"
testi_visibili
if tocca_testo "1080p, 4K, 60 fps"; then attendi 2; schermata "pro-da-app-assistenza"; fi
t12_principale

# --- 4. Le domande frequenti su Pro.
passo "=== DOMANDE FREQUENTI su Pro"
tocca_testo "App e assistenza"
attendi 1
if tocca_testo "Domande frequenti"; then
    attendi 2
    schermata "domande"
    if tocca_classe android.widget.EditText; then
        scrivi "Pro"
        attendi 2
        adb_sh input keyevent KEYCODE_BACK; attendi 1
        t12_pagina "domande-pro" 3
        tocca_testo "ripristin" && { attendi 2; t12_pagina "domanda-ripristino" 2; indietro; }
    fi
fi
t12_principale

# --- 5. Senza rete: app riaperta offline.
passo "=== SENZA RETE"
rete_spenta
chiudi_app
avvia_app
attendi_testo "Impostazioni" 20
attendi 2
schermata "principale-offline"
t12_apri_pro_dalla_pillola
schermata "pro-offline-subito"
attendi 12
t12_pagina "pro-offline-12s" 2
if tocca_testo "Riprova"; then attendi 10; schermata "pro-offline-riprova-10s"; testi_visibili; fi
if tocca_testo "Ripristina acquisti"; then
    attendi 2; schermata "pro-offline-ripristina-2s"; testi_visibili
    attendi 9; schermata "pro-offline-ripristina-11s"; testi_visibili
fi
passo "=== RETE DI NUOVO ACCESA, pagina Pro aperta"
rete_accesa
attendi 20
schermata "pro-rete-tornata-20s"
testi_visibili
chiudi_app
