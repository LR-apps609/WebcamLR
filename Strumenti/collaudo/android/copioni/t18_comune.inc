# Funzioni comuni dei copioni t18 (Andrea, formatore: giornate lunghe in onda, telefonate, batteria, calore).
# Si carica con `source` da t18_a_lunga.sh e t18_b_lunga.sh. La sessione in onda continua da un copione all'altro:
# il computer finto acceso dal primo copione resta acceso (il suo pid si nasconde a esegui.sh in /tmp/t18-cf).

T18_PASSAGGIO=/tmp/t18-cf
T18_INIZIO=$(date +%s)

# t18_fino_a <s>: aspetta che siano passati <s> secondi dall'inizio del copione.
t18_fino_a() { while [ $(( $(date +%s) - T18_INIZIO )) -lt "$1" ]; do sleep 1; done; }

# t18_pid: il processo dell'app.
t18_pid() { adb_sh pidof "$PACCHETTO" 2>/dev/null | tr -d '\r' | awk '{print $1}'; }

# t18_misura: una riga di misure in $USCITA/misure.csv.
_t18_prec_tick=0; _t18_prec_ora=0; _t18_prec_pid=""
t18_misura() {
    local f="$USCITA/misure.csv" pid mem tick ora cpu thr fd bat temp liv term inc cf fps mbit lat
    [ -s "$f" ] || echo "t_s,ora,pid,cpu_pct,pss_kb,java_kb,native_kb,graphics_kb,thread,fd,views,activities,batteria,temp_decimi,alimentazione,termico,cf_stato,cf_fps,cf_mbit,cf_latenza_ms" > "$f"
    pid=$(t18_pid)
    ora=$(date +%s)
    if [ -n "$pid" ]; then
        tick=$(adb_sh cat "/proc/$pid/stat" 2>/dev/null | awk '{print $14 + $15}')
        if [ "$pid" = "$_t18_prec_pid" ] && [ "$_t18_prec_ora" -gt 0 ] && [ -n "$tick" ]; then
            cpu=$(awk -v a="$tick" -v b="$_t18_prec_tick" -v s=$(( ora - _t18_prec_ora )) 'BEGIN { if (s > 0) printf "%.1f", (a - b) / s }')
        else cpu=""; fi
        _t18_prec_tick=${tick:-0}; _t18_prec_ora=$ora; _t18_prec_pid=$pid
        mem=$(adb_sh dumpsys meminfo "$PACCHETTO" 2>/dev/null | tr -d '\r' | awk '
            /Java Heap:/ {j=$3} /Native Heap:/ && !n {n=$3} /Graphics:/ && !g {g=$2}
            /TOTAL PSS:/ {p=$3} /^ *Views:/ {v=$2} /Activities:/ {a=$NF}
            END {printf "%s,%s,%s,%s,%s,%s", p, j, n, g, v, a}')
        thr=$(adb_sh "ls /proc/$pid/task 2>/dev/null | wc -l" | tr -d '\r ')
        fd=$(adb_sh "run-as $PACCHETTO ls /proc/$pid/fd 2>/dev/null | wc -l" | tr -d '\r ')
    else
        cpu=""; mem=",,,,,"; thr=""; fd=""
    fi
    bat=$(adb_sh dumpsys battery 2>/dev/null | tr -d '\r')
    liv=$(echo "$bat" | awk -F': ' '/^ *level:/ {print $2; exit}')
    temp=$(echo "$bat" | awk -F': ' '/^ *temperature:/ {print $2; exit}')
    inc=$(echo "$bat" | awk -F': ' '/AC powered:/ {a=$2} /USB powered:/ {u=$2} /^ *status:/ {s=$2} END {print ((a=="true"||u=="true") ? "rete" : "batteria") "-s" s}')
    term=$(adb_sh dumpsys thermalservice 2>/dev/null | tr -d '\r' | awk -F': ' '/Thermal Status/ {print $2; exit}')
    cf=$(stato_computer)
    read -r fps mbit lat < <(tail -n 10 "$CF/statistiche.csv" 2>/dev/null | grep -v '^ora' | awk -F, '{f+=$5; m+=$6; l+=$7; n++} END {if (n) printf "%.1f %.2f %.0f", f/n, m/n, l/n}')
    echo "$(( ora - T18_INIZIO )),$(date +%H:%M:%S),$pid,$cpu,$mem,$thr,$fd,$liv,$temp,$inc,$term,$cf,$fps,$mbit,$lat" >> "$f"
}

# t18_campiona_sempre <ogni>: misure in sottofondo finché non si chiama t18_campiona_ferma.
t18_campiona_sempre() {
    ( while :; do t18_misura; sleep "${1:-30}"; done ) >/dev/null 2>&1 &
    T18_CAMPIONATORE=$!
    passo "MISURE in sottofondo ogni ${1:-30} s (misure.csv)"
}
t18_campiona_ferma() { [ -n "${T18_CAMPIONATORE:-}" ] && kill "$T18_CAMPIONATORE" 2>/dev/null; wait "$T18_CAMPIONATORE" 2>/dev/null; t18_misura; }

# t18_guarda <nome>: fotografia e testi a schermo, e lo stato del computer.
t18_guarda() {
    schermata "$1"
    testi_visibili
    passo "COMPUTER: stato «$(stato_computer)», ultime statistiche: $(tail -n 1 "$CF/statistiche.csv" 2>/dev/null)"
}

# t18_video_ok <etichetta>: il computer riceve fotogrammi negli ultimi 5 secondi? Lo scrive in note.txt.
t18_video_ok() {
    local fps
    fps=$(tail -n 5 "$CF/statistiche.csv" 2>/dev/null | grep -v '^ora' | awk -F, '{s += $5; n++} END {if (n) printf "%.1f", s / n; else print 0}')
    nota "$1: computer «$(stato_computer)», ${fps} fps negli ultimi 5 s"
    awk -v f="$fps" 'BEGIN { exit !(f > 0) }'
}

# t18_emu <comando>: comando della console dell'emulatore (adb emu), con la risposta nel registro.
t18_emu() { local r; r=$(adb emu "$@" 2>&1 | tr -d '\r' | tr '\n' ' '); passo "EMU $*: $r"; }
