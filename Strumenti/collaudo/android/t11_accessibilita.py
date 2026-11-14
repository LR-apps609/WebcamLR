#!/usr/bin/env python3
"""Collaudo t11 (Marta, TalkBack): legge un dump di uiautomator come lo leggerebbe un lettore di schermo.

  t11_accessibilita.py <dump.xml> fuoco    → il nodo con il fuoco della tastiera (focused="true"), o «nessuno»
  t11_accessibilita.py <dump.xml> controlla → controlli toccabili senza nome, immagini con e senza descrizione,
                                              caselle e interruttori con il loro stato
"""
import sys
import xml.etree.ElementTree as ET


def nome_di(nodo):
    """Il testo che TalkBack direbbe: text o content-desc del nodo, altrimenti dei figli (come fa per i contenitori)."""
    proprio = (nodo.get("content-desc") or nodo.get("text") or "").strip()
    if proprio:
        return proprio
    parti = []
    for figlio in nodo.iter("node"):
        if figlio is nodo:
            continue
        t = (figlio.get("content-desc") or figlio.get("text") or "").strip()
        if t:
            parti.append(t)
    return " · ".join(parti)


def descrivi(nodo):
    classe = (nodo.get("class") or "").rsplit(".", 1)[-1]
    stato = []
    for chiave in ("checkable", "checked", "selected", "enabled"):
        if nodo.get(chiave) == "true" and chiave != "enabled":
            stato.append(chiave)
    if nodo.get("enabled") == "false":
        stato.append("DISATTIVATO")
    rid = (nodo.get("resource-id") or "").split("/")[-1]
    return f"{classe} «{nome_di(nodo)[:160]}» id={rid} {nodo.get('bounds')} {' '.join(stato)}".strip()


def main():
    radice = ET.parse(sys.argv[1]).getroot()
    modo = sys.argv[2]
    nodi = list(radice.iter("node"))
    if modo == "fuoco":
        f = [n for n in nodi if n.get("focused") == "true"]
        print(descrivi(f[-1]) if f else "nessuno")
        return
    pacchetto = "it.lrapps"
    senza = []
    for n in nodi:
        if not (n.get("package") or "").startswith(pacchetto):
            continue
        if (n.get("clickable") == "true" or n.get("long-clickable") == "true" or n.get("checkable") == "true") and not nome_di(n):
            senza.append(descrivi(n))
        classe = n.get("class") or ""
        if classe.endswith("ImageView") or classe.endswith("Image"):
            print("  IMMAGINE: " + descrivi(n))
        if n.get("checkable") == "true":
            print("  STATO: " + descrivi(n))
    for s in senza:
        print("  SENZA NOME: " + s)
    print(f"  ({len(nodi)} nodi, {len(senza)} toccabili senza nome)")


if __name__ == "__main__":
    main()
