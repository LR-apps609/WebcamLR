"""Banco di prova della qualità dello sfondo (README.md accanto).

    python -I banco.py --dati <cartella VM240K> --uscita <cartella risultati> [--varianti ...] [--fotogrammi 120]
    python -I banco.py --dati ... --uscita ... --tempi            # solo i tempi per fotogramma

Una variante si scrive modello/Nome[:parametro=valore...], per esempio pieno/A, leggero/D, pieno/B:raggio=4:eps=0.01,
modnet/E. Modelli: pieno (Selfie Multiclass 256×256), leggero (Selfie Segmenter landscape 144×256), modnet (MODNet
fotografico, export ONNX ufficiale) e modnetw (MODNet webcam, Strumenti/banco_sfondo/converti_modnet_webcam.py), con
la misura d'ingresso dopo «@», per esempio modnetw@896x512/M (di base 512×288; lati multipli di 32).
"""

import argparse
import json
import os
import statistics
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

QUI = Path(__file__).resolve().parent
sys.path.insert(0, str(QUI))

import cv2  # noqa: E402
import numpy as np  # noqa: E402
import onnxruntime as ort  # noqa: E402

import clip as clip_mod  # noqa: E402
import misure  # noqa: E402
import ricette_windows as rw  # noqa: E402
import varianti  # noqa: E402

MODELLI_WINDOWS = QUI.parents[1] / "Windows/WebcamLR.Effetti/Modelli"
PREDEFINITE = ["pieno/A0", "pieno/A", "pieno/B", "pieno/C", "pieno/Cm", "pieno/D", "pieno/D:fondo_modello=1:fine=0",
               "leggero/A0", "leggero/A", "leggero/D:fondo_modello=1:fine=0",
               "modnet/E0", "modnet/E", "modnet/E:fondo_modello=1:fine=0"]


class Modello:
    """Un modello ONNX con la preparazione di Windows (Preparazione.BgraInRgb)."""

    def __init__(self, nome, cartella_modnet, fili):
        self.nome = nome
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        if fili:
            so.intra_op_num_threads = fili
        if nome == "pieno":
            file, (self.l, self.a), self.scala, self.sposta = MODELLI_WINDOWS / "ritaglio_persona.onnx", (256, 256), 1 / 127.5, -1.0
        elif nome == "leggero":
            file, (self.l, self.a), self.scala, self.sposta = MODELLI_WINDOWS / "ritaglio_persona_leggero.onnx", (256, 144), 1 / 255, 0.0
        elif nome.split("@")[0] in ("modnet", "modnetw"):
            # MODNet: RGB in [-1, 1], NCHW, lati multipli di 32 (512×288 per il 16:9, se non si dice altro).
            base, _, misura = nome.partition("@")
            self.l, self.a = (int(x) for x in misura.split("x")) if misura else (512, 288)
            file = Path(cartella_modnet) / ("modnet_photographic.onnx" if base == "modnet" else "modnet_webcam.onnx")
            self.scala, self.sposta = 1 / 127.5, -1.0
        else:
            raise ValueError(nome)
        self.sessione = ort.InferenceSession(str(file), so, providers=["CPUExecutionProvider"])
        self.ingresso = self.sessione.get_inputs()[0].name

    def calcola(self, src):
        x = rw.bgra_in_rgb(src, self.l, self.a, self.scala, self.sposta)
        if self.nome.startswith("modnet"):
            x = np.ascontiguousarray(x.transpose(0, 3, 1, 2))
        t0 = time.perf_counter()
        u = self.sessione.run(None, {self.ingresso: x})[0]
        self.ms = (time.perf_counter() - t0) * 1000  # solo la rete (la preparazione in numpy non conta)
        if self.nome.startswith("modnet"):
            return np.clip(u[0, 0], 0, 1).astype(np.float32)
        return rw.persona(u)


def crea_variante(spec):
    modello, resto = spec.split("/", 1)
    nome, *parti = resto.split(":")
    parametri = {k: float(v) for k, v in (p.split("=") for p in parti)}
    return modello, varianti.VARIANTI[nome](**parametri)


def ideale_sfocato(src, vera):
    """Lo sfondo sfocato «perfetto» che si può ottenere dall'immagine: sfocatura normalizzata con la persona vera tolta
    (senza allargarla), con la stessa piramide di Windows. Nessun alone per costruzione; la parte nascosta dietro la
    persona non si conosce e non conta."""
    quarto = rw.dimezza(rw.dimezza(src))
    vera_byte = np.floor(vera * 255 + 0.5).astype(np.uint8)
    piccolo = rw.sfocata_senza_alone(quarto, lambda l, a: rw.campiona(vera_byte, l, a), varianti.INTENSITA, 1920, 1080,
                                     allarga=lambda p: np.clip(p, 0, np.float32(0.99)))
    return rw.ingrandisci8(piccolo, 1920, 1080)


