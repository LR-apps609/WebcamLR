# t09 · Anna: con il carattere al 200% l'ingranaggio sparisce dalla schermata principale; qui si apre Impostazioni con
# il carattere normale e si ingrandisce il carattere DENTRO Impostazioni, per vedere quelle pagine al 200%. Poi
# «Segnala un bug» da App e assistenza, in verticale e in orizzontale.
source "$_CARTELLA_LIB/t09_comune.sh"
telefono_piccolo_testo_grande 1.0
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 && tocca_testo "Salta"
tocca_testo "Inizia"
attendi_testo "Non trovo nessun computer" 30
schermata "principale-carattere-1"
for scala in 1.15 1.3 1.5 1.8; do
    adb_sh settings put system font_scale $scala; attendi 2
    schermata "principale-carattere-$scala"
    c_e_testo "Impostazioni" && passo "Carattere $scala: ingranaggio visibile" || nota "carattere $scala: l'ingranaggio «Impostazioni» non c'è più nella schermata principale"
done
adb_sh settings put system font_scale 1.0; attendi 2
tocca_testo "Impostazioni" || fallisci "Impostazioni non si apre neanche con il carattere normale"
attendi 1
adb_sh settings put system font_scale 2.0; passo "CARATTERE 2.0 dentro Impostazioni"; attendi 3
giro "imp200" 14
if tocca_testo "Qualità"; then attendi 1; schermata "imp200-qualita"; indietro; fi
if tocca_testo "Lingua"; then attendi 1; giro "imp200-lingua" 3; indietro; fi
if tocca_testo "Registro del collegamento"; then attendi 1; giro "imp200-registro" 3; indietro; fi
if tocca_testo "Segnala un bug"; then attendi 1; giro "imp200-segnala" 5; indietro; fi
ruota orizzontale
attendi 2
giro "imp200-orizz" 16
ruota verticale
indietro
attendi 1
schermata "principale-dopo-impostazioni-200"
segnala_da_app "v"
ruota orizzontale
attendi 2
segnala_da_app "o"
