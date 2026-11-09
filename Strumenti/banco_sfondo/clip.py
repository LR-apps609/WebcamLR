"""Le clip di prova: persone di VideoMatte240K (primo piano + alfa vera) composte a 1920×1080 su sfondi nitidi che
si muovono come davanti a un telefono tenuto in mano (panoramica lenta e tremolio), più il rumore del sensore.

Gli sfondi sono le scene di Strumenti/genera_sfondi.py (disegnate da noi, nessuna licenza di terzi) senza la
sfocatura finale: un fondo nitido, come quello vero di una stanza, è il caso difficile per il bordo.
Tutto è deterministico (semi fissi): stesse clip a ogni esecuzione.
"""

import importlib.util
import math
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

RADICE = Path(__file__).resolve().parents[2]
L, A = 1920, 1080


@dataclass(frozen=True)
class Clip:
    nome: str
    persona: str  # cartella di VideoMatte240K_JPEG_HD/test
    sfondo: str  # scena di genera_sfondi.py
    descrizione: str


CLIP = [
    Clip("vm0000_libreria", "0000", "libreria", "libri colorati e nitidi dietro (molti bordi)"),
    Clip("vm0001_ufficio", "0001", "ufficio", "fondo chiaro, vetrata"),
    Clip("vm0002_soggiorno", "0002", "soggiorno", "parete calda, divano"),
    Clip("vm0003_studio", "0003", "studio", "giacca scura su fondo scuro (il caso della felpa di Ledion)"),
    Clip("vm0004_cemento", "0004", "cemento", "parete grigia con texture"),
]

_sfondi = {}


def sfondo_nitido(scena: str) -> np.ndarray:
    """La scena di genera_sfondi.py senza le sfocature (BGR, 1920×1080), un po' più grande per poterla muovere."""
    if scena not in _sfondi:
        spec = importlib.util.spec_from_file_location("genera_sfondi", RADICE / "Strumenti/genera_sfondi.py")
        modulo = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(modulo)
        modulo.sfoca = lambda img, raggio: img  # niente «fuori fuoco»: fondo nitido
        rgb = np.asarray(getattr(modulo, scena)().convert("RGB"))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        _sfondi[scena] = cv2.resize(bgr, (int(L * 1.12), int(A * 1.12)), interpolation=cv2.INTER_CUBIC)
    return _sfondi[scena]


def movimento(i: int, seme: int):
    """Spostamento dello sfondo (panoramica lenta) e tremolio comune a tutta l'immagine, in pixel."""
    rnd = np.random.default_rng(seme)
    fasi = rnd.uniform(0, 2 * math.pi, 4)
    t = i / 30.0
    pan = (60 * math.sin(2 * math.pi * t / 6 + fasi[0]), 25 * math.sin(2 * math.pi * t / 4.5 + fasi[1]))
    trema = (1.5 * math.sin(2 * math.pi * t * 1.7 + fasi[2]) + 0.8 * math.sin(2 * math.pi * t * 4.1),
             1.2 * math.sin(2 * math.pi * t * 2.3 + fasi[3]) + 0.6 * math.sin(2 * math.pi * t * 3.7))
    return pan, trema


def fotogrammi(clip: Clip, cartella_vm: Path, quanti: int, rumore: float = 2.0):
    """Generatore di (immagine BGR uint8, alfa vera float32 0..1, sfondo pulito BGR uint8) a 1920×1080."""
    base = cartella_vm / "VideoMatte240K_JPEG_HD" / "test"
    fondo_grande = sfondo_nitido(clip.sfondo)
    seme = int(clip.persona) + 11
    rnd = np.random.default_rng(seme * 7)
    for i in range(quanti):
        fgr = cv2.imread(str(base / "fgr" / clip.persona / f"{i:05d}.jpg"))
        pha = cv2.imread(str(base / "pha" / clip.persona / f"{i:05d}.jpg"), cv2.IMREAD_GRAYSCALE)
        if fgr is None or pha is None:
            return
        fgr = cv2.resize(fgr, (L, A), interpolation=cv2.INTER_AREA).astype(np.float32)
        alfa = cv2.resize(pha, (L, A), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
        (px, py), (tx, ty) = movimento(i, seme)
        # Sfondo: finestra 1920×1080 che scorre sulla scena allargata (panoramica + tremolio).
        ox = (fondo_grande.shape[1] - L) / 2 + px + tx
        oy = (fondo_grande.shape[0] - A) / 2 + py + ty
        m = np.float32([[1, 0, -ox], [0, 1, -oy]])
        fondo = cv2.warpAffine(fondo_grande, m, (L, A), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
        # Il tremolio muove anche la persona (è la fotocamera che trema).
        mt = np.float32([[1, 0, tx], [0, 1, ty]])
        fgr = cv2.warpAffine(fgr, mt, (L, A), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        alfa = cv2.warpAffine(alfa, mt, (L, A), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        composta = fgr * alfa[..., None] + fondo.astype(np.float32) * (1 - alfa[..., None])
        composta += rnd.normal(0, rumore, composta.shape).astype(np.float32)
        yield np.clip(composta + 0.5, 0, 255).astype(np.uint8), np.clip(alfa, 0, 1), fondo
