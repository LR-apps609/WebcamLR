#!/usr/bin/env python3
"""Genera i token grafici delle quattro app e del sito da Documenti/token.json (descritto in Documenti/Stile.md).

Scrive:
- Stile/Sources/Stile/Token.swift            colori di `Tema`, `Spazi`, `Raggi`, `Opacita`, `Veli`, `StileTesto` (iPhone e Mac)
- Windows/WebcamLR.App/Token.xaml            Color, SolidColorBrush, FontFamily, Thickness, CornerRadius, Double
- Windows/WebcamLR.App/Token.cs             gli stessi token per il codice C# (costanti)
- Windows/WebcamLR.App/App.xaml              solo il blocco tra «genera_token: inizio» e «genera_token: fine»
- Android/app/src/main/kotlin/it/lrapps/webcamlr/android/ui/Token.kt   `Colori`, `Spazi`, `Raggi`, `Opacita`, `Veli`, `StiliTesto`
- Android/app/src/main/res/values/colors.xml i pochi colori che servono alle risorse di Android
- Strumenti/uscita/token.css                 variabili CSS per il sito (si porta sul ramo main nella fase 6)
- Documenti/Stile.md                         solo le tabelle tra «genera_token:inizio» e «genera_token:fine»

Uso:
    python3 Strumenti/genera_token.py              riscrive i file
    python3 Strumenti/genera_token.py --controlla  non scrive nulla; esce con 1 se un file non coincide con token.json

I token si cambiano solo in Documenti/token.json, poi si rilancia questo script. Il campo "attivo" ("oggi" o "beta4")
sceglie quale valore usano i colori che ne hanno due.
"""
import json
import re
import sys
from pathlib import Path

RADICE = Path(__file__).resolve().parent.parent
TABELLA = RADICE / "Documenti" / "token.json"

SWIFT = RADICE / "Stile" / "Sources" / "Stile" / "Token.swift"
XAML = RADICE / "Windows" / "WebcamLR.App" / "Token.xaml"
CS = RADICE / "Windows" / "WebcamLR.App" / "Token.cs"
APP_XAML = RADICE / "Windows" / "WebcamLR.App" / "App.xaml"
KOTLIN = RADICE / "Android" / "app" / "src" / "main" / "kotlin" / "it" / "lrapps" / "webcamlr" / "android" / "ui" / "Token.kt"
COLORS_XML = RADICE / "Android" / "app" / "src" / "main" / "res" / "values" / "colors.xml"
CSS = RADICE / "Strumenti" / "uscita" / "token.css"
STILE_MD = RADICE / "Documenti" / "Stile.md"

AVVISO = "File generato da Strumenti/genera_token.py da Documenti/token.json: non modificarlo a mano."
PESI_KOTLIN = {400: "Normal", 500: "Medium", 600: "SemiBold", 700: "Bold"}


# ---------------------------------------------------------------------------------------------------------------
# Lettura della tabella

def leggi():
    with open(TABELLA, encoding="utf-8") as f:
        t = json.load(f)
    if t["attivo"] not in ("oggi", "beta4"):
        sys.exit(f"token.json: «attivo» deve essere «oggi» o «beta4», non «{t['attivo']}»")
    for c in t["colori"] + t["contorni"]:
        for chiave in ("oggi", "beta4"):
            if chiave in c and not re.fullmatch(r"#[0-9A-F]{6}", c[chiave]):
                sys.exit(f"token.json: {c['nome']}.{chiave} = {c[chiave]!r}, serve #RRGGBB in maiuscolo")
    nomi = [c["nome"] for c in tutti_i_colori(t)]
    doppi = {n for n in nomi if nomi.count(n) > 1}
    if doppi:
        sys.exit(f"token.json: nomi di colore doppi: {sorted(doppi)}")
    return t


def tutti_i_colori(t):
    return t["colori"] + t["contorni"]


def valore(t, c):
    """Il valore attivo di un colore: quello della beta 4 se è attiva e il colore ne ha uno, altrimenti quello di oggi."""
    if t["attivo"] == "beta4" and "beta4" in c:
        return c["beta4"]
    return c["oggi"]


def colore_per_nome(t, nome):
    for c in tutti_i_colori(t):
        if c["nome"] == nome:
            return valore(t, c)
    sys.exit(f"token.json: colore sconosciuto «{nome}»")


def risolvi(t, rif):
    """«#RRGGBB», «@nome» o «@nome/0.6» → (rgb «RRGGBB», alfa 0–255)."""
    alfa = 255
    if rif.startswith("@"):
        nome, _, opacita = rif[1:].partition("/")
        rgb = colore_per_nome(t, nome)[1:]
        if opacita:
            alfa = round(float(opacita) * 255)
    else:
        rgb = rif[1:]
        if len(rgb) == 8:
            alfa, rgb = int(rgb[:2], 16), rgb[2:]
    return rgb.upper(), alfa


def esa_xaml(rgb, alfa):
    return f"#{rgb}" if alfa == 255 else f"#{alfa:02X}{rgb}"


def maiuscola(nome):
    return nome[0].upper() + nome[1:]


def trattini(nome):
    return re.sub(r"([A-Z])", lambda m: "-" + m.group(1).lower(), nome)


def serpente(nome):
    return re.sub(r"([A-Z])", lambda m: "_" + m.group(1).lower(), nome)


