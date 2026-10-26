#!/usr/bin/env python3
"""Testi dell'app Android (P22): italiano in values/strings.xml, inglese in values-en/strings.xml.

Uso:
  python3 Strumenti/controlla_testi_android.py          controlla (esce con 1 se c'è un errore)
  python3 Strumenti/controlla_testi_android.py --severo anche gli avvisi fanno uscire con 1

Errori:
1. le chiavi di values/ e di values-en/ sono le stesse (tranne quelle con translatable="false");
2. ogni R.string.… del Kotlin e ogni @string/… delle risorse esiste in tutte e due le lingue;
3. italiano e inglese hanno gli stessi segnaposto (%1$s, %d, %.1f…), e nessun testo è vuoto;
4. i file XML sono ben formati.

Avvisi (euristici):
5. letterali Kotlin che sembrano frasi italiane fuori da log e commenti: un testo che l'utente vede va nelle
   risorse (stringResource nell'interfaccia, Testi.testo(…) fuori, vedi sistema/Testi.kt). Una riga che deve
   restare così (dati per il protocollo, chiavi, nomi propri) si segna con il commento `// testo tecnico`;
6. chiavi delle risorse che il codice non usa più;
7. in values-en/ virgolette dritte (\\" e \\') invece di “…” e ’ (Glossario, «In inglese»).

Contenuti.kt (domande frequenti e guida) ha l'italiano e l'inglese nel codice, a coppie: si controlla solo che i due
elenchi abbiano gli stessi id.
"""
import re
import sys
import xml.dom.minidom
from collections import Counter
from pathlib import Path

RADICE = Path(__file__).resolve().parent.parent
APP = RADICE / "Android/app/src/main"
RES = APP / "res"
KOTLIN = APP / "kotlin"

# File con i testi nelle due lingue nel codice stesso, controllati a parte.
BILINGUI = {"Contenuti.kt"}

# Chiamate i cui argomenti non si vedono mai nell'interfaccia.
CHIAMATE_LOG = re.compile(r"\b(?:Log\.[vdiwe]|println|require|check|error|assert|TODO|[A-Z]\w*(?:Exception|Error)|ErroreProtocollo)\s*\(\s*$")

# Parole italiane frequenti (intere), per riconoscere una frase. Volutamente senza parole uguali in inglese.
PAROLE_ITALIANE = {
    "il", "lo", "la", "gli", "le", "di", "del", "della", "dei", "delle", "che", "non", "per", "con", "sul", "sulla",
    "nel", "nella", "al", "alla", "da", "dal", "dalla", "un", "una", "uno", "è", "sono", "si", "ci", "ma", "o", "e",
    "più", "tocca", "riprova", "collegamento", "collegato", "scollegato", "computer", "telefono", "fotocamera",
    "microfono", "impostazioni", "attivalo", "consentito", "disponibile", "acceso", "spento", "video", "rete",
    "codice", "errore", "ancora", "adesso", "questo", "questa", "senza", "tra", "fra", "poi", "solo", "anche",
    "tornata", "persa", "pausa", "caldo", "fresco", "attivo", "nuovo", "tentativo", "ritrovato", "primo",
    "fotogramma", "spedito", "chiuso", "fermo", "immagine", "inviata", "specchiata", "riprendo", "riavvio", "chiede",
    "nessun", "nessuna", "manca", "scegli", "chiudi", "controlla", "aggiorna", "acquisto", "ripristino", "riuscito",
    "riuscita", "lettura", "inquadra", "permesso", "schermo", "avviso", "ricollego", "scollega", "collega", "qualità",
    "scelta", "sicuro", "sicurezza", "fotocamere", "obiettivo", "frontale", "posteriore", "batteria", "trovato",
}
# Parole che, da sole, non bastano: compaiono anche in inglese o nei dati tecnici.
NEUTRE = {"video", "computer", "e", "o", "a", "la", "le", "da", "con"}
RE_ACCENTI = re.compile(r"[àèéìòùÀÈÉÌÒÙ]")
RE_SEGNAPOSTO = re.compile(r"%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[sdfxXc%]")


def errore(elenco, testo):
    elenco.append(testo)


