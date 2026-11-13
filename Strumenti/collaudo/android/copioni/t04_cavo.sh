# Copione «t04_cavo» (collaudo-20, tester t04): il cavo USB con il debug USB sotto stress.
# Cavo staccato «piano» (adb forward tolto) e «di colpo» (server adb spento: adbd chiude le connessioni come quando si
# tira il cavo), riattaccato dopo 8 s e dopo 40 s, passaggio a Wi-Fi e ritorno al cavo, statistiche e registri.

riaccendi() { c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte; return 0; }

# Il logcat di esegui.sh muore con il server adb: ne riapro uno mio che continua lo stesso file.
LETTORE_MIO=""
riapri_logcat() {
    [ -n "$LETTORE_MIO" ] && kill "$LETTORE_MIO" 2>/dev/null
    adb logcat -v threadtime >> "$USCITA/logcat-completo.txt" 2>/dev/null &
    LETTORE_MIO=$!
}

# cavo_strappato: come tirare il cavo. Il server adb del computer si spegne; adbd sul telefono chiude le connessioni.
cavo_strappato() {
    adb kill-server >/dev/null 2>&1
    passo "CAVO STRAPPATO (adb kill-server)"
    STRAPPO=$(date +%s)
}
# server_adb_di_nuovo: il cavo torna fisicamente (adb rivede il telefono) ma senza forward: il «PC» deve ancora aprirlo.
server_adb_di_nuovo() {
    adb start-server >/dev/null 2>&1
    timeout 60 adb wait-for-device
    passo "ADB di nuovo collegato all'emulatore"
    riapri_logcat
}

secondi_da() { echo $(( $(date +%s) - $1 )); }

avvia_computer_finto --nome "PC di Marco" --attesa-conferma 3 --ogni 10 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
# Il «Pixel Launcher isn't responding» dell'emulatore a volte si mangia il tocco: si riprova.
for _ in 1 2 3 4; do
    c_e_testo "Inizia" && break
    tocca_testo "Salta"
    attendi 3
done
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"

# --- A. Il dialogo del cavo: cosa dice a uno che usa adb.
if tocca_testo "Usa il cavo USB"; then
    schermata "A1-dialogo-cavo"
    testi_visibili
    if tocca_testo "Oppure con il debug USB (più veloce)"; then
        schermata "A2-debug-usb"
        testi_visibili
        scorri_giu
        schermata "A3-debug-usb-sotto"
        testi_visibili
    else
        nota "nel dialogo del cavo manca «Oppure con il debug USB (più veloce)»"
    fi
    indietro
    c_e_testo "Chiudi" && tocca_testo "Chiudi"
    attendi_testo "Impostazioni" 10 || indietro
fi

# --- B. Primo collegamento dal cavo: quanto ci mette, cosa mostra.
T0=$(date +%s)
collega_cavo
if attendi_testo "Conferma sul computer" 15; then schermata "B1-conferma-codice"; fi
attendi_computer video 45 || fallisci "dal cavo il computer finto non riceve il video"
nota "B: dal forward al primo video $(secondi_da $T0) s"
attendi 6
schermata "B2-in-onda"
testi_visibili
# I dettagli: un tocco sulla pillola di stato (la descrizione contiene «PC di Marco» o «In onda»).
if tocca_testo "PC di Marco" || tocca_testo "In onda"; then
    attendi 2
    schermata "B3-dettagli"
    testi_visibili
    scorri_giu
    schermata "B4-dettagli-sotto"
    testi_visibili
    indietro
else
    nota "B: non riesco ad aprire i dettagli del collegamento"
fi
statistiche_computer 8

# --- C. Cavo tolto «piano»: solo il forward sparisce, la connessione già aperta resta?
scollega_cavo
attendi 12
riaccendi
schermata "C1-forward-tolto-12s"
nota "C: forward tolto, stato del computer «$(stato_computer)», collegamenti $(collegamenti_computer)"
statistiche_computer 3

# --- D. Cavo strappato durante «in onda» e riattaccato dopo 8 s.
PRIMA=$(collegamenti_computer)
cavo_strappato
attendi 3
server_adb_di_nuovo
riaccendi
schermata "D1-strappato-subito"
testi_visibili
nota "D: dopo lo strappo il computer è «$(stato_computer)» ($(secondi_da $STRAPPO) s)"
attendi 3
T1=$(date +%s)
collega_cavo
if attendi_ricollegamento "$PRIMA" 40; then
    nota "D: riattaccato, video di nuovo dopo $(secondi_da $T1) s dal forward ($(secondi_da $STRAPPO) s dallo strappo)"