def numero(v):
    """4 → «4», 0.45 → «0.45»."""
    return str(int(v)) if float(v).is_integer() else repr(float(v))


def virgola(v):
    return numero(v).replace(".", ",")


def carattere(t, nome):
    for c in t["caratteri"]:
        if c["nome"] == nome:
            return c
    sys.exit(f"token.json: carattere sconosciuto «{nome}»")


def misura(stile, dove):
    """dove: «mac», «windows» o «telefono». Il Mac usa «computer» se non ha un valore suo."""
    if dove == "telefono":
        return stile["telefono"]
    if dove == "mac":
        return stile.get("mac", stile["computer"])
    return stile["computer"]


def rgb_decimale(rgb):
    return ", ".join(str(int(rgb[i:i + 2], 16)) for i in (0, 2, 4))


# ---------------------------------------------------------------------------------------------------------------
# Swift (Stile, per iPhone e Mac)

def genera_swift(t):
    r = [f"// {AVVISO}", f"// Valori attivi: «{t['attivo']}». Descrizione e regole in Documenti/Stile.md.", "",
         "import SwiftUI", "",
         "extension Tema {"]
    for c in t["colori"]:
        r.append(f"    /// {c['ruolo']}.")
        r.append(f"    public static let {c['nome']} = Color(esadecimale: 0x{valore(t, c)[1:]})")
    r.append("")
    r.append("    // Contorni dei controlli: nuovi nomi, oggi con il valore di `linea` (la beta 4 li porta a 3:1).")
    for c in t["contorni"]:
        r.append(f"    /// {c['ruolo']}.")
        r.append(f"    public static let {c['nome']} = Color(esadecimale: 0x{valore(t, c)[1:]})")
    deprecati = [(alias, c) for c in t["colori"] for alias in c.get("aliasDeprecati", [])]
    if deprecati:
        r.append("")
        r.append("    // Nomi di prima, deprecati.")
        for alias, c in deprecati:
            r.append(f"    /// Deprecato: usa `{c['nome']}`.")
            r.append(f"    public static var {alias}: Color {{ {c['nome']} }}")
    r.append("}")
    r.append("")

    r.append("/// Spazi tra gli elementi, in punti: 4 · 8 · 12 · 16 · 24 · 32.")
    r.append("public enum Spazi {")
    for s in t["spazi"]:
        r.append(f"    public static let {s['nome']}: CGFloat = {numero(s['valore'])}")
    r.append("}")
    r.append("")
    r.append("/// Raggi degli angoli, in punti. `capsula` su un quadrato fa il cerchio: SwiftUI limita il raggio a metà del lato corto.")
    r.append("public enum Raggi {")
    for s in t["raggi"]:
        r.append(f"    /// {maiuscola(s['uso'])}.")
        r.append(f"    public static let {s['nome']}: CGFloat = {numero(s['valore'])}")
    r.append("}")
    r.append("")
    r.append("/// Opacità comuni.")
    r.append("public enum Opacita {")
    for s in t["opacita"]:
        r.append(f"    /// {maiuscola(s['uso'])}.")
        r.append(f"    public static let {s['nome']}: Double = {numero(s['valore'])}")
    r.append("}")
    r.append("")
    base = t["veli"]["colore"]
    r.append(f"/// Veli sopra il video o sotto un foglio: `{base}` con l'opacità del livello.")
    r.append("public enum Veli {")
    for v in t["veli"]["livelli"]:
        r.append(f"    public static let {v['nome']}: Double = {numero(v['valore'])}")
    for v in t["veli"]["livelli"]:
        r.append(f"    public static let colore{maiuscola(v['nome'])} = Tema.{base}.opacity({numero(v['valore'])})")
    r.append("}")
    r.append("")

    stili = t["stiliTesto"]
    r.append("/// Gli stili di testo con nome. Misure: Mac e iPhone dalla tabella; crescono con Dynamic Type (`relativeTo:`).")
    r.append("/// Uso: `Text(\"IN ONDA\").stileTesto(.statoGrande)`, oppure solo il carattere con `StileTesto.corpo.font`.")
    r.append("public enum StileTesto: CaseIterable {")
    for s in stili:
        r.append(f"    /// {s['uso']}.")
        r.append(f"    case {s['nome']}")
    r.append("")
    r.append("    /// Nome PostScript del carattere (registrato da `Caratteri.registra()`).")
    r.append("    public var nomeCarattere: String {")
    r.append("        switch self {")
    for s in stili:
        r.append(f"        case .{s['nome']}: return \"{carattere(t, s['carattere'])['postscript']}\"")
    r.append("        }")
    r.append("    }")
    r.append("")
    r.append("    /// Misura di partenza in punti (Mac sul Mac, telefono su iPhone).")
    r.append("    public var misura: CGFloat {")
    r.append("        switch self {")
    for s in stili:
        mac, tel = misura(s, "mac"), misura(s, "telefono")
        if mac == tel:
            r.append(f"        case .{s['nome']}: return {numero(mac)}")
        else:
            r.append(f"        case .{s['nome']}:")
            r.append("            #if os(macOS)")
            r.append(f"            return {numero(mac)}")
            r.append("            #else")
            r.append(f"            return {numero(tel)}")
            r.append("            #endif")
    r.append("        }")
    r.append("    }")
    r.append("")
    r.append("    /// Lo stile di sistema con cui cresce per Dynamic Type.")
    r.append("    public var relativoA: Font.TextStyle {")
    r.append("        switch self {")
    for s in stili:
        r.append(f"        case .{s['nome']}: return .{s['relativoA']}")
    r.append("        }")
    r.append("    }")
    r.append("")
    r.append("    /// Spaziatura tra le lettere, in punti.")
    r.append("    public var spaziatura: CGFloat {")
    r.append("        switch self {")
    con = [s for s in stili if s.get("spaziatura")]
    for s in con:
        r.append(f"        case .{s['nome']}: return {numero(s['spaziatura'])}")
    if len(con) < len(stili):
        r.append("        default: return 0")
    r.append("        }")
    r.append("    }")
    r.append("")
    r.append("    /// Vero se lo stile si scrive in maiuscolo.")
    r.append("    public var maiuscolo: Bool {")
    r.append("        switch self {")
    con = [s for s in stili if s.get("maiuscolo")]
    for s in con:
        r.append(f"        case .{s['nome']}: return true")
    if len(con) < len(stili):
        r.append("        default: return false")
    r.append("        }")
    r.append("    }")
    r.append("")
    r.append("    public var font: Font {")
    r.append("        .custom(nomeCarattere, size: misura, relativeTo: relativoA)")
    r.append("    }")
    r.append("}")
    r.append("")
    r.append("extension View {")
    r.append("    /// Carattere, spaziatura e maiuscolo di uno degli stili di testo.")
    r.append("    public func stileTesto(_ stile: StileTesto) -> some View {")
    r.append("        font(stile.font)")
    r.append("            .tracking(stile.spaziatura)")
    r.append("            .textCase(stile.maiuscolo ? Text.Case.uppercase : nil)")
    r.append("    }")
    r.append("}")
    return "\n".join(r) + "\n"


