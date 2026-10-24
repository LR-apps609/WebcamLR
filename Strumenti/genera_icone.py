#!/usr/bin/env python3
"""Genera le icone delle app iPhone, Mac e Windows dal logo (Sito/logo.svg, LogoWebcamLR in Stile).

Il logo (versione del 25 ottobre): fondo verde scuro con una sfumatura in diagonale, griglia 3×3 di quadratini
in toni di verde salvia, il centro corallo (il «punto» della webcam).
- iPhone: quadrato pieno 1024×1024 senza trasparenza; gli angoli li arrotonda iOS.
- Mac: forma arrotondata 824×824 al centro di 1024×1024, con il margine della griglia delle icone di macOS.
- Windows: WebcamLR.ico con le misure da 16 a 256.

Uso: python3 Strumenti/genera_icone.py (serve Pillow). Riscrive i file in iPhone/Risorse, Mac/Risorse e Windows.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

RADICE = Path(__file__).resolve().parent.parent
# Fondo: dall'angolo in alto a sinistra a quello in basso a destra.
FONDO_CHIARO = (0x30, 0x45, 0x3E)
FONDO_SCURO = (0x0D, 0x1B, 0x18)
BORDO = (255, 255, 255, 22)
# I nove quadratini, riga per riga; il centro è il corallo.
CELLE = [
    [(0x8F, 0xA1, 0x99), (0xB2, 0xBF, 0xB7), (0x62, 0x7A, 0x71)],
    [(0xAC, 0xBA, 0xB2), (0xE6, 0x7A, 0x67), (0x76, 0x8D, 0x84)],
    [(0x83, 0x98, 0x8F), (0x96, 0xA8, 0x9F), (0x50, 0x68, 0x5F)],
]
# Misure in unità di 100, come il viewBox di logo.svg.
INIZIO, CELLA, PASSO, RAGGIO_CELLA, RAGGIO_FONDO = 18, 18, 23, 4, 22
SOVRACAMPIONE = 4


def sfumatura(lato: int) -> Image.Image:
    """Sfumatura diagonale da FONDO_CHIARO (in alto a sinistra) a FONDO_SCURO (in basso a destra)."""
    piccola = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            piccola.putpixel((x, y), tuple(round(a + (b - a) * t) for a, b in zip(FONDO_CHIARO, FONDO_SCURO)))
    return piccola.resize((lato, lato), Image.BICUBIC)


def disegna(lato: int, area: int, angoli: bool) -> Image.Image:
    """Logo grande `area` al centro di un quadrato `lato`."""
    s = SOVRACAMPIONE
    grande = lato * s
    inizio = (lato - area) / 2 * s
    unita = area * s / 100
    immagine = Image.new("RGBA", (grande, grande), (0, 0, 0, 0))

    fondo = sfumatura(round(area * s) if angoli else grande).convert("RGBA")
    if angoli:
        maschera = Image.new("L", fondo.size, 0)
        ImageDraw.Draw(maschera).rounded_rectangle([0, 0, fondo.size[0] - 1, fondo.size[1] - 1],
                                                   radius=RAGGIO_FONDO * unita, fill=255)
        immagine.paste(fondo, (round(inizio), round(inizio)), maschera)
        ImageDraw.Draw(immagine, "RGBA").rounded_rectangle(
            [inizio, inizio, inizio + 100 * unita - 1, inizio + 100 * unita - 1],
            radius=RAGGIO_FONDO * unita, outline=BORDO, width=max(1, round(unita * 0.6)))
    else:
        immagine.paste(fondo, (0, 0))

    disegno = ImageDraw.Draw(immagine, "RGBA")
    for riga in range(3):
        for colonna in range(3):
            x0 = inizio + (INIZIO + colonna * PASSO) * unita
            y0 = inizio + (INIZIO + riga * PASSO) * unita
            disegno.rounded_rectangle([x0, y0, x0 + CELLA * unita, y0 + CELLA * unita],
                                      radius=RAGGIO_CELLA * unita, fill=CELLE[riga][colonna] + (255,))

    return immagine.resize((lato, lato), Image.LANCZOS)


def scrivi_json(percorso: Path, contenuto: dict) -> None:
    percorso.parent.mkdir(parents=True, exist_ok=True)
    percorso.write_text(json.dumps(contenuto, indent=2, ensure_ascii=False) + "\n")


def catalogo(cartella: Path) -> Path:
    scrivi_json(cartella / "Assets.xcassets/Contents.json", {"info": {"author": "xcode", "version": 1}})
    return cartella / "Assets.xcassets/AppIcon.appiconset"


def iphone() -> None:
    icone = catalogo(RADICE / "iPhone/Risorse")
    icone.mkdir(parents=True, exist_ok=True)
    # Niente canale alfa: App Store e iOS non vogliono trasparenza nell'icona.
    disegna(1024, 1024, angoli=False).convert("RGB").save(icone / "Icona-1024.png")
    scrivi_json(icone / "Contents.json", {
        "images": [{"filename": "Icona-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })


def mac() -> None:
    icone = catalogo(RADICE / "Mac/Risorse")
    icone.mkdir(parents=True, exist_ok=True)
    grande = disegna(1024, 824, angoli=True)
    immagini = []
    for punti in (16, 32, 128, 256, 512):
        for scala in (1, 2):
            pixel = punti * scala
            nome = f"Icona-{punti}@{scala}x.png"
            grande.resize((pixel, pixel), Image.LANCZOS).save(icone / nome)
            immagini.append({"filename": nome, "idiom": "mac", "scale": f"{scala}x", "size": f"{punti}x{punti}"})
    scrivi_json(icone / "Contents.json", {"images": immagini, "info": {"author": "xcode", "version": 1}})


def windows() -> None:
    misure = [16, 24, 32, 48, 64, 128, 256]
    grande = disegna(256, 256, angoli=True)
    grande.save(RADICE / "Windows/WebcamLR.App/Assets/WebcamLR.ico", sizes=[(m, m) for m in misure])


def svg() -> str:
    """Il logo in SVG, per il sito (Sito/logo.svg)."""
    celle = "".join(
        f'<rect x="{INIZIO + c * PASSO}" y="{INIZIO + r * PASSO}" width="{CELLA}" height="{CELLA}" rx="{RAGGIO_CELLA}" '
        f'fill="#{"".join(f"{v:02x}" for v in CELLE[r][c])}"/>'
        for r in range(3) for c in range(3))
    chiaro = "".join(f"{v:02x}" for v in FONDO_CHIARO)
    scuro = "".join(f"{v:02x}" for v in FONDO_SCURO)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="f" x1="0" y1="0" '
            f'x2="1" y2="1"><stop offset="0" stop-color="#{chiaro}"/><stop offset="1" stop-color="#{scuro}"/>'
            f'</linearGradient></defs><rect width="100" height="100" rx="{RAGGIO_FONDO}" fill="url(#f)"/>{celle}</svg>\n')


if __name__ == "__main__":
    iphone()
    mac()
    windows()
    (RADICE / "Strumenti/logo.svg").write_text(svg())
    print("Icone scritte in iPhone/Risorse, Mac/Risorse e Windows; logo SVG in Strumenti/logo.svg.")
