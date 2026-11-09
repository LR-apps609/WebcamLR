namespace WebcamLR.Effetti;

/// <summary>
/// Tutto quello che serve per l'ultimo passo dello sfondo: la persona sopra il fondo, a piena risoluzione. Le cose
/// piccole (alfa, fondo sfocato, colore dell'interno della persona, sfondo nuovo sfocato, maschera morbida) le prepara il
/// <see cref="Compositore"/> sul processore; il passo a piena risoluzione lo fa una <see cref="IComposizione"/>, sulla
/// scheda video (<see cref="ComposizioneSchedaVideo"/>) o sul processore (<see cref="ComposizioneProcessore"/>), con gli
/// stessi conti (Qualità 5).
/// </summary>
public sealed class PianoComposizione
{
    /// <summary>Il fotogramma com'è, a piena misura.</summary>
    public required ImmagineBgra Sorgente { get; init; }

    /// <summary>La maschera rifinita (0–255, persona = 255), a metà o a un quarto della misura.</summary>
    public required byte[] Alfa { get; init; }
    public required int LarghezzaAlfa { get; init; }
    public required int AltezzaAlfa { get; init; }

    /// <summary>Sfondo sostituito: l'immagine scelta alla misura del video (null con lo sfocato).</summary>
    public ImmagineBgra? FondoPieno { get; init; }

    /// <summary>
    /// Identifica <see cref="FondoPieno"/> (immagine e misura): la scheda video lo carica una volta sola e poi lo riusa
    /// finché la chiave non cambia.
    /// </summary>
    public string? ChiaveFondo { get; init; }

    /// <summary>Sfondo sfocato: lo sfondo senza la persona, sfocato, piccolo (null con il sostituito).</summary>
    public ImmagineBgra? FondoPiccolo { get; init; }

    /// <summary>
    /// Mosaico (Qualità 8): <see cref="FondoPiccolo"/> ha un pixel per quadretto e si ingrandisce «al più vicino», non
    /// bilineare: il pixel x della misura piena prende la colonna ⌊x · colonne / L⌋ (e così le righe), come
    /// <see cref="RicetteSfondo.Mosaico"/> conta i quadretti. Così i quadretti restano netti.
    /// </summary>
    public bool FondoAQuadretti { get; init; }

    /// <summary>
    /// Qualità 12: filtro di colore e regolazioni (<see cref="RicetteColore.Catena"/>) sull'immagine intera, persona e
    /// fondo, dopo la miscela: sul pixel finale in byte, con gli stessi interi di <see cref="CatenaColore.Applica"/> (la
    /// scheda video ha le stesse tabelle). Null = niente; al massimo <see cref="MassimoStadiColore"/> stadi.
    /// </summary>
    public CatenaColore? Colore { get; init; }

    /// <summary>
    /// Quanti stadi della catena di colore porta al massimo la composizione: lo shader ne ha posto per tanti (il
    /// processore ne farebbe di più). Oggi una catena ne ha al massimo due (filtro e regolazioni).
    /// </summary>
    public const int MassimoStadiColore = 3;

    /// <summary>Le tabelle del calore per R, G, B (null = niente calore), da applicare alla persona.</summary>
    public byte[][]? Calore { get; init; }

    /// <summary>
    /// Bordo pulito (sostituito, non al livello bilineare): il colore dell'interno sicuro della persona, piccolo. Dove la
    /// maschera è parziale il pixel prende sempre più questo colore, così il vecchio sfondo non resta sull'orlo.
    /// </summary>
    public ImmagineBgra? ColorePersona { get; init; }

    /// <summary>Light wrap (sostituito): lo sfondo nuovo sfocato, piccolo; null = niente light wrap.</summary>
    public ImmagineBgra? SfondoMorbido { get; init; }

    /// <summary>Light wrap: la maschera sfocata (0–255), piccola, per trovare l'orlo interno della persona.</summary>
    public byte[]? MascheraMorbida { get; init; }
    public int LarghezzaMorbida { get; init; }
    public int AltezzaMorbida { get; init; }
}

/// <summary>Chi fa il passo a piena risoluzione dello sfondo: la scheda video o il processore.</summary>
public interface IComposizione : IDisposable
{
    /// <summary>Per il registro: «scheda video (nome)» o «processore».</summary>
    string Descrizione { get; }

