using System.Reflection;
using System.Runtime.InteropServices;
using Vortice.D3DCompiler;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;

namespace WebcamLR.Effetti;

/// <summary>
/// Qualità 5: il passo a piena risoluzione dello sfondo (persona sopra il fondo sfocato o sostituito, bordo pulito, light
/// wrap, calore) sulla scheda video, con Direct3D 11 e un compute shader (SchedaVideo/Composizione.hlsl, compilato qui
/// all'apertura con D3DCompile). Stessi conti di <see cref="ComposizioneProcessore"/>.
///
/// Per fotogramma: il fotogramma (8 MB a 1080p) e le cose piccole salgono sulla scheda video, lo shader compone, il
/// risultato torna in memoria (le uscite del motore sono in memoria: webcam, anteprima, registrazione, foto). L'immagine
/// dello sfondo sostituito e la sua versione sfocata salgono solo quando cambiano.
///
/// <see cref="Crea"/> lancia un errore (e il motore resta sul processore) se: non è Windows; Direct3D 11 con il livello
/// 11.0 non si apre; c'è solo il driver di base di Microsoft (WARP, sul processore: più lento del nostro); lo shader non
/// compila; il risultato su due fotogrammi di prova differisce da quello del processore (<see cref="Verifica"/>).
/// Non è thread-safe: la usa solo la coda di resa (l'apertura può essere su un altro thread, prima).
/// </summary>
public sealed class ComposizioneSchedaVideo : IComposizione
{
    /// <summary>Differenza massima (0–255) con il processore sui fotogrammi di prova: oltre, la scheda video non si usa.</summary>
    public const int DifferenzaMassima = 4;

    /// <summary>Differenza media massima con il processore sui fotogrammi di prova.</summary>
    public const double DifferenzaMediaMassima = 0.6;

    private const int Gruppo = 16;
    private const uint Pulito = 1, Luce = 2, ConCalore = 4;

    private readonly ID3D11Device dispositivo;
    private readonly ID3D11DeviceContext contesto;
    private readonly ID3D11ComputeShader shader;
    private readonly ID3D11SamplerState campionatore;
    private readonly ID3D11Buffer parametri;

    private readonly Texture sorgente = new(Format.R8G8B8A8_UNorm), alfa = new(Format.R8_UNorm), fondo = new(Format.R8G8B8A8_UNorm),
        colore = new(Format.R8G8B8A8_UNorm), morbido = new(Format.R8G8B8A8_UNorm), maschera = new(Format.R8_UNorm),
        calore = new(Format.R8G8B8A8_UNorm);
    private ID3D11Texture2D? uscita, lettura;
    private ID3D11UnorderedAccessView? vistaUscita;
    private (int L, int A) misuraUscita;
    // Cosa c'è già sulla scheda video, per non ricaricarlo: il fondo pieno (chiave), lo sfondo morbido e il calore (oggetto).
    private string? chiaveFondo;
    private object? morbidoCaricato, caloreCaricato;
    private readonly byte[] tabellaCalore = new byte[256 * 4];

    public string Descrizione { get; }
    public bool SullaSchedaVideo => true;

    private ComposizioneSchedaVideo(ID3D11Device dispositivo, string nome)
    {
        this.dispositivo = dispositivo;
        contesto = dispositivo.ImmediateContext;
        Descrizione = $"scheda video, {nome}";
        try
        {
            shader = dispositivo.CreateComputeShader(CompilaShader().Span);
            campionatore = dispositivo.CreateSamplerState(SamplerDescription.LinearClamp);
            parametri = dispositivo.CreateBuffer(new BufferDescription(16, BindFlags.ConstantBuffer, ResourceUsage.Default));
            // Tutte le texture esistono da subito (1×1 nera): lo shader ne ha sempre una legata a ogni registro, anche
            // per le parti spente (niente viste nulle passate al driver).
            var nero = new byte[4];
            foreach (var t in new[] { sorgente, alfa, fondo, colore, morbido, maschera, calore }) Carica(t, nero, 1, 1, 4);
        }
        catch
        {
            shader?.Dispose();
            campionatore?.Dispose();
            contesto.Dispose();
            throw;
        }
    }