# ---------------------------------------------------------------------------------------------------------------
# Windows (WinUI 3)

def genera_xaml(t):
    r = ['<?xml version="1.0" encoding="utf-8"?>',
         f"<!-- {AVVISO}",
         f"     Valori attivi: «{t['attivo']}». Incluso in App.xaml (MergedDictionaries). Chiavi: ColoreNome (Color), Nome",
         "     (SolidColorBrush, le stesse di prima), SpazioNome (Double), MargineNome (Thickness), RaggioNome (CornerRadius),",
         "     OpacitaNome (Double), MisuraStile (Double, punti per computer). -->",
         "<ResourceDictionary",
         '    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"',
         '    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">',
         "",
         "    <!-- Colori della famiglia WebcamLR, gli stessi di Stile (Tema) e di Android (Colori). Il corallo (Tally) solo per",
         "         «in onda» e registrazione. I nomi di prima restano come alias: Scheda = PannelloChiaro, Ciano = Accento. -->"]
    inizio_chiavi = len(r) - 2
    for c in tutti_i_colori(t):
        r.append(f'    <Color x:Key="Colore{maiuscola(c["nome"])}">{valore(t, c)}</Color>')
    base = t["veli"]["colore"]
    r.append("")
    for v in t["veli"]["livelli"]:
        r.append(f'    <x:Double x:Key="OpacitaVelo{maiuscola(v["nome"])}">{numero(v["valore"])}</x:Double>')
    r.append("")
    # I pennelli (Nome, Velo…, quelli solo di Windows e le sfumature): nei dizionari dei temi, «Default» con i colori di
    # WebcamLR e «HighContrast» con i colori di sistema (soloWindows.contrastoElevato), così con il Contrasto elevato di
    # Windows superfici, testi e contorni seguono il tema scelto. I «fissi» stanno fuori, uguali in tutti i temi.
    pennelli = []  # (chiave, righe XAML, commento o None)
    for c in tutti_i_colori(t):
        chiavi = [maiuscola(c["nome"])] + c.get("aliasWindows", []) + [maiuscola(a) for a in c.get("aliasDeprecati", [])]
        for k in chiavi:
            pennelli.append((k, [f'<SolidColorBrush x:Key="{k}" Color="{valore(t, c)}" />'], None))
    for i, v in enumerate(t["veli"]["livelli"]):
        rgb, alfa = risolvi(t, "@" + base + "/" + str(v["valore"]))
        k = f"Velo{maiuscola(v['nome'])}"
        commento = f"Veli: {base} con l'opacità del livello." if i == 0 else None
        pennelli.append((k, [f'<SolidColorBrush x:Key="{k}" Color="{esa_xaml(rgb, alfa)}" />'], commento))
    for p in t["soloWindows"]["pennelli"]:
        pennelli.append((p["chiave"], [f'<SolidColorBrush x:Key="{p["chiave"]}" Color="{esa_xaml(*risolvi(t, p["colore"]))}" />'],
                         p["ruolo"] + "."))
    for s in t["soloWindows"]["sfumature"]:
        righe = [f'<LinearGradientBrush x:Key="{s["chiave"]}" StartPoint="{s["inizio"]}" EndPoint="{s["fine"]}">']
        n = len(s["fermate"])
        for i, f in enumerate(s["fermate"]):
            righe.append(f'    <GradientStop Offset="{numero(i / (n - 1))}" Color="{esa_xaml(*risolvi(t, f))}" />')
        righe.append("</LinearGradientBrush>")
        pennelli.append((s["chiave"], righe, None))
    sistema = gruppi_contrasto(t, [k for k, _, _ in pennelli])
    fissi = set(t["soloWindows"]["contrastoElevato"]["fissi"])
    # In XAML il contenuto di un dizionario non si può spezzare con un elemento proprietà: i dizionari dei temi vanno
    # prima di tutte le chiavi (dopo l'intestazione).
    temi = ["    <!-- I pennelli (SolidColorBrush e sfumature) nei dizionari dei temi: «Default» con i colori di WebcamLR,",
            "         «HighContrast» con i colori di sistema quando in Windows è acceso un tema a contrasto (soloWindows.",
            "         contrastoElevato in token.json). Nello XAML si leggono con ThemeResource, così seguono il cambio di tema. -->"]
    temi.append("    <ResourceDictionary.ThemeDictionaries>")
    temi.append('        <ResourceDictionary x:Key="Default">')
    for k, righe, commento in pennelli:
        if k in fissi:
            continue
        if commento:
            temi.append(f"            <!-- {commento} -->")
        temi.extend("            " + riga for riga in righe)
    temi.append("        </ResourceDictionary>")
    temi.append("        <!-- Contrasto elevato: i colori del tema di Windows (Impostazioni › Accessibilità › Temi a contrasto). -->")
    temi.append('        <ResourceDictionary x:Key="HighContrast">')
    for k, _, _ in pennelli:
        if k in fissi:
            continue
        colore = sistema[k]
        valore_hc = "Transparent" if colore is None else f"{{ThemeResource SystemColor{colore}Color}}"
        temi.append(f'            <SolidColorBrush x:Key="{k}" Color="{valore_hc}" />')
    temi.append("        </ResourceDictionary>")
    temi.append("    </ResourceDictionary.ThemeDictionaries>")
    temi.append("")
    r[inizio_chiavi:inizio_chiavi] = temi
    r.append("    <!-- Uguali in tutti i temi. -->")
    for k, righe, commento in pennelli:
        if k in fissi:
            if commento:
                r.append(f"    <!-- {commento} -->")
            r.extend("    " + riga for riga in righe)
    r.append("")
    r.append("    <!-- Barlow Condensed per i titoli e le etichette, Barlow per il testo, IBM Plex Mono per i numeri tecnici")
    r.append("         (SIL Open Font License, file OFL-*.txt nella cartella Caratteri), come in Stile/Sources/Stile/Caratteri.swift. -->")
    for c in t["caratteri"]:
        r.append(f'    <FontFamily x:Key="{c["windows"]}">ms-appx:///Assets/Caratteri/{c["file"]}#{c["windowsFamiglia"]}</FontFamily>')
    r.append("")
    r.append("    <!-- Misure degli stili di testo (computer), in punti. -->")
    for s in t["stiliTesto"]:
        r.append(f'    <x:Double x:Key="Misura{maiuscola(s["nome"])}">{numero(misura(s, "windows"))}</x:Double>')
    for s in t["stiliTesto"]:
        if s.get("spaziatura"):
            millesimi = round(s["spaziatura"] / misura(s, "windows") * 1000)
            r.append(f'    <x:Int32 x:Key="Spaziatura{maiuscola(s["nome"])}">{millesimi}</x:Int32>')
    r.append("")
    r.append("    <!-- Spazi (Double e Thickness uniforme), raggi e opacità. RaggioCapsula: WinUI limita il raggio a metà del lato. -->")
    for s in t["spazi"]:
        r.append(f'    <x:Double x:Key="Spazio{maiuscola(s["nome"])}">{numero(s["valore"])}</x:Double>')
    for s in t["spazi"]:
        r.append(f'    <Thickness x:Key="Margine{maiuscola(s["nome"])}">{numero(s["valore"])}</Thickness>')
    for s in t["raggi"]:
        r.append(f'    <CornerRadius x:Key="Raggio{maiuscola(s["nome"])}">{numero(s["valore"])}</CornerRadius>')
    for s in t["opacita"]:
        r.append(f'    <x:Double x:Key="Opacita{maiuscola(s["nome"])}">{numero(s["valore"])}</x:Double>')
    m = t["soloWindows"]["misure"]
    r.append("")
    r.append("    <!-- Solo Windows (soloWindows.misure): le misure di oggi fuori dalla scala comune, a parità di aspetto.")
    r.append("         La beta 4 le riporta sulla scala. Ogni raggio ha anche RaggioNomeValore (Double) per RadiusX/RadiusY. -->")
    for s in m["testo"]:
        r.append(f'    <x:Double x:Key="Misura{maiuscola(s["nome"])}">{numero(s["valore"])}</x:Double>')
    for s in m["spazi"]:
        r.append(f'    <x:Double x:Key="Spazio{maiuscola(s["nome"])}">{numero(s["valore"])}</x:Double>')
    for s in m["raggi"]:
        r.append(f'    <CornerRadius x:Key="Raggio{maiuscola(s["nome"])}">{numero(s["valore"])}</CornerRadius>')
    for s in t["raggi"] + m["raggi"]:
        r.append(f'    <x:Double x:Key="Raggio{maiuscola(s["nome"])}Valore">{numero(s["valore"])}</x:Double>')
    for s in m["spaziature"]:
        r.append(f'    <x:Int32 x:Key="Spaziatura{maiuscola(s["nome"])}">{numero(s["valore"])}</x:Int32>')
    if m["spessori"]:
        r.append("")
        r.append("    <!-- Spessori (Thickness: sinistra, sopra, destra, sotto) di margini e padding. -->")
    for s in m["spessori"]:
        r.append(f'    <Thickness x:Key="{s["chiave"]}">{spessore(s["valore"])}</Thickness>')
    r.append("</ResourceDictionary>")
    # Le chiavi del dizionario «HighContrast» ripetono quelle di «Default»: si controllano una volta sola.
    testo = "\n".join(r)
    a = testo.find('<ResourceDictionary x:Key="HighContrast">')
    b = testo.find("</ResourceDictionary>", a)
    nessun_doppione(re.findall(r'x:Key="([^"]+)"', testo[:a] + testo[b:]), "Token.xaml")
    return testo + "\n"


