# t20 · Luisa (aggiornamento dalla beta 4 e reinstallazione): funzioni comuni ai copioni t20_*.
T20_BETA4="d49224a1681b661f5337382397a1e6ba58bdbf84"   # «1.0 beta 4 «Volto nuovo»: build 5»
T20_CARTELLA="${RUNNER_TEMP:-/tmp}/t20"
T20_APK_VECCHIO="$T20_CARTELLA/beta4.apk"
mkdir -p "$T20_CARTELLA"

# t20_preferenze <nome>: copia i file di shared_prefs dell'app (run-as, APK di debug) in $USCITA/preferenze-<nome>.txt
t20_preferenze() {
    local file="$USCITA/preferenze-$1.txt" f
    {
        echo "### $1 · $(date '+%H:%M:%S')"
        adb_sh "run-as $PACCHETTO ls -la shared_prefs" 2>&1
        for f in $(adb_sh "run-as $PACCHETTO ls shared_prefs" 2>/dev/null | tr -d '\r'); do
            echo "--- $f"
            adb_sh "run-as $PACCHETTO cat shared_prefs/$f" 2>&1
        done
        echo "--- file dell'app"
        adb_sh "run-as $PACCHETTO find . -maxdepth 2" 2>&1 | head -40
    } > "$file"
    passo "PREFERENZE salvate in $(basename "$file")"
    sed 's/^/        /' "$file" >> "$USCITA/passi.log"
}

# t20_versione <nome>: versione installata, prima installazione e ultimo aggiornamento.
t20_versione() {
    local riga
    riga=$(adb_sh dumpsys package "$PACCHETTO" | grep -E 'versionCode|versionName|firstInstallTime|lastUpdateTime' | tr -d '\r' | sed 's/^ *//' | tr '\n' ' ')
    passo "VERSIONE ($1): ${riga:-non installata}"
}

# t20_interruttori <nome>: i Switch/checkbox dell'albero corrente con il loro stato (checked).
t20_interruttori() {
    albero "$1"
    local x
    x=$(ls -t "$USCITA/albero/"*"$1"*.xml 2>/dev/null | head -1)
    [ -n "$x" ] || return 0
    python3 - "$x" <<'PY' | sed 's/^/        INTERRUTTORE /' | tee -a "$USCITA/passi.log" >&2
import sys, xml.etree.ElementTree as ET
t = ET.parse(sys.argv[1])
nodi = list(t.iter('node'))
for i, n in enumerate(nodi):
    if n.get('checkable') == 'true':
        # il testo più vicino: nel nodo, nei figli, o nel genitore (Compose mette il testo accanto)
        testi = [m.get('text') or m.get('content-desc') for m in n.iter('node') if (m.get('text') or m.get('content-desc'))]
        print(f"checked={n.get('checked')} classe={n.get('class').split('.')[-1]} testo={' / '.join(testi)[:90]} bounds={n.get('bounds')}")
PY
}

# t20_conferme: quante volte il computer finto ha chiesto il codice (telefono nuovo per lui).
t20_conferme() { grep -c 'CONFERMA chiesta' "$CF/eventi.log" 2>/dev/null || echo 0; }

# t20_in_onda_e_scollega <nome>: aspetta il video, fotografa, poi «Scollega» dal telefono.
t20_in_onda_e_scollega() {
    if attendi_computer video 60; then
        attendi 3
        schermata "$1-in-onda"
        testi_visibili
    else
        schermata "$1-senza-video"
        testi_visibili
        nota "$1: il computer finto non riceve il video"
        return 1
    fi
    c_e_testo "Tocca due volte per riaccendere lo schermo" && tocca_due_volte
    if tocca_testo "Scollega"; then
        attendi 1
        c_e_testo "Scollega" && tocca_testo "Scollega"
        attendi_testo "Impostazioni" 15
        schermata "$1-dopo-scollega"
    else
        nota "$1: in onda non trovo «Scollega»"
    fi
}
