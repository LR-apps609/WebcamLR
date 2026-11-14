# t19 · Emma (inglese): tutte le schermate senza computer con la lingua di sistema inglese.
source "$(dirname "${BASH_SOURCE[0]}")/t19_comune.inc"

cancella_dati_app
t19_lingua_sistema
avvia_app
attendi_testo "Skip" 30 || fallisci "la presentazione non compare in inglese"
schermata "presentazione-1"
testi_visibili
for p in 2 3 4; do tocca_testo "Next" || break; attendi 1; schermata "presentazione-$p"; testi_visibili; done
tocca_testo "Start" || fallisci "manca «Start»"
for permesso in 1 2 3; do
    attendi_id "permission_message" 8 || break
    schermata "permesso-$permesso"
    consenti_dialogo || break
done
attendi_testo "Settings" 20 || fallisci "niente schermata principale"
schermata "principale-cerco"
testi_visibili
attendi_testo "find any computer" 40 || attendi_testo "No computer" 5
giro "principale" 4

if tocca_testo "More answers in the FAQ"; then attendi 1; giro "faq-da-principale" 3; indietro; fi
if tocca_testo "Use the USB cable"; then
    attendi 1; giro "cavo" 3
    if tocca_testo "How it works"; then attendi 1; giro "cavo-come-funziona" 4; indietro; fi
    tocca_testo "Close" || indietro
fi
if tocca_testo "Connect manually (address)"; then
    attendi 1; schermata "indirizzo"
    tocca_classe android.widget.EditText; scrivi "abc"; tocca_testo "Connect"; attendi 2
    schermata "indirizzo-sbagliato"; testi_visibili
    tocca_testo "Cancel" || indietro
fi
t19_torna
if tocca_testo "Connect manually (address)"; then
    tocca_classe android.widget.EditText; svuota_campo; scrivi "10.0.2.2:5999"; tocca_testo "Connect"
    attendi 3; schermata "indirizzo-chiuso-3s"; attendi 12; schermata "indirizzo-chiuso-15s"; testi_visibili
fi
t19_torna
if tocca_testo "Send me the link for the computer"; then attendi 2; schermata "mandami-link"; testi_visibili; indietro; fi
t19_torna
if tocca_testo "Scan the computer’s QR code" || tocca_testo "QR code"; then attendi 3; schermata "lettore-qr"; testi_visibili; indietro; fi
t19_torna

# Rete spenta sulla schermata principale.
rete_spenta; attendi 6; schermata "principale-senza-rete"; testi_visibili; rete_accesa; attendi 3
t19_torna

# Impostazioni.
tocca_testo "Settings" || fallisci "Settings non si apre"
attendi 1
giro "impostazioni" 10
if tocca_testo "Quality"; then attendi 1; giro "qualita" 3; indietro; fi
if tocca_testo "Language"; then attendi 2; giro "lingua" 3; indietro; attendi 1; fi
c_e_testo "Connection log" || t19_lingua_sistema
if tocca_testo "Connection log"; then attendi 1; giro "registro" 3; indietro; fi
indietro; attendi 1
t19_torna

# App e assistenza.
tocca_testo "App and support" || fallisci "App and support non si apre"
attendi 1
giro "app" 5
if tocca_testo "1080p, 4K, 60 fps"; then attendi 4; giro "pro" 4; indietro; fi
if tocca_testo "Guide"; then attendi 1; giro "guida" 8; indietro; fi
if tocca_testo "FAQ"; then
    attendi 1; giro "faq" 10
    tocca_testo "The phone can’t find the computer" && { attendi 1; schermata "faq-aperta"; testi_visibili; }
    indietro
fi
if tocca_testo "Report a bug"; then
    attendi 1; giro "segnala" 3
    tocca_classe android.widget.EditText; scrivi "The video freezes after a minute"; attendi 1
    schermata "segnala-scritto"
    tocca_testo "Send the report"; attendi 3; schermata "segnala-inviato"; testi_visibili
    indietro; attendi 1
fi
t19_torna
tocca_testo "App and support"; attendi 1
if tocca_testo "Simulate Pro"; then attendi 2; schermata "simula-pro"; testi_visibili; fi
if tocca_testo "Privacy"; then attendi 3; schermata "privacy"; testi_visibili; indietro; fi
t19_torna
schermata "principale-con-pro"
testi_visibili
tocca_testo "Settings" && { attendi 1; giro "impostazioni-pro" 10; indietro; }
t19_torna

# Permessi negati: l'app dopo un «Don't allow».
cancella_dati_app
t19_lingua_sistema
avvia_app
attendi_testo "Skip" 30 && tocca_testo "Skip"
tocca_testo "Start"
for permesso in 1 2 3; do attendi_id "permission_message" 8 || break; rifiuta_dialogo || break; done
attendi 3
giro "permessi-negati" 3
schermata "fine"