def gruppi_contrasto(t, chiavi):
    """{chiave del pennello: colore di sistema (Window, WindowText…) o None se trasparente o fisso}; esce se un pennello
    non ha il suo colore per il Contrasto elevato, se ne ha due o se il gruppo nomina un pennello che non c'è."""
    gruppi = t["soloWindows"]["contrastoElevato"]
    sistema = {}
    for nome, elenco in gruppi.items():
        if nome.startswith("_"):
            continue
        for k in elenco:
            if k in sistema:
                sys.exit(f"token.json: contrastoElevato, {k} è in due gruppi")
            sistema[k] = None if nome in ("Trasparente", "fissi") else nome
    mancanti = [k for k in chiavi if k not in sistema]
    if mancanti:
        sys.exit(f"token.json: contrastoElevato non dice il colore di sistema di: {', '.join(mancanti)}")
    in_piu = sorted(set(sistema) - set(chiavi))
    if in_piu:
        sys.exit(f"token.json: contrastoElevato nomina pennelli che non esistono: {', '.join(in_piu)}")
    return sistema


def nessun_doppione(nomi, file):
    """Una chiave ripetuta in Token.xaml non compila (o chiude l'app all'avvio), un nome ripetuto in Token.cs non compila."""
    doppi = sorted({n for n in nomi if nomi.count(n) > 1})
    if doppi:
        sys.exit(f"token.json: {file} avrebbe nomi ripetuti: {', '.join(doppi)}")


