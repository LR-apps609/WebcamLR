# Collaudo t07 (Paolo, attento alla privacy): nega i permessi UNO PER UNO al primo avvio e guarda cosa spiega l'app.
#   A) solo la fotocamera negata (microfono e notifiche sì), poi prova a collegarsi;
#   B) solo il microfono negato, in onda accende «Microfono al computer»;
#   C) solo le notifiche negate, in onda va alla Home: c'è un avviso? cosa dice l'app?
# Su Android 14 non c'è un permesso «rete locale» (c'è solo INTERNET, concesso all'installazione): si annota.
source "$(dirname "${BASH_SOURCE[0]}")/t07_comune.inc"

primo_avvio_negando() {
    cancella_dati_app
    lingua_italiana
    avvia_app
    attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
    tocca_testo "Salta"
    attendi_testo "Goditi l'esperienza" 10
    schermata "$1-pagina-permessi"
    tocca_testo "Inizia" || fallisci "manca «Inizia»"
    rispondi_dialoghi "$2"
    attendi 3
    schermata "$1-principale"
    testi_visibili
    avvisi_permessi "$1 principale"
    stato_permessi "$1"
}

avvia_computer_finto --nome "PC di Paolo" --attesa-conferma 3 || fallisci "il computer finto non parte"

# ------------------------------------------------ A) solo fotocamera negata
primo_avvio_negando "A" "pictures camera"
attendi 8
schermata "A-principale-dopo-10s"
avvisi_permessi "A dopo 10 s"
collega_indirizzo || nota "A: non riesco a usare «Collega a mano»"
attendi 4
schermata "A-collega"
if attendi_testo "Conferma sul computer" 10; then schermata "A-conferma"; fi
if attendi_computer video 25; then
    nota "A: con la fotocamera NEGATA il computer riceve video?! ($(stato_computer))"
else
    nota "A: con la fotocamera negata il computer non riceve video (stato $(stato_computer))"
fi
attendi 3
schermata "A-dopo-collegamento"
testi_visibili
avvisi_permessi "A dopo il collegamento"
if attendi_id "permission_message" 4; then
    schermata "A-richiesta-fotocamera"
    nota "A: collegandosi l'app richiede la fotocamera"
    rifiuta_dialogo
    attendi 2
    schermata "A-dopo-secondo-rifiuto"
    testi_visibili
fi
registro_telefono
ferma_computer_finto

# ------------------------------------------------ B) solo microfono negato
avvia_computer_finto --nome "PC di Paolo B" --attesa-conferma 3 || fallisci "il computer finto non parte (B)"
primo_avvio_negando "B" "audio"
collega_indirizzo || nota "B: non riesco a usare «Collega a mano»"
attendi_computer video 40 || nota "B: niente video al computer (stato $(stato_computer))"
attendi 3
schermata "B-in-onda"
testi_visibili
if tocca_testo "Microfono al computer"; then
    attendi 2
    schermata "B-microfono-toccato"
    testi_visibili
    if attendi_id "permission_message" 4; then
        nota "B: «Microfono al computer» richiede il permesso"
        schermata "B-richiesta-microfono"
        rifiuta_dialogo
        attendi 2
        schermata "B-dopo-rifiuto-microfono"
        testi_visibili
    fi
    avvisi_permessi "B dopo Microfono al computer"
else
    nota "B: in onda non trovo «Microfono al computer»"
fi
registro_telefono
ferma_computer_finto

# ------------------------------------------------ C) solo notifiche negate
avvia_computer_finto --nome "PC di Paolo C" --attesa-conferma 3 || fallisci "il computer finto non parte (C)"
primo_avvio_negando "C" "notifications"
collega_indirizzo || nota "C: non riesco a usare «Collega a mano»"
attendi_computer video 40 || nota "C: niente video al computer (stato $(stato_computer))"
attendi 3
schermata "C-in-onda"
testi_visibili
avvisi_permessi "C in onda"
home
attendi 5
adb_sh cmd statusbar expand-notifications
attendi 2
schermata "C-tendina-notifiche"
testi_visibili
adb_sh cmd statusbar collapse
nota "C: notifiche dell'app secondo il sistema: $(adb_sh dumpsys notification --noredact 2>/dev/null | grep -c "pkg=$PACCHETTO")"
attendi 20
nota "C: dopo 25 s alla Home il computer è «$(stato_computer)»; processo dell'app $(processo_app)"
statistiche_computer 3
avvia_app
attendi 3
schermata "C-riaperta"
testi_visibili
ferma_computer_finto
