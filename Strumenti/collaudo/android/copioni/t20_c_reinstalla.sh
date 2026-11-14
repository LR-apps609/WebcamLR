# t20 · Luisa, passo C: disinstalla la versione nuova (con i dati del passo B) e la reinstalla. Cosa resta? Il backup
# automatico di Android? Il primo avvio è pulito? Il computer (che ricorda ancora il telefono) lo riconosce?
source "$_CARTELLA_LIB/copioni/t20_comune.inc"
avvia_computer_finto --nome "PC di Luisa" --attesa-conferma 4 || fallisci "il computer finto non parte"
t20_versione "prima della disinstallazione"
t20_preferenze "prima-della-disinstallazione"
# Se il passo B non ha girato, i dati li creo qui con la versione nuova.
if ! grep -q 'benvenutoVisto' "$USCITA/preferenze-prima-della-disinstallazione.txt"; then
    nota "nessun dato del passo B: li creo con la versione nuova"
    lingua_italiana; permessi_concedi; avvia_app
    attendi_testo "Salta" 30 && tocca_testo "Salta"; tocca_testo "Inizia"
    attendi_testo "Impostazioni" 20
    collega_indirizzo; t20_in_onda_e_scollega "prima"
    chiudi_app
fi
# Il computer ora ricorda questo telefono: lo collego una volta, così il computer finto lo ha tra i fidati.
lingua_italiana
avvia_app
attendi 3
schermata "prima-principale"
c_e_testo "Annulla" && tocca_testo "Annulla"
c_e_testo "Salta" && { tocca_testo "Salta"; tocca_testo "Inizia"; }
collega_indirizzo
attendi_testo "Conferma sul computer" 8 && schermata "prima-conferma"
t20_in_onda_e_scollega "prima"
chiudi_app
conferme_prima=$(t20_conferme)

passo "DISINSTALLAZIONE (adb uninstall)"
adb uninstall "$PACCHETTO" >> "$USCITA/installazioni.txt" 2>&1
passo "Pacchetto dopo la disinstallazione: $(adb_sh pm list packages "$PACCHETTO" | tr -d '\r')"
{
    echo "### Cosa resta sul telefono dopo la disinstallazione"
    for d in /sdcard/Android/data/$PACCHETTO /sdcard/Android/media/$PACCHETTO /sdcard/Android/obb/$PACCHETTO /data/data/$PACCHETTO; do
        echo "--- $d"; adb_sh "ls -la $d" 2>&1
    done
    echo "--- /sdcard/Movies, /sdcard/Pictures, /sdcard/DCIM, /sdcard/Download"
    adb_sh "ls -laR /sdcard/Movies /sdcard/Pictures /sdcard/DCIM /sdcard/Download" 2>&1 | head -40
    echo "--- MediaStore con WebcamLR"
    adb_sh "content query --uri content://media/external/file --projection _data --where \"_data LIKE '%WebcamLR%'\"" 2>&1 | head -20
    echo "--- backup (bmgr)"
    adb_sh "bmgr enabled" 2>&1
    adb_sh "dumpsys backup" 2>&1 | grep -i -E 'webcamlr|Backup Manager is' | head -10
    echo "--- lingua per app"
    adb_sh "cmd locale get-app-locales $PACCHETTO" 2>&1
} > "$USCITA/resti-dopo-disinstallazione.txt"
sed 's/^/        /' "$USCITA/resti-dopo-disinstallazione.txt" >> "$USCITA/passi.log"

passo "REINSTALLAZIONE (adb install)"
adb install "$APK" >> "$USCITA/installazioni.txt" 2>&1 || fallisci "la reinstallazione non riesce"
t20_versione "reinstallata"
passo "Lingua dell'app appena reinstallata (prima di lingua_italiana): $(adb_sh cmd locale get-app-locales "$PACCHETTO" 2>&1 | tr -d '\r')"
passo "Permessi appena reinstallata: $(adb_sh dumpsys package "$PACCHETTO" | grep -E 'CAMERA|RECORD_AUDIO|POST_NOTIF' | tr -d '\r' | sed 's/^ *//' | tr '\n' ' ')"
t20_preferenze "reinstallata-prima-di-aprire"
lingua_italiana
avvia_app
attendi_testo "Salta" 30 && passo "Primo avvio: presentazione di nuovo (giusto)" || nota "dopo la reinstallazione la presentazione non compare"
schermata "reinstallata-presentazione"
tocca_testo "Salta"
tocca_testo "Inizia"
for i in 1 2 3; do consenti_dialogo 6 || break; done
attendi_testo "Impostazioni" 20
schermata "reinstallata-principale"
testi_visibili
tocca_testo "Impostazioni" && {
    attendi 1; schermata "reinstallata-impostazioni"; t20_interruttori "reinstallata-impostazioni"
    scorri_giu; schermata "reinstallata-impostazioni-giu"; t20_interruttori "reinstallata-impostazioni-giu"
    indietro
}
attendi 1
if tocca_testo "App e assistenza"; then
    attendi 1; scorri_giu; schermata "reinstallata-app-e-assistenza"; testi_visibili; indietro
fi
# Il computer ricorda ancora il telefono di prima: con la reinstallazione l'identità del telefono è nuova.
collega_indirizzo
if attendi_testo "Conferma sul computer" 15; then
    schermata "reinstallata-conferma-codice"
    passo "Dopo la reinstallazione il computer chiede di nuovo il codice (identità nuova del telefono)"
fi
t20_in_onda_e_scollega "reinstallata"
passo "Conferme chieste: prima $conferme_prima, ora $(t20_conferme)"
grep -E 'COLLEGATO|CONFERMA|CODICE' "$CF/eventi.log" | sed 's/^/        EVENTO /' >> "$USCITA/passi.log"
chiudi_app
t20_preferenze "reinstallata-dopo-uso"
