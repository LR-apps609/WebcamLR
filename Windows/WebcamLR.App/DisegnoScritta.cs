using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using WebcamLR.Effetti;

namespace WebcamLR;

/// <summary>
/// Il sottopancia del motore effetti (scritta con nome e ruolo), come sul Mac e sull'iPhone (EffettoScritta.swift): barra
/// scura arrotondata (il fondo di Tema all'80%), filo dell'accento a sinistra, nome in Barlow Condensed Bold, ruolo in
/// maiuscolo in Barlow Condensed SemiBold nell'accento chiaro. Misure in proporzione al lato corto del video; al massimo
/// il 60% della larghezza (un nome lunghissimo si tronca con «…»). Disegnato con GDI+ (System.Drawing, solo Windows) una
/// volta per testo e misura, non per fotogramma. I caratteri sono quelli dell'app (Assets\Caratteri).
/// </summary>
public sealed class DisegnoScritta : IDisegnoScritta
{
    private static readonly Color Fondo = Color.FromArgb(204, 0x13, 0x21, 0x1D);
    private static readonly Color Accento = Color.FromArgb(0x9F, 0xD0, 0xB6);
    private static readonly Color AccentoChiaro = Color.FromArgb(0xB9, 0xE2, 0xCB);
    private static readonly Color Testo = Color.FromArgb(0xE6, 0xEE, 0xEA);

    private readonly object blocco = new();
    private PrivateFontCollection? caratteri;
    private FontFamily? famigliaNome, famigliaRuolo;

    private void CaricaCaratteri()
    {
        if (caratteri is not null) return;
        caratteri = new PrivateFontCollection();
        var cartella = Path.Combine(AppContext.BaseDirectory, "Assets", "Caratteri");
        foreach (var file in new[] { "BarlowCondensed-Bold.ttf", "BarlowCondensed-SemiBold.ttf" })
        {
            try { caratteri.AddFontFile(Path.Combine(cartella, file)); }
            catch (Exception) { }
        }
        var famiglie = caratteri.Families;
        // GDI+ registra il file SemiBold come una famiglia a sé («… SemiBold»): il nome è l'altra.
        famigliaRuolo = famiglie.FirstOrDefault(f => f.Name.Contains("SemiBold", StringComparison.OrdinalIgnoreCase));
        famigliaNome = famiglie.FirstOrDefault(f => f != famigliaRuolo) ?? famigliaRuolo ?? FontFamily.GenericSansSerif;
        famigliaRuolo ??= famigliaNome;
    }

    private static Font Carattere(FontFamily famiglia, float pixel, FontStyle voluto)
    {
        // Un file a stile unico (Bold, SemiBold) in GDI+ ha solo quello: si chiede quello che c'è.
        var stile = famiglia.IsStyleAvailable(voluto) ? voluto
            : famiglia.IsStyleAvailable(FontStyle.Regular) ? FontStyle.Regular
            : famiglia.IsStyleAvailable(FontStyle.Bold) ? FontStyle.Bold
            : FontStyle.Italic;
        return new Font(famiglia, pixel, stile, GraphicsUnit.Pixel);
    }

    public ImmagineBgra? Disegna(string nome, string ruolo, int larghezzaVideo, int altezzaVideo)
    {
        lock (blocco)
        {
            CaricaCaratteri();
            var unita = Math.Min(larghezzaVideo, altezzaVideo) / 1080f;
            if (unita <= 0 || nome.Length == 0) return null;
            using var carattereNome = Carattere(famigliaNome!, 52 * unita, FontStyle.Bold);
            using var carattereRuolo = Carattere(famigliaRuolo!, 26 * unita, FontStyle.Regular);
            var filo = MathF.Round(6 * unita);
            var orizzontale = MathF.Round(26 * unita);
            var verticale = MathF.Round(14 * unita);
            var spazioRighe = MathF.Round(2 * unita);
            var larghezzaMassima = Math.Max(larghezzaVideo * 0.6f - filo - orizzontale * 2, 40 * unita);
            var ruoloMaiuscolo = ruolo.Trim().ToUpperInvariant();

            using var misura = new Bitmap(1, 1);
            using var g0 = Graphics.FromImage(misura);
            g0.TextRenderingHint = TextRenderingHint.AntiAlias;
            using var formato = new StringFormat(StringFormat.GenericTypographic)
            {
                Trimming = StringTrimming.EllipsisCharacter,
                FormatFlags = StringFormatFlags.NoWrap | StringFormatFlags.MeasureTrailingSpaces,
            };
            var dimNome = g0.MeasureString(nome, carattereNome, new SizeF(larghezzaMassima, 1000), formato);
            var dimRuolo = ruoloMaiuscolo.Length == 0 ? SizeF.Empty
                : g0.MeasureString(ruoloMaiuscolo, carattereRuolo, new SizeF(larghezzaMassima, 1000), formato);
            var altezzaNome = MathF.Ceiling(carattereNome.GetHeight(g0));
            var altezzaRuolo = ruoloMaiuscolo.Length == 0 ? 0 : MathF.Ceiling(carattereRuolo.GetHeight(g0));
            var larghezzaTesto = MathF.Ceiling(Math.Min(larghezzaMassima, Math.Max(dimNome.Width, dimRuolo.Width)));
            var larghezza = (int)Math.Ceiling(filo + orizzontale * 2 + larghezzaTesto);
            var altezza = (int)Math.Ceiling(verticale * 2 + altezzaNome + (altezzaRuolo > 0 ? spazioRighe + altezzaRuolo : 0));
            if (larghezza <= 0 || altezza <= 0) return null;

            using var bitmap = new Bitmap(larghezza, altezza, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bitmap))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                g.Clear(Color.Transparent);
                using var forma = Arrotondato(new RectangleF(0, 0, larghezza, altezza), 14 * unita);
                using (var pennello = new SolidBrush(Fondo)) g.FillPath(pennello, forma);
                g.SetClip(forma);
                using (var pennello = new SolidBrush(Accento)) g.FillRectangle(pennello, 0, 0, filo, altezza);
                g.ResetClip();
                var x = filo + orizzontale;
                using (var pennello = new SolidBrush(Testo))
                    g.DrawString(nome, carattereNome, pennello, new RectangleF(x, verticale, larghezzaTesto, altezzaNome), formato);
                if (altezzaRuolo > 0)
                {
                    using var pennello = new SolidBrush(AccentoChiaro);
                    g.DrawString(ruoloMaiuscolo, carattereRuolo, pennello,
                        new RectangleF(x, verticale + altezzaNome + spazioRighe, larghezzaTesto, altezzaRuolo), formato);
                }
            }
            // PArgb in memoria è B, G, R, A premoltiplicato: come vuole il motore.
            var immagine = new ImmagineBgra(larghezza, altezza);
            var dati = bitmap.LockBits(new Rectangle(0, 0, larghezza, altezza), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
            try
            {
                for (var y = 0; y < altezza; y++)
                    Marshal.Copy(dati.Scan0 + y * dati.Stride, immagine.Dati, y * immagine.Passo, larghezza * 4);
            }
            finally
            {
                bitmap.UnlockBits(dati);
            }
            return immagine;
        }
    }

    private static GraphicsPath Arrotondato(RectangleF r, float raggio)
    {
        var d = Math.Max(1, Math.Min(raggio * 2, Math.Min(r.Width, r.Height)));
        var percorso = new GraphicsPath();
        percorso.AddArc(r.X, r.Y, d, d, 180, 90);
        percorso.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        percorso.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        percorso.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        percorso.CloseFigure();
        return percorso;
    }
}
