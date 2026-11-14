# Funzioni comuni dei copioni t07 (Paolo, attento alla privacy). Si carica con `source` dai copioni t07_*.sh.

# rispondi_dialoghi <parole da negare>: risponde ai dialoghi di permesso di sistema uno per uno; nega quelli il cui
# messaggio contiene una delle parole (per esempio "pictures" per la fotocamera, "audio", "notifications"), consente
# gli altri. Fotografa ogni dialogo.
rispondi_dialoghi() {
    local nega="$1" n=0 f="$USCITA/.dialogo.xml" messaggio parola negato
    while attendi_id "permission_message" 8; do
        n=$((n + 1))
        _dump "$f"
        messaggio=$(python3 -I "$_NODO" "$f" elenca | grep -m1 -i "allow")
        schermata "dialogo-$n"
        negato=0
        for parola in $nega; do
            printf '%s' "$messaggio" | grep -qi "$parola" && negato=1
        done
        if [ "$negato" = 1 ]; then
            nota "dialogo $n «$messaggio»: Paolo NEGA"
            rifiuta_dialogo || break
        else
            nota "dialogo $n «$messaggio»: Paolo consente"
            consenti_dialogo || break
        fi
        [ "$n" -ge 4 ] && break
    done
    nota "dialoghi di sistema: $n"
}

stato_permessi() {
    adb_sh dumpsys package "$PACCHETTO" 2>/dev/null \
        | grep -E 'permission.(CAMERA|RECORD_AUDIO|POST_NOTIFICATIONS): granted' | sort -u | tr -s ' ' \
        | while read -r r; do nota "permesso ($1): $r"; done
    nota "appops ($1): $(adb_sh appops get "$PACCHETTO" 2>/dev/null | grep -E 'CAMERA|RECORD_AUDIO|POST_NOTIFICATION' | tr '\n' ';')"
}

processo_app() { adb_sh pidof "$PACCHETTO" | tr -d '\r'; }

# Testi della principale che spiegano un permesso mancante.
avvisi_permessi() {
    local t
    for t in "non può usare la fotocamera" "Manca il permesso" "Microfono non consentito" "notifiche" "Autorizzazioni" "Apri Impostazioni"; do
        if c_e_testo "$t"; then nota "$1: c'è «$t»"; fi
    done
}

# ---------------------------------------------------------------- traffico di rete dell'app

# osserva_rete_inizia: ogni mezzo secondo le connessioni TCP/UDP del processo dell'app (per UID, da /proc/net), in
# sottofondo. osserva_rete_ferma le decodifica: indirizzo remoto, porta, nome inverso (dal runner).
osserva_rete_inizia() {
    UID_APP=$(adb_sh cmd package list packages -U "$PACCHETTO" | grep -m1 -oE 'uid:[0-9]+' | cut -d: -f2)
    [ -n "$UID_APP" ] || UID_APP=$(adb_sh dumpsys package "$PACCHETTO" | grep -m1 -oE '(userId|appId)=[0-9]+' | cut -d= -f2)
    local leggi="cat"
    adb_sh "cat /proc/net/tcp6" 2>/dev/null | grep -q 'local_address' || leggi="su 0 cat"
    nota "rete: UID dell'app $UID_APP, lettura di /proc/net con «$leggi»"
    adb shell "while true; do for f in tcp tcp6 udp udp6; do $leggi /proc/net/\$f | grep ' $UID_APP ' | sed \"s/^/\$f /\"; done; sleep 0.5; done" \
        > "$USCITA/rete-grezzo.txt" 2>/dev/null </dev/null &
    _osservatore=$!
    passo "OSSERVO LA RETE DELL'APP (UID $UID_APP)"
}

osserva_rete_ferma() {
    [ -n "${_osservatore:-}" ] && kill "$_osservatore" 2>/dev/null
    _osservatore=""
    python3 -I - "$USCITA/rete-grezzo.txt" "$UID_APP" > "$USCITA/rete-connessioni.txt" <<'FINE'
import sys, socket, struct
righe = open(sys.argv[1], errors="replace").read().splitlines()
uid = sys.argv[2]
def ip(h):
    a, p = h.split(":")
    porta = int(p, 16)
    if len(a) == 8:
        return socket.inet_ntoa(struct.pack("<I", int(a, 16))), porta
    b = bytes.fromhex(a)
    b = b"".join(b[i:i+4][::-1] for i in range(0, 16, 4))
    if b[:12] == b"\0" * 10 + b"\xff\xff":
        return socket.inet_ntoa(b[12:]), porta
    return socket.inet_ntop(socket.AF_INET6, b), porta
visti = {}
for r in righe:
    c = r.split()
    if len(c) < 10 or c[8] != uid:
        continue
    proto = c[0]
    try:
        loc, rem = ip(c[2]), ip(c[3])
    except Exception:
        continue
    if rem[0] in ("0.0.0.0", "::"):
        chiave = (proto, "ASCOLTO", loc[1])
    else:
        chiave = (proto, rem[0], rem[1])
    visti[chiave] = visti.get(chiave, 0) + 1
for (proto, rem, porta), n in sorted(visti.items(), key=lambda x: (x[0][1], x[0][2])):
    nome = ""
    if rem not in ("ASCOLTO",) and not rem.startswith(("10.0.2.", "127.", "::1")):
        try:
            nome = socket.gethostbyaddr(rem)[0]
        except Exception:
            nome = "?"
    print(f"{proto:5} {rem:40} porta {porta:6} campioni {n:5} {nome}")
FINE
    passo "CONNESSIONI DELL'APP VISTE (proto, indirizzo remoto, porta, campioni da 0,5 s, nome):"
    sed 's/^/        /' "$USCITA/rete-connessioni.txt" | tee -a "$USCITA/passi.log" >&2
    local esterne
    esterne=$(grep -v -E 'ASCOLTO| 10\.0\.2\.| 127\.|::1 ' "$USCITA/rete-connessioni.txt" | wc -l)
    nota "rete: connessioni dell'app verso fuori dal banco (non 10.0.2.x, non locali): $esterne"
}

# Le righe del logcat che parlerebbero di statistiche inviate (datatransport/Firelog, clearcut, MediaPipe).
logcat_statistiche() {
    adb logcat -d -v time 2>/dev/null | grep -i -E 'TRuntime|datatransport|clearcut|firelog|mediapipe|TasksStats|cct|GoogleApi' \
        | grep -v -i 'Strumenti' | tail -n 80 > "$USCITA/logcat-statistiche.txt"
    passo "LOGCAT statistiche: $(wc -l < "$USCITA/logcat-statistiche.txt") righe (logcat-statistiche.txt)"
    sed 's/^/        /' "$USCITA/logcat-statistiche.txt" | tail -n 40 | tee -a "$USCITA/passi.log" >&2
}

# I lavori pianificati dell'app (datatransport carica le statistiche con un JobService).
lavori_app() {
    adb_sh dumpsys jobscheduler 2>/dev/null | grep -E "JOB #.*$PACCHETTO|$PACCHETTO/" | sort -u > "$USCITA/lavori.txt"
    passo "LAVORI PIANIFICATI DELL'APP: $(wc -l < "$USCITA/lavori.txt")"
    sed 's/^/        /' "$USCITA/lavori.txt" | head -n 20 | tee -a "$USCITA/passi.log" >&2
}
