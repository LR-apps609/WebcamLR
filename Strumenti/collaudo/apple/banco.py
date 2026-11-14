#!/usr/bin/env python3
"""Banco di prova di WebcamLR (collaudo-20), la parte in Python di esegui.sh. Gira sulle macchine macOS di GitHub.

  banco.py elenca <cartella CollaudoUI> <iphone|mac> "<copioni>"   → una riga «Classe/metodo» per test
  banco.py simulatore "<nome>"                                      → l'UDID del simulatore da usare
  banco.py estrai <file.xcresult> <cartella>                        → schermate, alberi, note.txt, esito.txt
  banco.py riepilogo <cartella dei risultati>                       → esito.txt di tutto (anche sullo stdout)
"""

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def errore(testo):
    print(testo, file=sys.stderr)


# --- elenca -------------------------------------------------------------------------------------------------------

def elenca(cartella, piattaforma, filtro):
    """I test dei copioni (classi figlie di CopioneCollaudo, metodi test…), filtrati.

    Filtro: voci separate da spazi o virgole. «CopioneFumo», «CopioneFumo/test01_primoAvvio», con davanti a scelta
    «iPhone:» o «Mac:» (la voce vale solo per quella piattaforma) o il nome del target («CollaudoUI-iPhone/…»).
    Vuoto: tutti i test."""
    test = []
    for file in sorted(Path(cartella).glob("*.swift")):
        classe = None
        for riga in file.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*(?:final\s+)?class\s+(\w+)\s*:\s*(\w+)", riga)
            if m:
                classe = m.group(1) if m.group(2) in ("CopioneCollaudo", "XCTestCase") else None
                continue
            m = re.match(r"\s*(?:@MainActor\s+)?func\s+(test\w*)\s*\(\s*\)", riga)
            if m and classe:
                test.append(f"{classe}/{m.group(1)}")
    voci = [v for v in re.split(r"[\s,]+", filtro.strip()) if v]
    if not voci:
        return test
    scelti = []
    for voce in voci:
        if ":" in voce:
            prefisso, voce = voce.split(":", 1)
            if prefisso.lower() != piattaforma:
                continue
        m = re.match(r"CollaudoUI-(iPhone|Mac)/(.+)$", voce, re.IGNORECASE)
        if m:
            if m.group(1).lower() != piattaforma:
                continue
            voce = m.group(2)
        for t in test:
            if (t == voce or t.split("/")[0] == voce) and t not in scelti:
                scelti.append(t)
    return scelti


# --- simulatore ---------------------------------------------------------------------------------------------------

def versione_runtime(chiave):
    numeri = re.findall(r"\d+", chiave.split("iOS")[-1])
    return tuple(int(n) for n in numeri)


def simulatore(nome):
    nome = nome.strip()
    dati = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    runtime = sorted((k for k in dati["devices"] if ".iOS-" in k), key=versione_runtime, reverse=True)
    if nome and nome.lower() not in ("recente", "il più recente"):
        for r in runtime:
            for d in dati["devices"][r]:
                if d["name"] == nome:
                    errore(f"Simulatore: {nome} ({r})")
                    return d["udid"]
        # Non c'è: si prova a crearlo sul runtime più recente.
        tipi = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
        tipo = next((t["identifier"] for t in tipi if t["name"] == nome), None)
        if tipo and runtime:
            for r in runtime:
                prova = subprocess.run(["xcrun", "simctl", "create", f"Collaudo {nome}", tipo, r],
                                       capture_output=True, text=True)
                if prova.returncode == 0:
                    errore(f"Simulatore: creato {nome} ({r})")
                    return prova.stdout.strip()
        errore(f"Simulatore: «{nome}» non disponibile, uso il più recente")
    # Il più recente: sul runtime più nuovo, l'iPhone con il numero più alto (prima i modelli base, poi gli altri).
    for r in runtime:
        iphone = [d for d in dati["devices"][r] if d["name"].startswith("iPhone")]
        if not iphone:
            continue

        def punteggio(d):
            m = re.match(r"iPhone (\d+)(.*)$", d["name"])
            if not m:
                return (0, 0)
            return (int(m.group(1)), 1 if m.group(2).strip() == "" else 0)

        scelto = max(iphone, key=punteggio)
        errore(f"Simulatore: {scelto['name']} ({r})")
        return scelto["udid"]
    raise SystemExit("Nessun simulatore iPhone disponibile")


# --- estrai -------------------------------------------------------------------------------------------------------

def xcresulttool(*argomenti):
    prova = subprocess.run(["xcrun", "xcresulttool", *argomenti], capture_output=True, text=True)
    if prova.returncode != 0:
        # Xcode 16+: senza --legacy alcuni comandi vecchi non vanno; qui si usano solo quelli nuovi.
        errore(prova.stderr.strip())
        return None
    return prova.stdout


def nome_pulito(suggerito):
    """«01 impostazioni_0_9F1C…-….png» → «01 impostazioni.png»."""
    base, punto, estensione = suggerito.rpartition(".")
    if not punto:
        base, estensione = suggerito, ""
    base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", base)
    base = base.replace("/", "-").strip() or "allegato"
    return base, estensione