def spessore(valore):
    """[4] → «4», [10, 4] → «10,4», [0, 8, 0, 2] → «0,8,0,2» (come in XAML)."""
    if len(valore) not in (1, 2, 4):
        sys.exit(f"token.json: spessore {valore!r}, servono 1, 2 o 4 numeri")
    return ",".join(numero(v) for v in valore)


def spessore_cs(valore):
    v = [numero(x) for x in valore]
    if len(v) == 1:
        return f"new({v[0]})"
    if len(v) == 2:
        v = [v[0], v[1], v[0], v[1]]
    return f"new({', '.join(v)})"


def argb(rgb, alfa=255):
    return f"0x{alfa:02X}{rgb}"


def genera_cs(t):
    """Gli stessi token di Token.xaml per il codice C# di WebcamLR.App (costanti, senza cercare nelle risorse)."""
    m = t["soloWindows"]["misure"]
    r = [f"// {AVVISO}",
         f"// Valori attivi: «{t['attivo']}». Gli stessi nomi e valori di Token.xaml, per il codice: colori in 0xAARRGGBB",
         "// (Colore(...) li fa diventare Windows.UI.Color), misure in Double, raggi in Double (new CornerRadius(Token.RaggioX)),",
         "// spessori come Thickness.",
         "using Microsoft.UI.Xaml;", "",
         "namespace WebcamLR;", "",
         "internal static class Token", "{",
         "    public static Windows.UI.Color Colore(uint argb) =>",
         "        Windows.UI.Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);", ""]
    for c in tutti_i_colori(t):
        r.append(f"    public const uint Colore{maiuscola(c['nome'])} = {argb(valore(t, c)[1:])};")
    base = t["veli"]["colore"]
    for v in t["veli"]["livelli"]:
        r.append(f"    public const uint ColoreVelo{maiuscola(v['nome'])} = {argb(*risolvi(t, '@' + base + '/' + str(v['valore'])))};")
    for p in t["soloWindows"]["pennelli"]:
        r.append(f"    public const uint Colore{p['chiave']} = {argb(*risolvi(t, p['colore']))};")
    r.append("")
    for s in t["stiliTesto"]:
        r.append(f"    public const double Misura{maiuscola(s['nome'])} = {numero(misura(s, 'windows'))};")
    for s in m["testo"]:
        r.append(f"    public const double Misura{maiuscola(s['nome'])} = {numero(s['valore'])};")
    for s in t["stiliTesto"]:
        if s.get("spaziatura"):
            r.append(f"    public const int Spaziatura{maiuscola(s['nome'])} = {round(s['spaziatura'] / misura(s, 'windows') * 1000)};")
    for s in m["spaziature"]:
        r.append(f"    public const int Spaziatura{maiuscola(s['nome'])} = {numero(s['valore'])};")
    r.append("")
    for s in t["spazi"] + m["spazi"]:
        r.append(f"    public const double Spazio{maiuscola(s['nome'])} = {numero(s['valore'])};")
    for s in t["raggi"] + m["raggi"]:
        r.append(f"    public const double Raggio{maiuscola(s['nome'])} = {numero(s['valore'])};")
    for s in t["opacita"]:
        r.append(f"    public const double Opacita{maiuscola(s['nome'])} = {numero(s['valore'])};")
    for v in t["veli"]["livelli"]:
        r.append(f"    public const double OpacitaVelo{maiuscola(v['nome'])} = {numero(v['valore'])};")
    if m["spessori"]:
        r.append("")
    for s in m["spessori"]:
        r.append(f"    public static Thickness {s['chiave']} => {spessore_cs(s['valore'])};")
    r.append("}")
    nessun_doppione(re.findall(r"^    public (?:const \w+|static Thickness) (\w+)", "\n".join(r), re.M), "Token.cs")
    return "\n".join(r) + "\n"


