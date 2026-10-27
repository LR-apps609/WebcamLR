#!/usr/bin/env python3
"""Genera gli sfondi pronti di WebcamLR (Documenti/Protocollo.md, «Sfondi e logo dal computer»).

Otto ambienti disegnati qui e messi fuori fuoco come da una fotocamera vera: niente foto esterne, niente
licenze di terzi, nessuna rete. Serve solo Pillow (python3 -m pip install pillow). Con la stessa versione di
Pillow il risultato è sempre lo stesso (semi fissi): le immagini nella repository si possono rigenerare e confrontare.
Con un id come argomento si rigenera solo quello (es. python3 Strumenti/genera_sfondi.py citta).

    python3 Strumenti/genera_sfondi.py

Scrive:
  iPhone/Risorse/Sfondi/<id>.jpg                  1920×1080 (il telefono li mette dietro la persona)
  Mac/Risorse/Sfondi/grandi/<id>.jpg              1920×1080 (il motore effetti del Mac li mette dietro la persona)
  Android/app/src/main/assets/sfondi/<id>.jpg     1920×1080
  Mac/Risorse/Sfondi/<id>.jpg                     320×180 (miniature del menu «Sfondi»)
  Windows/WebcamLR.App/Assets/Sfondi/<id>.jpg     320×180

Gli id sono quelli di SfondiPronti nelle tre implementazioni del protocollo, nello stesso ordine.

Sostituito man mano da Strumenti/prepara_sfondi.py (foto vere nitide, elencate in Strumenti/sfondi_foto.json):
gli id che hanno una foto lì, e `lrapps`, qui si saltano. Quando tutti hanno una foto questo script si può togliere.
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

RADICE = Path(__file__).resolve().parent.parent
L, A = 1920, 1080
MINIATURA = (320, 180)
QUALITA = 88

GRANDI = [RADICE / "iPhone/Risorse/Sfondi", RADICE / "Android/app/src/main/assets/sfondi",
          RADICE / "Mac/Risorse/Sfondi/grandi"]
PICCOLE = [RADICE / "Mac/Risorse/Sfondi", RADICE / "Windows/WebcamLR.App/Assets/Sfondi"]


# ---------------------------------------------------------------------------------------------- strumenti

def colore(esadecimale):
    esadecimale = esadecimale.lstrip("#")
    return tuple(int(esadecimale[i:i + 2], 16) for i in (0, 2, 4))


def mescola(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def varia(c, rnd, quanto):
    """Lo stesso colore, un po' più chiaro o più scuro (e appena spostato di tinta)."""
    f = 1 + rnd.uniform(-quanto, quanto)
    return tuple(max(0, min(255, round(x * f + rnd.uniform(-6, 6)))) for x in c)


def sfumatura_verticale(colori, dimensione=(L, A)):
    """Sfumatura dall'alto in basso tra più colori (a passi uguali), liscia: si allarga una colonna piccola."""
    colonna = Image.new("RGB", (1, len(colori)))
    for i, c in enumerate(colori):
        colonna.putpixel((0, i), c)
    return colonna.resize(dimensione, Image.BICUBIC)


def sfumatura_orizzontale(colori, dimensione=(L, A)):
    riga = Image.new("RGB", (len(colori), 1))
    for i, c in enumerate(colori):
        riga.putpixel((i, 0), c)
    return riga.resize(dimensione, Image.BICUBIC)


def alone(centro, raggi, dimensione=(L, A)):
    """Maschera L morbida: 255 al centro, 0 oltre i raggi (ellisse), con caduta gaussiana."""
    maschera = Image.radial_gradient("L").point(lambda v: 255 - v)  # 256×256, bianco al centro
    # La radiale di Pillow arriva a 0 sul bordo del cerchio inscritto: curva più morbida con una potenza.
    maschera = maschera.point(lambda v: round(255 * (v / 255) ** 2.2))
    rx, ry = raggi
    piccola = maschera.resize((max(2, int(2 * rx)), max(2, int(2 * ry))), Image.BICUBIC)
    tela = Image.new("L", dimensione, 0)
    tela.paste(piccola, (int(centro[0] - rx), int(centro[1] - ry)))
    return tela


