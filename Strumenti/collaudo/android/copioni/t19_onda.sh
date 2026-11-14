# t19 · Emma (inglese): con il computer finto. Codice di conferma, in onda, notifica, rete che cade, Scollega;
# poi un computer che rifiuta.
source "$(dirname "${BASH_SOURCE[0]}")/t19_comune.inc"

avvia_computer_finto --nome "Emma's PC" --attesa-conferma 8 || fallisci "il computer finto non parte"
t19_prepara
attendi 5
schermata "principale-con-computer"; testi_visibili
tocca_testo "Connect manually (address)" || fallisci "manca Connect manually"
tocca_classe android.widget.EditText; svuota_campo; scrivi "10.0.2.2:$(tr -d '\n' < "$CF/porta.txt" 2>/dev/null || echo 52740)"
tocca_testo "Connect" || invio
if attendi_testo "Confirm on the computer" 15; then schermata "conferma-codice"; testi_visibili; else schermata "dopo-connect"; testi_visibili; fi
attendi_computer video 45 || { schermata "senza-video"; testi_visibili; fallisci "niente video"; }
attendi 3
schermata "in-onda"; testi_visibili
t19_tendina "notifica-in-onda"
tocca_xy 540 300; attendi 1
for t in "Pause" "Mirror"; do tocca_testo "$t" && { attendi 2; schermata "in-onda-$t"; testi_visibili; tocca_testo "$t"; attendi 1; }; done
c_e_testo "Resume" && tocca_testo "Resume"
tocca_testo "Settings" && { attendi 1; giro "impostazioni-in-onda" 6; indietro; }
attendi 35
schermata "in-onda-oscurato"; testi_visibili
rete_spenta; attendi 8; schermata "rete-spenta"; testi_visibili
t19_tendina "notifica-rete-spenta"
attendi 10; rete_accesa
attendi_computer video 90; attendi 3
c_e_testo "Double-tap to turn the screen back on" && tocca_due_volte
schermata "ricollegato"; testi_visibili
if tocca_testo "Disconnect"; then attendi 1; schermata "domanda-scollega"; testi_visibili; tocca_testo "Disconnect"; attendi 3; fi
schermata "dopo-scollega"; testi_visibili
ferma_computer_finto
attendi 8
schermata "computer-spento"; testi_visibili

# Computer che rifiuta il telefono (nuovo).
avvia_computer_finto --nome "Office PC" --rifiuta || fallisci "il computer finto (rifiuta) non parte"
cancella_dati_app; t19_lingua_sistema; permessi_concedi; avvia_app
attendi_testo "Skip" 30 && tocca_testo "Skip"; tocca_testo "Start"; attendi_testo "Settings" 20
tocca_testo "Connect manually (address)"; tocca_classe android.widget.EditText; svuota_campo
scrivi "10.0.2.2:$(tr -d '\n' < "$CF/porta.txt" 2>/dev/null || echo 52740)"; tocca_testo "Connect" || invio
attendi 6; schermata "rifiutato-6s"; testi_visibili
attendi 10; schermata "rifiutato-16s"; testi_visibili
ferma_computer_finto