def estrai(xcresult, cartella):
    cartella = Path(cartella)
    cartella.mkdir(parents=True, exist_ok=True)
    xcresult = Path(xcresult)
    if not xcresult.exists():
        (cartella / "esito.txt").write_text("NESSUN RISULTATO: il test non è partito o xcodebuild si è fermato prima "
                                            "(vedi xcodebuild.log)\n", encoding="utf-8")
        return
    grezzi = cartella / "_allegati"
    if grezzi.exists():
        shutil.rmtree(grezzi)
    grezzi.mkdir()
    xcresulttool("export", "attachments", "--path", str(xcresult), "--output-path", str(grezzi))
    manifesto = grezzi / "manifest.json"
    note = []
    if manifesto.exists():
        elementi = []

        def cammina(nodo):
            if isinstance(nodo, dict):
                if "exportedFileName" in nodo:
                    elementi.append(nodo)
                for valore in nodo.values():
                    cammina(valore)
            elif isinstance(nodo, list):
                for valore in nodo:
                    cammina(valore)

        cammina(json.loads(manifesto.read_text(encoding="utf-8")))
        elementi.sort(key=lambda e: e.get("timestamp", 0))
        usati = set()
        for e in elementi:
            sorgente = grezzi / e["exportedFileName"]
            if not sorgente.exists():
                continue
            base, estensione = nome_pulito(e.get("suggestedHumanReadableName") or e["exportedFileName"])
            # Allegati automatici di Xcode 26 (eventi sintetizzati, istantanee dell'interfaccia): non servono.
            if base.startswith(("Synthesized Event", "UI Snapshot", "App UI hierarchy", "kXCTAttachment")):
                continue
            # La registrazione dello schermo (Xcode 26 la fa da sola): a parte, solo nell'artifact.
            if base.startswith("Screen Recording"):
                (cartella / "video").mkdir(exist_ok=True)
                shutil.copyfile(sorgente, cartella / "video" / f"{base}.{estensione or 'mp4'}")
                continue
            # Gli alberi e gli altri testi senza estensione: .txt.
            if estensione == "albero":
                base, estensione = f"{base}.albero", "txt"
            if re.fullmatch(r"\d+ nota", base):
                note.append(sorgente.read_text(encoding="utf-8", errors="replace").strip())
                continue
            nome = f"{base}.{estensione}" if estensione else base
            n = 2
            while nome in usati:
                nome = f"{base} ({n}).{estensione}" if estensione else f"{base} ({n})"
                n += 1
            usati.add(nome)
            shutil.copyfile(sorgente, cartella / nome)
    shutil.rmtree(grezzi, ignore_errors=True)
    if note:
        (cartella / "note.txt").write_text("\n".join(f"- {n}" for n in note) + "\n", encoding="utf-8")

    # Esito: i casi di test con il risultato e i messaggi d'errore.
    righe = []
    testo = xcresulttool("get", "test-results", "tests", "--path", str(xcresult))
    if testo:
        casi = []

        def cerca(nodo):
            if isinstance(nodo, dict):
                if nodo.get("nodeType") == "Test Case":
                    casi.append(nodo)
                    return
                for figlio in nodo.get("children", []) or []:
                    cerca(figlio)
                for figlio in nodo.get("testNodes", []) or []:
                    cerca(figlio)
            elif isinstance(nodo, list):
                for figlio in nodo:
                    cerca(figlio)

        cerca(json.loads(testo))
        for caso in casi:
            risultato = caso.get("result", "?")
            parola = {"Passed": "VERDE", "Failed": "ROSSO", "Skipped": "SALTATO"}.get(risultato, risultato.upper())
            righe.append(f"{parola}  {caso.get('nodeIdentifier') or caso.get('name')}  {caso.get('duration', '')}")
            messaggi = []

            def messaggi_di(nodo):
                for figlio in nodo.get("children", []) or []:
                    if figlio.get("nodeType") == "Failure Message":
                        messaggi.append(figlio.get("name", ""))
                    messaggi_di(figlio)

            messaggi_di(caso)
            righe += [f"    errore: {m}" for m in messaggi]
    if not righe:
        righe.append("NESSUN RISULTATO: nessun caso di test nel .xcresult (l'app si è chiusa? vedi xcodebuild.log)")
    (cartella / "esito.txt").write_text("\n".join(righe) + "\n", encoding="utf-8")


# --- riepilogo ----------------------------------------------------------------------------------------------------

def riepilogo(radice):
    radice = Path(radice)
    righe = []
    for piattaforma in ("iphone", "mac"):
        base = radice / piattaforma
        if not base.exists():
            continue
        righe.append(f"== {piattaforma} ==")
        compilazione = base / "_banco" / "esito-compilazione.txt"
        if compilazione.exists():
            righe.append(compilazione.read_text(encoding="utf-8").rstrip())
        for esito in sorted(base.glob("*/*/esito.txt")):
            immagini = len(list(esito.parent.glob("*.png")))
            for riga in esito.read_text(encoding="utf-8").splitlines():
                righe.append(riga if riga.startswith("    ") else f"{riga}  [{immagini} schermate]  "
                             f"{esito.parent.relative_to(radice)}")
        righe.append("")
    testo = "\n".join(righe) + "\n"
    (radice / "esito.txt").write_text(testo, encoding="utf-8")
    print(testo)


if __name__ == "__main__":
    comando, *argomenti = sys.argv[1:]
    if comando == "elenca":
        print("\n".join(elenca(argomenti[0], argomenti[1], argomenti[2] if len(argomenti) > 2 else "")))
    elif comando == "simulatore":
        print(simulatore(argomenti[0] if argomenti else ""))
    elif comando == "estrai":
        estrai(argomenti[0], argomenti[1])
    elif comando == "riepilogo":
        riepilogo(argomenti[0])
    else:
        raise SystemExit(__doc__)