    /// <summary>Vero sulla scheda video.</summary>
    bool SullaSchedaVideo { get; }

    /// <summary>
    /// La persona sopra il fondo in <paramref name="destinazione"/> (stessa misura della sorgente). Bloccante. Un errore
    /// (scheda video persa) si lancia: chi chiama rifà il fotogramma sul processore.
    /// </summary>
    void Componi(PianoComposizione piano, ImmagineBgra destinazione);
}

/// <summary>
/// Le regole del bordo con lo sfondo sostituito, come il Mac (RicetteEffetti.personaSuSfondoNuovo), in un posto solo:
/// le usano la composizione sul processore, quella sulla scheda video (Composizione.hlsl ha gli stessi numeri) e i test.
/// </summary>
public static class RegoleBordo
{
    /// <summary>
    /// Fiducia nel pixel vero per un alfa (0..1): 1 con la maschera piena, 0 sotto 0,6 (2,5·a − 1,5). Dove è bassa, il
    /// colore viene dall'interno della persona (bordo pulito).
    /// </summary>
    public static float Fiducia(float alfa) => Math.Clamp(2.5f * alfa - 1.5f, 0f, 1f);

    /// <summary>Peso dell'interno sicuro per la media del colore della persona: 0 sotto 0,75, 1 da 0,95; mai sotto 0,01.</summary>
    public static float PesoInterno(float alfa) => Math.Clamp(5f * alfa - 3.75f, 0f, 1f) * 0.99f + 0.01f;

    /// <summary>
    /// Peso del light wrap: alfa × (1 − alfa sfocato) è circa 0,5 sull'orlo interno e 0 dentro e fuori; × 0,3, al massimo
    /// 0,15 (il «leggero» del Mac: 0,7/0,35 schiariva i capelli scuri su uno sfondo chiaro di +29/255).
    /// </summary>
    public static float PesoLuce(float alfa, float alfaMorbido) => Math.Min(0.3f * alfa * (1f - alfaMorbido), 0.15f);

    /// <summary>«Schermo» di due valori 0..255: 255 − (255 − a)(255 − b)/255. Schiarisce sempre, non scurisce mai.</summary>
    public static float Schermo(float a, float b) => 255f - (255f - a) * (255f - b) / 255f;

    /// <summary>Sigma (in pixel a 1080p) della media del colore della persona.</summary>
    public const double SigmaColorePersona = 8;

    /// <summary>Sigma (in pixel a 1080p) dello sfondo nuovo sfocato per il light wrap.</summary>
    public const double SigmaSfondoMorbido = 14;

    /// <summary>Sigma (in pixel a 1080p) della maschera sfocata per il light wrap.</summary>
    public const double SigmaMascheraMorbida = 3;

    /// <summary>
    /// Un canale del pixel finale, con i valori già campionati alla sua posizione (0..255, alfa 0..1). È la stessa
    /// sequenza del compute shader: bordo pulito, calore (tabella), light wrap, miscela con il fondo. Il filtro di colore
    /// (<see cref="PianoComposizione.Colore"/>) viene dopo, sul pixel arrotondato ai byte.
    /// </summary>
    public static float Canale(float sorgente, float alfa, float fondo, float? colorePersona, byte[]? calore, float? sfondoMorbido,
        float alfaMorbido)
    {
        var p = sorgente;
        if (colorePersona is { } c)
        {
            var f = Fiducia(alfa);
            p = p * f + c * (1f - f);
        }
        if (calore is not null) p = calore[(int)Math.Clamp(p + 0.5f, 0f, 255f)];
        if (sfondoMorbido is { } s)
        {
            var w = PesoLuce(alfa, alfaMorbido);
            p += (Schermo(s, p) - p) * w;
        }
        return p * alfa + fondo * (1f - alfa);
    }
}

/// <summary>
/// La composizione sul processore: alfa e fondi piccoli ingranditi bilineari riga per riga (pesi in 256esimi), le miscele
/// con gli interi (con i vettori del processore per lo sfocato). Con lo sostituito <see cref="RegoleBordo.Canale"/> con
/// gli interi e le tabelle di fiducia, luce e «schermo» in byte, e i conti solo sull'orlo della persona (in virgola mobile
/// su tutti i pixel costava tre volte tanto).
/// </summary>
public sealed unsafe class ComposizioneProcessore : IComposizione
{
    public string Descrizione => "processore";
    public bool SullaSchedaVideo => false;

