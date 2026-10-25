#!/usr/bin/env python3
"""Disegna i testi della schermata di attesa della webcam virtuale per Windows (Barlow Condensed e Barlow).

La sorgente della webcam gira dentro Frame Server (un servizio di Windows, sessione 0) e il filtro DirectShow dentro
le app: niente caratteri installati né librerie grafiche su cui contare. I testi sono pochi e fissi, quindi si
disegnano qui una volta, con i caratteri di Stile, come maschere di opacità a 8 bit per un'immagine alta 2160 (4K).
La webcam le rimpicciolisce alla misura che serve (1080 = metà esatta, 720 = un terzo…) e le colora da sé.

Misure come in Mac/Sorgenti/AttesaWebcam.swift (disegnaTesti), per un'immagine alta 1080: titolo in Barlow Condensed
Bold da 84, riga sotto in Barlow Medium da 34. Qui il doppio. Ogni maschera è alta quanto la riga del carattere
(salita + discesa), larga quanto il testo più un margine: la webcam la centra sul punto giusto.

Uso: python3 Strumenti/genera_testi_attesa.py (serve Pillow). Riscrive
Windows/WebcamLR.Webcam.Logica/Risorse/TestiAttesa.bin; i testi devono restare uguali a TestiAttesa.cs
(lo controlla un test).

Formato (little endian, tutto compresso con zlib):
  «WLRT», u16 versione (1), u16 altezza di riferimento (2160), u16 numero di maschere
  per ogni maschera: u8 lunghezza della chiave, chiave UTF-8 («it.titolo.NonCollegata»),
                     u16 larghezza, u16 altezza, larghezza × altezza byte di opacità (riga per riga, dall'alto)
"""
import struct
import zlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RADICE = Path(__file__).resolve().parent.parent
CARATTERI = RADICE / "Stile" / "Sources" / "Stile" / "Caratteri"
USCITA = RADICE / "Windows" / "WebcamLR.Webcam.Logica" / "Risorse" / "TestiAttesa.bin"

ALTEZZA_RIFERIMENTO = 2160
SCALA = ALTEZZA_RIFERIMENTO / 1080
MARGINE = 4

# Uguali a TestiAttesa.cs (e ai testi del Mac, Localizable.xcstrings).
TESTI = {
    "it": {
        "titolo.NonCollegata": "La webcam non è collegata",
        "sottotitolo.NonCollegata": "Apri WebcamLR sul telefono",
        "titolo.Interrotta": "Collegamento interrotto",
        "sottotitolo.Interrotta": "Riconnessione in corso…",
        "titolo.Pausa": "Webcam in pausa",
    },
    "en": {
        "titolo.NonCollegata": "The webcam is not connected",
        "sottotitolo.NonCollegata": "Open WebcamLR on your phone",
        "titolo.Interrotta": "Connection lost",
        "sottotitolo.Interrotta": "Reconnecting…",
        "titolo.Pausa": "Webcam paused",
    },
}


def maschera(testo: str, carattere: ImageFont.FreeTypeFont) -> Image.Image:
    salita, discesa = carattere.getmetrics()
    larghezza = int(round(carattere.getlength(testo))) + 2 * MARGINE
    immagine = Image.new("L", (larghezza, salita + discesa), 0)
    # Linea di base a «salita» dall'alto: la riga intera (salita + discesa) è la maschera.
    ImageDraw.Draw(immagine).text((MARGINE, salita), testo, font=carattere, fill=255, anchor="ls")
    return immagine


def main() -> None:
    titolo = ImageFont.truetype(str(CARATTERI / "BarlowCondensed-Bold.ttf"), round(84 * SCALA))
    sottotitolo = ImageFont.truetype(str(CARATTERI / "Barlow-Medium.ttf"), round(34 * SCALA))
    voci = []
    for lingua, testi in TESTI.items():
        for chiave, testo in testi.items():
            carattere = titolo if chiave.startswith("titolo.") else sottotitolo
            voci.append((f"{lingua}.{chiave}", maschera(testo, carattere)))

    dati = bytearray(b"WLRT")
    dati += struct.pack("<HHH", 1, ALTEZZA_RIFERIMENTO, len(voci))
    for chiave, immagine in voci:
        nome = chiave.encode("utf-8")
        dati += struct.pack("<B", len(nome)) + nome
        dati += struct.pack("<HH", immagine.width, immagine.height)
        dati += immagine.tobytes()
    USCITA.parent.mkdir(parents=True, exist_ok=True)
    USCITA.write_bytes(zlib.compress(bytes(dati), 9))
    print(f"{USCITA.relative_to(RADICE)}: {len(voci)} testi, {len(dati) // 1024} KB → {USCITA.stat().st_size // 1024} KB compressi")


if __name__ == "__main__":
    main()
