# Copione «in onda»: il telefono si collega al computer finto con «Collega a mano» (10.0.2.2), conferma il codice,
# resta in onda 60 secondi, perde la rete per 20 secondi e si deve ricollegare da solo.

avvia_computer_finto --nome "PC di collaudo" --attesa-conferma 5 || fallisci "il computer finto non parte"
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_app
attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
tocca_testo "Salta"
tocca_testo "Inizia" || fallisci "manca «Inizia»"
attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"

# --- Collegamento a mano e codice di conferma.
collega_indirizzo || fallisci "non riesco a scrivere l'indirizzo in «Collega a mano»"
if attendi_testo "Conferma sul computer" 15; then
    schermata "conferma-codice"
    codice=$(codice_computer)
    if [ -n "$codice" ] && c_e_testo "$codice"; then
        passo "Il telefono mostra lo stesso codice del computer: $codice"
    else
        nota "il codice del computer ($codice) non si trova nella schermata del telefono"
    fi
else
    nota "nessuna schermata «Conferma sul computer» (il computer era già conosciuto?)"
fi

# --- In onda.
attendi_computer video 45 || fallisci "il computer finto non riceve il video"
attendi 3
schermata "in-onda-inizio"
testi_visibili
for secondi in 15 30 45 60; do
    attendi 15
    schermata "in-onda-${secondi}s"
done
statistiche_computer 5
fps=$(tail -n 3 "$CF/statistiche.csv" | awk -F, '{s += $5} END {if (NR) printf "%d", s / NR}')
[ "${fps:-0}" -gt 0 ] || fallisci "dopo 60 secondi il computer non riceve fotogrammi (fps ${fps:-0})"
passo "Video al computer: ${fps} fps di media negli ultimi 3 secondi"

# --- Caduta di rete sul telefono: Wi-Fi e dati spenti per 20 secondi.
prima=$(collegamenti_computer)
rete_spenta
attendi 4
schermata "rete-spenta-4s"
if attendi_testo "mi ricollego" 20; then
    schermata "rete-spenta-riconnessione"
else
    nota "con la rete spenta il telefono non mostra «…mi ricollego…»"
    schermata "rete-spenta-20s"
fi
attendi 10
rete_accesa
attendi_ricollegamento "$prima" 90 || fallisci "dopo la rete riaccesa il telefono non torna in onda da solo"
attendi 5
schermata "ricollegato"
statistiche_computer 3

# --- Scollega dal telefono: la domanda, poi la lista dei computer.
if tocca_testo "Scollega"; then
    schermata "domanda-scollega"
    tocca_testo "Scollega"
    attendi_testo "Impostazioni" 15 || nota "dopo «Scollega» non torna la schermata principale"
    schermata "dopo-scollega"
else
    nota "in onda non trovo «Scollega»"
fi
ferma_computer_finto
salvati=$(ls "$CF/fotogrammi"/*.png 2>/dev/null | wc -l)
passo "Fotogrammi decodificati dal computer finto: $salvati"