    public void Componi(PianoComposizione piano, ImmagineBgra destinazione)
    {
        var src = piano.Sorgente;
        int l = src.Larghezza, a = src.Altezza, lw = piano.LarghezzaAlfa, aw = piano.AltezzaAlfa;
        var fondoPieno = piano.FondoPieno;
        var fondoPiccolo = piano.FondoPiccolo;
        if (fondoPieno is null && fondoPiccolo is null) throw new ArgumentException("Piano senza fondo", nameof(piano));
        var (ax0, ax1, afx) = Campionamento8(l, lw);
        var (ay0, ay1, afy) = Campionamento8(a, aw);
        var calore = piano.Calore;
        byte[] cr = calore?[0] ?? [], cg = calore?[1] ?? [], cb = calore?[2] ?? [];
        var coloreFinale = piano.Colore;
        var rifinita = piano.ColorePersona is not null || piano.SfondoMorbido is not null;
        var colore = piano.ColorePersona is { } cp ? new Righe(cp, l, a) : null;
        var morbido = piano.SfondoMorbido is { } sm ? new Righe(sm, l, a) : null;
        var piccolo = fondoPiccolo is not null ? new Righe(fondoPiccolo, l, a, piano.FondoAQuadretti) : null;
        var (mx0, mx1, mfx) = piano.MascheraMorbida is not null ? Campionamento8(l, piano.LarghezzaMorbida) : ([], [], []);
        var (my0, my1, mfy) = piano.MascheraMorbida is not null ? Campionamento8(a, piano.AltezzaMorbida) : ([], [], []);
        Elaborazione.PerRighe(a, (inizio, fine) =>
        {
            var rigaAlfa = new int[lw];
            var alfa4 = new byte[l * 4];
            var fondo = new byte[l * 4];
            var rigaColore = new byte[colore is null ? 0 : l * 4];
            var rigaMorbido = new byte[morbido is null ? 0 : l * 4];
            var rigaMaschera = new byte[piano.MascheraMorbida is null ? 0 : l];
            var appoggio = new int[Math.Max(lw, Math.Max(piano.LarghezzaMorbida, 1))];
            var appoggio3 = new int[Math.Max(Math.Max(piccolo?.Larghezza ?? 0, colore?.Larghezza ?? 0), morbido?.Larghezza ?? 0) * 3 + 3];
            fixed (byte* pa = piano.Alfa, a4 = alfa4, pf = fondo, ps = src.Dati, pd = destinazione.Dati)
            fixed (byte* tr = cr, tg = cg, tb = cb)
            fixed (int* ra = rigaAlfa, x0 = ax0, x1 = ax1, wx = afx)
            {
                for (var y = inizio; y < fine; y++)
                {
                    // Alfa: prima in verticale sulla riga di lavoro (×256), poi in orizzontale.
                    var r0 = pa + ay0[y] * lw;
                    var r1 = pa + ay1[y] * lw;
                    var wy = afy[y];
                    for (var x = 0; x < lw; x++) ra[x] = (r0[x] << 8) + (r1[x] - r0[x]) * wy;
                    var q = (uint*)a4;
                    for (var x = 0; x < l; x++)
                    {
                        var v = (uint)(((ra[x0[x]] << 8) + (ra[x1[x]] - ra[x0[x]]) * wx[x] + 32768) >> 16);
                        q[x] = 0xFF000000u | (v * 0x010101u);
                    }
                    if (fondoPieno is not null) fondoPieno.Dati.AsSpan(y * fondoPieno.Passo, l * 4).CopyTo(fondo);
                    else piccolo!.Riga(y, fondo, appoggio3);
                    var d = pd + y * destinazione.Passo;
                    var s = ps + y * src.Passo;
                    if (!rifinita)
                    {
                        // Persona (con il calore) sopra il fondo, con gli interi.
                        if (calore is not null)
                        {
                            for (var x = 0; x < l; x++)
                            {
                                d[x * 4] = tb[s[x * 4]];
                                d[x * 4 + 1] = tg[s[x * 4 + 1]];
                                d[x * 4 + 2] = tr[s[x * 4 + 2]];
                                d[x * 4 + 3] = s[x * 4 + 3];
                            }
                        }
                        else
                        {
                            Buffer.MemoryCopy(s, d, l * 4, l * 4);
                        }
                        Compositore.Miscela(new Span<byte>(d, l * 4), fondo, alfa4);
                        coloreFinale?.Applica(new Span<byte>(d, l * 4));
                        continue;
                    }
                    colore?.Riga(y, rigaColore, appoggio3);
                    morbido?.Riga(y, rigaMorbido, appoggio3);
                    if (piano.MascheraMorbida is { } mm)
                        RigaUnCanale(mm, piano.LarghezzaMorbida, my0[y], my1[y], mfy[y], mx0, mx1, mfx, rigaMaschera, appoggio);
                    // RegoleBordo.Canale con gli interi e le tabelle in byte. Fuori dalla persona (alfa 0) solo il fondo,
                    // dentro (alfa 255, lontano dall'orlo) solo la persona con il calore: i conti interi solo sull'orlo.
                    var conColore = colore is not null;
                    var conLuce = morbido is not null && rigaMaschera.Length > 0;
                    for (var x = 0; x < l; x++)
                    {
                        var i = x * 4;
                        int a8 = a4[i];
                        d[i + 3] = 255;
                        if (a8 == 0)
                        {
                            d[i] = pf[i];
                            d[i + 1] = pf[i + 1];
                            d[i + 2] = pf[i + 2];
                            continue;
                        }
                        int morbida8 = conLuce ? rigaMaschera[x] : 255;
                        int pf8 = conColore ? TabellaFiducia[a8] : 255;
                        int w8 = conLuce ? TabellaLuce[(a8 << 8) | morbida8] : 0;
                        for (var k = 0; k < 3; k++)
                        {
                            int p = s[i + k];
                            if (pf8 < 255) p = Dividi255(p * pf8 + rigaColore[i + k] * (255 - pf8));
                            if (calore is not null) p = k == 0 ? tb[p] : k == 1 ? tg[p] : tr[p];
                            if (w8 > 0) p = Dividi255(TabellaSchermo[(rigaMorbido[i + k] << 8) | p] * w8 + p * (255 - w8));
                            d[i + k] = a8 == 255 ? (byte)p : (byte)Dividi255(p * a8 + pf[i + k] * (255 - a8));
                        }
                    }
                    // Qualità 12: il filtro sulla riga finita (persona e fondo), come lo shader dopo la miscela.
                    coloreFinale?.Applica(new Span<byte>(d, l * 4));
                }
            }
        });
    }

