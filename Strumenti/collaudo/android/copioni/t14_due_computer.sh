# Copione t14 (famiglia con un PC e un portatile sulla stessa rete): DUE computer finti accesi insieme, su porte e con
# nomi diversi. Quale sceglie il telefono, passaggio dall'uno all'altro (QR dell'altro mentre si è in onda), un computer
# che rifiuta, cosa resta tra i computer conosciuti e a chi si ricollega da solo riaprendo l'app.
source "$(dirname "${BASH_SOURCE[0]}")/t08_comune.inc"

# ---- il secondo computer finto (stesso programma, cartella, porta e cavo suoi)
CF2="$USCITA/computer-finto-2"
PORTA2=52750
avvia_pc2() {
    ferma_pc2 >/dev/null 2>&1
    mkdir -p "$CF2"
    rm -f "$CF2/collegamento.txt" "$CF2/stato.txt"
    dotnet "$COMPUTER_FINTO" --uscita "$CF2" --porta "$PORTA2" --cavo 52810 --massimo-video 2 "$@" >> "$CF2/console.txt" 2>&1 </dev/null &
    echo $! > "$CF2/pid"
    local i
    for i in $(seq 1 30); do [ -s "$CF2/collegamento.txt" ] && break; sleep 1; done
    [ -s "$CF2/collegamento.txt" ] || { passo "PC2 non partito"; return 1; }
    passo "PC2 avviato sulla porta $(cat "$CF2/porta.txt") $*"
}
ferma_pc2() {
    local pid i
    pid=$(cat "$CF2/pid" 2>/dev/null) || return 0
    kill -TERM "$pid" 2>/dev/null
    for i in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    kill -KILL "$pid" 2>/dev/null
    rm -f "$CF2/pid"
    passo "PC2 fermato"
}
stato_pc2() { tr -d '\n' < "$CF2/stato.txt" 2>/dev/null; }
attendi_pc2() {
    local voluto="$1" fine=$(( $(date +%s) + ${2:-30} ))
    while [ "$(date +%s)" -lt "$fine" ]; do
        [ "$(stato_pc2)" = "$voluto" ] && { passo "PC2: $voluto"; return 0; }
        sleep 1
    done
    passo "PC2: non arriva a «$voluto» (è «$(stato_pc2)»)"; return 1
}
apri_link() {  # apri_link <cartella>: il link del QR code di quel computer, come la fotocamera di sistema
    local link; link=$(tr -d '\n' < "$1/collegamento.txt" 2>/dev/null)
    adb_sh "am start -a android.intent.action.VIEW -d '$link' $PACCHETTO" >/dev/null 2>&1
    passo "APRO IL LINK di $(basename "$1"): $link"
    sleep 3
}
stati() { passo "STATI: PC1 «$(stato_computer)» · PC2 «$(stato_pc2)»"; }
fine_t14() { ferma_pc2; rm -f "$CF2/identita.key"; }
trap fine_t14 EXIT

# ---- 1. due computer accesi, telefono appena installato
cancella_dati_app
lingua_italiana
permessi_concedi
avvia_computer_finto --nome "PC dello studio" --massimo-video 2 || fallisci "PC1 non parte"
avvia_pc2 --nome "Portatile di Mamma" || fallisci "PC2 non parte"
avvia_app
t08_salta_presentazione || fallisci "la schermata principale non compare"
attendi 12
schermata "home-due-pc-accesi"; testi_visibili
stati

# ---- 2. QR del PC dello studio
collega_qr || fallisci "link PC1 non aperto"
attendi_computer video 60 || { schermata "pc1-senza-video"; testi_visibili; fallisci "niente video a PC1"; }
attendi 3
schermata "in-onda-pc1"; testi_visibili; stati

# ---- 3. in onda su PC1, il QR del portatile: prima «Annulla», poi «Collega»
apri_link "$CF2"
schermata "domanda-altro-computer"; testi_visibili
if c_e_testo "Annulla"; then tocca_testo "Annulla"; else nota "nessuna domanda «Collegarsi a …?» aprendo il QR di un altro computer in onda"; fi
attendi 4
schermata "dopo-annulla"; testi_visibili; stati
[ "$(stato_computer)" = video ] || nota "dopo «Annulla» PC1 non riceve più video (è «$(stato_computer)»)"

apri_link "$CF2"
schermata "domanda-altro-2"; testi_visibili
inizio=$(date +%s)
c_e_testo "Collega" && tocca_testo "Collega"
if attendi_pc2 video 60; then nota "passaggio PC1 → PC2: video su PC2 in $(( $(date +%s) - inizio )) s"; else nota "passaggio PC1 → PC2 NON riuscito"; fi
attendi 3
schermata "in-onda-pc2"; testi_visibili; stati
[ "$(stato_computer)" = video ] && nota "PC1 riceve ancora video dopo il passaggio a PC2"

# ---- 4. ritorno a PC1 (già conosciuto) con il suo QR
apri_link "$CF"
schermata "domanda-ritorno-pc1"; testi_visibili
inizio=$(date +%s)
c_e_testo "Collega" && tocca_testo "Collega"
if attendi_computer video 60; then nota "ritorno PC2 → PC1: video su PC1 in $(( $(date +%s) - inizio )) s"; else nota "ritorno PC2 → PC1 NON riuscito"; fi
attendi 3
schermata "di-nuovo-pc1"; testi_visibili; stati

# ---- 5. il portatile ora rifiuta (stessa identità: il telefono lo conosce); il telefono è in onda su PC1
ferma_pc2
avvia_pc2 --nome "Portatile di Mamma" --rifiuta || nota "PC2 non riparte con --rifiuta"
apri_link "$CF2"
schermata "domanda-pc2-rifiuta"; testi_visibili
c_e_testo "Collega" && tocca_testo "Collega"
t08_guarda "pc2-rifiuta" 30
stati
grep -E "RIFIUT|CHIUS|COLLEGATO" "$CF2/eventi.log" 2>/dev/null | sed 's/^/        PC2: /' | tee -a "$USCITA/passi.log" >&2
[ "$(stato_computer)" = video ] || nota "dopo il rifiuto di PC2 il telefono non è tornato su PC1 (PC1 «$(stato_computer)»)"
t08_risveglia
c_e_testo "Riprova" && { schermata "rifiuto-con-riprova"; }

# ---- 6. schermata principale con due computer conosciuti
if c_e_testo "Scollega"; then tocca_testo "Scollega"; attendi 2; c_e_testo "Scollega" && tocca_testo "Scollega"; fi
c_e_testo "Indietro" && tocca_testo "Indietro"
attendi 8
schermata "home-dopo"; testi_visibili; stati
tocca_testo "App e assistenza" && { attendi 2; scorri_giu; schermata "computer-conosciuti"; testi_visibili; scorri_giu; schermata "computer-conosciuti-2"; testi_visibili; indietro; }

# ---- 7. riapro l'app: a quale si ricollega da solo? (PC2 rifiuta ancora, PC1 acceso)
ferma_pc2; avvia_pc2 --nome "Portatile di Mamma" || true
chiudi_app; attendi 2; avvia_app
attendi 20
schermata "riapro-app"; testi_visibili; stati
t08_risveglia
attendi 10
schermata "riapro-app-30s"; testi_visibili; stati

# ---- 8. PC1 spento: riapro l'app con solo PC2 acceso (l'ultimo usato era PC1)
ferma_computer_finto
chiudi_app; attendi 2; avvia_app
attendi 25
schermata "solo-pc2-acceso"; testi_visibili; stati
registro_telefono
