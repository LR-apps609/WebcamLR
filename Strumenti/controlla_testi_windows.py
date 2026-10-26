#!/usr/bin/env python3
"""Controlla i testi di WebcamLR per Windows (W2): ogni testo visibile ha l'italiano e l'inglese.

I file dei testi:
- l'app WinUI: Windows/WebcamLR.App/Strings/it-IT/Resources.resw e Strings/en-US/Resources.resw. Le voci
  «Nome.Proprietà» sono degli x:Uid dello XAML, le altre di Testi.T("Chiave") nel C#;
- la logica comune: Windows/WebcamLR.Ricevitore/Risorse/Testi.resx (italiano) e Testi.en.resx (inglese), lette da
  TestiRicevitore.T("Chiave");
- l'installatore e i messaggi della webcam (WebcamLR.Setup, WebcamLR.Webcam.Logica/StatoWebcam.cs): coppie
  Testi.S("italiano", "inglese") e S("italiano", "inglese") nel codice.

Controlla che:
1. le due lingue abbiano le stesse chiavi, nessun valore vuoto e gli stessi valori ({0}, {1:0}…);
2. ogni x:Uid dello XAML abbia le sue voci e ogni Testi.T / TestiRicevitore.T usi una chiave che esiste, con
   abbastanza valori per i segnaposto;
3. ogni coppia S("…", "…") abbia gli stessi valori interpolati nelle due lingue;
e avvisa (senza fallire) per i testi che sembrano italiani rimasti fuori: attributi dello XAML senza x:Uid,
letterali nel C# dell'interfaccia, chiavi non più usate, virgolette «» in inglese.

Non serve Windows: va anche su Linux. Uso: python3 Strumenti/controlla_testi_windows.py [-v]
Esce con 1 se trova errori.
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

RADICE = Path(__file__).resolve().parent.parent
WIN = RADICE / "Windows"
APP = WIN / "WebcamLR.App"
RICEVITORE = WIN / "WebcamLR.Ricevitore"

CATALOGHI = [
    # (nome, file italiano, file inglese, cartelle del codice, funzione che legge le chiavi)
    ("app", APP / "Strings" / "it-IT" / "Resources.resw", APP / "Strings" / "en-US" / "Resources.resw", [APP], "Testi.T"),
    ("ricevitore", RICEVITORE / "Risorse" / "Testi.resx", RICEVITORE / "Risorse" / "Testi.en.resx",
     [RICEVITORE, WIN / "WebcamLR.Microfono", APP], "TestiRicevitore.T"),
]

# Dove cercare i testi italiani rimasti fuori, e dove ci sono le coppie S("it", "en").
CODICE_INTERFACCIA = [APP, RICEVITORE, WIN / "WebcamLR.Setup", WIN / "WebcamLR.Microfono"]
CODICE_COPPIE = [WIN / "WebcamLR.Setup", WIN / "WebcamLR.Webcam.Logica"]

PROPRIETA_XAML = {"Text", "Content", "Header", "PlaceholderText", "ToolTipService.ToolTip", "AutomationProperties.Name",
                  "AutomationProperties.HelpText", "OnContent", "OffContent", "Description", "Label", "Title",
                  "PrimaryButtonText", "SecondaryButtonText", "CloseButtonText"}

# Testi uguali in tutte le lingue: nomi, sigle, unità.
UGUALI = {"WebcamLR", "Webcam", "LR", "Wi-Fi", "ISO", "Zoom", "NDI", "WebcamLR Pro", "Pro", "PRO", "App", "Video", "Privacy",
          "Tele", "HEVC", "H.264", "— ms", "Teams", "Chrome", "Edge", "Firefox", "Opera", "Brave", "OBS", "Discord", "WhatsApp",
          "Slack", "Skype", "Webex", "Telegram", "Signal", "OrbitLR", "GateLR", "Android", "Mac", "Windows", "iPhone", "Hotspot"}

# Chiamate i cui letterali non si mostrano (registro tecnico, eccezioni, chiavi di registro, nomi di file…).
TECNICHE = re.compile(r"(?:throw new \w+|Exception|Registro\.Scrivi|Scrivi|Debug\.WriteLine|GetManifestResourceStream|"
                      r"OpenSubKey|CreateSubKey|GetValue|SetValue|Resources\[|Pennello|Leggi|DllImport|Guid|"
                      r"ResourceManager|GetSubtree|Path\.Combine|EseguiAsync|Esegui|EseguiDaAmministratore|"
                      r"TryGetProperty|Testo|FileLibero|ProcessStartInfo|Split|Contains|StartsWith|EndsWith)\s*\($")

# I nomi delle risorse di App.xaml (colori, caratteri, stili): si passano come stringhe, non si mostrano.
CHIAVI_STILE = set(re.findall(r'x:Key="([^"]+)"', (APP / "App.xaml").read_text(encoding="utf-8"))) if (APP / "App.xaml").exists() else set()

SEGNAPOSTO = re.compile(r"(?<!\{)\{(\d+)(?:[,:][^{}]*)?\}(?!\})")


def leggi_catalogo(percorso):
    voci = {}
    for d in ET.parse(percorso).getroot().iter("data"):
        voci[d.get("name")] = d.findtext("value") or ""
    return voci


def segnaposti(testo):
    return sorted({int(n) for n in SEGNAPOSTO.findall(testo)})


# ——— Un lettore minimo di C#: letterali (anche interpolati e verbatim) con la loro posizione ———

def letterali_cs(testo):
    """(inizio, fine, letterale) per ogni letterale stringa, saltando commenti e caratteri."""
    i, n, out = 0, len(testo), []
    while i < n:
        if testo.startswith("//", i):
            j = testo.find("\n", i)
            i = n if j < 0 else j
            continue
        if testo.startswith("/*", i):
            j = testo.find("*/", i)
            i = n if j < 0 else j + 2
            continue
        if testo[i] == "'":
            m = re.compile(r"'(\\.|[^'\\])'").match(testo, i)
            if m:
                i = m.end()
                continue
        m = re.compile(r'(\$@|@\$|\$|@)?"').match(testo, i)
        if m and (i == 0 or not (testo[i - 1].isalnum() or testo[i - 1] == "_")):
            pref = m.group(1) or ""
            j, verb, interp = m.end(), "@" in pref, "$" in pref
            while j < n:
                d = testo[j]
                if interp and d == "{":
                    if testo.startswith("{{", j):
                        j += 2
                        continue
                    prof, j = 1, j + 1
                    while j < n and prof:
                        if testo[j] == '"':
                            k = j + 1
                            while k < n and testo[k] != '"':
                                k += 2 if testo[k] == "\\" else 1
                            j = k + 1
                            continue
                        prof += {"{": 1, "}": -1}.get(testo[j], 0)
                        j += 1
                    continue
                if not verb and d == "\\":
                    j += 2
                    continue
                if d == '"':
                    if verb and testo.startswith('""', j):
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            out.append((i, j, testo[i:j]))
            i = j
            continue
        i += 1
    return out


def corpo(letterale):
    """Il testo del letterale senza prefisso, virgolette e buchi interpolati."""
    pref = re.match(r'(\$@|@\$|\$|@)?"', letterale).group(1) or ""
    testo = letterale[len(pref) + 1:-1]
    return re.sub(r"\{[^{}]*\}", "", testo) if "$" in pref else testo


def buchi(letterale):
    """Le espressioni interpolate di un letterale $"…", nell'ordine."""
    if not letterale.startswith(("$", "@$")):
        return []
    return [b.split(":")[0].strip() for b in re.findall(r"(?<!\{)\{([^{}]+)\}", letterale)]


