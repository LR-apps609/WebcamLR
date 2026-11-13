# Copione t08 «computer che sparisce»: è il computer a cadere (il suo Wi-Fi), il telefono ha rete. Breve (10 s,
# --interrompi-dopo/--pausa), lunga (computer spento di colpo 70 s), poi un computer che rifiuta il telefono.
source "$(dirname "${BASH_SOURCE[0]}")/t08_comune.inc"

avvia_computer_finto --nome "PC di Luca" --interrompi-dopo 20 --pausa 10 || fallisci "il computer finto non parte"
t08_in_onda
prima=$(collegamenti_computer)
# L'interruzione arriva 20 s dopo il primo video: la si aspetta e si guarda.
for i in $(seq 1 40); do grep -q INTERROMPO "$CF/eventi.log" && break; sleep 1; done
schermata "pc-caduto"; testi_visibili
attendi 6
schermata "pc-caduto-6s"; testi_visibili
t08_ritorno "$prima" 90 "computer irraggiungibile 10 s"
attendi 8

# --- Computer spento di colpo (processo ucciso, niente «arrivederci»), riacceso dopo 70 s con la stessa identità.
prima=0
kill -KILL "$(cat "$CF/pid")" 2>/dev/null; rm -f "$CF/pid"
passo "COMPUTER FINTO ucciso di colpo"
t08_guarda "pc-spento" 68
mv "$CF/eventi.log" "$CF/eventi-1.log"
avvia_computer_finto --nome "PC di Luca" || fallisci "il computer finto non riparte"
t08_ritorno "$prima" 120 "computer spento 70 s e riacceso"
schermata "pc-riacceso"; testi_visibili
attendi 5

# --- Computer che rifiuta (risponde «arrivederci» a ogni telefono): si riavvia con --rifiuta, il telefono lo conosce.
mv "$CF/eventi.log" "$CF/eventi-2.log"
kill -KILL "$(cat "$CF/pid")" 2>/dev/null; rm -f "$CF/pid"
avvia_computer_finto --nome "PC di Luca" --rifiuta || fallisci "il computer finto non riparte con --rifiuta"
t08_guarda "rifiuta" 40
grep -E "RIFIUT|CONNESSIONE|CHIUSA" "$CF/eventi.log" | sed 's/^/        computer: /' | tee -a "$USCITA/passi.log" >&2
t08_risveglia
schermata "rifiuta-fine"; testi_visibili
registro_telefono
