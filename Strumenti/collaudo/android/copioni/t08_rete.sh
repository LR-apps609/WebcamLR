# Copione t08 «rete del telefono»: Luca è in riunione con un Wi-Fi pessimo. Cadute brevi (5 s), medie (15 s),
# ripetute (3 da 3 s), lunga (60 s) del Wi-Fi del telefono mentre è in onda: cosa mostra e quanto ci mette a tornare.
source "$(dirname "${BASH_SOURCE[0]}")/t08_comune.inc"

avvia_computer_finto --nome "PC di Luca" || fallisci "il computer finto non parte"
t08_in_onda
schermata "in-onda"
testi_visibili

# --- Caduta breve: 5 secondi.
prima=$(collegamenti_computer)
rete_spenta
schermata "breve-spenta"; testi_visibili
attendi 3
rete_accesa
t08_ritorno "$prima" 90 "caduta breve 5 s"
schermata "breve-tornato"; testi_visibili
attendi 10

# --- Caduta media: 15 secondi, con lo schermo acceso (tocco prima).
t08_risveglia
prima=$(collegamenti_computer)
rete_spenta
t08_guarda "media" 13
rete_accesa
t08_ritorno "$prima" 90 "caduta media 15 s"
schermata "media-tornato"; testi_visibili
attendi 10

# --- Cadute ripetute: 3 volte 3 s spenta / 4 s accesa.
prima=$(collegamenti_computer)
for i in 1 2 3; do
    rete_spenta; attendi 1
    rete_accesa; attendi 1
done
schermata "ripetute-dopo"; testi_visibili
t08_ritorno "$prima" 90 "tre cadute ripetute"
schermata "ripetute-tornato"; testi_visibili
attendi 10

# --- Caduta lunga: 60 secondi.
t08_risveglia
prima=$(collegamenti_computer)
rete_spenta
t08_guarda "lunga" 58
rete_accesa
t08_ritorno "$prima" 120 "caduta lunga 60 s"
schermata "lunga-tornato"; testi_visibili
statistiche_computer 5
grep -E "CHIUSA|COLLEGATO|INTERROMPO|RIFIUT|ASCOLTO" "$CF/eventi.log" | sed 's/^/        computer: /' | tee -a "$USCITA/passi.log" >&2
registro_telefono