def luce(img, centro, raggi, c, forza=1.0):
    """Aggiunge una luce colorata morbida (schermo), come una lampada o una finestra fuori fuoco."""
    maschera = alone(centro, raggi, img.size)
    if forza != 1.0:
        maschera = maschera.point(lambda v: min(255, round(v * forza)))
    strato = Image.composite(Image.new("RGB", img.size, c), Image.new("RGB", img.size, (0, 0, 0)), maschera)
    return ImageChops.screen(img, strato)


def ombra(img, centro, raggi, forza=0.5):
    """Scurisce in modo morbido (angoli, zone lontane dalla luce)."""
    maschera = alone(centro, raggi, img.size).point(lambda v: round(v * forza))
    return Image.composite(Image.new("RGB", img.size, (0, 0, 0)), img, maschera)


def vignetta(img, forza=0.35):
    """Bordi più scuri, come un obiettivo luminoso a tutta apertura."""
    maschera = alone((L / 2, A / 2), (L * 0.95, A * 1.05), img.size)
    scuro = ImageChops.multiply(img, Image.new("RGB", img.size, tuple(round(255 * (1 - forza)) for _ in range(3))))
    return Image.composite(img, scuro, maschera)


def sfoca(img, raggio):
    return img.filter(ImageFilter.GaussianBlur(raggio))


def bokeh(img, punti, nitidezza=1.5):
    """Dischi di luce fuori fuoco (punti: x, y, raggio, colore, intensità 0–1), sommati con «schermo».

    Un obiettivo vero trasforma i punti luminosi in dischi quasi uniformi con il bordo appena più chiaro: si disegna
    un disco pieno e un anello sottile, poi una sfocatura piccola per non avere bordi tagliati.
    """
    strato = Image.new("RGB", img.size, (0, 0, 0))
    disegno = ImageDraw.Draw(strato)
    for x, y, r, c, intensita in punti:
        pieno = tuple(round(v * intensita * 0.55) for v in c)
        bordo = tuple(round(v * intensita * 0.63) for v in c)
        disegno.ellipse((x - r, y - r, x + r, y + r), fill=pieno)
        disegno.ellipse((x - r, y - r, x + r, y + r), outline=bordo, width=max(1, round(r * 0.05)))
    strato = strato.filter(ImageFilter.GaussianBlur(nitidezza))
    return ImageChops.screen(img, strato)


def grana(img, seme, forza=5.0):
    """Rumore leggero a colori, come il sensore: toglie le bande delle sfumature (anche dopo il JPEG)."""
    rnd = random.Random(seme)
    canali = []
    for _ in range(3):
        rumore = Image.effect_noise(img.size, forza)
        # effect_noise non accetta un seme: si sposta a caso per non avere la stessa grana nei tre canali.
        rumore = ImageChops.offset(rumore, rnd.randrange(L), rnd.randrange(A))
        canali.append(rumore)
    rumore = Image.merge("RGB", canali)
    # Luminanza comune più un po' di colore, come un sensore a ISO medi.
    lum = Image.effect_noise(img.size, forza * 0.8).convert("RGB")
    rumore = Image.blend(rumore, lum, 0.6)
    return ImageChops.add(img, rumore, 1.0, -128)


