# Verifica della correzione dell'impaginazione (collaudo-20, rapporto t09 B1–B9): telefono piccolo con il carattere
# al 200%, in orizzontale e in verticale. Lo scorrimento tiene conto della rotazione: con `wm size` forzato
# `_dimensioni` dà sempre la misura verticale e in orizzontale lo swipe di lib.sh partiva fuori dallo schermo.
source "$_CARTELLA_LIB/t09_comune.sh"

_dimensioni() {
    local d
    d=$(adb_sh wm size | awk -F': ' '{d=$2} END {print d}' | tr -d '\r')
    if [ "${_rotazione:-0}" = 1 ]; then echo "${d#*x}x${d%x*}"; else echo "$d"; fi
}

avvia_computer_finto --nome "PC di Anna" --attesa-conferma 8 || nota "il computer finto non parte"
telefono_piccolo_testo_grande 2.0
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Il tuo telefono diventa la webcam" 30
# B8: presentazione in verticale (testo sotto «Salta», indirizzo intero) e in orizzontale.
giro "v-pres-1" 3
tocca_testo "Avanti"; attendi 1
giro "v-pres-2" 3
ruota orizzontale; attendi 2
giro "o-pres-2" 4
tocca_testo "Salta"; attendi 1
tocca_testo "Inizia"
sistema_calmo 30
attendi_testo "Non trovo nessun computer" 30 || true
# B1 e B2: barra in alto e pagina che scorre tutta in orizzontale.
giro "o-principale" 6
if c_e_testo "Impostazioni"; then passo "B1: ingranaggio presente"; else nota "B1: ingranaggio assente"; fi
# B4: «Collega a mano» con la tastiera, in orizzontale.
if tocca_testo "Collega a mano (indirizzo)"; then
    attendi 1
    tocca_classe android.widget.EditText && { attendi 2; schermata "o-indirizzo-tastiera"; testi_visibili; }
    if c_e_testo "Collega"; then passo "B4 o: «Collega» nell'albero con la tastiera"; else nota "B4 o: «Collega» non visibile con la tastiera"; fi
    indietro; attendi 1
    c_e_testo "Annulla" && tocca_testo "Annulla" || indietro
else
    nota "B2 o: «Collega a mano» non raggiungibile"
fi
alla_principale
# B3: dialogo del cavo in orizzontale.
if tocca_testo "Usa il cavo USB"; then attendi 1; giro "o-cavo" 5; tocca_testo "Chiudi" || indietro; fi
alla_principale
# B5: lettore QR in orizzontale.
if tocca_testo "Inquadra il QR code del computer"; then attendi 3; schermata "o-qr"; testi_visibili; indietro; attendi 1; fi
alla_principale
ruota verticale; attendi 2
# B5 in verticale e B4 in verticale.
if tocca_testo "Inquadra il QR code del computer"; then attendi 3; schermata "v-qr"; indietro; attendi 1; fi
alla_principale
if tocca_testo "Collega a mano (indirizzo)"; then
    attendi 1
    tocca_classe android.widget.EditText && { attendi 2; schermata "v-indirizzo-tastiera"; testi_visibili; }
    indietro; attendi 1
    c_e_testo "Annulla" && tocca_testo "Annulla" || indietro
fi
alla_principale
# B7 e B9: Impostazioni al 200% (riga Pro, Qualità, batteria), poi il carattere cambia con la pagina aperta.
if tocca_testo "Impostazioni"; then
    attendi 1
    giro "v-impostazioni" 10
    carattere_grande 1.0
    sistema_calmo 30
    schermata "v-impostazioni-dopo-cambio-carattere"
    if c_e_testo "WebcamLR Pro" || c_e_testo "Schermo e batteria"; then passo "B9: ancora in Impostazioni"; else nota "B9: non più in Impostazioni"; fi
    carattere_grande 2.0
    sistema_calmo 30
    schermata "v-impostazioni-di-nuovo-200"
    indietro
fi
alla_principale
# B7: dati tecnici di Segnala un bug.
if tocca_testo "App e assistenza"; then
    attendi 1
    if tocca_testo "Segnala un bug"; then attendi 1; giro "v-segnala" 6; indietro; fi
    indietro
fi
alla_principale
# B6: in onda, la pillola.
if collega_indirizzo; then
    if attendi_computer video 60; then
        attendi 3
        schermata "v-in-onda"
        testi_visibili
        if tocca_testo "Impostazioni"; then attendi 1; giro "v-in-onda-impostazioni" 4; indietro; attendi 1; fi
    else
        schermata "v-senza-video"; nota "niente video al computer"
    fi
fi
