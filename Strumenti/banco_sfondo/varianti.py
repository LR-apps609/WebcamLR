"""Le varianti da confrontare: dal fotogramma all'alfa a piena risoluzione e all'immagine con lo sfondo sfocato.

Ogni variante è un oggetto con stato (i filtri nel tempo) che riceve, fotogramma per fotogramma, l'immagine BGR a
1920×1080 e la persona grezza del modello (0..1 alla misura del modello) e restituisce l'alfa a piena misura (float
0..1) e l'immagine con lo sfondo sfocato (intensità «Medio», 0,55, come le prove di Effetti su Windows.md).

  A0  grezza: filtro nel tempo di Windows e ingrandimento bilineare, niente bordo e niente soglia (riferimento)
  A   come oggi su Windows (Compositore, livello Pieno): filtro guidato veloce con a, b al quarto (raggio 2 = circa
      8 px a 1080p, eps 1e-3) applicati a metà risoluzione, soglia morbida 0,17–0,67, sfocatura senza alone con la
      persona del modello allargata (2m − 0,3)
  B   A con il filtro guidato più fine, come sul Mac: a, b a metà risoluzione (lato corto 540), raggio r (in pixel a
      1080p) ed eps, applicati alla luminanza piena
  C   B più una media nel tempo (EMA) sulla maschera che dipende dal movimento dell'immagine
  Cm  B con il filtro nel tempo del Mac (media 0,3 con isteresi 0,3/0,7 e spinta 0,15) al posto di quello di Windows
  D   C più soglia smoothstep 0,3–0,7 e sfocatura normalizzata dalla maschera rifinita (allargata di 12 px, niente alone)
  E   MODNet (Apache-2.0) al posto di MediaPipe, con la rifinitura di D
  Q   come oggi su Windows (ramo prestazioni): D* più l'isteresi della maschera (Qualità 4, IsteresiMaschera). Vale
      per ogni modello, anche MODNet (la sua alfa entra nel bordo e nella soglia di oggi)
  M   matting diretto per MODNet: filtro nel tempo e media dal movimento di oggi, poi l'alfa ingrandita bilineare
      senza filtro guidato né soglia (l'alfa morbida dei capelli resta), sfocatura di oggi

Parametri (banco.py, «modello/Nome:parametro=valore»): B raggio, eps, fine=0 (filtro guidato di A invece di quello
fine); C peso_fermo, pendenza; D soglia_alfa, allarga_px, fondo_modello=1 (la sfocatura di A invece di quella del Mac).
La variante consigliata per Windows («D*» nei documenti) è pieno/D:fondo_modello=1:fine=0: il bordo e la sfocatura
di oggi, con l'EMA dipendente dal movimento e la soglia 0,3–0,7.
"""

import time

import cv2
import numpy as np

import ricette_windows as rw

F = np.float32
INTENSITA = 0.55  # «Medio»
L, A = 1920, 1080


class Variante:
    nome = "?"
    descrizione = ""

    def __init__(self, **parametri):
        self.parametri = parametri
        self.filtro = rw.FiltroTemporale()

    # --- maschera nel tempo (alla misura del modello) ---
    def nel_tempo(self, grezza: np.ndarray, ingresso_modello: np.ndarray) -> np.ndarray:
        return self.filtro.applica(grezza.copy())

    # --- bordo: dalla maschera piccola (byte) all'alfa a piena misura ---
    def bordo(self, src, meta, quarto, maschera_byte):
        raise NotImplementedError

    def fondo(self, quarto, maschera_byte, rifinita_bassa):
        """Sfondo sfocato piccolo (Windows: persona del modello allargata 2m − 0,3)."""
        return rw.sfocata_senza_alone(quarto, lambda l, a: rw.campiona(maschera_byte, l, a), INTENSITA, L, A)

    def elabora(self, src, grezza, ingresso_modello):
        """(alfa float 0..1 a piena misura, immagine sfocata uint8, millisecondi della rifinitura)."""
        t0 = time.perf_counter()
        filtrata = self.nel_tempo(grezza, ingresso_modello)
        maschera_byte = rw.in_byte(filtrata)
        meta = rw.dimezza(src)
        quarto = rw.dimezza(meta)
        alfa_byte, rifinita_bassa = self.bordo(src, meta, quarto, maschera_byte)
        alfa_piena = rw.ingrandisci8(alfa_byte, L, A) if alfa_byte.shape != (A, L) else alfa_byte
        fondo_piccolo = self.fondo(quarto, maschera_byte, rifinita_bassa)
        uscita = rw.miscela(src, rw.ingrandisci8(fondo_piccolo, L, A), alfa_piena)
        ms = (time.perf_counter() - t0) * 1000
        return alfa_piena.astype(F) / F(255), uscita, ms


