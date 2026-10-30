#!/usr/bin/env python3
"""Testi dell'app iPhone e di Stile da tradurre (P22): li cerca nel codice Swift e li confronta con i cataloghi.

Il codice resta in italiano: la chiave di ogni testo è la frase italiana, scritta come la genera Xcode
(«Mi ricollego a %@ tra %lld…»). I cataloghi (String Catalog, JSON) hanno l'italiano e l'inglese:
- iPhone/Risorse/Localizable.xcstrings: i testi dell'app (Text("…"), Button("…"), String(localized: "…")…);
- Stile/Sources/Stile/Resources/Localizable.xcstrings: i testi di Stile, cercati con `bundle: .stile`.

Uso:
  python3 Strumenti/estrai_testi.py              controlla e dice cosa manca (esce con 1 se qualcosa non va)
  python3 Strumenti/estrai_testi.py --aggiorna   aggiunge ai cataloghi le chiavi nuove (con l'italiano, senza inglese)
  python3 Strumenti/estrai_testi.py --dettagli   elenca anche le chiavi con segnaposto e da quale espressione vengono

Controlla:
1. ogni testo localizzato del codice ha la sua chiave nel catalogo, con l'inglese;
2. nel catalogo non restano chiavi che il codice non usa più;
3. in Stile ogni testo localizzato porta `bundle: .stile` (senza, si cercherebbe nell'app);
4. i letterali che non passano da nessuna traduzione: l'elenco «Da controllare», tolti quelli tecnici noti
   (chiavi di UserDefaults, simboli SF…). Ciò che resta va guardato a mano.

I segnaposto si deducono dall'espressione interpolata: %lld per gli interi, %@ per il resto. Dove il nome non
basta c'è la tabella TIPI qui sotto: se un'interpolazione nuova è un intero, va aggiunta lì.
"""
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

RADICE = Path(__file__).resolve().parent.parent

BERSAGLI = [
    {"nome": "iPhone", "sorgenti": RADICE / "iPhone/Sorgenti",
     "catalogo": RADICE / "iPhone/Risorse/Localizable.xcstrings", "bundle": None},
    {"nome": "Stile", "sorgenti": RADICE / "Stile/Sources/Stile",
     "catalogo": RADICE / "Stile/Sources/Stile/Resources/Localizable.xcstrings", "bundle": ".stile"},
]

# Chiamate di SwiftUI il cui primo argomento (senza etichetta) è un LocalizedStringKey.
CHIAVE_PRIMO_ARGOMENTO = {
    "Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField", "Link", "LabeledContent",
    "navigationTitle", "alert", "confirmationDialog", "accessibilityLabel", "accessibilityHint",
    "accessibilityValue", "Section", "Menu", "help",
}
# Chiamate con un'etichetta precisa che è un LocalizedStringKey (o String.LocalizationValue).
CHIAVE_ETICHETTA = {
    ("String", "localized"), ("accessibilityAction", "named"), ("searchable", "prompt"),
    # Funzioni dell'app con parametri LocalizedStringKey.
    ("permesso", "titolo"), ("permesso", "testo"), ("CursoreEffetto", "titolo"), ("rigaCursore", "titolo"),
}
# Funzioni dell'app il cui argomento senza etichetta è un LocalizedStringKey.
CHIAVE_SENZA_ETICHETTA = {"passo", "pulsante", "riga"}
# Etichette che non sono mai testo da tradurre.
ETICHETTE_TECNICHE = {"systemImage", "systemName", "icona", "destination", "bundle", "comment", "tableName", "id",
                      "verbatim", "forKey", "label", "name", "named", "withName"}

# Interpolazioni intere dove il nome non basta: (file, espressione) oppure (None, espressione) per tutti i file.
TIPI = {
    (None, "secondi"): "%lld", (None, "gradi"): "%lld", (None, "tentativo"): "%lld", (None, "numero"): "%lld",
    (None, "latenza"): "%lld", (None, "secondiAlRicollegamento"): "%lld", (None, "sessione.batteria"): "%lld",
    (None, "minuti"): "%lld",
    (None, "SessioneTelefono.tentativiMassimi"): "%lld", (None, "sessione.tempo"): "%lld",
    (None, "sessione.bianco"): "%lld", (None, "lettura.temperatura"): "%lld", (None, "cerca.computer.count"): "%lld",
    ("Qualita.swift", "$0"): "%lld", ("PresentazioneStile.swift", "totale"): "%lld",
    ("SessioneTelefono.swift", "larghezza"): "%lld", ("SessioneTelefono.swift", "altezza"): "%lld",
    ("SessioneTelefono.swift", "fps"): "%lld", ("SessioneTelefono.swift", "atteso.fps"): "%lld",
}

