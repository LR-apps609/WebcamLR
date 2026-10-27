#!/usr/bin/env python3
"""Controlla i testi del ricevitore Mac (P22): ogni testo visibile ha la sua traduzione inglese.

Legge il codice Swift di Mac/Sorgenti e Mac/FotocameraVirtuale e i due cataloghi dei testi
(Mac/Risorse/Localizable.xcstrings e Mac/FotocameraVirtuale/Localizable.xcstrings) e controlla che:

1. ogni testo che SwiftUI traduce da sé (Text("…"), Button("…"), .help("…")…) o che passa da
   String(localized: "…") abbia la sua chiave nel catalogo, con la traduzione inglese;
2. le chiavi con valori (\\(…) nel codice, %@ e %lld nel catalogo) abbiano lo stesso numero di valori
   e gli stessi tipi nella traduzione;
3. nessun testo che sembra italiano resti fuori dalla traduzione (per esempio un letterale passato a
   un parametro String e poi mostrato con Text(variabile), che SwiftUI non traduce).

Non serve Xcode: va anche su Linux. Uso: python3 Strumenti/controlla_testi_mac.py [-v]
Esce con 1 se trova errori. Gli avvisi (punto 3) vanno guardati, ma non fanno fallire.
"""
import json
import re
import sys
from pathlib import Path

RADICE = Path(__file__).resolve().parent.parent

# Cartelle di codice e il loro catalogo.
GRUPPI = [
    (RADICE / "Mac" / "Sorgenti", RADICE / "Mac" / "Risorse" / "Localizable.xcstrings"),
    (RADICE / "Mac" / "FotocameraVirtuale", RADICE / "Mac" / "FotocameraVirtuale" / "Localizable.xcstrings"),
]

# Chiamate che traducono da sé il letterale (LocalizedStringKey): nome → argomenti (posizione senza
# etichetta, o etichetta). Comprese le funzioni dell'app con un parametro LocalizedStringKey.
TRADUCONO = {
    "Text": {0}, "Button": {0}, "Label": {0}, "Toggle": {0}, "Picker": {0}, "TextField": {0},
    "SecureField": {0}, "Menu": {0}, "Section": {0}, "Link": {0}, "Window": {0}, "WindowGroup": {0},
    "Stepper": {0}, "DisclosureGroup": {0}, "LabeledContent": {0}, "GroupBox": {0}, "ProgressView": {0},
    "help": {0}, "accessibilityLabel": {0}, "accessibilityHint": {0}, "accessibilityValue": {0},
    "alert": {0}, "confirmationDialog": {0}, "navigationTitle": {0}, "LocalizedStringKey": {0},
    # Funzioni di WebcamLR con il nome come LocalizedStringKey (P22).
    "passo": {1}, "riga": {0}, "cursore": {0}, "cursoreRegolazione": {0}, "interruttore": {0, "aiuto"},
    "SezioneRichiudibile": {0},
}

# Chiamate tecniche: i loro letterali non si mostrano mai (registro di sistema, code, chiavi…).
TECNICHE = {
    "Logger", "info", "error", "debug", "notice", "fault", "warning", "log", "DispatchQueue", "fatalError",
    "precondition", "preconditionFailure", "assert", "assertionFailure", "systemName", "forKey", "forResource",
    "UUID", "URL", "CMIOExtensionProperty", "appending", "appendingPathComponent", "hasPrefix", "hasSuffix",
    "contains", "url", "path", "leggiTesto", "richiesta", "beginActivity", "Image", "NSImage", "dropFirst",
    "replacingOccurrences", "split", "joined", "Comando", "inviiInAttesa", "Locale", "CGColorSpace",
    "CTFontCreateWithName", "format", "dateFormat", "Bundle", "object", "setValue", "applyingFilter",
}