class A0(Variante):
    nome = "A0"
    descrizione = "grezza: maschera del modello ingrandita bilineare, nessuna rifinitura"

    def bordo(self, src, meta, quarto, maschera_byte):
        m = rw.campiona(maschera_byte, L, A)
        return np.floor(m * F(255) + F(0.5)).astype(np.uint8), None


class AWindows(Variante):
    nome = "A"
    descrizione = "come oggi su Windows (guidato veloce al quarto → metà, soglia 0,17–0,67, 2m − 0,3)"
    larghezza_soglia = 0.5
    centro_soglia = rw.CENTRO_SOGLIA

    def rifinisci(self, src, meta, quarto, maschera_byte):
        aq, lq = quarto.shape[:2]
        lavoro = rw.campiona(maschera_byte, lq, aq)
        raggio = max(2, int(round(2.0 * lq / 480)))
        return rw.filtro_guidato_veloce(rw.luminosita(meta), rw.luminosita(quarto), lavoro, raggio, 1e-3)

    def bordo(self, src, meta, quarto, maschera_byte):
        rifinita = self.rifinisci(src, meta, quarto, maschera_byte)
        return rw.soglia_morbida(rifinita, self.larghezza_soglia, self.centro_soglia), rifinita


class B(AWindows):
    nome = "B"
    descrizione = "filtro guidato fine: a, b a metà misura, luminanza piena"

    def __init__(self, raggio=8, eps=1e-3, fine=1, **altri):
        super().__init__(raggio=raggio, eps=eps, fine=fine, **altri)
        self.raggio_pieno, self.eps, self.fine = raggio, eps, bool(fine)

    def rifinisci(self, src, meta, quarto, maschera_byte):
        if not self.fine:  # fine=0: il filtro guidato di oggi (A)
            return super().rifinisci(src, meta, quarto, maschera_byte)
        am, lm = meta.shape[:2]
        lavoro = rw.campiona(maschera_byte, lm, am)
        raggio = max(1, int(round(self.raggio_pieno / 2)))  # a metà misura
        return rw.filtro_guidato_veloce(rw.luminosita(src), rw.luminosita(meta), lavoro, raggio, self.eps)


def movimento_locale(ingresso_modello: np.ndarray, precedente):
    """|ΔY| tra due fotogrammi ridotti alla misura della maschera (RGB 0..1, da bgra_in_rgb), media su 5×5: quanto si
    muove l'immagine in ogni punto."""
    rgb = ingresso_modello[0]
    y = (F(0.2126) * rgb[..., 0] + F(0.7152) * rgb[..., 1] + F(0.0722) * rgb[..., 2]).astype(F)
    if precedente is None:
        return y, None
    return y, rw.media_quadrata(np.abs(y - precedente), 2)


class C(B):
    nome = "C"
    descrizione = "B + EMA della maschera dipendente dal movimento"

    def __init__(self, peso_fermo=0.35, pendenza=12.0, **altri):
        super().__init__(**altri)
        self.parametri.update(peso_fermo=peso_fermo, pendenza=pendenza)
        self.peso_fermo, self.pendenza = F(peso_fermo), F(pendenza)
        self.media = None
        self.y_prec = None
        self.pesi = None  # il peso della nuova per punto nell'ultima maschera (None alla prima): serve all'isteresi

    def nel_tempo(self, grezza, ingresso_modello):
        m = self.filtro.applica(grezza.copy())
        y, mov = movimento_locale(ingresso_modello, self.y_prec)
        self.y_prec = y
        if self.media is None or mov is None:
            self.media = m.copy()
            self.pesi = None
            return m
        peso = np.clip(self.peso_fermo + self.pendenza * mov, self.peso_fermo, F(1))
        self.pesi = peso.astype(F)
        self.media = (self.media + (m - self.media) * peso).astype(F)
        return self.media.copy()