def sembra_italiano(testo):
    t = testo.strip()
    if not t or t in UGUALI or t in CHIAVI_STILE or not re.search(r"[A-Za-zÀ-ÿ]{2,}", t):
        return False
    if not re.search(r"[A-Za-zÀ-ÿ]{2,}", " ".join(p for p in re.split(r"\s+", t) if p not in UGUALI)):
        return False  # solo nomi uguali in tutte le lingue: «WebcamLR · »
    if re.fullmatch(r"[A-Z][a-z]+(?:[A-Z][a-z]+)+", t):
        return False  # identificativi composti: «TelefonoNellaWebcam»
    if re.fullmatch(r"[A-Za-z0-9_.\-/:@?=&%\\#]+", t) and not t[:1].isupper():
        return False  # chiavi, identificativi, percorsi
    if re.fullmatch(r"[A-Z0-9_\-]{8,}", t.replace("-", "")) or t.startswith(("ms-", "http", "mailto:", "SYSTEM\\", "SOFTWARE\\")):
        return False
    if re.fullmatch(r"[\W\d_]*(?:p|fps|ms|s|MB|KB|GB|Mbit/s|×)?[\W\d_]*(?:\s*(?:p|fps|ms|Mbit/s)\b[\W\d_]*)*", t):
        return False  # solo numeri e unità: «{0}p · {1} fps · {2}»
    return " " in t or t[:1].isupper() or re.search(r"[À-ÿ]", t) is not None