# Letterali che sembrano testo ma restano uguali in tutte le lingue (nomi, sigle, simboli).
UGUALI = {
    "WebcamLR", "Mac", "iPhone", "Android", "Windows", "HEVC", "H.264", "Wi-Fi", "ISO", "Zoom", "LR apps",
    "WebcamLR · video", "WebcamLR · ingresso", "WebcamLR · identità di questo Mac", "Grab.aif", "Shutter.aif",
    "BarlowCondensed-Bold", "BarlowCondensed-SemiBold", "HelveticaNeue-Bold", "HelveticaNeue-Medium",
    "Stile_Stile.bundle", "Caratteri", "Video dal telefono in tempo reale", "— ms", "— ms · —p — fps · —",
    "macOS \\(…).\\(…).\\(…)", "\\(…) · app \\(…)",
    # Le chiavi dei messaggi di usbmux (ClienteUSB.swift).
    "MessageType", "ClientVersionString", "ProgName", "DeviceID", "PortNumber", "Result", "Number", "Attached",
    "Detached", "Properties", "ConnectionType", "USB", "Listen", "Connect",
    # Firme di app (AppCompatibili.swift).
    "Cisco-Systems.Spark",
}

SPECIFICATORE = r"%(?:\d+\$)?(?:@|lld|llu|ld|lu|d|u|hhd|hhu|hd|hu|lf|f|g|e)"


class Letterale:
    def __init__(self, file, riga, parti, espressioni, pila, dopo_operatore):
        self.file = file
        self.riga = riga
        self.parti = parti  # testi e None al posto di ogni \(…)
        self.espressioni = espressioni  # il codice dentro ogni \(…), nell'ordine
        self.pila = pila  # le chiamate che lo contengono, dalla più esterna
        self.contesto = pila[-1] if pila else None  # (nome della chiamata, posizione, etichetta)
        self.dopo_operatore = dopo_operatore  # dopo ?? o +: il tipo è String, SwiftUI non traduce

    @property
    def valori(self):
        return sum(1 for p in self.parti if p is None)

    @property
    def testo(self):
        return "".join("\\(…)" if p is None else p for p in self.parti)

    def modello(self):
        """L'espressione regolare della chiave nel catalogo."""
        if self.valori == 0:
            return re.compile(re.escape("".join(self.parti)) + r"\Z")
        pezzi = []
        for p in self.parti:
            pezzi.append(SPECIFICATORE if p is None else re.escape(p.replace("%", "%%")))
        return re.compile("".join(pezzi) + r"\Z")

    def tradotto_da_swiftui(self):
        if self.contesto is None or self.dopo_operatore:
            return False
        nome, posizione, etichetta = self.contesto
        if nome == "String" and etichetta == "localized":
            return True
        argomenti = TRADUCONO.get(nome)
        if not argomenti:
            return False
        return (etichetta is None and posizione in argomenti) or (etichetta is not None and etichetta in argomenti)

    def tecnico(self):
        """Dentro una chiamata tecnica (anche più fuori), o commento e formato di String."""
        if self.contesto is not None and self.contesto[0] == "String" and self.contesto[2] == "localized":
            return False
        if any(nome in TECNICHE for nome, _, _ in self.pila):
            return True
        return self.contesto is not None and self.contesto[2] in ("comment", "format")


