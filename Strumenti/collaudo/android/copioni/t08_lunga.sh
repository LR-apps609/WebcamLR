# Copione t08 «rete che non torna»: il Wi-Fi del telefono resta spento 4 minuti mentre è in onda. Dopo quanto il
# telefono smette di riprovare, cosa dice, e se torna da solo quando la rete torna dopo tanto tempo.
source "$(dirname "${BASH_SOURCE[0]}")/t08_comune.inc"

avvia_computer_finto --nome "PC di Luca" || fallisci "il computer finto non parte"
t08_in_onda
prima=$(collegamenti_computer)
rete_spenta
inizio=$(date +%s)
for s in 5 20 45 75 110 150 200 240; do
    while [ $(( $(date +%s) - inizio )) -lt "$s" ]; do sleep 1; done
    t08_risveglia
    schermata "senza-rete-${s}s"
    testi_visibili
done
rete_accesa
t08_ritorno "$prima" 120 "rete tornata dopo 4 minuti"
schermata "dopo-4-minuti"; testi_visibili
registro_telefono
