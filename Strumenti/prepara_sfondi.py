#!/usr/bin/env python3
"""Prepara gli sfondi pronti di WebcamLR dalle foto elencate in Strumenti/sfondi_foto.json.

Ogni foto si scarica dall'URL salvato (o si prende da un file locale con --file id=percorso), si controlla con
l'impronta SHA-256 salvata, si ritaglia a 16:9 intorno al «centro» indicato e si salva senza metadati. Lo sfondo
`lrapps` (verde del marchio, #30453E → #0D1B18) si disegna qui, nitido. Gli id con "foto": null non si toccano.
Alla fine riscrive Documenti/Sfondi - licenze.md dal file JSON. Serve solo Pillow (python3 -m pip install pillow).

    python3 Strumenti/prepara_sfondi.py                       # tutti
    python3 Strumenti/prepara_sfondi.py citta lrapps          # solo questi
    python3 Strumenti/prepara_sfondi.py --file citta=~/Scaricati/foto.jpg
    python3 Strumenti/prepara_sfondi.py --aggiorna-impronte   # salva nel JSON l'impronta dei file scaricati

Scrive (stesse cartelle di prima, stessi id di SfondiPronti nelle tre implementazioni del protocollo):
  iPhone/Risorse/Sfondi/<id>.jpg                  1920×1080 JPEG qualità 88
  Mac/Risorse/Sfondi/grandi/<id>.jpg              1920×1080 JPEG qualità 88 (motore effetti del Mac)
  Android/app/src/main/assets/sfondi/<id>.jpg     1920×1080
  Mac/Risorse/Sfondi/<id>.jpg                     320×180 (miniature del menu «Sfondi»)
  Windows/WebcamLR.App/Assets/Sfondi/<id>.jpg     320×180

Gli originali scaricati restano in ~/.cache/webcamlr-sfondi (fuori dalla repository).
"""

import hashlib
import io
import json
import random
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageChops, ImageOps

RADICE = Path(__file__).resolve().parent.parent
ELENCO = RADICE / "Strumenti/sfondi_foto.json"
LICENZE = RADICE / "Documenti/Sfondi - licenze.md"
CACHE = Path.home() / ".cache/webcamlr-sfondi"
L, A = 1920, 1080
MINIATURA = (320, 180)
QUALITA = 88
AGENTE = "WebcamLR-prepara-sfondi/1.0 (script per gli sfondi di un'app; Python urllib)"

GRANDI = [RADICE / "iPhone/Risorse/Sfondi", RADICE / "Android/app/src/main/assets/sfondi",
          RADICE / "Mac/Risorse/Sfondi/grandi"]
PICCOLE = [RADICE / "Mac/Risorse/Sfondi", RADICE / "Windows/WebcamLR.App/Assets/Sfondi"]


# ---------------------------------------------------------------------------------------------- foto

def impronta(dati):
    return hashlib.sha256(dati).hexdigest()


def scarica(identificativo, foto):
    CACHE.mkdir(parents=True, exist_ok=True)
    nome = foto["file"].rsplit("/", 1)[-1].split("?", 1)[0] or "foto.jpg"
    copia = CACHE / f"{identificativo}-{nome}"
    if copia.exists():
        return copia.read_bytes()
    richiesta = urllib.request.Request(foto["file"], headers={"User-Agent": AGENTE})
    with urllib.request.urlopen(richiesta, timeout=60) as risposta:
        dati = risposta.read()
    copia.write_bytes(dati)
    return dati


def ritaglia(img, centro):
    """Ritaglio 16:9 il più grande possibile, spostato verso «centro» (frazioni 0–1), poi 1920×1080."""
    img = ImageOps.exif_transpose(img).convert("RGB")
    w, h = img.size
    if w / h > L / A:
        cw, ch = round(h * L / A), h
    else:
        cw, ch = w, round(w * A / L)
    cx, cy = centro
    x = min(max(round(cx * w - cw / 2), 0), w - cw)
    y = min(max(round(cy * h - ch / 2), 0), h - ch)
    img = img.crop((x, y, x + cw, y + ch))
    if cw < L:
        print(f"  attenzione: la foto è più piccola di {L}×{A} ({cw}×{ch}), si ingrandisce", file=sys.stderr)
    return img.resize((L, A), Image.LANCZOS)


# ---------------------------------------------------------------------------------------------- lrapps

