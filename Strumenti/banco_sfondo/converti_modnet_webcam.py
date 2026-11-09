"""MODNet «webcam» in ONNX senza PyTorch (Documenti/Prova MODNet.md).

Il modello webcam esiste solo come checkpoint PyTorch (modnet_webcam_portrait_matting.ckpt); quello fotografico ha anche
l'export ONNX ufficiale. La rete è la stessa: questo script prende il grafo dell'export ufficiale del fotografico e ne
sostituisce i pesi con quelli del checkpoint webcam. La corrispondenza tra pesi del grafo e chiavi del checkpoint (con
le BatchNorm del backbone fuse nelle convoluzioni, come ha fatto l'export) si trova confrontando i numeri del
checkpoint fotografico con il suo ONNX ufficiale: ogni peso deve combaciare, altrimenti ci si ferma.

I checkpoint si leggono senza PyTorch e senza eseguire codice: il formato è quello «legacy» di torch.save (pickle + i
dati grezzi dei tensori) e l'Unpickler accetta solo le classi che servono a ricostruire i tensori.

    python -I converti_modnet_webcam.py <ckpt fotografico> <onnx fotografico> <ckpt webcam> <onnx webcam in uscita>

Serve il pacchetto onnx (pip install onnx numpy). I file restano fuori dalla repository.
"""
import collections
import pickle
import struct
import sys

import numpy as np
import onnx
from onnx import numpy_helper

# --- Lettura del checkpoint (torch.save «legacy») ---------------------------------------------------------------------
TIPI = {"FloatStorage": np.float32, "DoubleStorage": np.float64, "HalfStorage": np.float16,
        "LongStorage": np.int64, "IntStorage": np.int32, "ByteStorage": np.uint8}


class TipoMemoria:
    def __init__(self, nome):
        self.nome = nome


def _rebuild_tensor_v2(memoria, inizio, forma, passi, *_):
    return ("tensore", memoria, inizio, tuple(forma), tuple(passi))


class Lettore(pickle.Unpickler):
    def __init__(self, f):
        super().__init__(f)
        self.memorie = {}

    def find_class(self, modulo, nome):
        if modulo == "collections" and nome == "OrderedDict":
            return collections.OrderedDict
        if modulo == "torch._utils" and nome == "_rebuild_tensor_v2":
            return _rebuild_tensor_v2
        if modulo == "torch" and nome in TIPI:
            return TipoMemoria(nome)
        raise pickle.UnpicklingError(f"classe non ammessa: {modulo}.{nome}")

    def persistent_load(self, pid):
        tipo, tipo_memoria, chiave, _dove, quanti, vista = pid
        assert tipo == "storage" and vista is None, pid
        self.memorie[chiave] = (tipo_memoria.nome, quanti)
        return chiave


def leggi(percorso):
    """Lo state_dict come {nome: array numpy}."""
    with open(percorso, "rb") as f:
        magia = pickle.load(f)
        assert magia == 0x1950A86A20F9469CFC6C, "non è un checkpoint legacy"
        pickle.load(f)  # versione del protocollo
        pickle.load(f)  # informazioni di sistema
        l = Lettore(f)
        oggetto = l.load()
        chiavi = pickle.load(f)
        dati = {}
        for k in chiavi:
            nome, quanti = l.memorie[k]
            n = struct.unpack("<q", f.read(8))[0]
            assert n == quanti
            dt = np.dtype(TIPI[nome])
            dati[k] = np.frombuffer(f.read(n * dt.itemsize), dt)
    risultato = collections.OrderedDict()
    for nome, t in oggetto.items():
        _, chiave, inizio, forma, passi = t
        base = dati[chiave]
        if len(forma) == 0:
            risultato[nome] = base[inizio:inizio + 1].reshape(())
            continue
        arr = np.lib.stride_tricks.as_strided(base[inizio:], forma, [p * base.itemsize for p in passi])
        risultato[nome] = np.ascontiguousarray(arr)
    return risultato

# --- Corrispondenza con il grafo dell'export ufficiale ---------------------------------------------------------------

EPS_BN = 1e-5


