# Webcam virtuale per Windows (round 3)

Qui andrà la sorgente video in C++ che Windows mostra come webcam:

- Windows 11: `MFCreateVirtualCamera` di Media Foundation, con una media source COM registrata da WebcamLR.
- Windows 10 e app vecchie (funzione 13): un filtro DirectShow.

L'app (`WebcamLR.App`, C#) riceve e decodifica il video dal telefono e lo passa alla sorgente tramite memoria condivisa.