INIZIO_APP = "<!-- genera_token: inizio"
FINE_APP = "<!-- genera_token: fine -->"


def blocco_app_xaml(t):
    w = t["soloWindows"]
    rientro = " " * 12
    r = [f"{INIZIO_APP} (Strumenti/genera_token.py da Documenti/token.json: non modificare a mano) -->",
         "<!-- Testo scuro sull'accento salvia (pulsanti principali, pulsanti accesi, interruttori), come in Stile:",
         "     il bianco sull'accento chiaro non si legge. -->",
         "<ResourceDictionary.ThemeDictionaries>"]
    primario = esa_xaml(*risolvi(t, w["testoSuAccento"]["primario"]))
    secondario = esa_xaml(*risolvi(t, w["testoSuAccento"]["secondario"]))
    for tema in ("Dark", "Default"):
        r.append(f'    <ResourceDictionary x:Key="{tema}">')
        r.append(f'        <SolidColorBrush x:Key="TextOnAccentFillColorPrimaryBrush" Color="{primario}" />')
        r.append(f'        <SolidColorBrush x:Key="TextOnAccentFillColorSecondaryBrush" Color="{secondario}" />')
        r.append("    </ResourceDictionary>")
    # Senza questo dizionario il Contrasto elevato prenderebbe «Default»: testo verde scuro sull'evidenziazione di sistema.
    r.append('    <ResourceDictionary x:Key="HighContrast">')
    for k in ("TextOnAccentFillColorPrimaryBrush", "TextOnAccentFillColorSecondaryBrush"):
        r.append(f'        <SolidColorBrush x:Key="{k}" Color="{{ThemeResource SystemColorHighlightTextColor}}" />')
    r.append("    </ResourceDictionary>")
    r.append("</ResourceDictionary.ThemeDictionaries>")
    r.append("")
    r.append("<!-- Azioni e selezione nell'accento salvia, non nel colore scelto in Windows (di serie blu): pulsanti principali,")
    r.append("     pulsanti accesi come «Specchia» e «Sfondo», interruttori, selezione negli elenchi.")
    r.append("     Con il tema scuro WinUI usa le varianti «Light»: Light2 è l'accento di Stile. -->")
    for k, v in w["accentoDiSistema"].items():
        r.append(f'<Color x:Key="{k}">{esa_xaml(*risolvi(t, v))}</Color>')
    r.append(FINE_APP)
    return "\n".join(rientro + riga if riga else "" for riga in r)


def sostituisci_blocco(testo, inizio, fine, nuovo, file):
    a = testo.find(inizio)
    b = testo.find(fine, a) if a >= 0 else -1
    if a < 0 or b < 0:
        sys.exit(f"{file}: mancano i segni «{inizio}» … «{fine}»")
    # Il blocco nuovo porta già il suo rientro: si sostituisce dall'inizio della riga del primo segno.
    a = testo.rfind("\n", 0, a) + 1
    return testo[:a] + nuovo + testo[b + len(fine):]


# ---------------------------------------------------------------------------------------------------------------
# Android (Compose)

def kotlin_colore(rgb, alfa=255):
    return f"Color(0x{alfa:02X}{rgb})"