    public void Dispose() { }

    /// <summary><see cref="RegoleBordo.Fiducia"/> in 255esimi, per ogni alfa in byte.</summary>
    private static readonly byte[] TabellaFiducia = Tabella(256, i => RegoleBordo.Fiducia(i / 255f) * 255f);

    /// <summary><see cref="RegoleBordo.PesoLuce"/> in 255esimi, per alfa × 256 + alfa sfocato (in byte).</summary>
    private static readonly byte[] TabellaLuce = Tabella(65536, i => RegoleBordo.PesoLuce((i >> 8) / 255f, (i & 255) / 255f) * 255f);

    /// <summary><see cref="RegoleBordo.Schermo"/> per sfondo × 256 + persona (in byte).</summary>
    private static readonly byte[] TabellaSchermo = Tabella(65536, i => RegoleBordo.Schermo(i >> 8, i & 255));

    /// <summary>v / 255 arrotondato, per v tra 0 e 255 × 255.</summary>
    private static int Dividi255(int v)
    {
        v += 128;
        return (v + (v >> 8)) >> 8;
    }

    private static byte[] Tabella(int n, Func<int, float> valore)
    {
        var tabella = new byte[n];
        for (var i = 0; i < n; i++) tabella[i] = (byte)Math.Clamp(valore(i) + 0.5f, 0f, 255f);
        return tabella;
    }

    /// <summary>Come <see cref="Elaborazione.Campionamento"/>, con il peso in 256esimi.</summary>
    internal static (int[] Primo, int[] Secondo, int[] Peso) Campionamento8(int destinazione, int sorgente)
    {
        var (primo, secondo, peso) = Elaborazione.Campionamento(destinazione, sorgente);
        return (primo, secondo, peso.Select(p => (int)(p * 256)).ToArray());
    }