    /// <summary>
    /// La composizione sulla scheda video principale, verificata contro il processore; un errore se non si può (vedi
    /// sopra): chi chiama resta sul processore. <paramref name="ancheSoftware"/>: anche WARP (solo per i test su Windows
    /// senza scheda video, per esempio la CI).
    /// </summary>
    public static ComposizioneSchedaVideo Crea(bool ancheSoftware = false)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Direct3D 11 c'è solo su Windows");
        ID3D11Device? dispositivo = null;
        var esito = D3D11.D3D11CreateDevice(IntPtr.Zero, DriverType.Hardware, DeviceCreationFlags.None,
            [FeatureLevel.Level_11_1, FeatureLevel.Level_11_0], out dispositivo);
        if (esito.Failure || dispositivo is null)
        {
            if (!ancheSoftware) throw new NotSupportedException($"Direct3D 11 (livello 11.0) non si apre: 0x{esito.Code:X8}");
            D3D11.D3D11CreateDevice(IntPtr.Zero, DriverType.Warp, DeviceCreationFlags.None,
                [FeatureLevel.Level_11_1, FeatureLevel.Level_11_0], out dispositivo).CheckError();
        }
        var nome = "?";
        try
        {
            using var dxgi = dispositivo!.QueryInterface<IDXGIDevice>();
            using var adattatore = dxgi.GetAdapter();
            var descrizione = adattatore.Description;
            nome = descrizione.Description.Trim();
            // Il «Microsoft Basic Render Driver» (VendorId 0x1414, DeviceId 0x8C) è WARP: gira sul processore.
            if (!ancheSoftware && descrizione.VendorId == 0x1414 && descrizione.DeviceId == 0x8C)
                throw new NotSupportedException("solo il driver di base di Microsoft, nessuna scheda video");
        }
        catch
        {
            dispositivo!.Dispose();
            throw;
        }
        ComposizioneSchedaVideo? gpu = null;
        try
        {
            gpu = new ComposizioneSchedaVideo(dispositivo!, nome);
            gpu.Verifica();
            return gpu;
        }
        catch
        {
            if (gpu is not null) gpu.Dispose();
            else dispositivo!.Dispose();
            throw;
        }
    }

    /// <summary>Il testo dello shader (risorsa della libreria) compilato per cs_5_0; l'errore del compilatore nel messaggio.</summary>
    private static ReadOnlyMemory<byte> CompilaShader()
    {
        using var flusso = Assembly.GetExecutingAssembly().GetManifestResourceStream("Composizione.hlsl")
                           ?? throw new InvalidOperationException("Composizione.hlsl non è nella libreria");
        using var lettore = new StreamReader(flusso);
        var testo = lettore.ReadToEnd();
        try
        {
            // Questa forma passa da sé l'elenco vuoto delle macro e lancia un errore con il messaggio del compilatore.
            return Compiler.Compile(testo, "Componi", "Composizione.hlsl", "cs_5_0", ShaderFlags.OptimizationLevel3, EffectFlags.None);
        }
        catch (Exception errore)
        {
            throw new InvalidOperationException($"lo shader non compila: {errore.Message}", errore);
        }
    }

    /// <summary>
    /// Due fotogrammi di prova (<see cref="PianoDiProva"/>: sfocato; sostituito con bordo pulito, light wrap e calore)
    /// sulla scheda video e sul processore: se differiscono più di <see cref="DifferenzaMassima"/> o in media più di
    /// <see cref="DifferenzaMediaMassima"/>, errore. Così uno shader sbagliato o un driver strano non arrivano mai al video.
    /// </summary>
    public void Verifica()
    {
        var processore = new ComposizioneProcessore();
        foreach (var sostituito in new[] { false, true })
        {
            var piano = PianoDiProva.Crea(200, 112, sostituito);
            var attesa = new ImmagineBgra(200, 112);
            var ottenuta = new ImmagineBgra(200, 112);
            processore.Componi(piano, attesa);
            Componi(piano, ottenuta);
            var (massima, media) = PianoDiProva.Differenza(attesa, ottenuta);
            if (massima > DifferenzaMassima || media > DifferenzaMediaMassima)
                throw new InvalidDataException($"risultato diverso dal processore ({(sostituito ? "sostituito" : "sfocato")}: " +
                                               $"differenza massima {massima}, media {media:0.00})");
        }
        // La prova non deve lasciare il suo fondo come «già caricato».
        chiaveFondo = null;
        morbidoCaricato = caloreCaricato = null;
    }

    public void Componi(PianoComposizione piano, ImmagineBgra destinazione)
    {
        var src = piano.Sorgente;
        int l = src.Larghezza, a = src.Altezza;
        if (destinazione.Larghezza != l || destinazione.Altezza != a) throw new ArgumentException("Uscita di misura diversa", nameof(destinazione));
        var fondoImmagine = piano.FondoPieno ?? piano.FondoPiccolo ?? throw new ArgumentException("Piano senza fondo", nameof(piano));

        Carica(sorgente, src.Dati, l, a, src.Passo);
        Carica(alfa, piano.Alfa, piano.LarghezzaAlfa, piano.AltezzaAlfa, piano.LarghezzaAlfa);
        if (piano.FondoPieno is null || piano.ChiaveFondo is null || piano.ChiaveFondo != chiaveFondo)
        {
            Carica(fondo, fondoImmagine.Dati, fondoImmagine.Larghezza, fondoImmagine.Altezza, fondoImmagine.Passo);
            chiaveFondo = piano.FondoPieno is null ? null : piano.ChiaveFondo;
        }
        var opzioni = 0u;
        if (piano.ColorePersona is { } cp)
        {
            Carica(colore, cp.Dati, cp.Larghezza, cp.Altezza, cp.Passo);
            opzioni |= Pulito;
        }
        if (piano.SfondoMorbido is { } sm && piano.MascheraMorbida is { } mm)
        {
            if (!ReferenceEquals(sm, morbidoCaricato))
            {
                Carica(morbido, sm.Dati, sm.Larghezza, sm.Altezza, sm.Passo);
                morbidoCaricato = sm;
            }
            Carica(maschera, mm, piano.LarghezzaMorbida, piano.AltezzaMorbida, piano.LarghezzaMorbida);
            opzioni |= Luce;
        }
        if (piano.Calore is { } tabelle)
        {
            if (!ReferenceEquals(tabelle, caloreCaricato))
            {
                for (var i = 0; i < 256; i++)
                {
                    tabellaCalore[i * 4] = tabelle[2][i];
                    tabellaCalore[i * 4 + 1] = tabelle[1][i];
                    tabellaCalore[i * 4 + 2] = tabelle[0][i];
                    tabellaCalore[i * 4 + 3] = 255;
                }
                Carica(calore, tabellaCalore, 256, 1, 256 * 4);
                caloreCaricato = tabelle;
            }
            opzioni |= ConCalore;
        }

        PreparaUscita(l, a);
        var valori = new Parametri { Larghezza = (uint)l, Altezza = (uint)a, Opzioni = opzioni };
        contesto.UpdateSubresource(in valori, parametri);
        contesto.CSSetShader(shader);
        contesto.CSSetConstantBuffer(0, parametri);
        contesto.CSSetSampler(0, campionatore);
        contesto.CSSetShaderResources(0, [sorgente.Vista!, alfa.Vista!, fondo.Vista!, colore.Vista!, morbido.Vista!, maschera.Vista!,
            calore.Vista!]);
        contesto.CSSetUnorderedAccessView(0, vistaUscita!, 0);
        contesto.Dispatch((uint)((l + Gruppo - 1) / Gruppo), (uint)((a + Gruppo - 1) / Gruppo), 1);
        // Le risorse si staccano: al prossimo fotogramma la sorgente si riscrive mentre lo shader non la legge più.
        contesto.CSUnsetUnorderedAccessView(0, 0);
        contesto.CSUnsetShaderResources(0, 7);
        contesto.CopyResource(lettura!, uscita!);

        // Map aspetta che la scheda video abbia finito: la resa resta sincrona, come sul processore.
        var mappata = contesto.Map(lettura!, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
        try
        {
            var byteRiga = l * 4;
            unsafe
            {
                var base0 = (byte*)mappata.DataPointer;
                for (var y = 0; y < a; y++)
                    new ReadOnlySpan<byte>(base0 + (long)y * mappata.RowPitch, byteRiga).CopyTo(destinazione.Dati.AsSpan(y * destinazione.Passo, byteRiga));
            }
        }
        finally
        {
            contesto.Unmap(lettura!, 0);
        }
    }

    /// <summary>La texture di uscita (scrivibile dallo shader) e quella da leggere dal processore, alla misura del video.</summary>
    private void PreparaUscita(int l, int a)
    {
        if (uscita is not null && misuraUscita == (l, a)) return;
        vistaUscita?.Dispose();
        uscita?.Dispose();
        lettura?.Dispose();
        uscita = dispositivo.CreateTexture2D(new Texture2DDescription(Format.R8G8B8A8_UNorm, (uint)l, (uint)a, 1, 1,
            BindFlags.UnorderedAccess, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
        lettura = dispositivo.CreateTexture2D(new Texture2DDescription(Format.R8G8B8A8_UNorm, (uint)l, (uint)a, 1, 1,
            BindFlags.None, ResourceUsage.Staging, CpuAccessFlags.Read, 1, 0, ResourceOptionFlags.None));
        vistaUscita = dispositivo.CreateUnorderedAccessView(uscita, null);
        misuraUscita = (l, a);
    }

    /// <summary>I byte in una texture (rifatta se la misura cambia).</summary>
    private void Carica(Texture texture, byte[] dati, int l, int a, int passo)
    {
        if (texture.Risorsa is null || texture.L != l || texture.A != a)
        {
            texture.Vista?.Dispose();
            texture.Risorsa?.Dispose();
            texture.Risorsa = dispositivo.CreateTexture2D(new Texture2DDescription(texture.Formato, (uint)l, (uint)a, 1, 1,
                BindFlags.ShaderResource, ResourceUsage.Default, CpuAccessFlags.None, 1, 0, ResourceOptionFlags.None));
            texture.Vista = dispositivo.CreateShaderResourceView(texture.Risorsa, null);
            texture.L = l;
            texture.A = a;
        }
        contesto.UpdateSubresource(new ReadOnlySpan<byte>(dati, 0, passo * a), texture.Risorsa, 0, (uint)passo, 0, null);
    }

    public void Dispose()
    {
        foreach (var t in new[] { sorgente, alfa, fondo, colore, morbido, maschera, calore })
        {
            t.Vista?.Dispose();
            t.Risorsa?.Dispose();
        }
        vistaUscita?.Dispose();
        uscita?.Dispose();
        lettura?.Dispose();
        parametri?.Dispose();
        campionatore?.Dispose();
        shader?.Dispose();
        contesto.ClearState();
        contesto.Dispose();
        dispositivo.Dispose();
    }

    private sealed class Texture(Format formato)
    {
        public Format Formato { get; } = formato;
        public ID3D11Texture2D? Risorsa;
        public ID3D11ShaderResourceView? Vista;
        public int L, A;
    }

    /// <summary>Il cbuffer Parametri dello shader (16 byte).</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct Parametri
    {
        public uint Larghezza, Altezza, Opzioni, Riservato;
    }
}
