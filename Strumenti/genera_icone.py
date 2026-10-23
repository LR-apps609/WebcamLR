#!/usr/bin/env python3
"""Genera le icone delle app iPhone e Mac dal logo della bozza (Sito/logo.svg, LogoWebcamLR in Stile).

Il logo: quadrato #26302d con una griglia 3×3 di quadratini bianchi semitrasparenti e il centro rosso tally.
- iPhone: quadrato pieno 1024×1024 senza trasparenza; gli angoli li arrotonda iOS.
- Mac: forma arrotondata 824×824 al centro di 1024×1024, con il margine della griglia delle icone di macOS.

Uso: python3 Strumenti/genera_icone.py (serve Pillow). Riscrive i file in iPhone/Risorse e Mac/Risorse.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

RADICE = Path(__file__).resolve().parent.parent
FONDO = (0x26, 0x30, 0x2D, 255)
TALLY = (0xEF, 0x5A, 0x4C, 255)
SOVRACAMPIONE = 4


def disegna(lato: int, area: int, angoli: bool) -> Image.Image:
    """Logo grande `area` al centro di un quadrato `lato`; le misure sono quelle di logo.svg (viewBox 100)."""
    s = SOVRACAMPIONE
    immagine = Image.new("RGBA", (lato * s, lato * s), (0, 0, 0, 0))
    disegno = ImageDraw.Draw(immagine)
    inizio = (lato - area) / 2 * s
    unita = area * s / 100

    def rettangolo(x, y, l, raggio, colore):
        x0, y0 = inizio + x * unita, inizio + y * unita
        disegno.rounded_rectangle([x0, y0, x0 + l * unita, y0 + l * unita], radius=raggio * unita, fill=colore)

    if angoli:
        rettangolo(0, 0, 100, 22, FONDO)
    else:
        disegno.rectangle([0, 0, lato * s, lato * s], fill=FONDO)

    # Quadratini sopra il fondo: bianco con opacità 0,35 agli angoli e 0,6 ai lati, come nel logo.
    for riga in range(3):
        for colonna in range(3):
            x, y = 22 + colonna * 20, 22 + riga * 20
            if riga == 1 and colonna == 1:
                colore = TALLY
            else:
                opacita = 0.35 if (riga + colonna) % 2 == 0 else 0.6
                colore = tuple(round(f + (255 - f) * opacita) for f in FONDO[:3]) + (255,)
            rettangolo(x, y, 16, 3, colore)

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


if __name__ == "__main__":
    iphone()
    mac()
    print("Icone scritte in iPhone/Risorse e Mac/Risorse.")