    /// <summary>Una riga di un piano a un canale ingrandita bilineare (prima in verticale, poi in orizzontale).</summary>
    private static void RigaUnCanale(byte[] piano, int lp, int y0, int y1, int wy, int[] x0, int[] x1, int[] wx, byte[] uscita, int[] appoggio)
    {
        int o0 = y0 * lp, o1 = y1 * lp;
        for (var x = 0; x < lp; x++) appoggio[x] = (piano[o0 + x] << 8) + (piano[o1 + x] - piano[o0 + x]) * wy;
        for (var x = 0; x < uscita.Length; x++)
            uscita[x] = (byte)(((appoggio[x0[x]] << 8) + (appoggio[x1[x]] - appoggio[x0[x]]) * wx[x] + 32768) >> 16);
    }

    /// <summary>Un'immagine BGRA piccola da ingrandire riga per riga alla misura piena (fondo sfocato, colore, sfondo morbido).</summary>
    private sealed class Righe
    {
        private readonly ImmagineBgra immagine;
        private readonly int[] x0, x1, wx, y0, y1, wy;

        /// <param name="vicino">«Al più vicino» (mosaico): ogni punto prende un pixel solo, ⌊x · lp / l⌋, peso zero.</param>
        public Righe(ImmagineBgra immagine, int l, int a, bool vicino = false)
        {
            this.immagine = immagine;
            (x0, x1, wx) = vicino ? Vicini(l, immagine.Larghezza) : Campionamento8(l, immagine.Larghezza);
            (y0, y1, wy) = vicino ? Vicini(a, immagine.Altezza) : Campionamento8(a, immagine.Altezza);
        }

        private static (int[], int[], int[]) Vicini(int destinazione, int sorgente)
        {
            var indici = new int[destinazione];
            for (var i = 0; i < destinazione; i++) indici[i] = Math.Min(sorgente - 1, (int)((long)i * sorgente / destinazione));
            return (indici, indici, new int[destinazione]);
        }

        public int Larghezza => immagine.Larghezza;

        public void Riga(int y, byte[] uscita, int[] appoggio)
        {
            var lp = immagine.Larghezza;
            fixed (byte* pp = immagine.Dati, f0 = uscita)
            fixed (int* rp = appoggio, gx0 = x0, gx1 = x1, gwx = wx)
            {
                var q0 = pp + y0[y] * immagine.Passo;
                var q1 = pp + y1[y] * immagine.Passo;
                var wq = wy[y];
                for (var x = 0; x < lp; x++)
                {
                    rp[x * 3] = (q0[x * 4] << 8) + (q1[x * 4] - q0[x * 4]) * wq;
                    rp[x * 3 + 1] = (q0[x * 4 + 1] << 8) + (q1[x * 4 + 1] - q0[x * 4 + 1]) * wq;
                    rp[x * 3 + 2] = (q0[x * 4 + 2] << 8) + (q1[x * 4 + 2] - q0[x * 4 + 2]) * wq;
                }
                var f = f0;
                var n = uscita.Length / 4;
                for (var x = 0; x < n; x++, f += 4)
                {
                    var i0 = gx0[x] * 3;
                    var i1 = gx1[x] * 3;
                    var w = gwx[x];
                    f[0] = (byte)(((rp[i0] << 8) + (rp[i1] - rp[i0]) * w + 32768) >> 16);
                    f[1] = (byte)(((rp[i0 + 1] << 8) + (rp[i1 + 1] - rp[i0 + 1]) * w + 32768) >> 16);
                    f[2] = (byte)(((rp[i0 + 2] << 8) + (rp[i1 + 2] - rp[i0 + 2]) * w + 32768) >> 16);
                    f[3] = 255;
                }
            }
        }
    }
}

/// <summary>Il passo a piena risoluzione cambia posto: <paramref name="SullaSchedaVideo"/> o no, e perché (per il registro).</summary>
public sealed record CambioComposizione(bool SullaSchedaVideo, string Descrizione, string? Motivo);