def genera_kotlin(t):
    r = [f"// {AVVISO}", f"// Valori attivi: «{t['attivo']}». Descrizione e regole in Documenti/Stile.md.",
         "package it.lrapps.webcamlr.android.ui", "",
         "import androidx.compose.ui.graphics.Color",
         "import androidx.compose.ui.text.TextStyle",
         "import androidx.compose.ui.text.font.FontWeight",
         "import androidx.compose.ui.unit.dp",
         "import androidx.compose.ui.unit.sp", "",
         "/**",
         " * Colori della famiglia WebcamLR, gli stessi di Stile (Tema) e di Windows. Il corallo del logo è il colore del",
         " * tally: solo «in onda» e registrazione. I colori del logo e il fondo delle schermate stanno in Tema.kt.",
         " */",
         "object Colori {"]
    for c in t["colori"]:
        r.append(f"    /** {c['ruolo']}. */")
        r.append(f"    val {c['nome']} = {kotlin_colore(valore(t, c)[1:])}")
    r.append("")
    r.append("    // Contorni dei controlli: nuovi nomi, oggi con il valore di `linea` (la beta 4 li porta a 3:1).")
    for c in t["contorni"]:
        r.append(f"    /** {c['ruolo']}. */")
        r.append(f"    val {c['nome']} = {kotlin_colore(valore(t, c)[1:])}")
    deprecati = [(alias, c) for c in t["colori"] for alias in c.get("aliasDeprecati", [])]
    if deprecati:
        r.append("")
        for alias, c in deprecati:
            r.append(f'    @Deprecated("Nome di prima: usa {c["nome"]}", ReplaceWith("{c["nome"]}"))')
            r.append(f"    val {alias} get() = {c['nome']}")
    r.append("}")
    r.append("")
    r.append("/** Spazi tra gli elementi: 4 · 8 · 12 · 16 · 24 · 32 dp. */")
    r.append("object Spazi {")
    for s in t["spazi"]:
        r.append(f"    val {s['nome']} = {numero(s['valore'])}.dp")
    r.append("}")
    r.append("")
    r.append("/** Raggi degli angoli. [capsula] su un quadrato fa il cerchio: Compose limita il raggio a metà del lato corto. */")
    r.append("object Raggi {")
    for s in t["raggi"]:
        r.append(f"    /** {maiuscola(s['uso'])}. */")
        r.append(f"    val {s['nome']} = {numero(s['valore'])}.dp")
    r.append("}")
    r.append("")
    r.append("/** Opacità comuni. */")
    r.append("object Opacita {")
    for s in t["opacita"]:
        r.append(f"    /** {maiuscola(s['uso'])}. */")
        r.append(f"    const val {s['nome']} = {numero(s['valore'])}f")
    r.append("}")
    r.append("")
    base = t["veli"]["colore"]
    r.append(f"/** Veli sopra il video o sotto un foglio: [Colori.{base}] con l'opacità del livello. */")
    r.append("object Veli {")
    for v in t["veli"]["livelli"]:
        r.append(f"    const val {v['nome']} = {numero(v['valore'])}f")
    for v in t["veli"]["livelli"]:
        velo = kotlin_colore(*risolvi(t, "@" + base + "/" + str(v["valore"])))
        r.append(f"    val colore{maiuscola(v['nome'])} = {velo}")
    r.append("}")
    r.append("")
    r.append("/** Gli stili di testo con nome, misure del telefono in sp (crescono con la dimensione del carattere di Android). */")
    r.append("object StiliTesto {")
    for s in t["stiliTesto"]:
        c = carattere(t, s["carattere"])
        extra = f", letterSpacing = {numero(s['spaziatura'])}.sp" if s.get("spaziatura") else ""
        nota = " Si scrive in maiuscolo." if s.get("maiuscolo") else ""
        r.append(f"    /** {s['uso']}.{nota} */")
        r.append(f"    val {s['nome']} = TextStyle(fontFamily = Caratteri.{c['android']}, fontWeight = FontWeight.{PESI_KOTLIN[c['peso']]}, "
                 f"fontSize = {numero(misura(s, 'telefono'))}.sp{extra})")
    r.append("}")
    return "\n".join(r) + "\n"


def genera_colors_xml(t):
    r = ['<?xml version="1.0" encoding="utf-8"?>',
         f"<!-- {AVVISO} -->",
         "<resources>"]
    for nome in t["risorseAndroid"]:
        r.append(f'    <color name="{serpente(nome)}">#FF{colore_per_nome(t, nome)[1:]}</color>')
    r.append("</resources>")
    return "\n".join(r) + "\n"


# ---------------------------------------------------------------------------------------------------------------
# Sito (CSS)

def genera_css(t):
    r = [f"/* {AVVISO}", f"   Valori attivi: «{t['attivo']}». Si porta nel sito (ramo main) nella fase 6: vedi Documenti/Stile.md. */", "",
         ":root {"]
    for c in tutti_i_colori(t):
        nome = c.get("css", trattini(c["nome"]))
        r.append(f"  --{nome}: {valore(t, c).lower()};")
    for c in tutti_i_colori(t):
        nome = c.get("css", trattini(c["nome"]))
        for alias in c.get("aliasCss", []):
            r.append(f"  --{alias}: var(--{nome}); /* nome di prima, deprecato */")
    r.append("")
    base = t["veli"]["colore"]
    rgb = colore_per_nome(t, base)[1:]
    for v in t["veli"]["livelli"]:
        r.append(f"  --velo-{v['nome']}: rgba({rgb_decimale(rgb)}, {numero(v['valore'])});")
    r.append("")
    for k, v in t["pileCss"].items():
        r.append(f"  --{k}: {v};")
    for s in t["stiliTesto"]:
        r.append(f"  --misura-{trattini(s['nome'])}: {numero(misura(s, 'windows'))}px;")
    for s in t["stiliTesto"]:
        if s.get("spaziatura"):
            r.append(f"  --spaziatura-{trattini(s['nome'])}: {numero(s['spaziatura'])}px;")
    r.append("")
    for s in t["spazi"]:
        r.append(f"  --spazio-{s['nome']}: {numero(s['valore'])}px;")
    for s in t["raggi"]:
        r.append(f"  --raggio-{s['nome']}: {numero(s['valore'])}px;")
    for s in t["opacita"]:
        r.append(f"  --opacita-{s['nome']}: {numero(s['valore'])};")
    r.append("}")
    diversi = [s for s in t["stiliTesto"] if misura(s, "telefono") != misura(s, "windows")]
    if diversi:
        r.append("")
        r.append("/* Sul telefono, le misure del telefono. */")
        r.append("@media (max-width: 600px) {")
        r.append("  :root {")
        for s in diversi:
            r.append(f"    --misura-{trattini(s['nome'])}: {numero(misura(s, 'telefono'))}px;")
        r.append("  }")
        r.append("}")
    return "\n".join(r) + "\n"


# ---------------------------------------------------------------------------------------------------------------
# Documenti/Stile.md (solo le tabelle)

INIZIO_MD = "<!-- genera_token:inizio"
FINE_MD = "<!-- genera_token:fine -->"


