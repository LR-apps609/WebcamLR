namespace WebcamLR.Webcam;

/// <summary>Un'immagine NV12 con le sue misure (l'immagine personale, lo sfondo sfocato).</summary>
public sealed record ImmagineNv12(int Larghezza, int Altezza, byte[] Dati);

/// <summary>
/// La schermata di attesa della webcam, come quella del Mac (Mac/Sorgenti/AttesaWebcam.swift e
/// Mac/FotocameraVirtuale/Fotocamera.swift): fondo quasi nero con la sfumatura verde del logo, il logo piccolo,
/// il titolo in Barlow Condensed e la riga sotto in Barlow, in italiano o in inglese. Misure per un'immagine alta 1080,
/// in proporzione per le altre: se cambiano sul Mac, cambiano anche qui.
/// Si disegna una volta per stato, stile, lingua e misura (lo fa <see cref="CompositoreWebcam"/>), mai per fotogramma.
/// </summary>
public static class DisegnoAttesa
{
    /// <summary>
    /// La schermata intera in NV12. <paramref name="sfondo"/>: l'immagine personale per <see cref="StileAttesa.Immagine"/>,
    /// lo sfondo già sfocato (<see cref="ImmaginiNv12.Sfoca"/>) per <see cref="StileAttesa.Sfocata"/>; se manca vale lo
    /// stile di WebcamLR, come sul Mac.
    /// </summary>
    public static byte[] CreaNv12(StatoAttesa stato, StileAttesa stile, LinguaAttesa lingua, int larghezza, int altezza, ImmagineNv12? sfondo = null)
    {
        var nv12 = new byte[FormatoWebcam.DimensioneNv12(larghezza, altezza)];
        if (stato == StatoAttesa.Nessuna) stato = StatoAttesa.NonCollegata;
        switch (stile)
        {
            case StileAttesa.Nero:
                ConversioneVideo.RiempiNero(nv12, larghezza, altezza);
                break;
            case StileAttesa.Immagine when sfondo is not null:
                ImmaginiNv12.Riempi(sfondo.Dati, sfondo.Larghezza, sfondo.Altezza, nv12, larghezza, altezza);
                break;
            case StileAttesa.Sfocata when sfondo is not null:
                ImmaginiNv12.Riempi(sfondo.Dati, sfondo.Larghezza, sfondo.Altezza, nv12, larghezza, altezza);
                DisegnaElementi(nv12, larghezza, altezza, stato, lingua);
                break;
            default:
                DisegnaFondo(nv12, larghezza, altezza);
                DisegnaElementi(nv12, larghezza, altezza, stato, lingua);
                break;
        }
        return nv12;
    }

    /// <summary>
    /// Il fondo: la sfumatura del logo (dall'angolo in alto a sinistra a quello in basso a destra) scurita della metà,
    /// con i bordi ancora più scuri (fino al 45% in più negli angoli), come disegnaFondo sul Mac. Un leggero retino
    /// (4×4) evita le strisce nella sfumatura così scura.
    /// </summary>
    public static void DisegnaFondo(Span<byte> nv12, int larghezza, int altezza)
    {
        var chiara = ColoriStile.SfumaturaChiara;
        var scura = ColoriStile.SfumaturaScura;
        double w = larghezza, h = altezza;
        var diagonale = w * w + h * h;
        var raggio = Math.Sqrt(diagonale) / 2;
        var luminanza = larghezza * altezza;
        // I colori di ogni pixel servono due volte (luminanza e, sommati a quattro, crominanza): una riga alla volta.
        var r = new float[larghezza * 2];
        var g = new float[larghezza * 2];
        var b = new float[larghezza * 2];
        for (var y = 0; y < altezza; y++)
        {
            var riga = (y & 1) * larghezza;
            var py = y + 0.5;
            for (var x = 0; x < larghezza; x++)
            {
                var px = x + 0.5;
                var t = Math.Clamp((px * w + py * h) / diagonale, 0, 1);
                var distanza = Math.Sqrt((px - w / 2) * (px - w / 2) + (py - h / 2) * (py - h / 2)) / raggio;
                var bordo = Math.Clamp((distanza - 0.35) / 0.65, 0, 1) * 0.45;
                var fattore = 0.5 * (1 - bordo);
                r[riga + x] = (float)((chiara.Rosso + (scura.Rosso - chiara.Rosso) * t) * fattore);
                g[riga + x] = (float)((chiara.Verde + (scura.Verde - chiara.Verde) * t) * fattore);
                b[riga + x] = (float)((chiara.Blu + (scura.Blu - chiara.Blu) * t) * fattore);
                var valore = 16 + 0.18359375f * r[riga + x] + 0.61328125f * g[riga + x] + 0.0625f * b[riga + x] + Retino[(y & 3) * 4 + (x & 3)];
                nv12[y * larghezza + x] = (byte)Math.Clamp((int)(valore + 0.5f), 16, 235);
            }
            if ((y & 1) == 0) continue;
            var uv = nv12.Slice(luminanza + (y / 2) * larghezza, larghezza);
            for (var x = 0; x < larghezza; x += 2)
            {
                var rm = (r[x] + r[x + 1] + r[larghezza + x] + r[larghezza + x + 1]) / 4;
                var gm = (g[x] + g[x + 1] + g[larghezza + x] + g[larghezza + x + 1]) / 4;
                var bm = (b[x] + b[x + 1] + b[larghezza + x] + b[larghezza + x + 1]) / 4;
                uv[x] = (byte)Math.Clamp((int)(128.5f - 0.1015625f * rm - 0.3359375f * gm + 0.4375f * bm), 16, 240);
                uv[x + 1] = (byte)Math.Clamp((int)(128.5f + 0.4375f * rm - 0.3984375f * gm - 0.0390625f * bm), 16, 240);
            }
        }
    }

