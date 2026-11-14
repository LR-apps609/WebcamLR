# t20 · Luisa, passo B: usa la beta 4 (telefono fidato con il computer finto, impostazioni cambiate), poi
# «adb install -r» della versione nuova sopra i dati. Il computer finto resta acceso per tutto il copione: ricorda il
# telefono come fidato (in memoria) e tiene la stessa identità. Domande: dati conservati? fidato ancora valido?
# presentazione riproposta? impostazioni migrate? un messaggio di novità?
source "$_CARTELLA_LIB/copioni/t20_comune.inc"
[ -f "$T20_APK_VECCHIO" ] || fallisci "manca l'APK della beta 4: lancia prima t20_a_compila nello stesso run"
avvia_computer_finto --nome "PC di Luisa" --attesa-conferma 4 || fallisci "il computer finto non parte"

# --- 1. La beta 4, come l'aveva Luisa.
passo "Tolgo la versione nuova e installo la beta 4"
adb uninstall "$PACCHETTO" >> "$USCITA/installazioni.txt" 2>&1
adb install "$T20_APK_VECCHIO" >> "$USCITA/installazioni.txt" 2>&1 || fallisci "la beta 4 non si installa"
t20_versione "beta 4"
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "beta 4: niente presentazione"
schermata "beta4-presentazione"
tocca_testo "Salta"
tocca_testo "Inizia"
attendi_testo "Impostazioni" 20 || fallisci "beta 4: niente schermata principale"
schermata "beta4-principale"
collega_indirizzo || fallisci "beta 4: «Collega a mano» non va"
attendi_testo "Conferma sul computer" 15 && schermata "beta4-conferma-codice"
t20_in_onda_e_scollega "beta4" || fallisci "beta 4: non va in onda con il computer finto (protocollo diverso?)"
passo "Conferme chieste dal computer finto finora: $(t20_conferme)"

# Impostazioni cambiate: griglia accesa, oscura spento, risparmio batteria spento, collegamento Wi-Fi.
tocca_testo "Impostazioni" || fallisci "beta 4: Impostazioni non si apre"
attendi 1
t20_interruttori "beta4-impostazioni-prima"
schermata "beta4-impostazioni-prima"
tocca_testo "Griglia dei terzi"
tocca_testo "Oscura lo schermo dopo 30 secondi senza tocchi"
tocca_testo "Risparmio batteria: 24 fps sotto il 20%"
tocca_testo "Wi-Fi"
attendi 1
schermata "beta4-impostazioni-cambiate"
t20_interruttori "beta4-impostazioni-cambiate"
scorri_giu
schermata "beta4-impostazioni-giu"
t20_interruttori "beta4-impostazioni-giu"
indietro
attendi 1
if tocca_testo "App e assistenza"; then
    attendi 1; schermata "beta4-app-e-assistenza"; testi_visibili
    scorri_giu; schermata "beta4-app-e-assistenza-giu"; testi_visibili
    indietro
fi
chiudi_app
t20_preferenze "beta4"
conferme_prima=$(t20_conferme)
collegamenti_prima=$(collegamenti_computer)

# --- 2. L'aggiornamento: adb install -r della versione nuova, come farebbe il Play Store.
passo "AGGIORNAMENTO: adb install -r della versione nuova"
if adb install -r "$APK" >> "$USCITA/installazioni.txt" 2>&1; then
    passo "Aggiornamento riuscito: $(tail -1 "$USCITA/installazioni.txt")"
else
    passo "install -r rifiutato: $(tail -2 "$USCITA/installazioni.txt" | tr '\n' ' ')"
    fallisci "l'aggiornamento dalla beta 4 non si installa"
fi
t20_versione "dopo l'aggiornamento"
passo "Lingua dell'app dopo l'aggiornamento: $(adb_sh cmd locale get-app-locales "$PACCHETTO" 2>&1 | tr -d '\r')"
passo "Permessi dopo l'aggiornamento: $(adb_sh dumpsys package "$PACCHETTO" | grep -E 'CAMERA|RECORD_AUDIO|POST_NOTIF' | grep granted | tr -d '\r' | sed 's/^ *//' | tr '\n' ' ')"
t20_preferenze "dopo-aggiornamento-prima-di-aprire"
avvia_app
attendi 3
schermata "nuova-primo-avvio"
testi_visibili
if c_e_testo "Salta" || c_e_testo "Il tuo telefono diventa la webcam"; then
    nota "dopo l'aggiornamento la presentazione è riproposta"
    tocca_testo "Salta"; tocca_testo "Inizia"
else
    passo "Presentazione non riproposta (giusto: l'aveva già vista)"
fi
# Collegati da solo all'ultimo computer (novità): aspetto un po' prima di collegare a mano.
for s in 5 10 15 20; do
    attendi 5
    schermata "nuova-attesa-${s}s"
    [ "$(collegamenti_computer)" -gt "$collegamenti_prima" ] && break
done
testi_visibili
if [ "$(collegamenti_computer)" -gt "$collegamenti_prima" ]; then
    passo "Dopo l'aggiornamento si è ricollegata da sola al computer di prima"
else
    nota "dopo l'aggiornamento non si ricollega da sola al computer di prima in 20 s: collego a mano"
    c_e_testo "Annulla" && tocca_testo "Annulla"
    collega_indirizzo || nota "nuova: «Collega a mano» non va"
fi
attendi_testo "Conferma sul computer" 8 && { schermata "nuova-conferma-codice"; nota "dopo l'aggiornamento il telefono mostra «Conferma sul computer»"; }
t20_in_onda_e_scollega "nuova"
conferme_dopo=$(t20_conferme)
if [ "$conferme_dopo" -gt "$conferme_prima" ]; then
    nota "dopo l'aggiornamento il computer ha chiesto di nuovo il codice: il telefono non è più fidato ($conferme_prima → $conferme_dopo)"
else
    passo "Fidato ancora valido: nessun nuovo codice dopo l'aggiornamento ($conferme_dopo conferme in tutto)"
fi
grep -E 'COLLEGATO|CONFERMA|CODICE' "$CF/eventi.log" | sed 's/^/        EVENTO /' >> "$USCITA/passi.log"

# Le impostazioni dopo l'aggiornamento.
tocca_testo "Impostazioni" && {
    attendi 1
    schermata "nuova-impostazioni"
    t20_interruttori "nuova-impostazioni"
    scorri_giu; schermata "nuova-impostazioni-giu"; t20_interruttori "nuova-impostazioni-giu"
    scorri_giu; schermata "nuova-impostazioni-giu2"; t20_interruttori "nuova-impostazioni-giu2"
    indietro
}
attendi 1
if tocca_testo "App e assistenza"; then
    attendi 1; schermata "nuova-app-e-assistenza"; testi_visibili
    scorri_giu; schermata "nuova-app-e-assistenza-giu"; testi_visibili
    indietro
fi
chiudi_app
t20_preferenze "nuova-dopo-uso"