# Letterali tecnici noti, fuori dai testi da tradurre (per l'elenco «Da controllare»).
CHIAMATE_TECNICHE = {
    "DispatchQueue", "applyingFilter", "UIFont", "Image", "string", "bool", "object", "set",
    "removeObject", "AppStorage", "URL", "URLQueryItem", "appendingPathComponent", "hasPrefix", "Comando",
    "assertionFailure", "url", "Logger", "registra", "replacingOccurrences",
    "joined", "forInfoDictionaryKey", "contains", "viaCavo", "FoglioDomande", "DomandaDaAprire", "apriDomanda",
    "path", "integer", "double", "data", "custom",
}
# Testi che restano uguali in ogni lingua o non si vedono (nomi di effetti per il registro, sigle, unità).
IGNORA = {
    "Pelle", "Scritta", "Sfondo", "Filtro", "Regolazioni", "Inquadratura automatica", "Luce sul volto", "Volto e scrivania",
    "Wi-Fi", "H.264", "HEVC", "0,5×", "1×", "macOS · %@", "Windows · %@", "OrbitLR", "GateLR", "WebcamLR",
    "Webcam", "LR", "PRO", "WebcamLR Pro", "Computer", "ISO", "—", "— ms",
    # Identificatori in minuscolo: id delle domande frequenti, chiavi, simboli SF, codici di lingua.
    "localhost", "cavo", "firewall", "aggiorna", "postura", "assistente", "prova", "h264", "hevc", "continuo",
    "wifi", "network", "personalhotspot", "it", "en", "mailto", "specchia",
    # L'indirizzo del sito, mostrato così com'è nella presentazione.
    "lr-apps609.github.io/WebcamLR",
}
# Il registro del collegamento si vede nell'app (Impostazioni › Registro del collegamento): le sue righe passano dal
# catalogo come tutti gli altri testi (String(localized:)), come sul Mac e su Android. Restano fuori solo le righe
# uguali in ogni lingua.
REGISTRO = {
    "Video %@×%@, %@ fps, %@",
}
# Argomenti che non si vedono: le parole in più per la ricerca nelle domande frequenti (`parole`), l'id di una
# risposta (`domanda`), i valori dei Picker (`tag`), i simboli SF.
ETICHETTE_NASCOSTE = {"parole", "domanda", "tag", "verbatim", "simbolo", "codec", "defaultValue"} | ETICHETTE_TECNICHE
RE_UNITA = re.compile(r"%[-+.\d]*(?:lld|ld|d|@|lf|f)|\b(?:ms|s|K|fps|p|ISO|iOS|x|k)\b")
# Identificatori, simboli SF, nomi di caratteri e file, risoluzioni («1080p», «4K»).
RE_TECNICO = re.compile(r"^(?:[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*|[a-z][A-Za-z0-9]*(?:[.\-_:|][A-Za-z0-9]*)+"
                        r"|[A-Z]{2,}[A-Za-z]*|[A-Z][A-Za-z]+-[A-Za-z]+|\d+[pK]\d*|[\d\W_]*|.*\.(?:png|jpg|ttf))$")


# ---------------------------------------------------------------------------------------------------------
# Lettura del Swift: letterali con interpolazioni, commenti esclusi.

def leggi_letterale(testo, i):
    """`testo[i]` è la virgoletta d'apertura. Ritorna (fine, parti) con fine sulla virgoletta di chiusura;
    le parti sono ("testo", s) o ("espr", s)."""
    parti = []
    attuale = []
    j = i + 1
    while True:
        c = testo[j]
        if c == "\\":
            succ = testo[j + 1]
            if succ == "(":
                if attuale:
                    parti.append(("testo", "".join(attuale)))
                    attuale = []
                k = j + 2
                profondita = 1
                inizio = k
                while profondita:
                    if testo[k] == '"':
                        k = leggi_letterale(testo, k)[0] + 1
                        continue
                    if testo[k] == "(":
                        profondita += 1
                    elif testo[k] == ")":
                        profondita -= 1
                    k += 1
                parti.append(("espr", testo[inizio:k - 1].strip()))
                j = k
                continue
            attuale.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(succ, succ))
            j += 2
            continue
        if c == '"':
            if attuale:
                parti.append(("testo", "".join(attuale)))
            return j, parti
        attuale.append(c)
        j += 1


def letterali(testo):
    """Tutti i letterali fuori dai commenti: lista di (inizio, fine, parti)."""
    risultato = []
    i = 0
    n = len(testo)
    while i < n:
        if testo.startswith("//", i):
            i = testo.find("\n", i)
            if i < 0:
                break
            continue
        if testo.startswith("/*", i):
            i = testo.find("*/", i) + 2
            continue
        if testo[i] == '"':
            fine, parti = leggi_letterale(testo, i)
            risultato.append((i, fine, parti))
            i = fine + 1
            continue
        i += 1
    return risultato