def chiamata_prima(testo, inizio):
    """Il nome della chiamata (con «(») che contiene il letterale, se il letterale ne è il primo argomento o uno dei primi."""
    prima = testo[max(0, inizio - 120):inizio]
    m = re.search(r"([\w.?\[\]]+\s*\()\s*(?:[^()]*,\s*)?$", prima)
    return m.group(1) if m else ""


def argomenti(testo, apertura):
    """Gli argomenti di una chiamata a partire dalla «(» in posizione apertura: elenco di testi."""
    prof, i, inizio, out = 0, apertura, apertura + 1, []
    lett = {a: b for a, b, _ in letterali_cs(testo[apertura:apertura + 4000])}
    while i < len(testo):
        if (i - apertura) in lett:
            i = apertura + lett[i - apertura]
            continue
        c = testo[i]
        if c in "([{":
            prof += 1
        elif c in ")]}":
            prof -= 1
            if prof == 0:
                out.append(testo[inizio:i].strip())
                return [a for a in out if a]
        elif c == "," and prof == 1:
            out.append(testo[inizio:i].strip())
            inizio = i + 1
        i += 1
    return out


def fine_chiamata(testo, apertura):
    """La posizione dopo la «)» che chiude la «(» in posizione apertura (saltando i letterali)."""
    prof, i = 0, apertura
    lett = {a: b for a, b, _ in letterali_cs(testo[apertura:apertura + 6000])}
    while i < len(testo):
        if (i - apertura) in lett:
            i = apertura + lett[i - apertura]
            continue
        c = testo[i]
        if c in "([{":
            prof += 1
        elif c in ")]}":
            prof -= 1
            if prof == 0:
                return i + 1
        i += 1
    return len(testo)


def commenti(testo):
    """Gli intervalli dei commenti // e /* */ (fuori dai letterali)."""
    lett = letterali_cs(testo)
    dentro = set()
    for a, b, _ in lett:
        dentro.update(range(a, b))
    out = []
    for m in re.finditer(r"//[^\n]*|/\*.*?\*/", testo, re.S):
        if m.start() not in dentro:
            out.append((m.start(), m.end()))
    return out


# Chiamate i cui argomenti non vanno controllati: già tradotti (T, S) o tecnici (registro, eccezioni, chiavi…).
DA_SALTARE = re.compile(r"(?<![\w.])(?:Testi\.T|TestiRicevitore\.T|Testi\.S|S|T|Registro\.Scrivi|Scrivi|Pennello|"
                        r"new \w*Exception|new ErroreProtocollo|OpenSubKey|CreateSubKey|OpenBaseKey|GetValue|SetValue|"
                        r"DllImport|Guid|ResourceManager|GetSubtree|ProcessStartInfo|GetManifestResourceStream|EseguiAsync|"
                        r"Esegui|EseguiDaAmministratore|TryGetProperty|Testo|Richiesta|Numero|Tipo|Apri|ApriPiena|FileLibero|"
                        r"ToString|TryParseExact|Append|Combine|GetFolderPath|Contains|StartsWith|EndsWith|Equals|Split)\s*\(")

# Assegnazioni e chiamate che mostrano il testo: lì anche una parola sola va tradotta.
VISIBILE = re.compile(r"(?:\b(?:Text|Content|Header|Title|PlaceholderText|PrimaryButtonText|SecondaryButtonText|CloseButtonText|"
                      r"Message|ToolTipText)\s*=|SetToolTip\(|SetName\(|SetHelpText\(|Notifica\(|Aggiungi\()\s*[^;]*$")