def texture(dimensione, seme, scale=((8, 1.0), (32, 0.6), (128, 0.35)), forza=40):
    """Macchie a più scale (rumore a valori interpolati), in L intorno a 128."""
    rnd = random.Random(seme)
    risultato = Image.new("L", dimensione, 128)
    for passo, peso in scale:
        w, h = max(2, dimensione[0] // passo), max(2, dimensione[1] // passo)
        piccola = Image.new("L", (w, h))
        piccola.putdata([round(128 + rnd.gauss(0, forza * peso)) for _ in range(w * h)])
        grande = piccola.resize(dimensione, Image.BICUBIC)
        risultato = ImageChops.add(risultato, grande, 1.0, -128)
    return risultato


def applica_texture(img, tex, quanto=0.5):
    """Scurisce e schiarisce l'immagine secondo la texture (128 = invariato)."""
    tex = tex.point(lambda v: max(0, min(255, round(128 + (v - 128) * quanto))))
    tex_rgb = Image.merge("RGB", (tex, tex, tex))
    # «Luce soffusa» semplice: img * tex / 128.
    return ImageChops.multiply(img, tex_rgb.point(lambda v: min(255, v * 2)))


def rettangolo(disegno, box, c, raggio=0):
    if raggio:
        disegno.rounded_rectangle(box, raggio, fill=c)
    else:
        disegno.rectangle(box, fill=c)


# ---------------------------------------------------------------------------------------------- scene

def ufficio():
    """Ufficio luminoso: open space, vetrata in fondo con il giorno, scrivanie e sedie, piante, pannelli a soffitto."""
    rnd = random.Random(11)
    orizzonte = 600
    img = Image.new("RGB", (L, A), colore("#dfe1df"))
    d = ImageDraw.Draw(img)
    # Soffitto in prospettiva (più chiaro verso il fondo) e pannelli luminosi.
    d.polygon([(0, 0), (L, 0), (L * 0.78, 250), (L * 0.22, 250)], fill=colore("#e9eae8"))
    d.polygon([(0, 0), (L * 0.22, 250), (L * 0.22, orizzonte + 60), (0, A)], fill=colore("#d2d4d1"))  # parete sinistra
    d.polygon([(L, 0), (L * 0.78, 250), (L * 0.78, orizzonte + 60), (L, A)], fill=colore("#d8d7d2"))  # parete destra
    # Vetrata di fondo: cielo chiaro, alberi e palazzi lontani, montanti.
    vetro = (L * 0.22, 250, L * 0.78, orizzonte + 60)
    d.rectangle(vetro, fill=colore("#eef4f8"))
    for _ in range(30):
        x, y = rnd.uniform(vetro[0], vetro[2]), rnd.uniform(470, 600)
        r = rnd.uniform(30, 80)
        d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=varia(colore("#a9c09f"), rnd, 0.08))
    for x in range(int(vetro[0]), int(vetro[2]) + 1, 150):
        d.rectangle((x, 250, x + 10, orizzonte + 60), fill=colore("#7d858a"))
    # Pavimento in prospettiva, grigio caldo con un riflesso della vetrata.
    d.polygon([(0, A), (L * 0.22, orizzonte + 60), (L * 0.78, orizzonte + 60), (L, A)], fill=colore("#a9a39a"))
    d.polygon([(L * 0.3, A), (L * 0.36, orizzonte + 60), (L * 0.64, orizzonte + 60), (L * 0.7, A)],
              fill=colore("#c3beb5"))
    # Colonna a destra.
    d.rectangle((1500, 0, 1590, A), fill=colore("#e4e3df"))
    # Scrivanie bianche, monitor e sedie nere, a due distanze.
    for x0, y0, s in ((560, 700, 0.55), (1300, 700, 0.55), (300, 820, 1.0), (1180, 830, 1.05)):
        rettangolo(d, (x0 - 300 * s, y0, x0 + 300 * s, y0 + 24 * s), colore("#f4f4f2"))
        rettangolo(d, (x0 - 280 * s, y0 + 24 * s, x0 - 262 * s, y0 + 190 * s), colore("#8e9192"))
        rettangolo(d, (x0 + 262 * s, y0 + 24 * s, x0 + 280 * s, y0 + 190 * s), colore("#8e9192"))
        for mx in (-170, 20):
            rettangolo(d, ((x0 + mx * s), y0 - 170 * s, x0 + (mx + 150) * s, y0 - 70 * s), colore("#24282c"), 4)
            rettangolo(d, (x0 + (mx + 70) * s, y0 - 70 * s, x0 + (mx + 80) * s, y0), colore("#5b6065"))
        # Sedia: schienale, seduta e base.
        cx = x0 + rnd.uniform(-120, 120) * s
        rettangolo(d, (cx - 70 * s, y0 - 30 * s, cx + 70 * s, y0 + 110 * s), colore("#2b2e31"), round(26 * s))
        rettangolo(d, (cx - 85 * s, y0 + 110 * s, cx + 85 * s, y0 + 140 * s), colore("#33373a"), round(12 * s))
        rettangolo(d, (cx - 6 * s, y0 + 140 * s, cx + 6 * s, y0 + 210 * s), colore("#55595c"))
    # Piante alte in vaso.
    for x0, y0, s in ((80, 900, 1.3), (1720, 860, 1.1), (900, 690, 0.55)):
        rettangolo(d, (x0 - 55 * s, y0, x0 + 55 * s, y0 + 120 * s), colore("#ebe7df"), round(10 * s))
        for _ in range(40):
            a = rnd.uniform(-math.pi * 0.95, -math.pi * 0.05)
            dist = rnd.uniform(10, 170) * s
            x, y = x0 + math.cos(a) * dist * 0.8, y0 - 30 * s + math.sin(a) * dist * 1.6
            r = rnd.uniform(18, 46) * s
            d.ellipse((x - r, y - r * 0.55, x + r, y + r * 0.55), fill=varia(colore("#46703f"), rnd, 0.22))
    img = sfoca(img, 20)
    # Il giorno dalla vetrata, i pannelli a soffitto, un po' di ombra davanti.
    img = luce(img, (L / 2, 420), (900, 380), colore("#fffaf2"), 0.6)
    for x in (L * 0.32, L * 0.5, L * 0.68):
        img = luce(img, (x, 120), (170, 26), colore("#fffdf6"), 0.9)
    img = ombra(img, (L / 2, A + 150), (1300, 420), 0.25)
    return vignetta(img, 0.2)


