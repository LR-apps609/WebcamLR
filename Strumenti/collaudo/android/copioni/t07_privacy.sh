# Collaudo t07 (Paolo, attento alla privacy): i testi sulla privacy confrontati con quello che l'app fa davvero.
#   - traffico di rete dell'app (da /proc/net, per UID) dall'avvio, in onda 60 s, a riposo, e con i lavori
#     pianificati dell'app eseguiti a forza (datatransport/Firelog di Google carica le statistiche così);
#   - nell'APK: c'è il codice di Google che manda statistiche (datatransport, Firelog/CCT, TasksStats di MediaPipe)?
#   - Domande frequenti: «privacy», «dati», «Google»;
#   - «Segnala un bug»: cosa mostra e il TESTO INTERO che parte (copiato dalla condivisione di Android).
source "$(dirname "${BASH_SOURCE[0]}")/t07_comune.inc"

# ------------------------------------------------ nell'APK
if [ -n "${APK:-}" ] && [ -f "$APK" ]; then
    for cerca in "com/google/android/datatransport" "TasksStatsProtoLogger" "TasksStatsDummyLogger" "firebaselogging" \
                 "play.googleapis.com/log" "clearcut" "com/google/mediapipe/tasks/core/logging"; do
        n=$(unzip -p "$APK" 'classes*.dex' 2>/dev/null | grep -a -c "$cerca")
        nota "APK: «$cerca» compare in $n righe dei dex"
    done
    unzip -p "$APK" 'classes*.dex' 2>/dev/null | grep -a -o -E 'https://[a-zA-Z0-9./_-]+' | sort -u | head -n 40 > "$USCITA/apk-indirizzi.txt"
    passo "APK: indirizzi https nei dex:"
    sed 's/^/        /' "$USCITA/apk-indirizzi.txt" | tee -a "$USCITA/passi.log" >&2
    unzip -p "$APK" 'classes*.dex' 2>/dev/null | grep -a -o -E 'Lcom/google/mediapipe/tasks/core/logging/[A-Za-z]+' | sort -u | tee -a "$USCITA/passi.log" >&2
else
    nota "APK non disponibile nel copione (APK=${APK:-vuoto})"
fi

avvia_computer_finto --nome "PC di Paolo Rossi" --attesa-conferma 3 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
osserva_rete_inizia
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la principale non compare"
attendi 20
schermata "principale-20s"

collega_indirizzo || fallisci "Collega a mano non riesce"
attendi_computer video 45 || fallisci "niente video al computer"
attendi 60
schermata "in-onda-60s"
# Fine della sessione: l'app chiusa e riaperta (il doppio tocco sullo schermo oscurato non sempre riesce sull'emulatore).
chiudi_app
attendi 2
avvia_app
attendi_testo "Impostazioni" 15
lavori_app
# I lavori dell'app eseguiti subito (quelli di datatransport caricherebbero le statistiche).
grep -oE "JOB #u0a[0-9]+/[0-9-]+" "$USCITA/lavori.txt" | sed 's#.*/##' | sort -u | while read -r id; do
    nota "eseguo a forza il lavoro $id: $(adb_sh cmd jobscheduler run -f "$PACCHETTO" "$id" 2>&1 | tr '\n' ' ')"
done
attendi 20

# ------------------------------------------------ Domande frequenti
tocca_testo "Impostazioni" || fallisci "manca Impostazioni"
tocca_testo "App e assistenza" || fallisci "manca App e assistenza"
schermata "app-e-assistenza"
testi_visibili
scorri_giu
schermata "app-e-assistenza-in-fondo"
testi_visibili
scorri_su
if tocca_testo "Domande frequenti"; then
    schermata "domande"
    for parola in privacy dati Google internet; do
        tocca_classe android.widget.EditText && { svuota_campo; scrivi "$parola"; }
        adb_sh input keyevent KEYCODE_ESCAPE
        attendi 1
        schermata "domande-$parola"
        testi_visibili
    done
    tocca_testo "Il mio video passa da Internet?" && { schermata "risposta-internet"; testi_visibili; scorri_giu; schermata "risposta-internet-2"; testi_visibili; }
    indietro; indietro
fi
c_e_testo "Segnala un bug" || { tocca_testo "Impostazioni"; tocca_testo "App e assistenza"; }

# ------------------------------------------------ Segnala un bug: cosa parte davvero
if tocca_testo "Segnala un bug"; then
    schermata "segnala"
    testi_visibili
    scorri_giu
    schermata "segnala-in-fondo"
    testi_visibili
    scorri_su
    tocca_classe android.widget.EditText && scrivi "Paolo prova cosa viene inviato"
    adb_sh input keyevent KEYCODE_ESCAPE
    attendi 1
    if tocca_testo "Invia la segnalazione"; then
        attendi 3
        schermata "condivisione"
        testi_visibili
        _dump "$USCITA/condivisione.xml"
        if tocca_testo "Copy"; then
            attendi 2
            indietro
            attendi 1
            schermata "dopo-copia"
            # Il testo copiato incollato nel campo della descrizione: così si legge tutto nel dump.
            tocca_classe android.widget.EditText && {
                adb_sh input keyevent KEYCODE_MOVE_END
                adb_sh input keyevent KEYCODE_ENTER
                adb_sh input keyevent 279
                attendi 2
            }
            _dump "$USCITA/campo-incollato.xml"
            python3 -I - "$USCITA/campo-incollato.xml" > "$USCITA/testo-segnalazione.txt" <<'FINE'
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).iter("node"):
    if n.get("class") == "android.widget.EditText":
        print(n.get("text"))
FINE
            passo "TESTO INTERO DELLA SEGNALAZIONE (incollato dalla condivisione):"
            sed 's/^/        | /' "$USCITA/testo-segnalazione.txt" | tee -a "$USCITA/passi.log" >&2
            schermata "segnala-con-testo-incollato"
        else
            nota "nella condivisione non trovo «Copy»"
            indietro
        fi
    fi
fi
indietro; indietro; indietro
registro_telefono

osserva_rete_ferma
lavori_app
logcat_statistiche
ferma_computer_finto
