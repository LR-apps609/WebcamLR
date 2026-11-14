# Collaudo t17 (Chiara, podcaster): il microfono del telefono verso il computer.
# A) permesso del microfono negato alla presentazione: Impostazioni, «Microfono al computer» in onda, il computer che
#    chiede l'audio; B) permesso concesso: il computer chiede l'audio e poi lo spegne, il pulsante sul telefono lo
#    riaccende e lo rispegne; cosa riceve il computer finto (eventi.log, audio.aac, volume con ffmpeg).

eventi_audio() {
    passo "EVENTI AUDIO del computer finto ($1):"
    grep -E "CAPACIT|STATO audio|FORMATO-AUDIO|AUDIO|COMANDO audio|COLLEGATO|CHIUSA" "$CF/eventi.log" 2>/dev/null | tail -n 25 | sed 's/^/        /' | tee -a "$USCITA/passi.log" >&2
}
sveglia() { c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte; return 0; }
volume_audio() {
    if [ -s "$CF/audio.aac" ] && command -v ffmpeg >/dev/null 2>&1; then
        passo "AUDIO RICEVUTO: $(stat -c %s "$CF/audio.aac") byte; volume:"
        ffmpeg -hide_banner -nostats -i "$CF/audio.aac" -af volumedetect -f null - 2>&1 | grep -E "Duration|Stream|mean_volume|max_volume|Error|error" | sed 's/^/        /' | tee -a "$USCITA/passi.log" >&2
    else
        passo "AUDIO RICEVUTO: nessun file audio.aac (o niente ffmpeg)"
    fi
}

# ================================================================ A) permesso negato
avvia_computer_finto --nome "PC di Chiara" --chiedi-audio 10 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
schermata "a-presentazione"
# Le pagine della presentazione: cerco quella dei permessi (testo del microfono).
for i in 1 2 3; do
    c_e_testo "microfono" && { schermata "a-presentazione-microfono"; testi_visibili; }
    tocca_testo "Avanti" || break
    attendi 1
done
schermata "a-presentazione-ultima"
testi_visibili
tocca_testo "Inizia" || fallisci "manca «Inizia»"
# Dialoghi di sistema: fotocamera sì, microfono no, notifiche sì (l'ordine lo decide l'app: leggo il testo).
for i in 1 2 3; do
    attendi 2
    f="$USCITA/.dialogo.xml"
    if _dump "$f" && grep -qi "record audio\|microphone" "$f"; then
        schermata "a-dialogo-microfono"
        rifiuta_dialogo 5
    elif grep -qi "camera\|photos" "$f" 2>/dev/null && grep -qi "permission_" "$f"; then
        consenti_dialogo 5
    elif grep -qi "permission_" "$f" 2>/dev/null; then
        consenti_dialogo 5
    fi
done
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
passo "PERMESSO MICROFONO ora: $(adb_sh dumpsys package "$PACCHETTO" | grep -A0 'RECORD_AUDIO' | head -3 | tr -s ' ')"
schermata "a-principale"

# Impostazioni: c'è qualcosa sul microfono?
tocca_testo "Impostazioni"
attendi 1
schermata "a-impostazioni-1"
testi_visibili
for i in 1 2 3 4; do scorri_giu; attendi 1; schermata "a-impostazioni-giu-$i"; testi_visibili; done
indietro
attendi 1

collega_qr || fallisci "nessun link del QR code"
attendi_computer video 45 || { schermata "a-senza-video"; testi_visibili; fallisci "il computer finto non riceve il video"; }
attendi 3
schermata "a-in-onda"
testi_visibili
# Il computer chiede l'audio dopo 10 s (--chiedi-audio): cosa fa il telefono senza permesso?
attendi 10
sveglia
schermata "a-dopo-comando-audio-del-computer"
testi_visibili
eventi_audio "permesso negato, dopo comando audio"
# Tocco «Microfono al computer» sul telefono.
sveglia
if tocca_testo "Microfono al computer"; then
    attendi 2
    schermata "a-tocco-microfono-negato"
    testi_visibili
    attendi 4
    schermata "a-tocco-microfono-negato-6s"
else
    nota "in onda non trovo «Microfono al computer»"
    schermata "a-senza-pulsante-microfono"
fi
eventi_audio "permesso negato, dopo il tocco"
registro_telefono
ferma_computer_finto
chiudi_app

# ================================================================ B) permesso concesso
permessi_concedi
avvia_computer_finto --nome "PC di Chiara" --chiedi-audio 8 --spegni-audio 35 || fallisci "il computer finto non riparte"
avvia_app
attendi 3
schermata "b-avvio"
c_e_testo "Salta" && tocca_testo "Salta" && tocca_testo "Inizia"
attendi_testo "Impostazioni" 20
collega_qr || fallisci "nessun link del QR code (B)"
attendi_computer video 45 || { schermata "b-senza-video"; testi_visibili; fallisci "B: il computer finto non riceve il video"; }
attendi 3
schermata "b-in-onda-prima-dell-audio"
eventi_audio "B, prima del comando"
attendi 12
sveglia
schermata "b-audio-chiesto-dal-computer"
testi_visibili
eventi_audio "B, 12 s dopo il comando audio vero"
statistiche_computer 4
attendi 20
eventi_audio "B, dopo comando audio falso"
sveglia
schermata "b-audio-spento-dal-computer"
statistiche_computer 3
# Riaccendo dal telefono.
sveglia
tocca_testo "Microfono al computer" || nota "B: non trovo «Microfono al computer»"
attendi 8
schermata "b-audio-acceso-dal-telefono"
testi_visibili
eventi_audio "B, acceso dal telefono"
statistiche_computer 3
# Rete che cade con il microfono acceso: l'audio riprende da solo?
prima=$(collegamenti_computer)
rete_spenta
attendi 12
rete_accesa
attendi_ricollegamento "$prima" 40 || nota "B: dopo la rete il telefono non si ricollega in 40 s"
attendi 8
sveglia
schermata "b-dopo-la-rete"
eventi_audio "B, dopo la rete"
statistiche_computer 3
# Spengo dal telefono.
sveglia
tocca_testo "Microfono al computer" || true
attendi 4
schermata "b-audio-spento-dal-telefono"
eventi_audio "B, spento dal telefono"
volume_audio
registro_telefono
# Inglese: il pulsante e il registro.
lingua_inglese
attendi 3
sveglia
schermata "b-inglese-in-onda"
testi_visibili
lingua_italiana
ferma_computer_finto
eventi_audio "fine"