def lrapps():
    """Verde WebcamLR, nitido: sfumatura diagonale del marchio (#30453E in alto a sinistra → #0D1B18 in basso a
    destra) con una luce salvia larga e morbida dall'alto a sinistra. Nessuna sfocatura, nessun disegno."""
    alto, basso, salvia = (0x30, 0x45, 0x3E), (0x0D, 0x1B, 0x18), (0x5D, 0x7A, 0x6C)
    # Sfumatura lineare a 2×2 allargata: bilineare = diagonale perfettamente liscia.
    angoli = Image.new("RGB", (2, 2))
    mezzo = tuple(round((a + b) / 2) for a, b in zip(alto, basso))
    angoli.putdata([alto, mezzo, mezzo, basso])
    img = angoli.resize((L, A), Image.BILINEAR, box=(0.5, 0.5, 1.5, 1.5))
    # Luce: gradiente radiale di Pillow (256×256), curva morbida, allargato a ellisse.
    radiale = Image.radial_gradient("L").point(lambda v: round(255 * max(0.0, 1 - v / 255) ** 2.0 * 0.32))
    alone = Image.new("L", (L, A), 0)
    rx, ry = 1250, 900
    alone.paste(radiale.resize((2 * rx, 2 * ry), Image.BICUBIC), (round(L * 0.28) - rx, round(A * 0.18) - ry))
    luce = Image.composite(Image.new("RGB", (L, A), salvia), Image.new("RGB", (L, A), (0, 0, 0)), alone)
    img = ImageChops.screen(img, luce)
    # Una grana lievissima (±1–2 livelli) evita le bande della sfumatura dopo il JPEG.
    # Con un seme fisso (non effect_noise, che non ne accetta uno): lo stesso file a ogni esecuzione.
    rnd = random.Random(97)
    tessera = Image.new("L", (256, 256))
    tessera.putdata([max(0, min(255, round(rnd.gauss(128, 1.5)))) for _ in range(256 * 256)])
    rumore = Image.new("L", (L, A))
    for x in range(0, L, 256):
        for y in range(0, A, 256):
            rumore.paste(tessera, (x, y))
    return ImageChops.add(img, Image.merge("RGB", [rumore] * 3), scale=1.0, offset=-128)


# ---------------------------------------------------------------------------------------------- uscita

def salva(identificativo, img):
    assert img.size == (L, A), (identificativo, img.size)
    for cartella in GRANDI:
        cartella.mkdir(parents=True, exist_ok=True)
        img.save(cartella / f"{identificativo}.jpg", quality=QUALITA, optimize=True, progressive=True)
    piccola = img.resize(MINIATURA, Image.LANCZOS)
    for cartella in PICCOLE:
        cartella.mkdir(parents=True, exist_ok=True)
        piccola.save(cartella / f"{identificativo}.jpg", quality=QUALITA, optimize=True)


def scrivi_licenze(sfondi):
    righe = [
        "# Sfondi pronti · licenze",
        "",
        "Scritto da `Strumenti/prepara_sfondi.py` a partire da `Strumenti/sfondi_foto.json`: non modificarlo a mano.",
        "Regola: solo foto in pubblico dominio o CC0 (nessuna attribuzione obbligatoria, uso commerciale permesso, anche",
        "dentro un'app a pagamento), senza persone riconoscibili, marchi od opere d'arte in primo piano.",
        "",
    ]
    for voce in sfondi:
        righe.append(f"## `{voce['id']}`")
        righe.append("")
        if voce.get("disegnato"):
            righe.append("Disegnato da `Strumenti/prepara_sfondi.py` (sfumatura del marchio LR Apps): nessuna licenza di terzi.")
        elif voce.get("foto"):
            f = voce["foto"]
            righe += [
                f"- Titolo: {f['titolo']}",
                f"- Autore: {f['autore']}",
                f"- Pagina: <{f['pagina']}>",
                f"- File: <{f['file']}>",
                f"- Licenza: {f['licenza']} — «{f['citazione']}»",
                f"- Controllata e scaricata il: {f['controllata']}",
            ]
        else:
            righe.append("Ancora la scena disegnata da `Strumenti/genera_sfondi.py` (nessuna foto di terzi): foto da scegliere.")
        righe.append("")
    LICENZE.write_text("\n".join(righe), encoding="utf-8")


def main(argomenti):
    locali, scelte, aggiorna = {}, set(), False
    i = 0
    while i < len(argomenti):
        a = argomenti[i]
        if a == "--file":
            identificativo, percorso = argomenti[i + 1].split("=", 1)
            locali[identificativo] = Path(percorso).expanduser()
            scelte.add(identificativo)
            i += 1
        elif a == "--aggiorna-impronte":
            aggiorna = True
        else:
            scelte.add(a)
        i += 1

    elenco = json.loads(ELENCO.read_text(encoding="utf-8"))
    cambiato = False
    for voce in elenco["sfondi"]:
        identificativo = voce["id"]
        if scelte and identificativo not in scelte:
            continue
        if voce.get("disegnato"):
            salva(identificativo, lrapps())
            print(f"{identificativo}: disegnato")
            continue
        foto = voce.get("foto")
        if not foto:
            print(f"{identificativo}: nessuna foto nell'elenco, resta com'è")
            continue
        dati = locali[identificativo].read_bytes() if identificativo in locali else scarica(identificativo, foto)
        attesa = foto.get("sha256")
        if attesa and attesa != impronta(dati):
            sys.exit(f"{identificativo}: l'impronta del file non è quella salvata ({impronta(dati)}): il file è cambiato?")
        if not attesa:
            if not aggiorna:
                sys.exit(f"{identificativo}: manca sha256 nell'elenco (riprova con --aggiorna-impronte)")
            foto["sha256"] = impronta(dati)
            cambiato = True
        salva(identificativo, ritaglia(Image.open(io.BytesIO(dati)), foto.get("centro", [0.5, 0.5])))
        print(f"{identificativo}: foto preparata")

    if cambiato:
        ELENCO.write_text(json.dumps(elenco, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    scrivi_licenze(elenco["sfondi"])


if __name__ == "__main__":
    main(sys.argv[1:])
