# Copione «in onda con il QR code»: il link del QR code del computer finto (con il gettone, quindi senza codice di
# conferma) aperto come farebbe la fotocamera di sistema; 30 secondi in onda.

avvia_computer_finto --nome "PC del QR code" || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"

collega_qr || fallisci "nessun link del QR code"
attendi 2
schermata "dopo-il-qr"
attendi_computer video 45 || fallisci "con il QR code il computer finto non riceve il video"
attendi 3
schermata "qr-in-onda"
testi_visibili
attendi 25
schermata "qr-in-onda-30s"
statistiche_computer 3
ferma_computer_finto