def blocco_md(t):
    attivo = "oggi" if t["attivo"] == "oggi" else "beta 4"
    r = [f"{INIZIO_MD} (tabelle scritte da Strumenti/genera_token.py da Documenti/token.json: non modificarle a mano) -->", "",
         f"Valori attivi: **{attivo}** (`\"attivo\": \"{t['attivo']}\"` in token.json). La colonna «Attivo» dice quale "
         "valore hanno davvero le app; «Oggi» e «Beta 4» sono i due valori possibili.", "",
         "### Colori", "",
         "| Token | Attivo | Oggi | Beta 4 | Ruolo |",
         "| --- | --- | --- | --- | --- |"]

    def riga(c):
        b4 = c.get("beta4", "")
        quale = "beta 4" if t["attivo"] == "beta4" and b4 else "oggi"
        nome = f"`{c['nome']}`"
        alias = c.get("aliasDeprecati", [])
        if alias:
            nome += " (alias deprecato: " + ", ".join(f"~~`{a}`~~" for a in alias) + ")"
        aliasWindows = c.get("aliasWindows", [])
        if aliasWindows:
            nome += " (su Windows anche " + ", ".join(f"`{a}`" for a in aliasWindows) + ")"
        b4testo = b4 if b4 else "="
        return f"| {nome} | **{valore(t, c)}** ({quale}) | {c['oggi']} | {b4testo} | {c['ruolo']} |"

    for c in t["colori"]:
        r.append(riga(c))
    r += ["", f"{len(t['colori'])} colori di oggi. Contorni dei controlli (nomi nuovi, già usati dai componenti: oggi "
               "valgono quanto `linea`, la beta 4 li porta a 3:1):", "",
          "| Token | Attivo | Oggi | Beta 4 | Ruolo |",
          "| --- | --- | --- | --- | --- |"]
    for c in t["contorni"]:
        r.append(riga(c))

    r += ["", "### Tipografia", "",
          "| Stile | Carattere | Peso | Mac | Windows e sito | Telefono | Dynamic Type | Uso |",
          "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for s in t["stiliTesto"]:
        c = carattere(t, s["carattere"])
        extra = ""
        if s.get("maiuscolo"):
            extra += ", maiuscolo"
        if s.get("spaziatura"):
            extra += f", spaziatura {virgola(s['spaziatura'])}"
        r.append(f"| `{s['nome']}` | {c['famiglia']} | {c['peso']}{extra} | {virgola(misura(s, 'mac'))} | "
                 f"{virgola(misura(s, 'windows'))} | {virgola(misura(s, 'telefono'))} | `{s['relativoA']}` | {s['uso']} |")

    r += ["", "### Spazi, raggi, opacità, veli", "",
          "| Gruppo | Nome | Valore | Uso |", "| --- | --- | --- | --- |"]
    for s in t["spazi"]:
        r.append(f"| Spazi | `{s['nome']}` | {virgola(s['valore'])} | |")
    for s in t["raggi"]:
        r.append(f"| Raggi | `{s['nome']}` | {virgola(s['valore'])} | {s['uso']} |")
    for s in t["opacita"]:
        r.append(f"| Opacità | `{s['nome']}` | {virgola(s['valore'])} | {s['uso']} |")
    for v in t["veli"]["livelli"]:
        r.append(f"| Veli | `{v['nome']}` | {virgola(v['valore'])} | `{t['veli']['colore']}` a questa opacità |")
    r += ["", FINE_MD]
    return "\n".join(r)


# ---------------------------------------------------------------------------------------------------------------

def uscite(t):
    """{percorso: testo atteso}."""
    risultato = {
        SWIFT: genera_swift(t),
        XAML: genera_xaml(t),
        CS: genera_cs(t),
        KOTLIN: genera_kotlin(t),
        COLORS_XML: genera_colors_xml(t),
        CSS: genera_css(t),
    }
    app = APP_XAML.read_text(encoding="utf-8")
    risultato[APP_XAML] = sostituisci_blocco(app, INIZIO_APP, FINE_APP, blocco_app_xaml(t), APP_XAML)
    md = STILE_MD.read_text(encoding="utf-8")
    risultato[STILE_MD] = sostituisci_blocco(md, INIZIO_MD, FINE_MD, blocco_md(t), STILE_MD)
    return risultato


def main():
    controlla = "--controlla" in sys.argv[1:]
    sconosciuti = [a for a in sys.argv[1:] if a != "--controlla"]
    if sconosciuti:
        sys.exit(f"Argomento sconosciuto: {' '.join(sconosciuti)}\n{__doc__}")
    t = leggi()
    diversi = []
    for percorso, testo in uscite(t).items():
        attuale = percorso.read_text(encoding="utf-8") if percorso.exists() else None
        if attuale == testo:
            continue
        relativo = percorso.relative_to(RADICE)
        if controlla:
            diversi.append(str(relativo))
        else:
            percorso.parent.mkdir(parents=True, exist_ok=True)
            percorso.write_text(testo, encoding="utf-8")
            print(f"scritto {relativo}")
    if controlla:
        if diversi:
            print("I token generati non coincidono con Documenti/token.json in:")
            for d in diversi:
                print(f"  {d}")
            print("Rilancia: python3 Strumenti/genera_token.py")
            sys.exit(1)
        print("Token: tutti i file coincidono con Documenti/token.json.")


if __name__ == "__main__":
    main()