def leggi_stringhe(percorso, errori):
    """{chiave: (testo, traducibile)} da uno strings.xml, con i testi come li legge Android (escape tolti)."""
    try:
        documento = xml.dom.minidom.parse(str(percorso))
    except Exception as e:  # noqa: BLE001
        errore(errori, f"{percorso.relative_to(RADICE)}: XML non valido ({e})")
        return {}
    voci = {}
    for nodo in documento.getElementsByTagName("string"):
        nome = nodo.getAttribute("name")
        testo = "".join(n.toxml() if n.nodeType == n.ELEMENT_NODE else n.data for n in nodo.childNodes)
        if nome in voci:
            errore(errori, f"{percorso.relative_to(RADICE)}: «{nome}» due volte")
        voci[nome] = (testo, nodo.getAttribute("translatable") != "false")
    for etichetta in ("plurals", "string-array"):
        for nodo in documento.getElementsByTagName(etichetta):
            voci[nodo.getAttribute("name")] = ("", nodo.getAttribute("translatable") != "false")
    return voci


def segnaposti(testo):
    trovati = [s for s in RE_SEGNAPOSTO.findall(testo) if s != "%%"]
    # %s e %1$s sono lo stesso segnaposto se ce n'è uno solo.
    if len(trovati) == 1:
        trovati = [re.sub(r"^%\d+\$", "%", trovati[0])]
    return Counter(trovati)


def senza_commenti_e_letterali(testo):
    """Il Kotlin con commenti tolti; ritorna anche i letterali [(riga, inizio, contenuto)] fuori dai commenti."""
    letterali = []
    pulito = []
    i, n = 0, len(testo)
    while i < n:
        if testo.startswith("//", i):
            fine = testo.find("\n", i)
            fine = n if fine < 0 else fine
            pulito.append(" " * (fine - i))
            i = fine
            continue
        if testo.startswith("/*", i):
            fine = testo.find("*/", i + 2)
            fine = n if fine < 0 else fine + 2
            pulito.append(re.sub(r"[^\n]", " ", testo[i:fine]))
            i = fine
            continue
        if testo.startswith('"""', i):
            fine = testo.find('"""', i + 3)
            fine = n if fine < 0 else fine + 3
            letterali.append((testo.count("\n", 0, i) + 1, i, testo[i + 3:fine - 3]))
            pulito.append('"' + re.sub(r"[^\n]", " ", testo[i + 1:fine - 1]) + '"')
            i = fine
            continue
        if testo[i] == '"':
            j = i + 1
            profondita = 0
            while j < n:
                c = testo[j]
                if c == "\\":
                    j += 2
                    continue
                if testo.startswith("${", j):
                    profondita += 1
                    j += 2
                    continue
                if c == "}" and profondita:
                    profondita -= 1
                elif c == '"' and not profondita:
                    break
                elif c == "\n":
                    break
                j += 1
            letterali.append((testo.count("\n", 0, i) + 1, i, testo[i + 1:j]))
            pulito.append('"' + " " * (j - i - 1) + '"')
            i = j + 1
            continue
        if testo[i] == "'" and i + 2 < n:
            fine = testo.find("'", i + 1 if testo[i + 1] != "\\" else i + 3)
            if 0 < fine - i <= 8:
                pulito.append(testo[i:fine + 1])
                i = fine + 1
                continue
        pulito.append(testo[i])
        i += 1
    return "".join(pulito), letterali


