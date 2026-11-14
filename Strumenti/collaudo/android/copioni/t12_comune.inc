# Funzioni comuni dei copioni t12 (Roberto, vuole capire WebcamLR Pro prima di comprarlo). Si carica con «source».

# Primo avvio pulito fino alla schermata principale.
t12_prepara() {
    cancella_dati_app
    lingua_italiana
    permessi_concedi
    avvia_app
    attendi_testo "Salta" 30 || fallisci "la presentazione non compare"
    local i
    for i in 1 2 3 4 5; do
        c_e_testo "Inizia" && break
        tocca_testo "Salta"
        attendi 2
    done
    tocca_testo "Inizia" || fallisci "manca «Inizia»"
    attendi_testo "Impostazioni" 20 || fallisci "la schermata principale non compare"
    attendi 2
}

# Torna alla schermata principale (quella con «Collega a mano (indirizzo)») senza scollegare.
t12_principale() {
    local i
    for i in 1 2 3 4 5; do
        c_e_testo "Collega a mano (indirizzo)" && return 0
        indietro
    done
    c_e_testo "Collega a mano (indirizzo)"
}

# Fotografa tutta la pagina aperta, scorrendo: $1 nome, $2 quante schermate (3).
t12_pagina() {
    local nome="$1" n="${2:-3}" i
    schermata "$nome-1"
    testi_visibili
    for i in $(seq 2 "$n"); do
        scorri_giu
        schermata "$nome-$i"
        testi_visibili
    done
    for i in $(seq 2 "$n"); do scorri_su; done
}

# Apre la pagina Pro dalla pillola «PRO · Sblocca / Attivo ✓» in cima alla schermata principale.
t12_apri_pro_dalla_pillola() {
    if tocca_testo "Sblocca"; then :; elif tocca_testo "Attivo"; then :; else return 1; fi
    attendi 1
    c_e_testo "Una volta sola" || c_e_testo "Pro attivo" || c_e_testo "tutto il gratis"
}

# Scrive in passi.log lo stato dei pulsanti della pagina Pro (abilitato, cliccabile).
t12_stato_pulsanti() {
    local f="$USCITA/.t12.xml"
    _dump "$f" || return
    python3 -I - "$f" <<'PY' | while read -r r; do passo "  $r"; done
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") + " " + (n.get("content-desc") or "")
    for chiave in ("Sblocca", "Ripristina", "Riprova", "Simula", "Torna all"):
        if chiave in t:
            print("NODO", repr(t.strip()[:90]), "enabled=" + str(n.get("enabled")), "clickable=" + str(n.get("clickable")), "checked=" + str(n.get("checked")))
            break
PY
}
