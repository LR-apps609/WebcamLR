# Copione di fumo: primo avvio pulito e una fotografia (schermata + albero) di ogni schermata raggiungibile senza
# computer. Le funzioni sono in ../lib.sh (già caricata da esegui.sh).

cancella_dati_app
lingua_italiana
avvia_app

# --- Presentazione: quattro pagine, l'ultima chiede i permessi.
attendi_testo "Il tuo telefono diventa la webcam" 30 || fallisci "la presentazione non compare al primo avvio"
schermata "presentazione-1-webcam"
tocca_testo "Avanti" || fallisci "manca «Avanti» nella pagina 1"
attendi_testo "Scarica WebcamLR sul computer" || fallisci "pagina 2 della presentazione non raggiunta"
schermata "presentazione-2-computer"
tocca_testo "Avanti" || fallisci "manca «Avanti» nella pagina 2"
attendi_testo "Le impostazioni extra sono sul computer" || fallisci "pagina 3 della presentazione non raggiunta"
schermata "presentazione-3-impostazioni"
tocca_testo "Avanti" || fallisci "manca «Avanti» nella pagina 3"
attendi_testo "Goditi l'esperienza" || fallisci "pagina dei permessi non raggiunta"
schermata "presentazione-4-permessi"
testi_visibili

# --- I dialoghi di sistema dei permessi (fotocamera, microfono, notifiche): si fotografano e si consentono.
tocca_testo "Inizia" || fallisci "manca «Inizia»"
for permesso in 1 2 3; do
    attendi_id "permission_message" 8 || break
    schermata "permesso-sistema-$permesso"
    consenti_dialogo || break
done

# --- Schermata principale: la ricerca del computer, poi (senza computer) «Non trovo nessun computer».
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare dopo i permessi"
schermata "principale-ricerca"
testi_visibili
if attendi_testo "Non trovo nessun computer" 40; then
    schermata "principale-non-trovo"
else
    nota "dopo 40 secondi senza computer non compare «Non trovo nessun computer»"
    schermata "principale-dopo-40s"
fi
scorri_giu
schermata "principale-in-fondo"
scorri_su

# --- I dialoghi della schermata principale.
if tocca_testo "Usa il cavo USB"; then
    schermata "dialogo-cavo-usb"
    tocca_testo "Chiudi" || indietro
fi
if tocca_testo "Collega a mano (indirizzo)"; then
    schermata "dialogo-indirizzo"
    tocca_testo "Annulla" || indietro
fi
scorri_su

# --- Lettore QR (fotocamera emulata).
if tocca_testo "Inquadra il QR code del computer"; then
    attendi 3
    schermata "lettore-qr"
    indietro
fi

# --- Impostazioni.
attendi_testo "Impostazioni" 10
tocca_testo "Impostazioni" || fallisci "non si apre Impostazioni"
attendi_testo "Fotocamera" || nota "Impostazioni: non vedo la sezione «Fotocamera»"
schermata "impostazioni-1"
scorri_giu
schermata "impostazioni-2"
scorri_giu
schermata "impostazioni-3"
if tocca_testo "Registro del collegamento"; then
    schermata "impostazioni-registro"
    indietro
fi
indietro

# --- App e assistenza (icona «?» in cima), WebcamLR Pro, domande, guida, segnala.
tocca_testo "App e assistenza" || fallisci "non si apre App e assistenza"
attendi_testo "Domande frequenti" || nota "App e assistenza: non vedo «Domande frequenti»"
schermata "app-1"
scorri_giu
schermata "app-2"
scorri_su; scorri_su
if tocca_testo "1080p, 4K, 60 fps"; then
    attendi 2
    schermata "pro-1"
    scorri_giu
    schermata "pro-2"
    indietro
else
    nota "App e assistenza: la riga di WebcamLR Pro non si tocca"
fi
if tocca_testo "Guida"; then
    schermata "guida-1"
    scorri_giu
    schermata "guida-2"
    indietro
fi
if tocca_testo "Domande frequenti"; then
    schermata "domande-frequenti"
    indietro
fi
if tocca_testo "Segnala un bug"; then
    schermata "segnala-bug"
    indietro
fi
indietro

# --- In orizzontale.
attendi_testo "Impostazioni" 10
ruota orizzontale
schermata "principale-orizzontale"
ruota verticale

attendi_testo "Impostazioni" 10 || fallisci "la schermata principale non torna dopo la rotazione"
schermata "fine"