def libreria():
    """Libreria: scaffali di legno pieni di libri, luce calda di una lampada da terra a destra."""
    rnd = random.Random(23)
    img = sfumatura_verticale([colore("#3a2a1f"), colore("#4a3526"), colore("#3d2b1f")])
    d = ImageDraw.Draw(img)
    tinte = ["#7a2e2a", "#2f4a63", "#3f5a3b", "#b08a3e", "#d9cfbd", "#5b3a52", "#8c5a2b", "#24323d",
             "#a2442f", "#6d7b6a", "#c6a27a", "#1f2a24", "#e6dccb", "#4d6c7c"]
    larghezza_scaffale = 420
    for x0 in range(-60, L, larghezza_scaffale):
        # Montanti.
        rettangolo(d, (x0, 0, x0 + 26, A), colore("#5a3f2b"))
        for y0 in range(40, A, 250):
            # Ripiano.
            rettangolo(d, (x0, y0 + 200, x0 + larghezza_scaffale, y0 + 226), colore("#6b4b33"))
            rettangolo(d, (x0 + 26, y0 - 24, x0 + larghezza_scaffale, y0 + 200), colore("#2a1e16"))
            x = x0 + 34
            fine = x0 + larghezza_scaffale - 8
            while x < fine:
                if rnd.random() < 0.06:  # un vuoto, un oggetto
                    x += rnd.uniform(30, 70)
                    continue
                w = rnd.uniform(16, 42)
                h = rnd.uniform(140, 196)
                c = varia(colore(rnd.choice(tinte)), rnd, 0.12)
                if rnd.random() < 0.08 and x + h < fine:  # una pila orizzontale
                    for k in range(rnd.randint(2, 5)):
                        spessore = rnd.uniform(16, 26)
                        rettangolo(d, (x, y0 + 200 - (k + 1) * spessore, x + h, y0 + 200 - k * spessore),
                                   varia(colore(rnd.choice(tinte)), rnd, 0.12))
                    x += h + 6
                    continue
                inclinato = rnd.random() < 0.05
                if inclinato:
                    d.polygon([(x, y0 + 200), (x + w, y0 + 200), (x + w + 40, y0 + 200 - h), (x + 40, y0 + 200 - h)],
                              fill=c)
                    x += w + 44
                else:
                    rettangolo(d, (x, y0 + 200 - h, x + w, y0 + 200), c)
                    # Fascette sul dorso.
                    if rnd.random() < 0.6:
                        fascia = mescola(c, colore("#e9d9a8"), 0.5)
                        yb = y0 + 200 - h * rnd.uniform(0.6, 0.85)
                        rettangolo(d, (x + 2, yb, x + w - 2, yb + 5), fascia)
                    x += w + rnd.uniform(0, 3)
    img = sfoca(img, 17)
    # Luce calda dalla lampada a destra, il resto della stanza più scuro.
    img = ombra(img, (200, 900), (1300, 900), 0.55)
    img = luce(img, (1500, 300), (900, 700), colore("#ffb469"), 0.5)
    return vignetta(img, 0.35)


