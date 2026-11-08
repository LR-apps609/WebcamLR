"""Il motore effetti di Windows (WebcamLR.Effetti) riscritto in numpy, passo per passo, per il banco di prova.

Ogni funzione ha lo stesso nome (in minuscolo) e gli stessi conti del C#:
- Preparazione.BgraInRgb, Preparazione.Persona            -> bgra_in_rgb, persona
- FiltroTemporale.Applica                                   -> FiltroTemporale.applica
- Elaborazione.Dimezza, Luminosita, Campiona, MediaQuadrata,
  FiltroGuidato, FiltroGuidatoVeloce, SogliaMorbida, Gaussiana -> stessi nomi
- Compositore.SfocataSenzaAlone, Componi (parte «sfocato») -> sfocata_senza_alone, componi
I conti sono in float32 come in C#; cambia solo l'ordine delle somme (differenze di 1e-6). VerificaCs/ confronta
le maschere con la libreria C# vera.
"""

import math

import cv2
import numpy as np

F = np.float32

# --- Preparazione.cs ------------------------------------------------------------------------------------------------


def bgra_in_rgb(bgr: np.ndarray, larghezza_dest: int, altezza_dest: int, scala: float, spostamento: float) -> np.ndarray:
    """Media dei pixel coperti da ogni punto del modello (confini interi come in C#), RGB NHWC float32."""
    altezza, larghezza = bgr.shape[:2]
    x0 = (np.arange(larghezza_dest + 1, dtype=np.int64) * larghezza) // larghezza_dest
    ya = (np.arange(altezza_dest, dtype=np.int64) * altezza) // altezza_dest
    yb = np.maximum(ya + 1, (np.arange(1, altezza_dest + 1, dtype=np.int64) * altezza) // altezza_dest)
    xa = x0[:-1]
    xb = np.maximum(xa + 1, x0[1:])
    # Immagine integrale (somme intere esatte, come gli int del C#).
    integ = np.zeros((altezza + 1, larghezza + 1, 3), dtype=np.int64)
    integ[1:, 1:] = bgr.astype(np.int64).cumsum(0).cumsum(1)
    s = (integ[yb][:, xb] - integ[ya][:, xb] - integ[yb][:, xa] + integ[ya][:, xa])
    n = ((yb - ya)[:, None] * (xb - xa)[None, :]).astype(F)
    rgb = s[..., ::-1].astype(F)  # BGR -> RGB
    out = rgb / n[..., None] * F(scala) + F(spostamento)
    return out.astype(F)[None]


def persona(uscita: np.ndarray) -> np.ndarray:
    """1 − sfondo con il multiclasse (softmax), il canale unico con il leggero; [H, W] in [0, 1]."""
    u = uscita[0]
    if u.shape[-1] == 1:
        return np.clip(u[..., 0], 0, 1).astype(F)
    return np.clip(F(1) - u[..., 0], 0, 1).astype(F)


def in_byte(m: np.ndarray) -> np.ndarray:
    """(byte)(m × 255f + 0,5f)."""
    return np.floor(m.astype(F) * F(255) + F(0.5)).astype(np.uint8)


# --- FiltroTemporale.cs ---------------------------------------------------------------------------------------------


class FiltroTemporale:
    """Peso della nuova 0,7 + 3 × |differenza| (al massimo 1), senza ritardo."""

    PESO_MINIMO = F(0.7)
    PENDENZA = F(3)

    def __init__(self):
        self.precedente = None

    def applica(self, maschera: np.ndarray) -> np.ndarray:
        if self.precedente is None or self.precedente.shape != maschera.shape:
            self.precedente = maschera.copy()
            return maschera
        peso = np.minimum(F(1), self.PESO_MINIMO + self.PENDENZA * np.abs(maschera - self.precedente))
        v = (maschera * peso + self.precedente * (F(1) - peso)).astype(F)
        self.precedente = v.copy()
        return v


# --- Elaborazione.cs ------------------------------------------------------------------------------------------------


def dimezza(bgr: np.ndarray) -> np.ndarray:
    """Media 2×2 con arrotondamento ((a+b+c+d+2) >> 2); le misure dispari perdono l'ultima riga o colonna."""
    a, l = bgr.shape[0] // 2, bgr.shape[1] // 2
    s = bgr[: 2 * a, : 2 * l].astype(np.uint16)
    somma = s[0::2, 0::2] + s[0::2, 1::2] + s[1::2, 0::2] + s[1::2, 1::2] + 2
    return (somma >> 2).astype(np.uint8)


def luminosita(bgr: np.ndarray) -> np.ndarray:
    b, g, r = (bgr[..., i].astype(F) for i in range(3))
    return (F(0.0722 / 255) * b + F(0.7152 / 255) * g + F(0.2126 / 255) * r).astype(F)


def campionamento(destinazione: int, sorgente: int):
    """I due vicini e il peso del secondo per ogni punto (centri dei pixel), come Elaborazione.Campionamento."""
    scala = sorgente / destinazione
    p = np.clip((np.arange(destinazione) + 0.5) * scala - 0.5, 0, sorgente - 1)
    primo = p.astype(np.int64)
    secondo = np.minimum(primo + 1, sorgente - 1)
    return primo, secondo, (p - primo).astype(F)


def ricampiona(piano: np.ndarray, larghezza: int, altezza: int) -> np.ndarray:
    """Bilineare con Campionamento: prima in orizzontale per riga, poi in verticale (float32)."""
    piano = piano.astype(F)
    x0, x1, fx = campionamento(larghezza, piano.shape[1])
    y0, y1, fy = campionamento(altezza, piano.shape[0])
    a, b = piano[y0], piano[y1]
    sopra = a[:, x0] + (a[:, x1] - a[:, x0]) * fx
    sotto = b[:, x0] + (b[:, x1] - b[:, x0]) * fx
    return (sopra + (sotto - sopra) * fy[:, None]).astype(F)


def campiona(maschera_byte: np.ndarray, larghezza: int, altezza: int) -> np.ndarray:
    """La maschera (byte) alla misura data, bilineare, in 0..1."""
    return (ricampiona(maschera_byte.astype(F), larghezza, altezza) * F(1 / 255)).astype(F)


def media_quadrata(x: np.ndarray, raggio: int) -> np.ndarray:
    """Media su (2r+1)² con i bordi ristretti (solo i pixel dentro l'immagine)."""
    x = x.astype(F)

    def lungo(v, asse):
        n = v.shape[asse]
        c = np.cumsum(v, axis=asse, dtype=np.float64)
        zero = np.zeros_like(np.take(c, [0], axis=asse))
        c = np.concatenate([zero, c], axis=asse)
        i = np.arange(n)
        hi = np.minimum(i + raggio, n - 1) + 1
        lo = np.maximum(i - raggio, 0)
        s = np.take(c, hi, axis=asse) - np.take(c, lo, axis=asse)
        forma = [1] * v.ndim
        forma[asse] = n
        return (s / (hi - lo).reshape(forma)).astype(F)

    return lungo(lungo(x, 1), 0)


def filtro_guidato(guida, p, raggio, eps, solo_coefficienti=False):
    """He, Sun e Tang con medie quadrate; restituisce q, o (media a, media b)."""
    m_i = media_quadrata(guida, raggio)
    m_p = media_quadrata(p, raggio)
    m_ip = media_quadrata(guida * p, raggio)
    m_ii = media_quadrata(guida * guida, raggio)
    a = ((m_ip - m_i * m_p) / (m_ii - m_i * m_i + F(eps))).astype(F)
    b = (m_p - a * m_i).astype(F)
    ma, mb = media_quadrata(a, raggio), media_quadrata(b, raggio)
    if solo_coefficienti:
        return ma, mb
    return (ma * guida + mb).astype(F)


def filtro_guidato_veloce(guida_alta, guida_bassa, p_bassa, raggio_basso, eps):
    """Coefficienti sulla guida piccola, ingranditi bilineari, applicati alla guida grande."""
    ma, mb = filtro_guidato(guida_bassa, p_bassa, raggio_basso, eps, solo_coefficienti=True)
    altezza, larghezza = guida_alta.shape
    return (ricampiona(ma, larghezza, altezza) * guida_alta + ricampiona(mb, larghezza, altezza)).astype(F)


CENTRO_SOGLIA = 0.42


def soglia_morbida(valori, larghezza, centro=CENTRO_SOGLIA):
    """t tra 0 e 1, poi smoothstep; in byte come in C#."""
    ampiezza = F(min(max(larghezza, 0.05), 1.0))
    inizio = F(centro) - ampiezza / F(2)
    t = np.clip((valori - inizio) / ampiezza, 0, 1).astype(F)
    return np.floor(t * t * (F(3) - F(2) * t) * F(255) + F(0.5)).astype(np.uint8)


def gaussiana(dati: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussiana separabile, nucleo fino a 3σ (normalizzato), bordi ripetuti."""
    if sigma < 0.3:
        return dati
    raggio = max(1, int(math.ceil(sigma * 3)))
    i = np.arange(-raggio, raggio + 1, dtype=np.float64)
    nucleo = np.exp(-i * i / (2 * sigma * sigma))
    nucleo = (nucleo / nucleo.sum()).astype(np.float32)
    return cv2.sepFilter2D(dati.astype(F), -1, nucleo, nucleo, borderType=cv2.BORDER_REPLICATE)


# --- Compositore.cs (sfondo sfocato) --------------------------------------------------------------------------------


def sigma_sfocatura(intensita: float) -> float:
    return max(1.5, 32 * math.pow(min(max(intensita, 0), 1), 1.6))


def gradino_sfocatura(sigma_piena: float) -> int:
    gradino, sigma = 0, sigma_piena / 4
    while sigma > 3 and gradino < 3:
        sigma /= 2
        gradino += 1
    return gradino


def piramide(quarto: np.ndarray, gradino: int) -> np.ndarray:
    livello = quarto
    for _ in range(gradino):
        livello = dimezza(livello)
    return livello


def sfocata_senza_alone(quarto, persona_livello_fn, intensita, larghezza_piena, altezza_piena,
                        allarga=lambda p: np.clip(F(2) * p - F(0.3), 0, F(0.99)), soglia_alfa=0.02):
    """Sfocatura normalizzata: sfondo × (1 − persona allargata), sfocato e diviso per l'alfa sfocato (piccolo).
    `persona_livello_fn(l, a)` dà la persona (0..1) alla misura del gradino; `allarga` è la regola della persona tolta
    (Windows: 2m − 0,3, al massimo 0,99). Dove l'alfa sfocato è sotto `soglia_alfa` Windows prende il pixel com'è
    (con la persona); con 0 si divide sempre, come il Mac (unpremultiplyingAlpha)."""
    sigma = sigma_sfocatura(intensita) * min(larghezza_piena, altezza_piena) / 1080.0
    livello = piramide(quarto, gradino_sfocatura(sigma))
    a, l = livello.shape[:2]
    sigma_piccola = sigma * (l / larghezza_piena)
    p = persona_livello_fn(l, a)
    w = (F(1) - allarga(p)).astype(F)
    pre = np.concatenate([livello.astype(F) * w[..., None], w[..., None]], axis=2)
    pre = gaussiana(pre, sigma_piccola)
    ws = pre[..., 3]
    with np.errstate(divide="ignore", invalid="ignore"):
        colore = np.floor(np.minimum(F(255), pre[..., :3] / ws[..., None] + F(0.5)))
    uscita = np.where((ws > F(soglia_alfa))[..., None], colore, livello.astype(F)).astype(np.uint8)
    return uscita


def ingrandisci8(piano: np.ndarray, larghezza: int, altezza: int) -> np.ndarray:
    """L'ingrandimento a pesi in 256esimi di Componi (prima in verticale, poi in orizzontale), per byte."""
    x0, x1, fx = campionamento(larghezza, piano.shape[1])
    y0, y1, fy = campionamento(altezza, piano.shape[0])
    wx = (fx * 256).astype(np.int64)
    wy = (fy * 256).astype(np.int64)
    p = piano.astype(np.int64)
    r0, r1 = p[y0], p[y1]
    if p.ndim == 2:
        riga = (r0 << 8) + (r1 - r0) * wy[:, None]
        return ((((riga[:, x0] << 8) + (riga[:, x1] - riga[:, x0]) * wx[None, :]) + 32768) >> 16).astype(np.uint8)
    riga = (r0 << 8) + (r1 - r0) * wy[:, None, None]
    return ((((riga[:, x0] << 8) + (riga[:, x1] - riga[:, x0]) * wx[None, :, None]) + 32768) >> 16).astype(np.uint8)


def miscela(sopra: np.ndarray, sotto: np.ndarray, alfa: np.ndarray) -> np.ndarray:
    """sopra × alfa + sotto × (1 − alfa) in byte, con la divisione per 255 di Compositore.Miscela."""
    a = alfa.astype(np.int32)[..., None]
    v = sopra.astype(np.int32) * a + sotto.astype(np.int32) * (255 - a) + 128
    return ((v + (v >> 8)) >> 8).astype(np.uint8)
