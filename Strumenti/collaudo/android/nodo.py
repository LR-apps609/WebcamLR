#!/usr/bin/env python3
"""Cerca un nodo nel dump di uiautomator (lib.sh lo usa per tocca_testo, tocca_id, attendi_testo).

Uso:
  nodo.py <dump.xml> testo "<testo>" [indice]   → stampa «x y» (centro del nodo), uscita 1 se non c'è
  nodo.py <dump.xml> id "<resource-id>" [indice]
  nodo.py <dump.xml> elenca                       → i testi e le descrizioni visibili, uno per riga

Per il testo si prova, nell'ordine: text uguale, content-desc uguale, poi text o content-desc che contiene il testo
(senza badare a maiuscole e apostrofi tipografici). `indice` (da 1) sceglie la n-esima corrispondenza dello stesso
livello, dall'alto in basso.
"""
import re
import sys
import xml.etree.ElementTree as ET

LIMITI = re.compile(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]")


def normalizza(testo):
    testo = (testo or "").replace("’", "'").replace("‘", "'").replace(" ", " ")
    return " ".join(testo.split()).casefold()


def nodi(radice):
    for nodo in radice.iter("node"):
        m = LIMITI.match(nodo.get("bounds", ""))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 <= x1 or y2 <= y1:
            continue
        yield nodo, ((x1 + x2) // 2, (y1 + y2) // 2)


def cerca_testo(radice, voluto):
    v = normalizza(voluto)
    elenco = list(nodi(radice))
    livelli = [
        lambda n: normalizza(n.get("text")) == v,
        lambda n: normalizza(n.get("content-desc")) == v,
        lambda n: v in normalizza(n.get("text")) or v in normalizza(n.get("content-desc")),
    ]
    for prova in livelli:
        trovati = [centro for nodo, centro in elenco if prova(nodo)]
        if trovati:
            return trovati
    return []


def cerca_id(radice, voluto):
    trovati = []
    for nodo, centro in nodi(radice):
        rid = nodo.get("resource-id", "")
        if rid == voluto or rid.endswith(":id/" + voluto):
            trovati.append(centro)
    return trovati


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        radice = ET.parse(sys.argv[1]).getroot()
    except Exception as errore:  # dump vuoto o troncato
        print(f"dump illeggibile: {errore}", file=sys.stderr)
        return 1
    modo = sys.argv[2]
    if modo == "elenca":
        visti = set()
        for nodo, _ in nodi(radice):
            for chiave in ("text", "content-desc"):
                valore = " ".join((nodo.get(chiave) or "").split())
                if valore and valore not in visti:
                    visti.add(valore)
                    print(valore)
        return 0
    if len(sys.argv) < 4:
        return 2
    trovati = cerca_testo(radice, sys.argv[3]) if modo == "testo" else cerca_id(radice, sys.argv[3])
    indice = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    if len(trovati) < indice:
        return 1
    x, y = trovati[indice - 1]
    print(x, y)
    return 0


if __name__ == "__main__":
    sys.exit(main())