class CMac(B):
    nome = "Cm"
    descrizione = "B + filtro nel tempo del Mac (media 0,3 con isteresi)"

    def __init__(self, **altri):
        super().__init__(**altri)
        self.media = None
        self.stato = None

    def nel_tempo(self, grezza, ingresso_modello):
        # Come MotoreEffetti.filtraNelTempo: lavora sui byte della maschera, al posto del filtro di Windows.
        v = rw.in_byte(grezza).astype(F) / F(255)
        if self.media is None:
            self.media, self.stato = v.copy(), v >= F(0.55)
        else:
            self.media = (self.media + (v - self.media) * F(0.3)).astype(F)
            self.stato = np.where(self.stato & (self.media < F(0.3)), False,
                                  np.where(~self.stato & (self.media > F(0.7)), True, self.stato))
        return np.clip(self.media + np.where(self.stato, F(0.15), F(-0.15)), 0, 1).astype(F)


class D(C):
    nome = "D"
    descrizione = "C + smoothstep 0,3–0,7 + sfocatura normalizzata dalla maschera rifinita (allargata 12 px)"
    larghezza_soglia = 0.4
    centro_soglia = 0.5

    def __init__(self, soglia_alfa=0.0, allarga_px=12.0, fondo_modello=0, **altri):
        super().__init__(**altri)
        self.parametri.update(soglia_alfa=soglia_alfa, allarga_px=allarga_px, fondo_modello=fondo_modello)
        self.soglia_alfa, self.allarga_px, self.fondo_modello = soglia_alfa, allarga_px, bool(fondo_modello)

    def fondo(self, quarto, maschera_byte, rifinita_bassa):
        if self.fondo_modello:
            return super().fondo(quarto, maschera_byte, rifinita_bassa)  # la sfocatura di oggi (A)

        def persona_livello(l, a):
            p = rw.ricampiona(np.clip(rifinita_bassa, 0, 1), l, a)
            raggio = int(round(self.allarga_px * l / L))
            if raggio < 1:
                return p
            nucleo = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * raggio + 1, 2 * raggio + 1))
            return cv2.dilate(p, nucleo)

        # Come il Mac: la persona esce già da 0,1 ed è piena da 0,5 (2,5m − 0,25), mai del tutto (0,99).
        return rw.sfocata_senza_alone(quarto, persona_livello, INTENSITA, L, A,
                                      allarga=lambda p: np.clip(F(2.5) * p - F(0.25), 0, F(0.99)),
                                      soglia_alfa=self.soglia_alfa)


class E(D):
    nome = "E"
    descrizione = "MODNet (fotografico, Apache-2.0) con la rifinitura di D"


class E0(A0):
    nome = "E0"
    descrizione = "MODNet grezzo (ingrandimento bilineare)"


class Q(D):
    nome = "Q"
    descrizione = "come oggi su Windows: D* (bordo e sfocatura di A, EMA dal movimento, soglia 0,3–0,7) + isteresi"

    def __init__(self, isteresi=1, **altri):
        altri.setdefault("fondo_modello", 1)
        altri.setdefault("fine", 0)
        super().__init__(**altri)
        self.parametri.update(isteresi=isteresi)
        self.isteresi = rw.IsteresiMaschera() if isteresi else None

    def nel_tempo(self, grezza, ingresso_modello):
        m = super().nel_tempo(grezza, ingresso_modello)
        return self.isteresi.applica(m, self.pesi) if self.isteresi else m


class M(C):
    nome = "M"
    descrizione = "matting diretto: filtro nel tempo e media dal movimento, alfa bilineare senza soglia, sfocatura di oggi"

    def bordo(self, src, meta, quarto, maschera_byte):
        m = rw.campiona(maschera_byte, L, A)
        return np.floor(m * F(255) + F(0.5)).astype(np.uint8), None


VARIANTI = {"A0": A0, "A": AWindows, "B": B, "C": C, "Cm": CMac, "D": D, "E": E, "E0": E0, "Q": Q, "M": M}
