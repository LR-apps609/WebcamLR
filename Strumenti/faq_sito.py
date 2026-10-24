# Estrae le domande frequenti da DomandeFrequenti.swift e le stampa come HTML.
# Uso: python3 Strumenti/faq_sito.py Stile/Sources/Stile/DomandeFrequenti.swift > voci.html, poi incolla in Sito/aiuto.html.
import re, html, sys
s = open(sys.argv[1], encoding="utf-8").read()
voci = re.findall(r'DomandaFrequente\(\s*id: "(.*?)",\s*domanda: "(.*?)",\s*risposta: "(.*?)",\s*parole: \[(.*?)\]\)', s, re.S)
out = []
for id_, d, r, p in voci:
    parole = re.findall(r'"(.*?)"', p)
    out.append('    <details id="d-%s" data-parole="%s"><summary>%s</summary><p>%s</p></details>' % (
        id_, html.escape(" ".join(parole)), html.escape(d, quote=False), html.escape(r, quote=False)))
print(len(voci), file=sys.stderr)
print("\n".join(out))