def confronto(src, alfa, uscita, vera, titolo):
    """Originale | maschera (verde: mancante, rosso: in più) | sfocatura, più l'ingrandimento del bordo della testa."""
    l, a = 640, 360
    m = (alfa * 255).astype(np.uint8)
    maschera = cv2.cvtColor(m, cv2.COLOR_GRAY2BGR)
    persa = (vera >= 0.5) & (alfa < 0.5)
    in_piu = (vera < 0.5) & (alfa >= 0.5)
    maschera[persa] = (0, 200, 0)
    maschera[in_piu] = (0, 0, 230)
    riga = np.hstack([cv2.resize(x, (l, a), interpolation=cv2.INTER_AREA) for x in (src, maschera, uscita)])
    # Ingrandimento: un riquadro 480×270 centrato sul bordo superiore della persona vera.
    ys, xs = np.nonzero(vera >= 0.5)
    if len(ys):
        cy, cx = int(ys.min()) + 90, int(np.median(xs[ys < ys.min() + 40]))
        y0, x0 = int(np.clip(cy - 135, 0, 1080 - 270)), int(np.clip(cx - 240, 0, 1920 - 480))
        zoom = [cv2.resize(x[y0:y0 + 270, x0:x0 + 480], (l, a), interpolation=cv2.INTER_NEAREST)
                for x in (src, maschera, uscita)]
        riga = np.vstack([riga, np.hstack(zoom)])
    barra = np.zeros((36, riga.shape[1], 3), np.uint8)
    cv2.putText(barra, titolo, (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (235, 240, 235), 1, cv2.LINE_AA)
    return np.vstack([barra, riga])


def esegui_clip(argomenti):
    c, specs, cartella_dati, cartella_modnet, uscita, quanti, fotogramma_confronto = argomenti
    os.environ["OMP_NUM_THREADS"] = "1"
    cv2.setNumThreads(1)
    istanze = [(s,) + crea_variante(s) for s in specs]
    modelli = {m: Modello(m, cartella_modnet, 1) for m in {m for _, m, _ in istanze}}
    somme = {s: {} for s in specs}
    prec = {s: None for s in specs}
    vera_prec = None
    for i, (src, vera, _fondo) in enumerate(clip_mod.fotogrammi(c, Path(cartella_dati), quanti)):
        verita = misure.Verita(vera)
        ideale = rw.miscela(src, ideale_sfocato(src, vera), np.floor(vera * 255 + 0.5).astype(np.uint8))
        grezze, ingressi = {}, {}
        for nome, m in modelli.items():
            grezze[nome] = m.calcola(src)
            ingressi[nome] = rw.bgra_in_rgb(src, grezze[nome].shape[1], grezze[nome].shape[0], 1 / 255, 0)
        for s, nome_modello, v in istanze:
            alfa, out, _ = v.elabora(src, grezze[nome_modello], ingressi[nome_modello])
            r = misure.per_fotogramma(alfa, verita, out, ideale, prec[s], vera_prec)
            for k, val in r.items():
                somme[s].setdefault(k, []).append(val)
            prec[s] = alfa
            if i == fotogramma_confronto:
                cartella = Path(uscita) / "confronti"
                cartella.mkdir(parents=True, exist_ok=True)
                titolo = f"{c.nome}  fotogramma {i}  {s}"
                cv2.imwrite(str(cartella / f"{c.nome}__{s.replace('/', '_').replace(':', '_')}.jpg"),
                            confronto(src, alfa, out, vera, titolo), [cv2.IMWRITE_JPEG_QUALITY, 88])
        vera_prec = vera
    return c.nome, {s: {k: float(np.mean(v)) for k, v in d.items()} for s, d in somme.items()}


def tempi(specs, cartella_dati, cartella_modnet, quanti, fili):
    """Mediana dei ms per fotogramma: la rete (onnxruntime sul processore) e la rifinitura in numpy (lenta: conta solo il
    rapporto tra le varianti; i ms veri della variante A in C# li dà verifica_cs.py)."""
    c = clip_mod.CLIP[0]
    istanze = [(s,) + crea_variante(s) for s in specs]
    modelli = {m: Modello(m, cartella_modnet, fili) for m in {m for _, m, _ in istanze}}
    t_modello = {m: [] for m in modelli}
    t_var = {s: [] for s in specs}
    for i, (src, _, _) in enumerate(clip_mod.fotogrammi(c, Path(cartella_dati), quanti)):
        grezze, ingressi = {}, {}
        for nome, m in modelli.items():
            grezze[nome] = m.calcola(src)
            if i >= 5:
                t_modello[nome].append(m.ms)
            ingressi[nome] = rw.bgra_in_rgb(src, grezze[nome].shape[1], grezze[nome].shape[0], 1 / 255, 0)
        for s, nome_modello, v in istanze:
            _, _, ms = v.elabora(src, grezze[nome_modello], ingressi[nome_modello])
            if i >= 5:
                t_var[s].append(ms)
    return ({m: statistics.median(v) for m, v in t_modello.items()},
            {s: statistics.median(v) for s, v in t_var.items()})


COLONNE = [("iou", "IoU", "{:.4f}"), ("mad_bordo", "MAD bordo ×10⁻³", "{:.1f}"), ("grad_bordo", "Grad bordo ×10⁻³", "{:.1f}"),
           ("dtssd", "dtSSD ×10⁻²", "{:.3f}"), ("tremolio", "Tremolio bordo ×10⁻³", "{:.2f}"),
           ("alone", "Alone (0–255)", "{:.2f}"), ("errore_immagine", "Errore immagine bordo (0–255)", "{:.2f}"),
           ("mad_capelli", "MAD capelli ×10⁻³", "{:.1f}"), ("grad_capelli", "Grad capelli ×10⁻³", "{:.1f}"),
           ("immagine_capelli", "Errore immagine capelli (0–255)", "{:.2f}")]


def tabella(medie, righe):
    testo = ["| Variante | " + " | ".join(t for _, t, _ in COLONNE) + " |", "|---" * (len(COLONNE) + 1) + "|"]
    for s in righe:
        if s in medie:
            testo.append(f"| {s} | " + " | ".join(f.format(medie[s].get(k, float('nan'))) for k, _, f in COLONNE) + " |")
    return "\n".join(testo)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dati", required=True, help="cartella con VideoMatte240K_JPEG_HD/test (scarica_dati.py)")
    p.add_argument("--modnet", help="cartella con modnet_photographic.onnx (scarica_dati.py) e modnet_webcam.onnx")
    p.add_argument("--uscita", required=True)
    p.add_argument("--varianti", nargs="*", default=PREDEFINITE)
    p.add_argument("--clip", nargs="*", help="solo queste clip (nomi in clip.py)")
    p.add_argument("--fotogrammi", type=int, default=120)
    p.add_argument("--confronto", type=int, default=60, help="fotogramma delle immagini di confronto")
    p.add_argument("--processi", type=int, default=os.cpu_count())
    p.add_argument("--tempi", action="store_true", help="misura solo i tempi per fotogramma")
    p.add_argument("--fili", type=int, default=0, help="fili di onnxruntime per --tempi (0: scelta sua)")
    a = p.parse_args()
    uscita = Path(a.uscita)
    uscita.mkdir(parents=True, exist_ok=True)

    if a.tempi:
        tm, tv = tempi(a.varianti, a.dati, a.modnet, min(a.fotogrammi, 45), a.fili)
        print(json.dumps({"modello_ms": tm, "rifinitura_ms": tv}, indent=1))
        (uscita / f"tempi_fili{a.fili}.json").write_text(json.dumps({"modello_ms": tm, "rifinitura_ms": tv}, indent=1))
        return

    clips = [c for c in clip_mod.CLIP if not a.clip or c.nome in a.clip]
    lavori = [(c, a.varianti, a.dati, a.modnet, a.uscita, a.fotogrammi, a.confronto) for c in clips]
    with ProcessPoolExecutor(max_workers=min(a.processi, len(lavori))) as ex:
        per_clip = dict(ex.map(esegui_clip, lavori))
    file_json = uscita / "risultati.json"
    vecchi = json.loads(file_json.read_text()) if file_json.exists() else {}
    for nome, d in per_clip.items():
        vecchi.setdefault(nome, {}).update(d)
    file_json.write_text(json.dumps(vecchi, indent=1))
    # Media sulle clip (ogni clip pesa uguale).
    tutte = sorted({s for d in vecchi.values() for s in d}, key=lambda s: (s.split("/")[0], s))
    medie = {s: {k: float(np.mean([vecchi[c][s][k] for c in vecchi if s in vecchi[c] and k in vecchi[c][s]]))
                 for k, _, _ in COLONNE} for s in tutte}
    righe = ["## Media sulle clip", "", tabella(medie, tutte), ""]
    for c in sorted(vecchi):
        righe += [f"## {c}", "", tabella(vecchi[c], tutte), ""]
    (uscita / "risultati.md").write_text("\n".join(righe))
    print("\n".join(righe))


if __name__ == "__main__":
    main()