class Lettore:
    """Un lettore minimo di Swift: commenti, letterali (con \\(…) annidati) e parentesi con il nome della chiamata."""

    def __init__(self, file, testo):
        self.file = file
        self.s = testo
        self.i = 0
        self.pila = []  # elementi: [nome, posizione, etichetta]
        self.letterali = []
        self.attesa_etichetta = False

    def riga(self, i):
        return self.s.count("\n", 0, i) + 1

    def leggi(self):
        self.codice(fino_a_parentesi=False)
        return self.letterali

    def codice(self, fino_a_parentesi):
        s = self.s
        profondita_iniziale = len(self.pila)
        while self.i < len(s):
            c = s[self.i]
            if s.startswith("//", self.i):
                fine = s.find("\n", self.i)
                self.i = len(s) if fine < 0 else fine
                continue
            if s.startswith("/*", self.i):
                fine = s.find("*/", self.i + 2)
                self.i = len(s) if fine < 0 else fine + 2
                continue
            if c == '"':
                self.letterale()
                self.attesa_etichetta = False
                continue
            if c in "([{":
                nome = self.nome_prima(self.i) if c == "(" else c
                self.pila.append([nome, 0, None])
                self.attesa_etichetta = c == "("
                self.i += 1
                continue
            if c in ")]}":
                if fino_a_parentesi and c == ")" and len(self.pila) == profondita_iniziale:
                    self.i += 1
                    return
                if self.pila:
                    self.pila.pop()
                self.i += 1
                self.attesa_etichetta = False
                continue
            if c == ",":
                if self.pila:
                    self.pila[-1][1] += 1
                    self.pila[-1][2] = None
                self.attesa_etichetta = True
                self.i += 1
                continue
            if c.isalpha() or c == "_":
                m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(s, self.i)
                parola = m.group(0)
                fine = m.end()
                if self.attesa_etichetta and self.pila and self.pila[-1][0] not in "[{":
                    dopo = re.compile(r"\s*:(?!:)").match(s, fine)
                    if dopo:
                        self.pila[-1][2] = parola
                        self.i = dopo.end()
                        self.attesa_etichetta = False
                        continue
                self.attesa_etichetta = False
                self.i = fine
                continue
            if not c.isspace():
                self.attesa_etichetta = False
            self.i += 1

    def nome_prima(self, i):
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", self.s[max(0, i - 80):i])
        return m.group(1) if m else "("

    def letterale(self):
        s = self.s
        inizio = self.i
        prima = s[max(0, inizio - 6):inizio].rstrip()
        dopo_operatore = prima.endswith("??") or prima.endswith("+")
        pila = [tuple(elemento) for elemento in self.pila]
        multiriga = s.startswith('"""', self.i)
        self.i += 3 if multiriga else 1
        parti = []
        espressioni = []
        corrente = []
        while self.i < len(s):
            c = s[self.i]
            if multiriga and s.startswith('"""', self.i):
                self.i += 3
                break
            if not multiriga and c == '"':
                self.i += 1
                break
            if c == "\\":
                d = s[self.i + 1]
                if d == "(":
                    parti.append("".join(corrente))
                    corrente = []
                    parti.append(None)
                    self.i += 2
                    # Dentro \( … ): codice, con i suoi letterali e le sue parentesi.
                    self.pila.append(["\\(", 0, None])
                    inizio_espressione = self.i
                    self.codice(fino_a_parentesi=True)
                    self.pila.pop()
                    espressioni.append(s[inizio_espressione:self.i - 1])
                    continue
                if d == "u":
                    fine = s.index("}", self.i)
                    corrente.append(chr(int(s[self.i + 3:fine], 16)))
                    self.i = fine + 1
                    continue
                corrente.append({"n": "\n", "t": "\t", "0": "\0", '"': '"', "'": "'", "\\": "\\"}.get(d, d))
                self.i += 2
                continue
            corrente.append(c)
            self.i += 1
        parti.append("".join(corrente))
        parti = [p for p in parti if p != ""] or [""]
        self.letterali.append(Letterale(self.file, self.riga(inizio), parti, espressioni, pila, dopo_operatore))


def sembra_testo(letterale):
    """Vero per un letterale che sembra una frase o una parola da mostrare (non una chiave o un percorso)."""
    testo = "".join(p for p in letterale.parti if p is not None)
    if testo.strip() in UGUALI or letterale.testo.strip() in UGUALI or not re.search(r"[A-Za-zÀ-ÿ]{2,}", testo):
        return False
    if re.fullmatch(r"[a-z0-9_.\-/:@?=&]+", testo):  # chiavi, identificativi, percorsi, indirizzi
        return False
    if re.fullmatch(r"[A-Za-z0-9_.\-]+", testo) and not re.search(r"[À-ÿ]", testo) and not testo[:1].isupper():
        return False
    if testo.startswith("/") or testo.startswith("x-apple") or testo.startswith("it.lrapps"):
        return False
    return " " in testo.strip() or testo[:1].isupper() or re.search(r"[À-ÿ]", testo) is not None


