# Collaudo t02 (Giorgio, 62 anni): segue solo quello che dice lo schermo. Permessi consentiti, «Non trovo nessun
# computer» e le domande frequenti, il QR code, «in onda», il tasto Home e l'avviso, Scollega, chiudi e riapri; poi
# un telefono «nuovo» con la conferma del codice sul computer; infine Aiuto/Domande frequenti e Guida.

avvia_computer_finto --nome "PC di Giorgio" --attesa-conferma 12 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
carattere_grande 1.3
avvia_app
attendi_testo "Il tuo telefono diventa la webcam" 30 || fallisci "la presentazione non compare"
tocca_testo "Avanti"; tocca_testo "Avanti"; tocca_testo "Avanti"
attendi_testo "Inizia" 10 || tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
n=0
while attendi_id "permission_message" 8; do
    n=$((n + 1)); consenti_dialogo || break; [ "$n" -ge 4 ] && break
done
nota "dialoghi di sistema consentiti: $n"

# --- La schermata principale, come la vede Giorgio, e dopo un po' senza computer.
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
schermata "principale-subito"
testi_visibili
attendi 20
schermata "principale-dopo-20s"
testi_visibili
if tocca_testo "Altre risposte nelle domande frequenti"; then
    attendi 2
    schermata "aiuto-non-trovo"
    testi_visibili
    scorri_giu
    schermata "aiuto-non-trovo-2"
    indietro
    attendi 2
fi

# --- Il QR code del computer (qui: il link del QR, come lo aprirebbe la fotocamera del telefono).
collega_qr || fallisci "nessun link del QR code"
for i in 1 2 3; do attendi 1; schermata "qr-dopo-${i}s"; done
testi_visibili
attendi_computer video 45 || { schermata "qr-niente-video"; testi_visibili; fallisci "niente video al computer dal QR"; }
attendi 3
schermata "in-onda-subito"
testi_visibili
attendi 35
schermata "in-onda-35s-oscurato"
testi_visibili
tocca_due_volte
attendi 2
schermata "in-onda-riacceso"
testi_visibili

# --- Tasto Home: il video continua? cosa dice l'avviso?
home
attendi 4
adb_sh cmd statusbar expand-notifications
attendi 2
schermata "avviso-tendina"
testi_visibili
adb_sh cmd statusbar collapse
attendi 1
nota "stato del computer dopo Home: $(stato_computer)"
avvia_app
attendi 3
schermata "tornato-in-app"
testi_visibili

# --- Chiude e riapre l'app (come chi la «toglie» dalle recenti).
chiudi_app
attendi 3
nota "stato del computer dopo la chiusura: $(stato_computer)"
avvia_app
attendi 3
schermata "riaperta-3s"
testi_visibili
attendi 10
schermata "riaperta-13s"
testi_visibili
nota "stato del computer dopo la riapertura: $(stato_computer)"

# --- Scollega (se è in onda).
[ "$(stato_computer)" = video ] && { c_e_testo "Scollega" || tocca_due_volte; }
if tocca_testo "Scollega"; then
    attendi 1
    schermata "scollega-domanda"
    testi_visibili
    tocca_testo "Scollega" || indietro
    attendi 3
    schermata "dopo-scollega"
    testi_visibili
fi

# --- Un telefono «nuovo» (dati cancellati): collegamento a mano con il codice da confermare sul computer.
cancella_dati_app
permessi_concedi
avvia_app
attendi_testo "Salta" 30 && tocca_testo "Salta"
tocca_testo "Inizia"
attendi_testo "Impostazioni" 20 || fallisci "la principale non torna dopo i dati cancellati"
collega_indirizzo || nota "collegamento a mano non riuscito"
for i in 1 2 3 4; do attendi 2; schermata "conferma-${i}"; done
testi_visibili
nota "codice chiesto dal computer: $(codice_computer)"
attendi_computer video 45 || nota "dopo la conferma niente video"
attendi 3
schermata "conferma-in-onda"
[ "$(stato_computer)" = video ] && { c_e_testo "Scollega" || tocca_due_volte; }
tocca_testo "Scollega" && { attendi 1; tocca_testo "Scollega"; attendi 2; }

# --- Aiuto: App e assistenza › Domande frequenti, una risposta, la ricerca, la Guida.
attendi_testo "Impostazioni" 15
tocca_testo "App e assistenza" || fallisci "non si apre App e assistenza"
attendi 2
schermata "app-assistenza"
testi_visibili
if tocca_testo "Domande frequenti"; then
    attendi 2
    schermata "faq-1"
    testi_visibili
    scorri_giu; schermata "faq-2"; testi_visibili
    scorri_giu; schermata "faq-3"; testi_visibili
    scorri_su; scorri_su; scorri_su
    if tocca_classe android.widget.EditText; then
        scrivi "videochiamata"
        attendi 2
        schermata "faq-cerca-videochiamata"
        testi_visibili
        svuota_campo
        scrivi "permessi"
        attendi 2
        schermata "faq-cerca-permessi"
        testi_visibili
        indietro
    fi
    indietro
    attendi 1
fi
if tocca_testo "Guida"; then
    attendi 2
    schermata "guida-1"; testi_visibili
    scorri_giu; schermata "guida-2"; testi_visibili
    scorri_giu; schermata "guida-3"; testi_visibili
    indietro
fi
schermata "fine"
statistiche_computer 3
ferma_computer_finto
