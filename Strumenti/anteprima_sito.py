#!/usr/bin/env python3
"""Genera Sito/anteprima.png e Sito/anteprima-en.png (Open Graph, 1200×630, italiano e inglese) e Sito/apple-touch-icon.png
(180×180) con l'identità di LR Apps.

Fondo con la sfumatura del logo (#30453E → #0D1B18), logo a griglia 3×3 con il centro corallo, «Webcam» quasi bianco e
«LR» nell'accento salvia, come MarchioWebcamLR in Stile. Caratteri da Sito/caratteri (Barlow, licenza OFL).
Uso: python3 Strumenti/anteprima_sito.py (serve Pillow).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RADICE = Path(__file__).resolve().parent.parent
SITO = RADICE / "Sito"
CARATTERI = SITO / "caratteri"

CHIARO = (0x30, 0x45, 0x3E)
SCURO = (0x0D, 0x1B, 0x18)
TESTO = (0xE6, 0xEE, 0xEA)
TESTO_TENUE = (0xB4, 0xC2, 0xBB)
ACCENTO = (0x9F, 0xD0, 0xB6)
BORDO = (0x3A, 0x52, 0x4A)
CELLE = [
    [(0x8F, 0xA1, 0x99), (0xB2, 0xBF, 0xB7), (0x62, 0x7A, 0x71)],
    [(0xAC, 0xBA, 0xB2), (0xE6, 0x7A, 0x67), (0x76, 0x8D, 0x84)],
    [(0x83, 0x98, 0x8F), (0x96, 0xA8, 0x9F), (0x50, 0x68, 0x5F)],
]
S = 2  # sovracampionamento


def sfumatura(w: int, h: int) -> Image.Image:
    """Diagonale dall'angolo in alto a sinistra (chiaro) a quello in basso a destra (scuro)."""
    piccola = Image.new("RGB", (64, 64))
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            piccola.putpixel((x, y), tuple(round(a + (b - a) * t) for a, b in zip(CHIARO, SCURO)))
    return piccola.resize((w, h), Image.BICUBIC)


def logo(d: ImageDraw.ImageDraw, x: float, y: float, lato: float, fondo: bool) -> None:
    """Il logo in unità di 100 (come Sito/logo.svg), con l'angolo in alto a sinistra in (x, y)."""
    u = lato / 100
    if fondo:
        d.rounded_rectangle([x, y, x + lato, y + lato], radius=22 * u, fill=SCURO + (90,), outline=BORDO, width=max(1, round(u)))
    for r, riga in enumerate(CELLE):
        for c, colore in enumerate(riga):
            cx, cy = x + (18 + 23 * c) * u, y + (18 + 23 * r) * u
            d.rounded_rectangle([cx, cy, cx + 18 * u, cy + 18 * u], radius=4 * u, fill=colore)


TESTI = {
    "anteprima.png": ("CAVO USB · WI-FI · SENZA FILIGRANA", "L'iPhone come webcam per Mac e Windows"),
    "anteprima-en.png": ("USB CABLE · WI-FI · NO WATERMARK", "Your phone as a webcam for Mac and Windows"),
}


def anteprima(nome: str) -> None:
    sopra, frase = TESTI[nome]
    w, h = 1200 * S, 630 * S
    im = sfumatura(w, h).convert("RGBA")
    d = ImageDraw.Draw(im, "RGBA")
    # Gli angoli del mirino
    m, l, sp = 40 * S, 40 * S, 3 * S
    for (ax, ay, dx, dy) in [(m, m, 1, 1), (w - m, m, -1, 1), (m, h - m, 1, -1), (w - m, h - m, -1, -1)]:
        d.line([(ax, ay + dy * l), (ax, ay), (ax + dx * l, ay)], fill=(0xC9, 0xD5, 0xCF), width=sp)
    # Il riquadro del logo con la sua sfumatura, come Sito/logo.svg, e un bordo leggero.
    lx, ly, ll = 96 * S, 205 * S, 220 * S
    maschera = Image.new("L", (ll, ll), 0)
    ImageDraw.Draw(maschera).rounded_rectangle([0, 0, ll - 1, ll - 1], radius=round(ll * .22), fill=255)
    im.paste(sfumatura(ll, ll), (lx, ly), maschera)
    d.rounded_rectangle([lx, ly, lx + ll - 1, ly + ll - 1], radius=round(ll * .22), outline=BORDO, width=2 * S)
    logo(d, lx, ly, ll, fondo=False)
    titolo = ImageFont.truetype(str(CARATTERI / "BarlowCondensed-Bold.ttf"), 150 * S)
    sotto = ImageFont.truetype(str(CARATTERI / "BarlowCondensed-SemiBold.ttf"), 46 * S)
    occhiello = ImageFont.truetype(str(CARATTERI / "BarlowCondensed-SemiBold.ttf"), 28 * S)
    x = 372 * S
    d.text((x, 180 * S), sopra, font=occhiello, fill=TESTO_TENUE)
    d.text((x, 210 * S), "Webcam", font=titolo, fill=TESTO)
    d.text((x + d.textlength("Webcam", font=titolo), 210 * S), "LR", font=titolo, fill=ACCENTO)
    d.text((x, 385 * S), frase, font=sotto, fill=TESTO)
    im.convert("RGB").resize((1200, 630), Image.LANCZOS).save(SITO / nome, optimize=True)


def icona() -> None:
    """Icona quadrata piena, come quella dell'iPhone: gli angoli li arrotonda iOS."""
    lato = 180 * 4
    im = sfumatura(lato, lato).convert("RGBA")
    logo(ImageDraw.Draw(im, "RGBA"), 0, 0, lato, fondo=False)
    im.convert("RGB").resize((180, 180), Image.LANCZOS).save(SITO / "apple-touch-icon.png", optimize=True)


if __name__ == "__main__":
    for nome in TESTI:
        anteprima(nome)
    icona()
    print("Scritti Sito/anteprima.png, Sito/anteprima-en.png e Sito/apple-touch-icon.png")