/// <summary>
/// Un piano di composizione sintetico (sfumature, bordo morbido, fondo piccolo o pieno, calore, filtro): per verificare la scheda
/// video contro il processore all'apertura (ComposizioneSchedaVideo.Verifica) e nei test.
/// </summary>
public static class PianoDiProva
{
    /// <param name="quadretti">Con lo sfocato: il fondo piccolo come un mosaico (11×7 quadretti, «al più vicino»).</param>
    /// <param name="filtro">
    /// Qualità 12: un filtro del protocollo sull'immagine intera; con <paramref name="regolazioni"/> anche contrasto e
    /// saturazione (uno stadio in più).
    /// </param>
    public static PianoComposizione Crea(int l, int a, bool sostituito, bool quadretti = false, string? filtro = null,
        bool regolazioni = false)
    {
        var colore = filtro is null ? null : RicetteColore.Catena(filtro, 0, regolazioni ? 0.3 : 0, regolazioni ? -0.4 : 0);
        var src = Immagine(l, a, (x, y) => ((byte)(40 + x * 180 / l), (byte)(30 + y * 200 / a), (byte)((x * 7 + y * 3) % 256)));
        int lw = Math.Max(1, l / 2), aw = Math.Max(1, a / 2);
        var alfa = new byte[lw * aw];
        for (var y = 0; y < aw; y++)
            for (var x = 0; x < lw; x++)
                alfa[y * lw + x] = (byte)Math.Clamp((lw / 2 - x) * 24 + 128 + (y % 7) * 5, 0, 255);
        int lq = Math.Max(1, l / 4), aq = Math.Max(1, a / 4);
        var tabelle = new byte[3][];
        for (var c = 0; c < 3; c++)
        {
            tabelle[c] = new byte[256];
            for (var i = 0; i < 256; i++) tabelle[c][i] = (byte)Math.Clamp(i + (1 - c) * 12, 0, 255);
        }
        if (!sostituito)
        {
            return new PianoComposizione
            {
                Sorgente = src, Alfa = alfa, LarghezzaAlfa = lw, AltezzaAlfa = aw,
                FondoPiccolo = quadretti
                    ? Immagine(11, 7, (x, y) => ((byte)(30 + x * 20), (byte)(220 - y * 30), (byte)((x * 53 + y * 97) % 256)))
                    : Immagine(Math.Max(1, l / 8), Math.Max(1, a / 8), (x, y) => ((byte)(200 - x * 9), (byte)(60 + y * 11), 90)),
                FondoAQuadretti = quadretti,
                Calore = tabelle,
                Colore = colore,
            };
        }
        var maschera = new byte[lq * aq];
        for (var y = 0; y < aq; y++)
            for (var x = 0; x < lq; x++)
                maschera[y * lq + x] = (byte)Math.Clamp((lq / 2 - x) * 30 + 128, 0, 255);
        return new PianoComposizione
        {
            Sorgente = src, Alfa = alfa, LarghezzaAlfa = lw, AltezzaAlfa = aw, Calore = tabelle,
            FondoPieno = Immagine(l, a, (x, y) => ((byte)(250 - y), (byte)(x % 200), (byte)(220 - x / 2))), ChiaveFondo = "prova",
            ColorePersona = Immagine(lq, aq, (x, y) => ((byte)(60 + x * 3), (byte)(100 + y * 2), 140)),
            SfondoMorbido = Immagine(lq, aq, (x, y) => ((byte)(230 - x), (byte)(200 - y * 2), (byte)(250 - x - y))),
            MascheraMorbida = maschera, LarghezzaMorbida = lq, AltezzaMorbida = aq,
            Colore = colore,
        };
    }

    /// <summary>Differenza massima e media (0–255) sui canali di colore di due immagini della stessa misura.</summary>
    public static (int Massima, double Media) Differenza(ImmagineBgra x, ImmagineBgra y)
    {
        var massima = 0;
        long somma = 0, conta = 0;
        for (var i = 0; i < x.Larghezza * x.Altezza * 4; i++)
        {
            if (i % 4 == 3) continue;
            var d = Math.Abs(x.Dati[i] - y.Dati[i]);
            massima = Math.Max(massima, d);
            somma += d;
            conta++;
        }
        return (massima, (double)somma / Math.Max(1, conta));
    }

    private static ImmagineBgra Immagine(int l, int a, Func<int, int, (byte B, byte G, byte R)> colore)
    {
        var immagine = new ImmagineBgra(l, a);
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var (b, g, r) = colore(x, y);
                var o = (y * l + x) * 4;
                immagine.Dati[o] = b;
                immagine.Dati[o + 1] = g;
                immagine.Dati[o + 2] = r;
                immagine.Dati[o + 3] = 255;
            }
        }
        return immagine;
    }
}
