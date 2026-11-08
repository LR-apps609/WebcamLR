"""Controlla che la versione numpy (ricette_windows.py, variante A) faccia gli stessi conti della libreria C# vera.

    python -I verifica_cs.py --dati <cartella VM240K> --lavoro <cartella di appoggio> [--fotogrammi 30]

Scrive i fotogrammi di una clip in BGRA, li passa a VerificaCs (RitaglioPersona pieno e leggero con il filtro nel
tempo, poi Compositore.Rendi con la sfocatura «Medio»), e confronta:
1. le maschere (byte) di C# con quelle di Python (stessa preparazione, stesso FiltroTemporale);
2. l'immagine sfocata di C# con quella della variante A di Python, data la stessa maschera.
Stampa anche le mediane dei tempi di C# (Release): sono i tempi veri della variante A sul processore.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

QUI = Path(__file__).resolve().parent
sys.path.insert(0, str(QUI))

import numpy as np  # noqa: E402

import banco  # noqa: E402
import clip as clip_mod  # noqa: E402
import ricette_windows as rw  # noqa: E402
import varianti  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dati", required=True)
    p.add_argument("--lavoro", required=True)
    p.add_argument("--fotogrammi", type=int, default=30)
    p.add_argument("--clip", default="vm0003_studio")
    a = p.parse_args()
    lavoro = Path(a.lavoro)
    lavoro.mkdir(parents=True, exist_ok=True)
    c = next(x for x in clip_mod.CLIP if x.nome == a.clip)
    fotogrammi = []
    for i, (src, _, _) in enumerate(clip_mod.fotogrammi(c, Path(a.dati), a.fotogrammi)):
        bgra = np.dstack([src, np.full(src.shape[:2], 255, np.uint8)])
        (lavoro / f"f{i:05d}.bgra").write_bytes(bgra.tobytes())
        fotogrammi.append(src)
    progetto = QUI / "VerificaCs"
    r = subprocess.run(["dotnet", "run", "-c", "Release", "--project", str(progetto), "--", str(lavoro),
                        str(len(fotogrammi)), "1920", "1080"], capture_output=True, text=True, check=True)
    tempi_cs = json.loads(r.stdout.strip().splitlines()[-1])

    modelli = {m: banco.Modello(m, None, 0) for m in ("pieno", "leggero")}
    filtri = {m: rw.FiltroTemporale() for m in modelli}
    variante_a = varianti.AWindows()
    variante_a.nel_tempo = lambda grezza, _: grezza  # la maschera arriva già filtrata (quella di C#)
    diff_maschere = {m: [] for m in modelli}
    diff_uscita = []
    for i, src in enumerate(fotogrammi):
        for m, mod in modelli.items():
            py = rw.in_byte(filtri[m].applica(mod.calcola(src)))
            cs = np.frombuffer((lavoro / f"{m}_{i:05d}.bin").read_bytes(), np.uint8).reshape(py.shape)
            diff_maschere[m].append(np.abs(py.astype(int) - cs.astype(int)))
        cs_maschera = np.frombuffer((lavoro / f"pieno_{i:05d}.bin").read_bytes(), np.uint8).reshape(256, 256)
        _, uscita_py, _ = variante_a.elabora(src, cs_maschera.astype(np.float32) / 255, None)
        uscita_cs = np.frombuffer((lavoro / f"uscita_{i:05d}.bgra").read_bytes(), np.uint8).reshape(1080, 1920, 4)[..., :3]
        diff_uscita.append(np.abs(uscita_py.astype(int) - uscita_cs.astype(int)))
    esito = {
        "maschere": {m: {"massima": int(max(d.max() for d in v)), "media": float(np.mean([d.mean() for d in v])),
                         "punti_diversi_%": float(np.mean([(d > 0).mean() for d in v]) * 100)}
                     for m, v in diff_maschere.items()},
        "immagine_A": {"massima": int(max(d.max() for d in diff_uscita)), "media": float(np.mean([d.mean() for d in diff_uscita])),
                       "punti_oltre_2_%": float(np.mean([(d > 2).mean() for d in diff_uscita]) * 100)},
        "tempi_cs_ms": tempi_cs,
    }
    print(json.dumps(esito, indent=1))


if __name__ == "__main__":
    main()
