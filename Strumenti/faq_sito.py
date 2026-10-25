# Estrae le domande frequenti da DomandeFrequenti.swift e le stampa come HTML per Sito/aiuto.html.
# Uso (dal ramo sito, con il file del ramo dell'app):
#   git show round-2:Stile/Sources/Stile/DomandeFrequenti.swift > /tmp/DomandeFrequenti.swift
#   python3 Strumenti/faq_sito.py /tmp/DomandeFrequenti.swift > voci.html
# poi incolla le righe in Sito/aiuto.html, dentro <div id="elenco-domande">, al posto di quelle tra i commenti
# «DALL'APP: inizio» e «DALL'APP: fine». Le domande «solo sul sito» restano sotto, a mano.
# Legge sia i testi semplici ("…") sia quelli tradotti (String(localized: "…", bundle: .stile)).
import html
import re
import sys

TESTO = r'(?:String\(localized:\s*)?"((?:[^"\\]|\\.)*)"(?:,\s*bundle:\s*\.stile\))?'
VOCE = re.compile(
    r'DomandaFrequente\(\s*id:\s*"(.*?)",\s*domanda:\s*' + TESTO + r',\s*risposta:\s*' + TESTO +
    r',\s*parole:\s*\[(.*?)\]\)', re.S)

sorgente = open(sys.argv[1], encoding="utf-8").read()
voci = VOCE.findall(sorgente)
righe = []
for id_, domanda, risposta, parole in voci:
    elenco = re.findall(r'"(.*?)"', parole)
    righe.append('    <details id="d-%s" data-parole="%s"><summary>%s</summary><p>%s</p></details>' % (
        id_, html.escape(" ".join(elenco)), html.escape(domanda, quote=False), html.escape(risposta, quote=False)))
print(len(voci), "domande", file=sys.stderr)
if not voci:
    sys.exit("Nessuna domanda trovata: il formato di DomandeFrequenti.swift è cambiato?")
print("\n".join(righe))
