# Copione «cavo»: la via del cavo USB con il debug USB. Il computer finto prova ogni secondo la porta che
# «adb forward» porta alla 52741 del telefono, dove l'app ascolta quando è in primo piano.

avvia_computer_finto --nome "PC sul cavo" --attesa-conferma 4 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
schermata "principale-prima-del-cavo"

collega_cavo
if attendi_testo "Conferma sul computer" 20; then
    schermata "cavo-conferma-codice"
fi
attendi_computer video 45 || fallisci "dal cavo il computer finto non riceve il video"
attendi 5
schermata "cavo-in-onda"
testi_visibili
attendi 15
schermata "cavo-in-onda-20s"
statistiche_computer 3
grep -q "via cavo USB" "$CF/eventi.log" || nota "il computer finto non ha visto la sessione arrivare dal cavo"
ferma_computer_finto