def soggiorno():
    """Soggiorno: parete calda, divano, quadro, lampada accesa, tenda e piante vicino alla finestra."""
    rnd = random.Random(37)
    img = sfumatura_verticale([colore("#d8c6ae"), colore("#cdb79c"), colore("#bba184")])
    d = ImageDraw.Draw(img)
    # Finestra a sinistra con la tenda di lino.
    rettangolo(d, (0, 80, 420, 820), colore("#f3efe6"))
    for x in range(0, 460, 46):
        d.rectangle((x, 60, x + 30, 860), fill=varia(colore("#e9dfcf"), rnd, 0.04))
    rettangolo(d, (420, 40, 560, 880), colore("#d9ccb7"))
    # Quadro grande sopra il divano.
    rettangolo(d, (840, 210, 1340, 520), colore("#2f2a26"))
    rettangolo(d, (856, 226, 1324, 504), colore("#93a7a0"))
    rettangolo(d, (856, 380, 1324, 504), colore("#6f8478"))
    rettangolo(d, (856, 440, 1324, 504), colore("#c2a27c"))
    # Mensola con vasi.
    rettangolo(d, (1500, 380, 1820, 396), colore("#8a6a4a"))
    for x, h, c in ((1530, 90, "#f0ebe2"), (1600, 60, "#9b6b4a"), (1690, 120, "#3d4d47"), (1760, 50, "#e2d7c3")):
        rettangolo(d, (x, 380 - h, x + 44, 380), colore(c), 10)
    # Divano.
    rettangolo(d, (640, 600, 1560, 900), colore("#6f7c80"), 40)
    rettangolo(d, (680, 540, 1520, 700), colore("#7b888c"), 40)
    for x in (700, 1000, 1290):
        rettangolo(d, (x, 560, x + 240, 700), varia(colore("#87949a"), rnd, 0.05), 30)
    rettangolo(d, (760, 600, 900, 690), colore("#c9a46b"), 26)  # cuscino senape
    rettangolo(d, (1360, 590, 1490, 690), colore("#b56b4b"), 26)  # cuscino terracotta
    # Pavimento di legno e tappeto.
    rettangolo(d, (0, 880, L, A), colore("#7d5a3e"))
    d.ellipse((520, 900, 1700, 1180), fill=colore("#cbbda6"))
    # Pianta grande accanto alla finestra.
    for _ in range(60):
        x, y = rnd.gauss(560, 70), rnd.gauss(600, 150)
        r = rnd.uniform(26, 60)
        d.ellipse((x - r, y - r * 0.45, x + r, y + r * 0.45), fill=varia(colore("#3f6a3c"), rnd, 0.25))
    rettangolo(d, (500, 800, 620, 900), colore("#c4b39a"), 12)
    # Lampada da terra a destra.
    rettangolo(d, (1700, 380, 1712, 900), colore("#2d2a27"))
    img = sfoca(img, 28)
    img = luce(img, (200, 400), (700, 700), colore("#fff6e4"), 0.45)  # giorno dalla finestra
    img = luce(img, (1705, 330), (520, 520), colore("#ffb86e"), 0.55)  # lampada
    img = bokeh(img, [(1705, 330, 80, colore("#ffd9a0"), 0.35)], 10)
    img = ombra(img, (L / 2, A + 200), (1400, 500), 0.25)
    return vignetta(img, 0.3)