def sembra_italiano(contenuto):
    testo = re.sub(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*", " ", contenuto)
    testo = RE_SEGNAPOSTO.sub(" ", testo)
    if not re.search(r"[A-Za-zÀ-ÿ]{2,}", testo):
        return False
    parole = re.findall(r"[A-Za-zÀ-ÿ']+", testo.lower())
    if RE_ACCENTI.search(testo) and len(parole) >= 1 and " " in testo.strip():
        return True
    italiane = [p for p in parole if p in PAROLE_ITALIANE]
    forti = [p for p in italiane if p not in NEUTRE]
    return " " in testo.strip() and len(forti) >= 1 and len(parole) >= 2


def dentro_chiamata_log(pulito, inizio):
    """Vero se il letterale che comincia a `inizio` è (anche indirettamente) un argomento di Log/require/…"""
    profondita = 0
    i = inizio - 1
    limite = max(0, inizio - 400)
    while i >= limite:
        c = pulito[i]
        if c in ")}":
            profondita += 1
        elif c in "({":
            if profondita == 0:
                # `require(…) { "…" }`: anche la lambda del messaggio conta come argomento.
                prima = pulito[max(0, i - 60):i].rstrip()
                if c == "{" and prima.endswith(")"):
                    prima = prima[:prima.rfind("(")] if "(" in prima else prima
                if CHIAMATE_LOG.search(prima + "("):
                    return True
                if c == "{":
                    return False
            else:
                profondita -= 1
        elif c == ";" and profondita == 0:
            return False
        i -= 1
    return False


def controlla_contenuti(percorso, errori):
    testo = percorso.read_text(encoding="utf-8")
    for oggetto in ("DomandeFrequenti", "Guida"):
        blocco = re.search(r"object " + oggetto + r"\b([\s\S]*?)(?=\nobject |\Z)", testo)
        if not blocco:
            continue
        parti = re.split(r"private val inglesi", blocco.group(1))
        if len(parti) != 2:
            errore(errori, f"{percorso.name}: {oggetto} senza «italiane» e «inglesi»")
            continue
        id_it = re.findall(r'(?:DomandaFrequente|SezioneGuida)\(\s*"([^"]+)"', parti[0])
        id_en = re.findall(r'(?:DomandaFrequente|SezioneGuida)\(\s*"([^"]+)"', parti[1])
        if id_it != id_en:
            errore(errori, f"{percorso.name}: {oggetto}, id diversi tra italiano e inglese: "
                           f"solo it {sorted(set(id_it) - set(id_en))}, solo en {sorted(set(id_en) - set(id_it))}"
                           + (" (ordine diverso)" if set(id_it) == set(id_en) else ""))


def main():
    severo = "--severo" in sys.argv
    errori, avvisi = [], []

    for f in sorted(RES.rglob("*.xml")):
        try:
            xml.dom.minidom.parse(str(f))
        except Exception as e:  # noqa: BLE001
            errore(errori, f"{f.relative_to(RADICE)}: XML non valido ({e})")

    italiano = leggi_stringhe(RES / "values/strings.xml", errori)
    inglese = leggi_stringhe(RES / "values-en/strings.xml", errori)
    traducibili = {k for k, (_, t) in italiano.items() if t}
    for k in sorted(traducibili - set(inglese)):
        errore(errori, f"«{k}»: manca in values-en/strings.xml")
    for k in sorted(set(inglese) - set(italiano)):
        errore(errori, f"«{k}»: solo in values-en/strings.xml")
    for k in sorted(traducibili & set(inglese)):
        it, en = italiano[k][0], inglese[k][0]
        if not it.strip() and k in italiano and italiano[k][0] != "":
            errore(errori, f"«{k}»: testo italiano vuoto")
        if italiano[k][0] == "" and inglese[k][0] == "":
            continue
        if not en.strip():
            errore(errori, f"«{k}»: testo inglese vuoto")
        if segnaposti(it) != segnaposti(en):
            errore(errori, f"«{k}»: segnaposto diversi, it {dict(segnaposti(it))} en {dict(segnaposti(en))}")
        if re.search(r"(?<!\\)'", it) or re.search(r"(?<!\\)'", en):
            errore(errori, f"«{k}»: apostrofo senza \\ (aapt lo rifiuta)")
        if '\\"' in en or "\\'" in en:
            avvisi.append(f"«{k}»: in inglese virgolette “…” e apostrofo ’, come nel Glossario")

    usate = set()
    for f in sorted(APP.rglob("*.xml")):
        usate |= set(re.findall(r"@string/([A-Za-z0-9_]+)", f.read_text(encoding="utf-8")))
    for f in sorted(KOTLIN.rglob("*.kt")):
        testo = f.read_text(encoding="utf-8")
        dove = f.relative_to(RADICE)
        pulito, letterali = senza_commenti_e_letterali(testo)
        chiavi = set(re.findall(r"\bR\.string\.([A-Za-z0-9_]+)", pulito))
        usate |= chiavi
        for k in sorted(chiavi - set(italiano)):
            errore(errori, f"{dove}: R.string.{k} non esiste in values/strings.xml")
        if f.name in BILINGUI:
            controlla_contenuti(f, errori)
            continue
        righe = testo.split("\n")
        for riga, inizio, contenuto in letterali:
            if not sembra_italiano(contenuto):
                continue
            if "testo tecnico" in righe[riga - 1]:
                continue
            if dentro_chiamata_log(pulito, inizio):
                continue
            avvisi.append(f"{dove}:{riga}: «{contenuto[:90]}»")

    for k in sorted(traducibili - usate - {"app_name"}):
        avvisi.append(f"«{k}»: nelle risorse ma non usata nel codice")

    print(f"== Android: {len(italiano)} testi in values/, {len(inglese)} in values-en/")
    if errori:
        print(f"   Errori ({len(errori)}):")
        for e in errori:
            print(f"     - {e}")
    if avvisi:
        print(f"   Da controllare ({len(avvisi)}): letterali che sembrano italiano fuori dalle risorse, chiavi inutili")
        for a in avvisi:
            print(f"     - {a}")
    if errori or (severo and avvisi):
        print(f"\n{len(errori)} errori, {len(avvisi)} avvisi.")
        return 1
    print("\nTutto a posto." + (f" ({len(avvisi)} avvisi da guardare)" if avvisi else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