def candidati(sd):
    """(ricetta, tensore) per ogni modo in cui un peso del checkpoint può comparire nel grafo."""
    out = []
    for k, v in sd.items():
        if v.dtype != np.float32:
            continue
        out.append((("grezzo", k), v))
        if v.ndim == 2:
            out.append((("trasposto", k), v.T.copy()))
        if v.ndim == 4 and k.endswith(".weight"):
            prefisso, indice = k[:-len(".weight")].rsplit(".", 1)
            bn = f"{prefisso}.{int(indice) + 1}"
            if f"{bn}.running_mean" in sd and sd[f"{bn}.weight"].shape[0] == v.shape[0]:
                s = sd[f"{bn}.weight"] / np.sqrt(sd[f"{bn}.running_var"] + EPS_BN)
                out.append((("fuso_peso", k, bn), (v * s[:, None, None, None]).astype(np.float32)))
                b0 = sd.get(k[:-len("weight")] + "bias", np.zeros_like(s))
                out.append((("fuso_bias", k, bn), (sd[f"{bn}.bias"] + (b0 - sd[f"{bn}.running_mean"]) * s).astype(np.float32)))
    return out


def applica(ricetta, sd):
    tipo, k = ricetta[0], ricetta[1]
    if tipo == "grezzo":
        return sd[k]
    if tipo == "trasposto":
        return sd[k].T.copy()
    bn = ricetta[2]
    s = sd[f"{bn}.weight"] / np.sqrt(sd[f"{bn}.running_var"] + EPS_BN)
    if tipo == "fuso_peso":
        return (sd[k] * s[:, None, None, None]).astype(np.float32)
    b0 = sd.get(k[:-len("weight")] + "bias", np.zeros_like(s))
    return (sd[f"{bn}.bias"] + (b0 - sd[f"{bn}.running_mean"]) * s).astype(np.float32)


def main():
    ckpt_foto, onnx_foto, ckpt_web, uscita = sys.argv[1:5]
    sd_foto = leggi(ckpt_foto)
    sd_web = leggi(ckpt_web)
    assert list(sd_foto) == list(sd_web), "i due checkpoint non hanno le stesse chiavi"
    modello = onnx.load(onnx_foto)
    cand = candidati(sd_foto)
    ricette = {}
    peggiore = 0.0
    # Solo i pesi veri: gli ingressi di Conv, BatchNormalization e MatMul (le scale dei Resize restano come sono).
    pesi = {i for n in modello.graph.node if n.op_type in ("Conv", "BatchNormalization", "MatMul") for i in n.input}
    for init in modello.graph.initializer:
        t = numpy_helper.to_array(init)
        if t.dtype != np.float32 or init.name not in pesi:
            continue
        migliori = []
        for r, c in cand:
            if c.shape == t.shape:
                d = float(np.max(np.abs(c - t)) / (np.max(np.abs(t)) + 1e-12))
                if d < 1e-4:
                    migliori.append((d, r))
        if not migliori:
            sys.exit(f"{init.name} {t.shape}: nessun peso del checkpoint combacia")
        migliori.sort()
        if len(migliori) > 1 and migliori[1][0] < 1e-4 and migliori[1][1][1] != migliori[0][1][1]:
            # Due pesi diversi uguali (succede solo con tensori costanti): devono dare lo stesso valore anche nel webcam.
            a, b = applica(migliori[0][1], sd_web), applica(migliori[1][1], sd_web)
            if not np.allclose(a, b):
                sys.exit(f"{init.name}: corrispondenza ambigua {migliori[:2]}")
        ricette[init.name] = migliori[0][1]
        peggiore = max(peggiore, migliori[0][0])
    usate = {r[1] for r in ricette.values()}
    conv = [k for k, v in sd_foto.items() if v.dtype == np.float32 and k.endswith("weight") and v.ndim >= 2]
    # lr_branch.backbone è lo stesso modulo di backbone (stessi pesi); conv_lr e conv_hr servono solo all'addestramento.
    mancanti = [k for k in conv if k not in usate
                and not any(x in k for x in ("lr_branch.backbone.", "conv_lr.", "conv_hr."))]
    print(f"{len(ricette)} pesi del grafo riconosciuti (scarto relativo massimo {peggiore:.2e}); convoluzioni del "
          f"checkpoint non usate: {mancanti}")
    for init in modello.graph.initializer:
        if init.name in ricette:
            nuovo = applica(ricette[init.name], sd_web)
            init.CopyFrom(numpy_helper.from_array(nuovo.astype(np.float32), init.name))
    modello.producer_name = "WebcamLR (pesi MODNet webcam nel grafo dell'export ufficiale)"
    onnx.checker.check_model(modello)
    onnx.save(modello, uscita)
    print("Scritto", uscita)


if __name__ == "__main__":
    main()
