"""Scarica i dati del banco (fuori dalla repository): i primi fotogrammi delle 5 clip di prova di VideoMatte240K e
MODNet. Serve solo la libreria standard di Python.

    python -I scarica_dati.py <cartella dati> [--fotogrammi 120]

- VideoMatte240K (Lin et al., «Real-Time High-Resolution Background Matting», CVPR 2021), versione «JPEG HD»
  preparata per Robust Video Matting: primo piano (fgr) e alfa vera (pha) a 3840×2160. Il sito ufficiale
  (grail.cs.washington.edu) non è raggiungibile da qui; si usa la copia pubblica su Hugging Face
  (datasets/geyongtao/video_matting, file videomatte.zip, 23,7 GB) e se ne leggono solo i file che servono con
  richieste a intervalli (Range), senza scaricare l'archivio intero: circa 170 MB per 120 fotogrammi × 5 clip.
  Licenza: vedi README.md (solo ricerca e prove interne; niente ridistribuzione, niente addestramento).
- MODNet fotografico in ONNX (Apache-2.0, ZHKKKe/MODNet): la copia su Hugging Face DavG25/modnet-pretrained-models,
  uguale bit per bit a quella ufficiale (SHA-256 sotto) e a Xenova/modnet.
"""

import argparse
import hashlib
import io
import os
import struct
import sys
import urllib.request
import zipfile
import zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

URL_VM = "https://huggingface.co/datasets/geyongtao/video_matting/resolve/main/videomatte.zip"
URL_MODNET = ("https://huggingface.co/DavG25/modnet-pretrained-models/resolve/main/models/"
              "modnet_photographic_portrait_matting.onnx")
SHA_MODNET = "07c308cf0fc7e6e8b2065a12ed7fc07e1de8febb7dc7839d7b7f15dd66584df9"
CLIP_PROVA = ["0000", "0001", "0002", "0003", "0004"]


class FileRemoto(io.RawIOBase):
    """Un file su HTTP letto a pezzi (Range): basta per l'indice di uno zip."""

    def __init__(self, url):
        self.url, self.pos = url, 0
        self.size = int(urllib.request.urlopen(urllib.request.Request(url, method="HEAD")).headers["Content-Length"])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def readinto(self, b):
        if self.pos >= self.size or len(b) == 0:
            return 0
        fine = min(self.size, self.pos + len(b)) - 1
        dati = urllib.request.urlopen(urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{fine}"})).read()
        b[:len(dati)] = dati
        self.pos += len(dati)
        return len(dati)


def prendi(info, destinazione):
    uscita = destinazione / info.filename
    if uscita.exists() and uscita.stat().st_size == info.file_size:
        return
    inizio = info.header_offset
    req = urllib.request.Request(URL_VM, headers={"Range": f"bytes={inizio}-{inizio + 30 + 1024 + info.compress_size - 1}"})
    d = urllib.request.urlopen(req).read()
    n, e = struct.unpack("<HH", d[26:30])
    dati = d[30 + n + e: 30 + n + e + info.compress_size]
    if info.compress_type == zipfile.ZIP_DEFLATED:
        dati = zlib.decompress(dati, -15)
    uscita.parent.mkdir(parents=True, exist_ok=True)
    uscita.write_bytes(dati)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("cartella")
    p.add_argument("--fotogrammi", type=int, default=120)
    a = p.parse_args()
    dest = Path(a.cartella)
    print("Indice di videomatte.zip…")
    z = zipfile.ZipFile(io.BufferedReader(FileRemoto(URL_VM), buffer_size=1 << 20))
    voluti = {f"VideoMatte240K_JPEG_HD/test/{t}/{c}/{i:05d}.jpg" for c in CLIP_PROVA for t in ("fgr", "pha")
              for i in range(a.fotogrammi)}
    infos = [i for i in z.infolist() if i.filename in voluti]
    print(f"{len(infos)} file da scaricare")
    with ThreadPoolExecutor(16) as ex:
        list(ex.map(lambda i: prendi(i, dest / "vm240k"), infos))
    modnet = dest / "modnet" / "modnet_photographic.onnx"
    if not modnet.exists():
        modnet.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(URL_MODNET, modnet)
    impronta = hashlib.sha256(modnet.read_bytes()).hexdigest()
    if impronta != SHA_MODNET:
        sys.exit(f"MODNet: impronta diversa da quella attesa ({impronta})")
    print("Pronto:", dest / "vm240k", "e", modnet)


if __name__ == "__main__":
    main()
