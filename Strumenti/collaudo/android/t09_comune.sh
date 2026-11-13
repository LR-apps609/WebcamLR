# Funzioni comuni ai copioni t09_* (collaudo-20, tester t09: testo grande, schermo piccolo, orizzontale).
# Si carica dai copioni con: source "$_CARTELLA_LIB/t09_comune.sh"

# telefono_piccolo_testo_grande [scala=2.0]: 720x1280 a 320 dpi (360x640 dp, un telefono piccolo) e carattere grande.
telefono_piccolo_testo_grande() {
    adb_sh wm size 720x1280; adb_sh wm density 320
    adb_sh settings put system font_scale "${1:-2.0}"
    passo "TELEFONO PICCOLO 720x1280 @320dpi, carattere ${1:-2.0}x"
    sleep 3
    # Il cambio di densità fa andare in ANR il Pixel Launcher per un po': si aspetta che si calmi.
    sistema_calmo 90
}

# Le righe di testo dell'ultimo albero salvato, per capire se lo scorrimento ha cambiato qualcosa.
_t09_impronta() {
    local f
    f=$(ls -t "$USCITA"/albero/*.xml 2>/dev/null | grep -v prima-di | head -1)
    [ -n "$f" ] && python3 -I "$_NODO" "$f" elenca | md5sum | cut -c1-12
}

# giro <nome> [massimo=6]: fotografa, poi scorre giù e fotografa finché la schermata cambia; alla fine torna su.
giro() {
    local nome="$1" massimo="${2:-6}" i=1 prima ora
    schermata "$nome-1"
    testi_visibili
    prima=$(_t09_impronta)
    while [ "$i" -lt "$massimo" ]; do
        i=$((i + 1))
        _scorri giu
        schermata "$nome-$i"
        ora=$(_t09_impronta)
        if [ "$ora" = "$prima" ]; then passo "GIRO $nome: fine dello scorrimento dopo $((i - 1)) schermate"; break; fi
        prima="$ora"
    done
    local j
    for j in $(seq 1 "$i"); do _scorri su; done
}

# alla_principale: torna indietro finché non si vede l'ingranaggio «Impostazioni» della schermata principale.
alla_principale() {
    local k
    for k in 1 2 3 4; do
        c_e_testo "Collega a mano (indirizzo)" && return 0
        c_e_testo "Inquadra il QR code del computer" && return 0
        indietro
    done
    avvia_app
}

# giro_completo <prefisso>: presentazione già passata; principale, dialoghi, QR, Impostazioni, App, Pro, Segnala.
giro_completo() {
    local p="$1"
    attendi_testo "Impostazioni" 20 || nota "$p: non vedo «Impostazioni» nella schermata principale"
    attendi_testo "Non trovo nessun computer" 30 || true
    giro "$p-principale" 6
    if tocca_testo "Collega a mano (indirizzo)"; then
        attendi 1
        schermata "$p-collega-a-mano"
        testi_visibili
        tocca_classe android.widget.EditText && { attendi 1; schermata "$p-collega-a-mano-tastiera"; testi_visibili; indietro; attendi 1; }
        schermata "$p-collega-a-mano-dopo-indietro"
        if c_e_testo "Annulla"; then tocca_testo "Annulla"; else indietro; c_e_testo "Annulla" && tocca_testo "Annulla"; fi
    else
        nota "$p: «Collega a mano (indirizzo)» non raggiungibile"
    fi
    alla_principale
    if tocca_testo "Usa il cavo USB"; then
        attendi 1
        giro "$p-dialogo-cavo" 4
        tocca_testo "Chiudi" || indietro
    fi
    alla_principale
    if tocca_testo "Mandami il link per il computer"; then
        attendi 2
        schermata "$p-manda-link"
        indietro
    fi
    alla_principale
    if tocca_testo "Inquadra il QR code del computer"; then
        attendi 3
        schermata "$p-lettore-qr"
        testi_visibili
        indietro
    fi
    alla_principale
    if tocca_testo "Impostazioni"; then
        attendi 1
        giro "$p-impostazioni" 12
        if tocca_testo "Qualità"; then attendi 1; schermata "$p-impostazioni-qualita"; indietro; fi
        if tocca_testo "Segnala un bug"; then
            attendi 1
            giro "$p-segnala" 5
            tocca_classe android.widget.EditText && {
                scrivi "Il testo grande non si legge bene nella schermata principale"
                attendi 1
                indietro   # chiude la tastiera
                giro "$p-segnala-scritto" 5
            }
            indietro
        fi
        indietro
    else
        nota "$p: ingranaggio «Impostazioni» non raggiungibile"
    fi
    alla_principale
    if tocca_testo "App e assistenza"; then
        attendi 1
        giro "$p-app" 8
        if tocca_testo "1080p, 4K, 60 fps"; then
            attendi 2
            giro "$p-pro" 6
            indietro
        else
            nota "$p: riga WebcamLR Pro non raggiungibile in App e assistenza"
        fi
        if tocca_testo "Domande frequenti"; then attendi 1; giro "$p-domande" 4; indietro; fi
        indietro
    fi
    alla_principale
    if tocca_testo "Sblocca"; then attendi 2; schermata "$p-pro-dalla-principale"; indietro; fi
}

# presentazione <prefisso>: le quattro pagine, fotografate e scorse, poi «Inizia» e i permessi.
presentazione() {
    local p="$1" pag
    attendi_testo "Il tuo telefono diventa la webcam" 30 || nota "$p: la presentazione non compare"
    for pag in 1 2 3; do
        giro "$p-presentazione-$pag" 4
        tocca_testo "Avanti" || { nota "$p: «Avanti» non raggiungibile nella pagina $pag"; break; }
        attendi 1
    done
    giro "$p-presentazione-4" 4
    tocca_testo "Inizia" || nota "$p: «Inizia» non raggiungibile"
    local k
    for k in 1 2 3; do attendi_id "permission_message" 8 || break; consenti_dialogo || break; done
}

# segnala_da_app <prefisso>: «App e assistenza› Segnala un bug», scrive una descrizione, fotografa e torna indietro.
segnala_da_app() {
    local p="$1"
    alla_principale
    tocca_testo "App e assistenza" || { nota "$p: «App e assistenza» non raggiungibile"; return 1; }
    attendi 1
    if tocca_testo "Segnala un bug"; then
        attendi 1
        giro "$p-segnala" 6
        if tocca_classe android.widget.EditText; then
            attendi 1
            schermata "$p-segnala-tastiera"
            scrivi "Con il testo grande la schermata principale non mostra le impostazioni"
            attendi 1
            schermata "$p-segnala-scritto-tastiera"
            indietro
            giro "$p-segnala-scritto" 6
        fi
        indietro
    else
        nota "$p: «Segnala un bug» non raggiungibile in App e assistenza"
    fi
    alla_principale
}