def contesto(testo, inizio, spazi):
    """La chiamata che contiene il letterale e l'etichetta del suo argomento: (chiamata, etichetta, apertura).
    `spazi`: gli intervalli dei letterali, da saltare camminando all'indietro."""
    profondita = 0
    i = inizio - 1
    argomento_inizio = None
    while i >= 0:
        salto = spazi.get(i)
        if salto is not None:
            i = salto - 1
            continue
        c = testo[i]
        if c in ")]}":
            profondita += 1
        elif c in "([{":
            if profondita == 0:
                if c == "[":
                    # Un elenco è trasparente: conta la chiamata che lo contiene (per esempio `parole: [...]`).
                    argomento_inizio = None
                    i -= 1
                    continue
                if argomento_inizio is None:
                    argomento_inizio = i + 1
                if c != "(":
                    return None, None, i
                m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", testo[:i])
                chiamata = m.group(1) if m else None
                prefisso = testo[argomento_inizio:inizio].lstrip(" \n[")
                e = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)", prefisso)
                etichetta = e.group(1) if e else None
                return chiamata, etichetta, i
            profondita -= 1
        elif c == "," and profondita == 0 and argomento_inizio is None:
            argomento_inizio = i + 1
        i -= 1
    return None, None, None


def argomenti(testo, apertura):
    """Il testo tra la parentesi `apertura` e quella che la chiude."""
    profondita = 0
    i = apertura
    while i < len(testo):
        c = testo[i]
        if c == '"':
            i = leggi_letterale(testo, i)[0] + 1
            continue
        if c == "(":
            profondita += 1
        elif c == ")":
            profondita -= 1
            if profondita == 0:
                return testo[apertura + 1:i]
        i += 1
    return testo[apertura + 1:]


def segnaposto(file, espressione):
    for chiave in ((file, espressione), (None, espressione)):
        if chiave in TIPI:
            return TIPI[chiave]
    if re.match(r"^Int\(", espressione) or espressione.endswith(".count"):
        return "%lld"
    return "%@"


def chiave(file, parti):
    """La chiave come la scrive Xcode: senza interpolazioni il testo così com'è; con le interpolazioni i
    segnaposto e i % del testo raddoppiati."""
    if not any(tipo == "espr" for tipo, _ in parti):
        return "".join(valore for _, valore in parti)
    return "".join(valore.replace("%", "%%") if tipo == "testo" else segnaposto(file, valore) for tipo, valore in parti)


def analizza(bersaglio):
    """Ritorna (usate, italiano, problemi, da_controllare, con_segnaposto). `italiano`: il testo italiano
    di ogni chiave, cioè la chiave stessa o il `defaultValue:` di String(localized:defaultValue:)."""
    usate = OrderedDict()
    italiano = {}
    problemi = []
    da_controllare = []
    con_segnaposto = []
    # Anche le sottocartelle (per esempio iPhone/Sorgenti/Presentazione).
    for percorso in sorted(bersaglio["sorgenti"].rglob("*.swift")):
        testo = percorso.read_text(encoding="utf-8")
        trovati = letterali(testo)
        spazi = {fine: inizio for inizio, fine, _ in trovati}
        for inizio, fine, parti in trovati:
            riga = testo.count("\n", 0, inizio) + 1
            dove = f"{percorso.relative_to(RADICE)}:{riga}"
            chiamata, etichetta, apertura = contesto(testo, inizio, spazi)
            if etichetta in ETICHETTE_TECNICHE and not (chiamata, etichetta) in CHIAVE_ETICHETTA:
                localizzato = False
            elif (chiamata, etichetta) in CHIAVE_ETICHETTA:
                localizzato = True
            elif etichetta is None and (chiamata in CHIAVE_PRIMO_ARGOMENTO or chiamata in CHIAVE_SENZA_ETICHETTA):
                localizzato = True
            else:
                localizzato = False
            # Dentro una somma di stringhe («a + "\n" + b») il letterale è una String, non una chiave.
            if localizzato and (testo[:inizio].rstrip().endswith("+") or testo[fine + 1:].lstrip().startswith("+")):
                localizzato = False
            k = chiave(percorso.name, parti)
            if localizzato:
                if bersaglio["bundle"]:
                    if apertura is None or f"bundle: {bersaglio['bundle']}" not in argomenti(testo, apertura):
                        problemi.append(f"{dove}: «{k}» senza bundle: {bersaglio['bundle']}")
                usate.setdefault(k, []).append(dove)
                valore = k
                if chiamata == "String" and etichetta == "localized":
                    predefinito = re.search(r'defaultValue:\s*"((?:[^"\\]|\\.)*)"', argomenti(testo, apertura))
                    if predefinito:
                        valore = predefinito.group(1)
                if italiano.get(k, valore) != valore:
                    problemi.append(f"{dove}: «{k}» con due testi italiani diversi")
                italiano[k] = valore
                if any(tipo == "espr" for tipo, _ in parti):
                    espressioni = [valore for tipo, valore in parti if tipo == "espr"]
                    con_segnaposto.append((dove, k, espressioni))
            else:
                if chiamata in CHIAMATE_TECNICHE or etichetta in ETICHETTE_NASCOSTE:
                    continue
                if k in IGNORA or k in REGISTRO:
                    continue
                resto = RE_UNITA.sub("", RE_UNITA.sub("", k))
                if RE_TECNICO.match(k) or RE_TECNICO.match(resto) or not any(c.isalpha() for c in resto):
                    continue
                da_controllare.append(f"{dove}: «{k}» (in {chiamata or '?'}{', ' + etichetta if etichetta else ''})")
    return usate, italiano, problemi, da_controllare, con_segnaposto


