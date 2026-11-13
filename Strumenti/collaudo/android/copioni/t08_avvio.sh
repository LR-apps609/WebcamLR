# Copione t08 «collegamento iniziale»: la rete cade mentre il telefono aspetta la conferma sul computer, e il
# telefono prova a collegarsi a mano senza rete. Cosa dice a Luca, e se riprova da solo.
source "$(dirname "${BASH_SOURCE[0]}")/t08_comune.inc"

# --- 1. Rete spenta durante «Conferma sul computer» (il computer consentirebbe dopo 25 s).
avvia_computer_finto --nome "PC di Luca" --attesa-conferma 25 || fallisci "il computer finto non parte"
cancella_dati_app; lingua_italiana; permessi_concedi; avvia_app
t08_salta_presentazione || fallisci "la schermata principale non compare"
collega_indirizzo || fallisci "Collega a mano non riesce"
attendi_testo "Conferma sul computer" 20 && schermata "conferma"
rete_spenta
t08_guarda "conferma-senza-rete" 12
rete_accesa
t08_guarda "conferma-rete-tornata" 40
nota "rete caduta durante la conferma: computer «$(stato_computer)», collegamenti $(collegamenti_computer)"
grep -E "CONNESSIONE|CODICE|CONFERMA|COLLEGATO|CHIUSA" "$CF/eventi.log" | sed 's/^/        computer: /' | tee -a "$USCITA/passi.log" >&2
registro_telefono
chiudi_app

# --- 2. Collega a mano con la rete spenta (Luca ha il Wi-Fi caduto e prova lo stesso).
rete_spenta
avvia_app
attendi_testo "Impostazioni" 20
collega_indirizzo
t08_guarda "a-mano-senza-rete" 30
rete_accesa
t08_guarda "a-mano-rete-tornata" 30
nota "a mano senza rete, poi rete tornata: computer «$(stato_computer)»"
