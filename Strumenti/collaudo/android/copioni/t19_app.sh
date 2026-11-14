# t19 · Emma (inglese): App and support, Pro, Guide, FAQ, Report a bug, Simulate Pro, Privacy, Language, indirizzo
# sbagliato e permessi negati, con la lingua di sistema inglese.
source "$(dirname "${BASH_SOURCE[0]}")/t19_comune.inc"

t19_app_aperta() {
    t19_torna
    tocca_testo "App and support" || { avvia_app; attendi 3; tocca_testo "App and support"; } || return 1
    attendi 2
}

t19_prepara
attendi_testo "find any computer" 40
if tocca_testo "Connect manually (address)"; then
    attendi 1; schermata "indirizzo-vuoto"; testi_visibili
    tocca_classe android.widget.EditText; scrivi "abc"; attendi 1
    tocca_testo "Connect"; attendi 2
    schermata "indirizzo-abc"; testi_visibili
    c_e_testo "Cancel" && tocca_testo "Cancel"
fi
t19_torna

t19_app_aperta || fallisci "App and support non si apre"
giro "app" 5
if tocca_testo "1080p, 4K, 60 fps"; then attendi 5; giro "pro" 5; indietro; attendi 1; fi
t19_app_aperta
if tocca_testo "Guide"; then attendi 1; giro "guida" 8; indietro; attendi 1; fi
t19_app_aperta
if tocca_testo "FAQ"; then
    attendi 1
    tocca_classe android.widget.EditText && { scrivi "xyzzy"; attendi 1; schermata "faq-nessuna"; testi_visibili; indietro; }
    indietro; attendi 1
fi
t19_app_aperta
if tocca_testo "Report a bug"; then
    attendi 1; giro "segnala" 3
    tocca_classe android.widget.EditText && { scrivi "The video freezes after a minute"; attendi 1; indietro; }
    schermata "segnala-scritto"; testi_visibili
    if tocca_testo "Send the report"; then attendi 3; schermata "segnala-condividi"; testi_visibili; indietro; attendi 1; fi
    indietro; attendi 1
fi
t19_app_aperta
scorri_giu; scorri_giu
if tocca_testo "Simulate Pro"; then attendi 2; schermata "simula-pro"; testi_visibili; fi
t19_app_aperta
if tocca_testo "Privacy"; then attendi 4; schermata "privacy"; testi_visibili; indietro; attendi 1; fi
t19_app_aperta
if tocca_testo "WebcamLR website"; then attendi 4; schermata "sito"; testi_visibili; indietro; attendi 1; fi
t19_torna
schermata "principale-con-pro"; testi_visibili
if tocca_testo "Settings"; then
    attendi 1; giro "impostazioni-pro" 10
    if tocca_testo "Language"; then attendi 3; schermata "lingua"; testi_visibili; indietro; attendi 2; fi
    t19_lingua_sistema
fi
t19_torna

# Permessi negati.
cancella_dati_app
t19_lingua_sistema
avvia_app
attendi_testo "Skip" 30 && tocca_testo "Skip"
tocca_testo "Start"
for permesso in 1 2 3; do attendi_id "permission_message" 8 || break; rifiuta_dialogo || break; done
attendi 3
giro "permessi-negati" 3
schermata "fine"
