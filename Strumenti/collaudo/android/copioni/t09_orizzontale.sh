# t09 · Anna: telefono piccolo con il carattere al 200%, in orizzontale (640x360 dp). Si ruota con l'app già aperta
# (ruotare prima dell'avvio, sopra il launcher, non basta). Tutte le schermate.
source "$_CARTELLA_LIB/t09_comune.sh"
telefono_piccolo_testo_grande 2.0
cancella_dati_app
lingua_italiana
avvia_app
attendi_testo "Il tuo telefono diventa la webcam" 30
ruota orizzontale
attendi 2
presentazione "o"
ruota orizzontale
giro_completo "o"
segnala_da_app "o"