def studio():
    """Studio scuro: parete antracite, luci pratiche calde, una striscia LED salvia, riflessi fuori fuoco."""
    rnd = random.Random(41)
    img = sfumatura_verticale([colore("#16191b"), colore("#1d2124"), colore("#121416")])
    d = ImageDraw.Draw(img)
    # Pannelli fonoassorbenti a listelli.
    for x in range(0, L, 64):
        rettangolo(d, (x, 0, x + 44, 860), varia(colore("#26231f"), rnd, 0.05))
    # Mensole con oggetti in controluce.
    for y0 in (360, 620):
        rettangolo(d, (1180, y0, 1820, y0 + 14), colore("#3a332c"))
        x = 1200
        while x < 1780:
            w, h = rnd.uniform(30, 90), rnd.uniform(40, 140)
            rettangolo(d, (x, y0 - h, x + w, y0), varia(colore("#2c2a28"), rnd, 0.3), 6)
            x += w + rnd.uniform(20, 60)
    # Scrivania in basso.
    rettangolo(d, (0, 860, L, A), colore("#0e0f10"))
    img = sfoca(img, 20)
    # Striscia LED salvia dietro le mensole e luce calda di una lampada.
    img = luce(img, (1500, 640), (520, 120), colore("#6e9a86"), 0.6)
    img = luce(img, (1500, 380), (520, 110), colore("#6e9a86"), 0.45)
    img = luce(img, (380, 300), (620, 620), colore("#c97b3c"), 0.55)
    punti = [(380, 300, 120, colore("#ffc887"), 0.9)]
    for _ in range(28):
        x, y = rnd.uniform(0, L), rnd.uniform(80, 820)
        c = rnd.choice([colore("#ffb871"), colore("#ffd9a8"), colore("#8fc0a9"), colore("#e67a67")])
        punti.append((x, y, rnd.uniform(18, 60), c, rnd.uniform(0.15, 0.45)))
    img = bokeh(img, punti, 3)
    return vignetta(img, 0.4)


def citta():
    """Città di sera dietro una vetrata: cielo blu profondo, palazzi con le finestre accese, luci in bokeh."""
    rnd = random.Random(53)
    img = sfumatura_verticale([colore("#0d1a33"), colore("#1d2c52"), colore("#3a3d63"), colore("#6a4a5a"),
                               colore("#1a1a26")])
    d = ImageDraw.Draw(img)
    # Palazzi lontani (più chiari, nella foschia) e vicini (più scuri).
    for strato, (base, tinta, altezza) in enumerate(((760, "#262d4a", 380), (860, "#171b2e", 520))):
        x = -50
        while x < L:
            w = rnd.uniform(90, 230)
            h = rnd.uniform(altezza * 0.4, altezza)
            rettangolo(d, (x, base - h, x + w, A), varia(colore(tinta), rnd, 0.1))
            # Finestre accese.
            for fy in range(int(base - h + 20), A, 26):
                for fx in range(int(x + 10), int(x + w - 12), 22):
                    if rnd.random() < 0.38:
                        c = rnd.choice([colore("#ffd28a"), colore("#fff1cf"), colore("#bcd4ff"), colore("#ffb066")])
                        rettangolo(d, (fx, fy, fx + 10, fy + 14), mescola(c, colore(tinta), rnd.uniform(0, 0.5)))
            x += w + rnd.uniform(4, 30)
    img = sfoca(img, 14)
    img = luce(img, (L * 0.55, 760), (1300, 260), colore("#ff9a6a"), 0.35)  # bagliore della città
    punti = []
    for _ in range(90):
        x, y = rnd.uniform(-40, L + 40), rnd.uniform(420, 1040)
        c = rnd.choice([colore("#ffcf87"), colore("#ffe6bd"), colore("#ff8a5c"), colore("#9fc3ff"),
                        colore("#fff4dd"), colore("#e67a67")])
        punti.append((x, y, rnd.uniform(14, 52), c, rnd.uniform(0.2, 0.7)))
    # Fari e lampioni in basso, più grandi.
    for _ in range(14):
        x, y = rnd.uniform(0, L), rnd.uniform(900, 1080)
        punti.append((x, y, rnd.uniform(50, 95), rnd.choice([colore("#ffd59c"), colore("#ff7b5c")]), rnd.uniform(0.4, 0.8)))
    img = bokeh(img, punti, 2.5)
    # Riflesso leggero sul vetro.
    img = luce(img, (300, 200), (700, 420), colore("#2e3c5c"), 0.25)
    img = sfoca(img, 1.2)
    return vignetta(img, 0.3)


