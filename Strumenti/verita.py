#!/usr/bin/env python3
"""Documento della verità (pagina su claude.ai che tiene i dati dentro di sé).

Il giro di Claude, sempre partendo dalla versione online (mai dalla memoria):
  1. Artifact read con path "index.html" e out_dir <cartella>  -> <cartella>/index.html
  2. python3 Strumenti/verita.py estrai <cartella>/index.html dati.json
  3. python3 Strumenti/verita.py elenca dati.json               # eventi «⏳ inviato»
  4. modifica dati.json (test, bug, diario, cambiamenti...) e segna le ricevute:
     python3 Strumenti/verita.py ricevi dati.json <id-evento> "risposta di una riga"
  5. python3 Strumenti/verita.py costruisci <cartella>/index.html dati.json pagina.html
     (stile e codice presi dalla versione online, dati da dati.json, ora di Roma in «salvato»)
  6. Artifact publish di pagina.html sullo stesso url. Se c'è un conflitto: ricomincia da 1 e unisci.

Il blocco dati è <script type="application/json" id="dati">; stile e codice sono #stile e #codice.
La forma del documento deve restare identica a quella che la pagina pubblica da sola (vedi costruisciPagina nel codice).
"""
import json, re, sys
from datetime import datetime
from zoneinfo import ZoneInfo

SCHELETRO_A = ('<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover">'
               '<style>:root{color-scheme:light;box-sizing:border-box;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
               'html{scroll-padding-top:env(safe-area-inset-top,0px)}body{margin:0;padding:0;font:14px -apple-system,BlinkMacSystemFont,sans-serif;background:#fff;color:#000}'
               'img{max-width:100%}[hidden]:not([hidden=until-found i]){display:none!important}</style></head><body>\n')
SCHELETRO_B = '\n</body></html>'
TESTA = ('<title>WebcamLR · Documento della verità</title>\n'
         '<meta name="claude:viewport-fit-sides" content="cover">\n'
         '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=Barlow:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">\n')
LIMITE_REGISTRO = 200


def ora_roma():
    return datetime.now(ZoneInfo("Europe/Rome")).isoformat(timespec="seconds")


def blocco(html, id_):
    m = re.search(r'<(script|style)\b[^>]*\bid="' + id_ + r'"[^>]*>(.*?)</\1>', html, re.S)
    if not m:
        sys.exit(f"blocco #{id_} non trovato nella pagina")
    return m.group(2)


def pagina(S, stile, codice):
    dati = json.dumps(S, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    return (SCHELETRO_A + TESTA + '<style id="stile">' + stile + '</style>\n<div id="app"></div>\n'
            '<script type="application/json" id="dati">' + dati + '</script>\n'
            '<script id="codice">' + codice + '</script>' + SCHELETRO_B)


def roma(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(ZoneInfo("Europe/Rome")).strftime("%d/%m/%Y · %H:%M")


def main(a):
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    if cmd == "estrai":
        S = json.loads(blocco(open(a[1]).read(), "dati"))
        json.dump(S, open(a[2], "w"), ensure_ascii=False, indent=1)
        print(f"dati estratti: {len(S.get('registro', []))} eventi, salvata il {roma(S['salvato'])} da {S.get('salvatoDa')}")
    elif cmd == "elenca":
        S = json.load(open(a[1]))
        da = [e for e in S.get("registro", []) if e.get("stato") == "inviato"]
        print(f"{len(da)} segnalazioni «⏳ inviato»")
        for e in da:
            extra = {k: e[k] for k in ("prima", "dopo", "nota", "cosaSuccesso", "correggi", "dispositivo", "durata", "priorita", "foto") if e.get(k)}
            print(f"- {e['id']} · {roma(e['t'])} · {e['tipo']} · su {e.get('su', '-')} «{e.get('suNome', '')}» · {json.dumps(extra, ensure_ascii=False)}")
    elif cmd == "ricevi":
        S = json.load(open(a[1]))
        e = next((x for x in S.get("registro", []) if x["id"] == a[2]), None)
        if not e:
            sys.exit("evento non trovato")
        risposta = a[3]
        if len(risposta) > 140:
            sys.exit("risposta troppo lunga: una riga al massimo")
        e.update(stato="ricevuto", ricevuto=ora_roma(), risposta=risposta)
        json.dump(S, open(a[1], "w"), ensure_ascii=False, indent=1)
        print("ricevuto", a[2])
    elif cmd == "costruisci":
        online = open(a[1]).read()
        S = json.load(open(a[2]))
        reg = S.get("registro", [])
        if len(reg) > LIMITE_REGISTRO:
            vecchi, S["registro"] = reg[:-LIMITE_REGISTRO], reg[-LIMITE_REGISTRO:]
            if any(e.get("stato") == "inviato" for e in vecchi):
                sys.exit("ci sono eventi non ancora ricevuti tra i più vecchi: gestiscili prima")
            t = ora_roma()
            S.setdefault("archivio", []).append({"id": "ev-" + t[:16].replace(":", "").replace("-", ""), "tipo": "eventi", "nome": f"{len(vecchi)} eventi dal {roma(vecchi[0]['t'])} al {roma(vecchi[-1]['t'])}",
                                                 "finito": "; ".join(sorted({f"{e['tipo']}" for e in vecchi})), "creata": t, "modificata": t, "ordine": 999})
        S["salvato"] = ora_roma()
        S["salvatoDa"] = "Claude"
        open(a[3], "w").write(pagina(S, blocco(online, "stile"), blocco(online, "codice")))
        print("scritta", a[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
