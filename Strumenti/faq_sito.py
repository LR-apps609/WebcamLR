# Estrae le domande frequenti da DomandeFrequenti.swift e le stampa come HTML per Sito/aiuto.html (italiano)
# e, con --inglese, per Sito/en/aiuto.html (inglese, dal catalogo dei testi di Stile).
# Uso (dal ramo sito, con i file del ramo dell'app):
#   git show beta4:Stile/Sources/Stile/DomandeFrequenti.swift > /tmp/DomandeFrequenti.swift
#   git show beta4:Stile/Sources/Stile/Resources/Localizable.xcstrings > /tmp/Stile.xcstrings
#   python3 Strumenti/faq_sito.py /tmp/DomandeFrequenti.swift > voci.html
#   python3 Strumenti/faq_sito.py /tmp/DomandeFrequenti.swift --inglese /tmp/Stile.xcstrings > voci-en.html
# poi incolla le righe dentro <div id="elenco-domande">, al posto di quelle tra i commenti «DALL'APP: inizio» e
# «DALL'APP: fine» (in aiuto.html e in en/aiuto.html). Le domande «solo sul sito» restano sotto, a mano.
# --salta toglie le domande che nell'app non sono ancora aggiornate: sul sito le sostituisce una risposta «solo sul
# sito» con lo stesso id (dalla beta 4 nessuna: l'app ha già «costo» e «zoom-teams» aggiornate).
# Legge sia i testi semplici ("…") sia quelli tradotti (String(localized: "…", bundle: .stile)).
import argparse
import html
import json
import re
import sys

TESTO = r'(?:String\(localized:\s*)?"((?:[^"\\]|\\.)*)"(?:,\s*bundle:\s*\.stile\))?'
VOCE = re.compile(
    r'DomandaFrequente\(\s*id:\s*"(.*?)",\s*domanda:\s*' + TESTO + r',\s*risposta:\s*' + TESTO +
    r',\s*parole:\s*\[(.*?)\]\)', re.S)

# Parole della ricerca in inglese: nell'app le parole in più sono solo italiane (la ricerca inglese dell'app
# cerca nel testo tradotto). Qui i sinonimi che chi scrive in inglese usa davvero.
PAROLE_EN = {
    "non-trova": "find search list empty missing not showing discover iphone android",
    "rete-locale": "permission privacy denied local network iphone ios",
    "rete-ospiti": "hotel office school university public guest isolation hotspot",
    "cavo": "usb cable lightning usb-c wired tethering android iphone",
    "codice": "4 digits allow pairing confirm confirmation code",
    "identita": "security changed different identity",
    "ritardo": "lag latency slow stutter delay ms milliseconds freeze",
    "zoom-teams": "zoom teams meet facetime obs camera virtual webcam",
    "caldo": "heat hot warm temperature overheating",
    "batteria": "battery charge drain power",
    "nero": "black screen nothing hevc empty blank",
    "firewall": "windows firewall defender public network tethering",
    "qualita": "quality sharp 4k 1080p resolution light",
    "privacy": "privacy safe internet cloud data",
    "aggiorna": "update old version upgrade download",
    "costo": "price free pro subscription watermark ads cost",
    "registrazione": "recording record audio voice sound movie video file",
}


def leggi_catalogo(percorso):
    """Dal catalogo .xcstrings: frase italiana → traduzione inglese."""
    stringhe = json.load(open(percorso, encoding="utf-8"))["strings"]
    tradotte = {}
    for chiave, voce in stringhe.items():
        valore = voce.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
        if valore:
            tradotte[chiave] = valore
    return tradotte


def main():
    argomenti = argparse.ArgumentParser(description="Domande frequenti dell'app → HTML del sito")
    argomenti.add_argument("swift", help="DomandeFrequenti.swift del ramo dell'app")
    argomenti.add_argument("--inglese", metavar="XCSTRINGS", help="Localizable.xcstrings di Stile: stampa le domande in inglese")
    argomenti.add_argument("--salta", default="", help="id da non stampare, separati da virgole")
    a = argomenti.parse_args()

    sorgente = open(a.swift, encoding="utf-8").read()
    voci = VOCE.findall(sorgente)
    if not voci:
        sys.exit("Nessuna domanda trovata: il formato di DomandeFrequenti.swift è cambiato?")
    salta = {s.strip() for s in a.salta.split(",") if s.strip()}
    catalogo = leggi_catalogo(a.inglese) if a.inglese else None

    righe, mancanti = [], []
    for id_, domanda, risposta, parole in voci:
        if id_ in salta:
            continue
        if catalogo is not None:
            if domanda not in catalogo or risposta not in catalogo:
                mancanti.append(id_)
                continue
            domanda, risposta = catalogo[domanda], catalogo[risposta]
            elenco = PAROLE_EN.get(id_, "").split()
        else:
            elenco = re.findall(r'"(.*?)"', parole)
        righe.append('    <details id="d-%s" data-parole="%s"><summary>%s</summary><p>%s</p></details>' % (
            id_, html.escape(" ".join(elenco)), html.escape(domanda, quote=False), html.escape(risposta, quote=False)))

    print(len(righe), "domande", "(inglese)" if catalogo is not None else "(italiano)", file=sys.stderr)
    if mancanti:
        sys.exit("Senza traduzione inglese nel catalogo: " + ", ".join(mancanti))
    print("\n".join(righe))


if __name__ == "__main__":
    main()