def cemento():
    """Parete di cemento a vista: casseri, fori dei tiranti, luce radente dall'alto a sinistra."""
    rnd = random.Random(67)
    base = Image.new("RGB", (L, A), colore("#a7a49e"))
    tex = texture((L, A), 670, scale=((6, 0.25), (24, 0.5), (96, 0.7), (320, 1.0)), forza=7)
    img = applica_texture(base, tex, 1.0)
    d = ImageDraw.Draw(img)
    # Pori e bollicine d'aria, sparsi.
    for _ in range(2600):
        x, y, r = rnd.uniform(0, L), rnd.uniform(0, A), rnd.uniform(1.2, 4.5)
        d.ellipse((x - r, y - r, x + r, y + r), fill=varia(colore("#97948d"), rnd, 0.06))
    # Colature verticali: macchie allungate dall'alto in basso.
    colature = texture((L // 40, 6), 671, scale=((1, 1.0),), forza=5).resize((L, A), Image.BICUBIC)
    img = applica_texture(img, colature, 1.0)
    d = ImageDraw.Draw(img)
    pannello_l, pannello_a = 640, 360
    # Giunti tra i pannelli e leggere differenze di tinta.
    for i, x in enumerate(range(0, L + 1, pannello_l)):
        for j, y in enumerate(range(0, A + 1, pannello_a)):
            f = rnd.uniform(-0.05, 0.05)
            strato = Image.new("RGB", (pannello_l, pannello_a), tuple(round(128 * (1 + f)) for _ in range(3)))
            regione = img.crop((x, y, x + pannello_l, y + pannello_a))
            img.paste(ImageChops.multiply(regione, strato.point(lambda v: min(255, v * 2))), (x, y))
    d = ImageDraw.Draw(img)
    for x in range(0, L + 1, pannello_l):
        d.line((x, 0, x, A), fill=colore("#7d7a75"), width=3)
    for y in range(0, A + 1, pannello_a):
        d.line((0, y, L, y), fill=colore("#7d7a75"), width=3)
    # Fori dei tiranti.
    for x in range(0, L, pannello_l):
        for y in range(0, A, pannello_a):
            for fx in (0.17, 0.5, 0.83):
                for fy in (0.25, 0.75):
                    cx, cy = x + pannello_l * fx, y + pannello_a * fy
                    d.ellipse((cx - 13, cy - 13, cx + 13, cy + 13), fill=colore("#86837d"))
                    d.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=colore("#6a6762"))
    img = sfoca(img, 6)
    img = luce(img, (250, -100), (1500, 900), colore("#fff1dc"), 0.45)
    img = ombra(img, (L + 100, A + 100), (1400, 900), 0.4)
    return vignetta(img, 0.3)


def piante():
    """Piante: foglie in primo piano e dietro, luce del sole che filtra, parete chiara."""
    rnd = random.Random(79)
    img = sfumatura_orizzontale([colore("#f0eee4"), colore("#e4e6d6"), colore("#c9d2bc"), colore("#9eb092")])
    d = ImageDraw.Draw(img)
    verdi = ["#2f5a2e", "#3e6e36", "#4f7f3f", "#6c9550", "#86a865", "#24452a", "#5b7f5a"]

    def foglia(x, y, lunghezza, larghezza, angolo, c):
        punti = []
        for k in range(24):
            t = k / 23
            punti.append((t, math.sin(math.pi * t) * larghezza / 2))
        contorno = [(t * lunghezza, w) for t, w in punti] + [(t * lunghezza, -w) for t, w in reversed(punti)]
        ca, sa = math.cos(angolo), math.sin(angolo)
        d.polygon([(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in contorno], fill=c)

    # Strato lontano: cespugli.
    for _ in range(40):
        x, y = rnd.uniform(600, L + 100), rnd.uniform(200, A)
        r = rnd.uniform(60, 160)
        d.ellipse((x - r, y - r, x + r, y + r), fill=varia(colore(rnd.choice(verdi[3:])), rnd, 0.12))
    img = sfoca(img, 28)
    d = ImageDraw.Draw(img)
    # Strato medio: foglie grandi (monstera, ficus) che salgono dal basso.
    for _ in range(70):
        x, y = rnd.uniform(-100, L + 100), rnd.uniform(A * 0.35, A + 100)
        if 500 < x < 1400 and rnd.random() < 0.6:
            continue  # il centro resta più aperto: dietro la persona
        foglia(x, y, rnd.uniform(160, 340), rnd.uniform(70, 150), rnd.uniform(-2.6, -0.5),
               varia(colore(rnd.choice(verdi)), rnd, 0.15))
    img = sfoca(img, 14)
    d = ImageDraw.Draw(img)
    # Primo piano agli angoli: foglie scurissime, molto sfocate.
    for _ in range(14):
        x = rnd.choice([rnd.uniform(-150, 250), rnd.uniform(1650, L + 150)])
        y = rnd.uniform(-100, A + 100)
        foglia(x, y, rnd.uniform(300, 520), rnd.uniform(130, 220), rnd.uniform(0, 2 * math.pi),
               varia(colore("#1c3520"), rnd, 0.2))
    img = sfoca(img, 22)
    # Sole che filtra tra le foglie.
    img = luce(img, (420, 180), (900, 600), colore("#fff4d6"), 0.55)
    punti = [(rnd.gauss(500, 300), rnd.gauss(260, 160), rnd.uniform(20, 55), colore("#fff6dc"), rnd.uniform(0.25, 0.6))
             for _ in range(26)]
    img = bokeh(img, punti, 3)
    return vignetta(img, 0.25)


def lrapps():
    """Verde WebcamLR: la sfumatura del marchio (#30453E → #0D1B18) con una luce morbida e qualche riflesso salvia."""
    rnd = random.Random(97)
    img = sfumatura_verticale([colore("#30453E"), colore("#24372f"), colore("#172923"), colore("#0D1B18")])
    img = luce(img, (L * 0.3, A * 0.2), (1100, 700), colore("#5d7a6c"), 0.45)
    img = luce(img, (L * 0.85, A * 0.75), (700, 500), colore("#2d4a3f"), 0.4)
    punti = [(rnd.uniform(0, L), rnd.uniform(0, A), rnd.uniform(30, 110), colore("#a9c2b3"), rnd.uniform(0.06, 0.18))
             for _ in range(22)]
    img = bokeh(img, punti, 6)
    return vignetta(img, 0.3)


SCENE = [
    ("ufficio", ufficio),
    ("libreria", libreria),
    ("soggiorno", soggiorno),
    ("studio", studio),
    ("citta", citta),
    ("cemento", cemento),
    ("piante", piante),
    ("lrapps", lrapps),
]


def gia_foto():
    """Gli id che prepara_sfondi.py prepara (foto o lrapps nitido): qui non si sovrascrivono mai."""
    import json
    elenco = json.loads((RADICE / "Strumenti/sfondi_foto.json").read_text(encoding="utf-8"))
    return {v["id"] for v in elenco["sfondi"] if v.get("foto") or v.get("disegnato")}


def main(argomenti):
    scelte = set(argomenti)
    saltati = gia_foto()
    for cartella in GRANDI + PICCOLE:
        cartella.mkdir(parents=True, exist_ok=True)
    for indice, (identificativo, scena) in enumerate(SCENE):
        if scelte and identificativo not in scelte:
            continue
        if identificativo in saltati:
            print(f"{identificativo}: lo prepara Strumenti/prepara_sfondi.py, saltato")
            continue
        img = scena().convert("RGB")
        assert img.size == (L, A), (identificativo, img.size)
        img = grana(img, 1000 + indice, forza=5.0)
        for cartella in GRANDI:
            img.save(cartella / f"{identificativo}.jpg", quality=QUALITA, optimize=True, progressive=True)
        piccola = img.resize(MINIATURA, Image.LANCZOS)
        for cartella in PICCOLE:
            piccola.save(cartella / f"{identificativo}.jpg", quality=QUALITA, optimize=True)
        print(f"{identificativo}: fatto")


if __name__ == "__main__":
    main(sys.argv[1:])