def da_tradurre(letterale):
    """Un letterale già in un contesto tradotto ha bisogno della voce se ha almeno una parola (due lettere)."""
    testo = "".join(p for p in letterale.parti if p is not None)
    if testo.strip() in UGUALI or letterale.testo.strip() in UGUALI:
        return False
    return re.search(r"[A-Za-zÀ-ÿ]{2,}", testo) is not None


def specificatori(testo):
    trovati = re.findall(r"%%|" + SPECIFICATORE, testo)
    return sorted(re.sub(r"\d+\$", "", t) for t in trovati if t != "%%")


def controlla(verboso):
    errori = []
    avvisi = []
    totale_chiavi = 0
    for cartella, percorso_catalogo in GRUPPI:
        if not percorso_catalogo.exists():
            errori.append(f"manca il catalogo {percorso_catalogo.relative_to(RADICE)}")
            continue
        try:
            catalogo = json.loads(percorso_catalogo.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            errori.append(f"{percorso_catalogo.relative_to(RADICE)}: JSON non valido ({e})")
            continue
        nome_catalogo = percorso_catalogo.relative_to(RADICE)
        if catalogo.get("sourceLanguage") != "it":
            errori.append(f"{nome_catalogo}: sourceLanguage deve essere \"it\"")
        voci = catalogo.get("strings", {})
        totale_chiavi += len(voci)

        # Le traduzioni del catalogo.
        for chiave, voce in voci.items():
            if voce.get("shouldTranslate") is False:
                continue
            inglese = voce.get("localizations", {}).get("en", {}).get("stringUnit", {})
            if inglese.get("state") != "translated" or not inglese.get("value"):
                errori.append(f"{nome_catalogo}: «{chiave}» senza traduzione inglese")
                continue
            if specificatori(chiave) != specificatori(inglese["value"]):
                errori.append(f"{nome_catalogo}: «{chiave}» e «{inglese['value']}» hanno valori diversi")
            if "«" in inglese["value"] or "»" in inglese["value"]:
                avvisi.append(f"{nome_catalogo}: «{chiave}»: in inglese le virgolette sono “…”")

        # Il codice.
        usate = set()
        for file in sorted(cartella.rglob("*.swift")):
            nome_file = file.relative_to(RADICE)
            for letterale in Lettore(nome_file, file.read_text(encoding="utf-8")).leggi():
                if letterale.tecnico():
                    continue
                if letterale.tradotto_da_swiftui():
                    modello = letterale.modello()
                    trovate = [k for k in voci if modello.match(k)]
                    if len(trovate) == 1:
                        usate.add(trovate[0])
                        if verboso:
                            print(f"ok  {nome_file}:{letterale.riga}  {trovate[0]}")
                    elif not trovate:
                        # Senza parole da tradurre («%lld», «1×», «1/\(…) s»): resta uguale, non serve la voce.
                        if da_tradurre(letterale):
                            errori.append(f"{nome_file}:{letterale.riga}: «{letterale.testo}» non è nel catalogo")
                    else:
                        errori.append(f"{nome_file}:{letterale.riga}: «{letterale.testo}» corrisponde a più chiavi: {trovate}")
                elif sembra_testo(letterale):
                    avvisi.append(f"{nome_file}:{letterale.riga}: «{letterale.testo}» non viene tradotto "
                                  f"(contesto {letterale.contesto[0] if letterale.contesto else '—'})")
        for chiave in sorted(set(voci) - usate):
            avvisi.append(f"{nome_catalogo}: «{chiave}» non è più usata nel codice")

    for a in avvisi:
        print("avviso:", a)
    for e in errori:
        print("ERRORE:", e)
    print(f"{totale_chiavi} chiavi nei cataloghi, {len(errori)} errori, {len(avvisi)} avvisi.")
    return not errori


if __name__ == "__main__":
    sys.exit(0 if controlla("-v" in sys.argv) else 1)
