"""Converte i modelli MediaPipe di ritaglio della persona (Apache 2.0) in ONNX per Windows (WebcamLR.Effetti).

Uso (in un ambiente virtuale con: pip install tensorflow-cpu tf2onnx onnx onnxruntime numpy):
    python converti_ritaglio_onnx.py <cartella con i .tflite> <cartella di uscita>

I .tflite vengono da storage.googleapis.com/mediapipe-models/image_segmenter/:
  selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite  -> ritaglio_persona.onnx
  selfie_segmenter_landscape/float16/latest/selfie_segmenter_landscape.tflite -> ritaglio_persona_leggero.onnx

Ritocchi dopo tf2onnx (stesso risultato numerico, controllato alla fine):
- multiclasse: i Resize «nearest» usano tf_half_pixel_for_nn, deprecato da ONNX: diventa half_pixel con
  round_prefer_ceil (equivalente). In uscita si aggiunge il softmax (MediaPipe lo applica dai metadati), così
  «classi» somma a 1 e persona = 1 − classi[0]. Ingresso «immagine» [1,256,256,3] RGB in [-1, 1].
- leggero: l'operatore personalizzato di MediaPipe Convolution2DTransposeBias diventa un ConvTranspose standard
  (nucleo 2×2, passo 2, più bias). Ingresso «immagine» [1,144,256,3] RGB in [0, 1], uscita «persona» [1,144,256,1].
"""
import os, subprocess, sys, tempfile
import numpy as np
import onnx
from onnx import helper, numpy_helper
import onnxruntime as ort


def tf2onnx(tflite, onnx_path):
    subprocess.run([sys.executable, "-m", "tf2onnx.convert", "--tflite", tflite, "--output", onnx_path, "--opset", "17"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def rinomina(g, ingresso, uscita):
    vi, vu = g.input[0].name, g.output[0].name
    for n in g.node:
        for i, x in enumerate(n.input):
            if x == vi: n.input[i] = ingresso
        for i, x in enumerate(n.output):
            if x == vu: n.output[i] = uscita
    g.input[0].name = ingresso
    g.output[0].name = uscita


def multiclasse(src, dst):
    m = onnx.load(src); g = m.graph
    for n in g.node:
        if n.op_type != "Resize": continue
        att = {a.name: a for a in n.attribute}
        if att["coordinate_transformation_mode"].s == b"tf_half_pixel_for_nn":
            att["coordinate_transformation_mode"].s = b"half_pixel"
            if "nearest_mode" in att: att["nearest_mode"].s = b"round_prefer_ceil"
            else: n.attribute.append(helper.make_attribute("nearest_mode", "round_prefer_ceil"))
    rinomina(g, "immagine", "logit")
    g.node.append(helper.make_node("Softmax", ["logit"], ["classi"], axis=-1, name="softmax_classi"))
    g.output[0].name = "classi"
    m.producer_name = "WebcamLR (selfie_multiclass_256x256.tflite di MediaPipe, Apache 2.0)"
    onnx.checker.check_model(m, full_check=True)
    onnx.save(m, dst)


def leggero(src, dst):
    m = onnx.load(src); g = m.graph
    init = {i.name: i for i in g.initializer}
    ct = next(n for n in g.node if n.op_type == "TFL_Convolution2DTransposeBias")
    tr = next(n for n in g.node if n.output[0] == ct.input[0])
    assert tr.op_type == "Transpose" and list(tr.attribute[0].ints) == [0, 2, 3, 1]
    w = numpy_helper.to_array(init[ct.input[1]])            # O, H, W, I (come TFLite)
    b = numpy_helper.to_array(init[ct.input[2]])
    g.initializer.append(numpy_helper.from_array(np.ascontiguousarray(w.transpose(3, 0, 1, 2)).astype(np.float32), "ct_peso"))
    g.initializer.append(numpy_helper.from_array(b.astype(np.float32), "ct_bias"))
    i = list(g.node).index(ct)
    g.node.remove(ct)
    g.node.insert(i, helper.make_node("Transpose", ["ct_nchw"], [ct.output[0]], perm=[0, 2, 3, 1], name="ct_a_nhwc"))
    g.node.insert(i, helper.make_node("ConvTranspose", [tr.input[0], "ct_peso", "ct_bias"], ["ct_nchw"],
                                      kernel_shape=[2, 2], strides=[2, 2], name="conv2d_transpose_std"))
    if not any(tr.output[0] in n.input for n in g.node): g.node.remove(tr)
    usati = {x for n in g.node for x in n.input}
    for t in list(g.initializer):
        if t.name not in usati: g.initializer.remove(t)
    tieni = [o for o in m.opset_import if o.domain in ("", "ai.onnx")]
    del m.opset_import[:]; m.opset_import.extend(tieni)
    rinomina(g, "immagine", "persona")
    m.producer_name = "WebcamLR (selfie_segmenter_landscape.tflite di MediaPipe, Apache 2.0)"
    onnx.checker.check_model(m, full_check=True)
    onnx.save(m, dst)


def confronta_multiclasse(grezzo, finale):
    so = ort.SessionOptions(); so.log_severity_level = 3
    a = ort.InferenceSession(grezzo, so, providers=["CPUExecutionProvider"])
    b = ort.InferenceSession(finale, so, providers=["CPUExecutionProvider"])
    x = np.random.default_rng(1).uniform(-1, 1, (1, 256, 256, 3)).astype(np.float32)
    la = a.run(None, {a.get_inputs()[0].name: x})[0]
    e = np.exp(la - la.max(-1, keepdims=True))
    differenza = float(np.abs(e / e.sum(-1, keepdims=True) - b.run(None, {"immagine": x})[0]).max())
    print("multiclasse: differenza massima con la conversione diretta", differenza)
    assert differenza < 1e-5


if __name__ == "__main__":
    origine, uscita = sys.argv[1:3]
    os.makedirs(uscita, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        grezzo = os.path.join(tmp, "multiclasse.onnx")
        tf2onnx(os.path.join(origine, "selfie_multiclass_256x256.tflite"), grezzo)
        multiclasse(grezzo, os.path.join(uscita, "ritaglio_persona.onnx"))
        confronta_multiclasse(grezzo, os.path.join(uscita, "ritaglio_persona.onnx"))
        grezzo = os.path.join(tmp, "leggero.onnx")
        tf2onnx(os.path.join(origine, "selfie_segmenter_landscape.tflite"), grezzo)
        leggero(grezzo, os.path.join(uscita, "ritaglio_persona_leggero.onnx"))
    print("fatto:", uscita)
