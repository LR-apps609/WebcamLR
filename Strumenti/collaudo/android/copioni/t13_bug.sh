# t13 (Elena): «Segnala un bug» vuoto, solo spazi, lungo (scritto) ed enorme (incollato: 300 000 caratteri con emoji).
source "$(dirname "${BASH_SOURCE[0]}")/t13_comune.inc"

apri_segnala() {
    tocca_testo "Impostazioni" || return 1
    attendi 1
    tocca_testo "Segnala un bug" || return 1
    attendi 2
}
stato_invia() {
    local f="$USCITA/.t13b.xml"
    _dump "$f" || return
    python3 -I - "$f" <<'PY' | while read -r r; do passo "  $r"; done
import sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter("node"):
    t = (n.get("text") or "") + (n.get("content-desc") or "")
    if "Invia la segnalazione" in t or n.get("class") == "android.widget.EditText":
        print("NODO", n.get("class"), "enabled=" + n.get("enabled"), "clickable=" + n.get("clickable"), "testo=" + repr(t[:80]), "lunghezza=" + str(len(n.get("text") or "")))
PY
}

t13_prepara
apri_segnala || fallisci "non trovo «Segnala un bug»"
schermata "segnala-vuota"
stato_invia
tocca_testo "Invia la segnalazione"
attendi 2
schermata "segnala-vuota-dopo-invia"
testi_visibili

# Solo spazi e a capo.
tocca_classe android.widget.EditText
scrivi "          "
adb_sh input keyevent KEYCODE_ENTER KEYCODE_ENTER KEYCODE_ENTER
scrivi "   "
schermata "segnala-solo-spazi"
stato_invia
tocca_testo "Invia la segnalazione"
attendi 2
schermata "segnala-solo-spazi-dopo-invia"
testi_visibili
svuota_campo 30

# Un testo lungo scritto a pezzi (circa 2000 caratteri).
pezzo="Ho provato a collegare il telefono ma non funziona e allora ho riprovato tante volte senza successo. "
inizio=$(date +%s)
for i in $(seq 1 20); do scrivi "$i $pezzo"; done
passo "Scrittura di circa 2000 caratteri: $(( $(date +%s) - inizio )) s"
schermata "segnala-lungo-fine-campo"
stato_invia
scorri_giu; scorri_giu
schermata "segnala-lungo-scorso"
tocca_testo "Invia la segnalazione"
attendi 3
schermata "segnala-lungo-invia"
testi_visibili
indietro
attendi 1
schermata "segnala-lungo-dopo-indietro"
# Si esce e si rientra: la bozza c'è ancora?
indietro; indietro
t13_torna
apri_segnala
schermata "segnala-bozza-rientro"
stato_invia
t13_torna

# --- Testo enorme incollato (simulato con la bozza salvata: 300 000 caratteri con emoji, arabo, a capo).
chiudi_app
adb exec-out run-as "$PACCHETTO" cat shared_prefs/impostazioni.xml > "$USCITA/.prefs.xml" 2>/dev/null
python3 -I - "$USCITA/.prefs.xml" "$USCITA/.prefs-nuove.xml" <<'PY'
import re, sys
from xml.sax.saxutils import escape
s = open(sys.argv[1], encoding="utf-8").read()
s = re.sub(r'\s*<string name="bozzaSegnalazione">.*?</string>', "", s, flags=re.S)
s = re.sub(r'\s*<boolean name="bozzaSegnalazioneInviata"[^>]*/>', "", s)
blocco = "Errore 🔥📷💻 ‮testo al contrario‬ مرحبا بالعالم «virgolette» <tag> & ecco \n"
testo = (blocco * (300000 // len(blocco) + 1))[:300000]
s = s.replace("</map>", '    <string name="bozzaSegnalazione">' + escape(testo) + "</string>\n</map>")
open(sys.argv[2], "w", encoding="utf-8").write(s)
print(len(testo))
PY
passo "Preferenze originali: $(wc -c < "$USCITA/.prefs.xml") byte, nuove: $(wc -c < "$USCITA/.prefs-nuove.xml") byte"
adb push "$USCITA/.prefs-nuove.xml" /data/local/tmp/t13-prefs.xml >/dev/null
adb_sh chmod 644 /data/local/tmp/t13-prefs.xml
adb_sh "run-as $PACCHETTO cp /data/local/tmp/t13-prefs.xml shared_prefs/impostazioni.xml"
passo "Bozza enorme nelle preferenze: $(adb_sh "run-as $PACCHETTO wc -c shared_prefs/impostazioni.xml")"
inizio=$(date +%s)
avvia_app
attendi_testo "Impostazioni" 30 || nota "con la bozza enorme la schermata principale non compare in 30 s"
passo "Avvio con la bozza enorme: $(( $(date +%s) - inizio )) s"
schermata "bozza-enorme-avvio"
inizio=$(date +%s)
apri_segnala || nota "non riesco ad aprire «Segnala un bug» con la bozza enorme"
passo "Apertura di «Segnala un bug» con la bozza enorme: $(( $(date +%s) - inizio )) s"
schermata "bozza-enorme-pagina"
stato_invia
# Elena tocca il campo e scrive ancora qualcosa in fondo.
tocca_classe android.widget.EditText
inizio=$(date +%s)
adb_sh input keyevent KEYCODE_MOVE_END
scrivi "ancora"
passo "Scrittura in fondo al testo enorme: $(( $(date +%s) - inizio )) s"
schermata "bozza-enorme-scritto"
indietro   # tastiera
tocca_testo "Invia la segnalazione"
attendi 4
schermata "bozza-enorme-invia"
testi_visibili
if ! adb_sh pidof "$PACCHETTO" >/dev/null; then nota "dopo «Invia la segnalazione» con 300 000 caratteri l'app non è più in esecuzione (crash?)"; fi
adb logcat -d -b crash 2>/dev/null | tail -n 40 > "$USCITA/t13-crash-buffer.txt"
grep -m3 "TransactionTooLarge\|FATAL" "$USCITA/t13-crash-buffer.txt" | while read -r r; do passo "  CRASH: $r"; done
indietro
attendi 2
schermata "bozza-enorme-dopo"
testi_visibili