def intervalli_da_saltare(testo):
    out = commenti(testo)
    for m in DA_SALTARE.finditer(testo):
        out.append((m.start(), fine_chiamata(testo, m.end() - 1)))
    for m in re.finditer(r"Resources\[", testo):
        out.append((m.start(), testo.find("]", m.end()) + 1))
    # Elenchi di nomi tecnici: «private static readonly string[] Parole = […]».
    for m in re.finditer(r"string\[\]\s+\w+\s*=", testo):
        out.append((m.start(), testo.find(";", m.end()) + 1))
    return out


def file_cs(cartelle):
    for cartella in cartelle:
        for f in sorted(cartella.rglob("*.cs")):
            if "/bin/" in f.as_posix() or "/obj/" in f.as_posix():
                continue
            yield f


def controlla(verboso):
    errori, avvisi = [], []

    def rel(p):
        return p.relative_to(RADICE).as_posix()

    # 1. Cataloghi: stesse chiavi, valori non vuoti, stessi segnaposto.
    cataloghi = {}
    for nome, it, en, cartelle, funzione in CATALOGHI:
        if not it.exists() or not en.exists():
            errori.append(f"manca {rel(it) if not it.exists() else rel(en)}")
            continue
        vi, ve = leggi_catalogo(it), leggi_catalogo(en)
        cataloghi[nome] = (vi, ve)
        for k in sorted(set(vi) - set(ve)):
            errori.append(f"{rel(en)}: manca «{k}»")
        for k in sorted(set(ve) - set(vi)):
            errori.append(f"{rel(it)}: manca «{k}»")
        for k in sorted(set(vi) & set(ve)):
            if not vi[k].strip() or not ve[k].strip():
                errori.append(f"{nome}: «{k}» senza testo in una lingua")
            if segnaposti(vi[k]) != segnaposti(ve[k]):
                errori.append(f"{nome}: «{k}» ha valori diversi: «{vi[k]}» / «{ve[k]}»")
            if "«" in ve[k] or "»" in ve[k]:
                avvisi.append(f"{rel(en)}: «{k}»: in inglese le virgolette sono “…”")

    # 2a. XAML: ogni x:Uid ha le sue voci; nessun testo italiano rimasto negli attributi.
    usate = {nome: set() for nome in cataloghi}
    if "app" in cataloghi:
        vi, _ = cataloghi["app"]
        per_uid = {}
        for k in vi:
            if "." in k:
                per_uid.setdefault(k.split(".", 1)[0], []).append(k)
        for xaml in sorted(APP.glob("*.xaml")):
            testo = xaml.read_text(encoding="utf-8")
            for m in re.finditer(r"<([A-Za-z][\w.:]*)((?:\s+[\w.:]+=\"[^\"]*\")*)\s*/?>", testo):
                riga = testo.count("\n", 0, m.start()) + 1
                att = dict(re.findall(r'\s([\w.:]+)="([^"]*)"', m.group(2)))
                uid = att.get("x:Uid")
                if uid:
                    if uid not in per_uid:
                        errori.append(f"{rel(xaml)}:{riga}: x:Uid=\"{uid}\" senza voci nei .resw")
                    else:
                        usate["app"].update(per_uid[uid])
                        if verboso:
                            print(f"ok  {rel(xaml)}:{riga}  x:Uid={uid}")
                if m.group(1) in ("Run", "Window"):
                    continue
                for nome_att, valore in att.items():
                    if nome_att in PROPRIETA_XAML and not valore.startswith("{") and sembra_italiano(valore):
                        avvisi.append(f"{rel(xaml)}:{riga}: {nome_att}=\"{valore}\" senza x:Uid (resta in italiano)")

    # 2b. C#: le chiavi usate esistono, con abbastanza valori.
    for nome, _, _, cartelle, funzione in CATALOGHI:
        if nome not in cataloghi:
            continue
        vi, _ = cataloghi[nome]
        modello = re.compile(r"(?<![\w.])" + re.escape(funzione) + r"\(")
        for f in file_cs(cartelle):
            testo = f.read_text(encoding="utf-8")
            nei_commenti = commenti(testo)
            for m in modello.finditer(testo):
                if any(a <= m.start() < b for a, b in nei_commenti):
                    continue
                riga = testo.count("\n", 0, m.start()) + 1
                args = argomenti(testo, m.end() - 1)
                if not args or not re.fullmatch(r'"[^"\\]*"', args[0]):
                    if not (f.name in ("Testi.cs", "Lingua.cs")):
                        avvisi.append(f"{rel(f)}:{riga}: {funzione} con una chiave non letterale ({args[0] if args else '—'})")
                    continue
                chiave = args[0][1:-1]
                if chiave not in vi:
                    errori.append(f"{rel(f)}:{riga}: «{chiave}» non è in {nome}")
                    continue
                usate[nome].add(chiave)
                servono = (max(segnaposti(vi[chiave])) + 1) if segnaposti(vi[chiave]) else 0
                if len(args) - 1 < servono:
                    errori.append(f"{rel(f)}:{riga}: «{chiave}» vuole {servono} valori, ne ha {len(args) - 1}")
                elif servono == 0 and len(args) > 1:
                    avvisi.append(f"{rel(f)}:{riga}: «{chiave}» non ha segnaposto ma riceve valori")
                if verboso:
                    print(f"ok  {rel(f)}:{riga}  {chiave}")
    for nome, (vi, _) in cataloghi.items():
        for k in sorted(set(vi) - usate[nome]):
            avvisi.append(f"{nome}: «{k}» non è più usata")

    # 3. Coppie S("italiano", "inglese"): stessi valori interpolati.
    coppie = 0
    for f in file_cs(CODICE_COPPIE):
        testo = f.read_text(encoding="utf-8")
        for m in re.finditer(r"(?<![\w])(?:Testi\.)?S\(", testo):
            args = argomenti(testo, m.end() - 1)
            if len(args) != 2:
                continue
            riga = testo.count("\n", 0, m.start()) + 1
            pezzi = [[l for _, _, l in letterali_cs(a)] for a in args]
            if not all(pezzi):
                continue
            coppie += 1
            bi = sorted(b for l in pezzi[0] for b in buchi(l))
            be = sorted(b for l in pezzi[1] for b in buchi(l))
            if bi != be:
                errori.append(f"{rel(f)}:{riga}: S(…) con valori diversi nelle due lingue: {bi} / {be}")
            if any("«" in l for l in pezzi[1]):
                avvisi.append(f"{rel(f)}:{riga}: S(…): in inglese le virgolette sono “…”")

    # 4. Testi che sembrano italiani rimasti fuori dalla traduzione: frasi (spazi o accenti) ovunque, parole sole
    #    solo dove si mostrano (Text = …, SetToolTip(…)…). Saltati i letterali dentro T(…), S(…) e le chiamate tecniche.
    for f in file_cs(CODICE_INTERFACCIA):
        if f.name in ("Testi.cs", "Lingua.cs"):
            continue
        testo = f.read_text(encoding="utf-8")
        saltare = intervalli_da_saltare(testo)
        for inizio_l, _, l in letterali_cs(testo):
            testo_l = corpo(l)
            if not sembra_italiano(testo_l) or any(a <= inizio_l < b for a, b in saltare):
                continue
            t_l = testo_l.strip()
            if t_l.startswith(("<", "/", "yyyy", "d MMMM", "MMMM")):
                continue  # XML, argomenti di riga di comando, formati di data
            if re.search(r"\b(?:Name|GroupName|Tag)\s*=\s*$", testo[max(0, inizio_l - 30):inizio_l]):
                continue  # nomi di thread, gruppi e etichette interne
            frase = " " in t_l or re.search(r"[À-ÿ]", t_l)
            if not frase and not VISIBILE.search(testo[max(0, inizio_l - 160):inizio_l]):
                continue
            # Parole di ricerca delle domande frequenti: in minuscolo, dentro un elenco […].
            if t_l == t_l.lower() and len(t_l.split()) <= 3 and re.search(r"\[[^\]]*$", testo[max(0, inizio_l - 200):inizio_l]):
                continue
            riga = testo.count("\n", 0, inizio_l) + 1
            avvisi.append(f"{rel(f)}:{riga}: «{testo_l[:70]}» non passa da T(…): resta in italiano?")

    for a in avvisi:
        print("avviso:", a)
    for e in errori:
        print("ERRORE:", e)
    totale = sum(len(vi) for vi, _ in cataloghi.values())
    print(f"{totale} chiavi nei cataloghi di Windows, {coppie} coppie S(…), {len(errori)} errori, {len(avvisi)} avvisi.")
    return not errori


if __name__ == "__main__":
    sys.exit(0 if controlla("-v" in sys.argv) else 1)
