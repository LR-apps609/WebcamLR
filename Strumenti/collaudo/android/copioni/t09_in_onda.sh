# t09 · Anna in onda: telefono piccolo, carattere al 200%, collegamento a mano, poi in verticale e in orizzontale,
# pulsanti, fogli e schermo oscurato.
source "$_CARTELLA_LIB/t09_comune.sh"
avvia_computer_finto --nome "PC di Anna" --attesa-conferma 8 || fallisci "il computer finto non parte"
telefono_piccolo_testo_grande 2.0
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 && tocca_testo "Salta"
tocca_testo "Inizia"
attendi_testo "Impostazioni" 20
collega_indirizzo || nota "non riesco a usare «Collega a mano» con il carattere al 200%"
if attendi_testo "Conferma sul computer" 15; then schermata "conferma-codice"; testi_visibili; fi
attendi_computer video 45 || { schermata "senza-video"; testi_visibili; fallisci "niente video al computer"; }
attendi 3
schermata "in-onda-verticale"
testi_visibili
for voce in "Impostazioni" "Microfono al computer" "1×"; do
    if tocca_testo "$voce"; then attendi 1; giro "in-onda-v-foglio-$voce" 4; indietro; attendi 1; fi
done
ruota orizzontale
attendi 3
schermata "in-onda-orizzontale"
testi_visibili
if tocca_testo "Impostazioni"; then attendi 1; giro "in-onda-o-foglio-impostazioni" 4; indietro; attendi 1; fi
schermata "in-onda-orizzontale-2"
attendi 32
schermata "in-onda-orizzontale-oscurato"
testi_visibili
tocca_due_volte
attendi 1
schermata "in-onda-orizzontale-riacceso"
ruota verticale
attendi 32
schermata "in-onda-verticale-oscurato"
testi_visibili
tocca_due_volte
attendi 1
if tocca_testo "Scollega"; then attendi 2; schermata "dopo-scollega"; testi_visibili; fi