else
    nota "D: riattaccato il cavo ma il video non torna in 40 s"
fi
attendi 4
riaccendi
schermata "D2-riattaccato"
testi_visibili
statistiche_computer 4

# --- E. Cavo strappato per 40 s (oltre i 30 s di attesa del telefono), poi riattaccato.
PRIMA=$(collegamenti_computer)
cavo_strappato
attendi 2
server_adb_di_nuovo
attendi 10
riaccendi
schermata "E1-strappato-15s"
testi_visibili
attendi 25
riaccendi
schermata "E2-strappato-40s"
testi_visibili
T2=$(date +%s)
collega_cavo
if attendi_ricollegamento "$PRIMA" 40; then
    nota "E: dopo 40 s senza cavo, riattaccato: video di nuovo dopo $(secondi_da $T2) s"
else
    nota "E: dopo 40 s senza cavo, riattaccato: il video NON torna da solo in 40 s (stato «$(stato_computer)»)"
fi
riaccendi
schermata "E3-riattaccato-dopo-40s"
testi_visibili

# Se non è tornato da solo, Marco tocca quello che l'app propone.
if [ "$(stato_computer)" != video ]; then
    for pulsante in "Riprova" "Ricollega" "Riprova ora"; do
        if c_e_testo "$pulsante"; then tocca_testo "$pulsante"; break; fi
    done
    attendi_ricollegamento "$PRIMA" 30 && nota "E: tornato dopo il tocco"
    schermata "E4-dopo-tocco"
fi

# --- F. Dal cavo al Wi-Fi: il cavo si strappa, Marco scollega e si collega dal Wi-Fi (a mano).
PRIMA=$(collegamenti_computer)
cavo_strappato
attendi 2
server_adb_di_nuovo
attendi 8
nota "F: senza cavo da 10 s, il computer è «$(stato_computer)»; sessioni Wi-Fi viste finora: $(grep -c 'via Wi-Fi' "$CF/eventi.log")"
riaccendi
schermata "F1-senza-cavo-10s"
if tocca_testo "Scollega"; then
    attendi 1
    schermata "F2-domanda-scollega"
    tocca_testo "Scollega"
fi
c_e_testo "Chiudi" && tocca_testo "Chiudi"
c_e_testo "OK" && tocca_testo "OK"
attendi_testo "Collega a mano (indirizzo)" 15 || { indietro; attendi_testo "Collega a mano (indirizzo)" 10; }
schermata "F3-lista-dopo-scollega"
testi_visibili
T3=$(date +%s)
collega_indirizzo
attendi_testo "Conferma sul computer" 10 && schermata "F4-conferma-wifi"
if attendi_ricollegamento "$PRIMA" 45; then
    nota "F: sul Wi-Fi dopo $(secondi_da $T3) s"
else
    nota "F: il Wi-Fi non parte in 45 s"
fi
attendi 4
riaccendi
schermata "F5-in-onda-wifi"
testi_visibili
statistiche_computer 4

# --- G. Ritorno al cavo mentre si è sul Wi-Fi: «cambia … quando attacchi il cavo» (collegamento_nota).
PRIMA=$(collegamenti_computer)
CAVO_PRIMA=$(grep -c 'via cavo USB' "$CF/eventi.log")
collega_cavo
attendi 25
CAVO_DOPO=$(grep -c 'via cavo USB' "$CF/eventi.log")
nota "G: cavo riattaccato sul Wi-Fi: sessioni dal cavo prima $CAVO_PRIMA, dopo 25 s $CAVO_DOPO; collegamenti $PRIMA → $(collegamenti_computer)"
riaccendi
schermata "G1-wifi-cavo-attaccato-25s"
testi_visibili
statistiche_computer 4

# --- H. I registri: telefono (Impostazioni › Registro del collegamento) e computer finto.
registro_telefono
riaccendi
schermata "H1-dopo-registro"
nota "H: eventi del computer finto:"
sed 's/^/        /' "$CF/eventi.log" >> "$USCITA/note.txt" 2>/dev/null
cp "$CF/statistiche.csv" "$USCITA/statistiche-copia.csv" 2>/dev/null
ferma_computer_finto
[ -n "$LETTORE_MIO" ] && kill "$LETTORE_MIO" 2>/dev/null
true