    /// <summary>Soglie del retino ordinato 4×4 (Bayer), da −0,47 a +0,47.</summary>
    private static readonly float[] Retino =
        new[] { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }.Select(v => (v + 0.5f) / 16f - 0.5f).ToArray();

    /// <summary>Dove vanno logo e testi, in pixel dall'alto: lo stesso calcolo di disegnaTesti sul Mac (lì y va verso l'alto).</summary>
    public readonly record struct Disposizione(double Unita, double LatoLogo, double CentroTitolo, double CentroSottotitolo, double AltoLogo, double SinistraLogo);

    public static Disposizione Calcola(int larghezza, int altezza, bool conSottotitolo)
    {
        var s = altezza / 1080.0;
        // Senza riga sotto il gruppo scende un po', per restare al centro.
        var giu = (conSottotitolo ? 26 : 52) * s;
        var lato = 120 * s;
        var cella = lato * 0.18;
        var passo = lato * 0.23;
        return new Disposizione(
            Unita: s,
            LatoLogo: lato,
            CentroTitolo: altezza / 2.0 - 10 * s + giu,
            CentroSottotitolo: altezza / 2.0 + 56 * s + giu,
            AltoLogo: altezza / 2.0 - 76 * s + giu - 2 * passo - cella,
            SinistraLogo: (larghezza - (2 * passo + cella)) / 2);
    }

    /// <summary>Il logo piccolo, il titolo e la riga sotto, centrati.</summary>
    public static void DisegnaElementi(Span<byte> nv12, int larghezza, int altezza, StatoAttesa stato, LinguaAttesa lingua)
    {
        var sottotitolo = TestiAttesa.Sottotitolo(stato, lingua) is not null;
        var d = Calcola(larghezza, altezza, sottotitolo);

        // Il logo: tre quadratini per riga, misure in centesimi del lato come in Stile (18, passo 23, angoli 4).
        var cella = d.LatoLogo * 0.18;
        var passo = d.LatoLogo * 0.23;
        for (var riga = 0; riga < 3; riga++)
        {
            for (var colonna = 0; colonna < 3; colonna++)
            {
                var (maschera, x, y, l, a) = ImmaginiNv12.RettangoloArrotondato(
                    d.SinistraLogo + colonna * passo, d.AltoLogo + riga * passo, cella, cella, d.LatoLogo * 0.04);
                ImmaginiNv12.Componi(nv12, larghezza, altezza, maschera, l, a, x, y, ColoriStile.CelleLogo[riga, colonna]);
            }
        }

        Scrivi(nv12, larghezza, altezza, TestiAttesa.Chiave(stato, lingua, titolo: true), d.CentroTitolo, ColoriStile.Testo);
        if (sottotitolo) Scrivi(nv12, larghezza, altezza, TestiAttesa.Chiave(stato, lingua, titolo: false), d.CentroSottotitolo, ColoriStile.TestoSecondario);
    }

    /// <summary>Un testo già disegnato (<see cref="MaschereTesti"/>), portato alla misura giusta e centrato su <paramref name="centroY"/>.</summary>
    private static void Scrivi(Span<byte> nv12, int larghezza, int altezza, string chiave, double centroY, ColoreStile colore)
    {
        if (MaschereTesti.Trova(chiave) is not { } maschera) return;
        var fattore = (double)altezza / MaschereTesti.AltezzaRiferimento;
        var l = Math.Max(1, (int)Math.Round(maschera.Larghezza * fattore));
        var a = Math.Max(1, (int)Math.Round(maschera.Altezza * fattore));
        var scalata = l == maschera.Larghezza && a == maschera.Altezza ? maschera.Opacita : ImmaginiNv12.Scala(maschera, l, a);
        ImmaginiNv12.Componi(nv12, larghezza, altezza, scalata, l, a,
            (int)Math.Round((larghezza - l) / 2.0), (int)Math.Round(centroY - a / 2.0), colore);
    }
}