# ---------------------------------------------------------------------------------------------------------
# Catalogo

def leggi_catalogo(percorso):
    if not percorso.exists():
        return {"sourceLanguage": "it", "strings": {}, "version": "1.0"}
    return json.loads(percorso.read_text(encoding="utf-8"))


def scrivi_catalogo(percorso, catalogo):
    """Come lo salva Xcode: chiavi in ordine, rientro di due spazi, « : » tra chiave e valore."""
    percorso.parent.mkdir(parents=True, exist_ok=True)
    percorso.write_text(json.dumps(catalogo, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True)
                        + "\n", encoding="utf-8")


def unita(voce, lingua):
    return voce.get("localizations", {}).get(lingua, {}).get("stringUnit", {})


def segnaposti(testo):
    return sorted(re.findall(r"%(?:\d+\$)?(?:lld|@|ld|d|lf|f)", testo.replace("%%", "")))


def main():
    aggiorna = "--aggiorna" in sys.argv
    dettagli = "--dettagli" in sys.argv
    errori = 0
    for bersaglio in BERSAGLI:
        usate, italiano, problemi, da_controllare, con_segnaposto = analizza(bersaglio)
        catalogo = leggi_catalogo(bersaglio["catalogo"])
        voci = catalogo["strings"]
        mancanti = [k for k in usate if k not in voci]
        senza_inglese = [k for k in usate if k in voci and not unita(voci[k], "en").get("value")]
        inutili = [k for k in voci if k not in usate]
        # L'italiano non deve cambiare: il valore «it» del catalogo è il testo del codice.
        italiano_diverso = [k for k in usate if k in voci and unita(voci[k], "it").get("value", k) != italiano[k]]
        segnaposti_diversi = [k for k in usate if k in voci and unita(voci[k], "en").get("value")
                              and segnaposti(re.sub(r"%\d+\$", "%", unita(voci[k], "en")["value"]))
                              != segnaposti(k)]
        print(f"== {bersaglio['nome']}: {len(usate)} testi nel codice, {len(voci)} nel catalogo")
        if aggiorna:
            for k in mancanti:
                voci[k] = {"extractionState": "manual",
                           "localizations": {"it": {"stringUnit": {"state": "translated", "value": italiano[k]}}}}
            scrivi_catalogo(bersaglio["catalogo"], catalogo)
            if mancanti:
                print(f"   aggiunte {len(mancanti)} chiavi (manca l'inglese)")
            senza_inglese += mancanti
            mancanti = []
        for titolo, elenco in (("Chiavi mancanti nel catalogo", mancanti), ("Senza inglese", senza_inglese),
                               ("Segnaposto diversi tra chiave e inglese", segnaposti_diversi),
                               ("Italiano del catalogo diverso dal codice", italiano_diverso),
                               ("Nel catalogo ma non più nel codice", inutili), ("Problemi", problemi)):
            if elenco:
                errori += len(elenco)
                print(f"   {titolo} ({len(elenco)}):")
                for voce in elenco:
                    print(f"     - {voce}" + (f"  ← {usate[voce][0]}" if voce in usate else ""))
        if da_controllare:
            print(f"   Da controllare: letterali non tradotti ({len(da_controllare)}):")
            for voce in da_controllare:
                print(f"     - {voce}")
        if dettagli:
            print(f"   Chiavi con segnaposto ({len(con_segnaposto)}):")
            for dove, k, espressioni in con_segnaposto:
                print(f"     - {dove}: «{k}» ← {', '.join(espressioni)}")
    if errori:
        print(f"\n{errori} cose da sistemare.")
        return 1
    print("\nTutto a posto: ogni testo ha la sua traduzione.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
