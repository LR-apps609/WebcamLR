"""Le misure di qualità, fotogramma per fotogramma, contro l'alfa vera (tutto a 1920×1080, alfa in 0..1).

- IoU: persona (alfa ≥ 0,5) contro persona vera.
- MAD bordo: errore medio |alfa − vera| nella fascia di ±10 px dal contorno vero (×1000).
- Grad bordo: errore medio sul gradiente (Sobel dopo una gaussiana σ = 1,4, come nelle prove di matting) nella
  stessa fascia (×1000).
- dtSSD: sqrt(media((Δalfa − Δvera)²)) × 100 tra fotogrammi successivi, su tutta l'immagine (come RVM).
- Tremolio bordo: media |Δalfa| dove la verità non cambia (|Δvera| < 0,01) entro 20 px dal contorno (×1000).
- Alone: errore medio di colore (0..255) dell'immagine sfocata rispetto a quella ideale nell'anello 0–40 px fuori
  dalla persona. Ideale = persona vera sopra lo sfondo sfocato con la sfocatura normalizzata dalla persona vera (stessa
  piramide di Windows): ci arriva una maschera perfetta, e il colore della persona che sbava fuori pesa qui.
- Errore immagine bordo: lo stesso nella fascia ±10 px dal contorno.
"""

import cv2
import numpy as np

F = np.float32


class Verita:
    """Le zone calcolate una volta per fotogramma dalla verità."""

    def __init__(self, vera: np.ndarray):
        self.vera = vera
        dentro = (vera >= 0.5).astype(np.uint8)
        # Distanza dal contorno: dai pixel dentro verso fuori e viceversa.
        d_fuori = cv2.distanceTransform(1 - dentro, cv2.DIST_L2, 3)
        d_dentro = cv2.distanceTransform(dentro, cv2.DIST_L2, 3)
        distanza = np.where(dentro > 0, d_dentro, d_fuori)
        self.dentro = dentro > 0
        self.fascia10 = distanza <= 10
        self.fascia20 = distanza <= 20
        self.anello = (~self.dentro) & (vera < 0.01) & (d_fuori <= 40)
        self.grad = gradiente(vera)


def gradiente(a: np.ndarray) -> np.ndarray:
    g = cv2.GaussianBlur(a.astype(F), (0, 0), 1.4)
    gx = cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(g, cv2.CV_32F, 0, 1, ksize=3)
    return np.sqrt(gx * gx + gy * gy)


def per_fotogramma(alfa, verita: Verita, uscita=None, ideale=None, alfa_prec=None, vera_prec=None):
    v = verita.vera
    p = alfa >= 0.5
    unione = np.count_nonzero(p | verita.dentro)
    r = {
        "iou": np.count_nonzero(p & verita.dentro) / unione if unione else 1.0,
        "mad_bordo": float(np.abs(alfa - v)[verita.fascia10].mean() * 1000),
        "grad_bordo": float(np.abs(gradiente(alfa) - verita.grad)[verita.fascia10].mean() * 1000),
    }
    if alfa_prec is not None:
        da, dv = alfa - alfa_prec, v - vera_prec
        r["dtssd"] = float(np.sqrt(np.mean((da - dv) ** 2)) * 100)
        ferma = (np.abs(dv) < 0.01) & verita.fascia20
        r["tremolio"] = float(np.abs(da)[ferma].mean() * 1000) if ferma.any() else 0.0
    if uscita is not None and ideale is not None:
        diff = np.abs(uscita.astype(F) - ideale.astype(F)).mean(axis=2)
        r["alone"] = float(diff[verita.anello].mean()) if verita.anello.any() else 0.0
        r["errore_immagine"] = float(diff[verita.fascia10].mean())
    return r
