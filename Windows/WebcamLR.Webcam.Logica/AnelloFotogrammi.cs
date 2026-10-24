using System.Runtime.CompilerServices;

namespace WebcamLR.Webcam;

/// <summary>Un fotogramma letto dall'anello.</summary>
/// <param name="Numero">Cresce di uno a ogni fotogramma scritto dall'app; 0 non esiste.</param>
/// <param name="TempoMs">Quando l'app l'ha scritto, in millisecondi dall'avvio di Windows (Environment.TickCount64, uguale per tutti i processi).</param>
public readonly record struct InfoFotogramma(long Numero, int Larghezza, int Altezza, long TempoMs);

/// <summary>
/// L'anello di fotogrammi nella memoria condivisa tra l'app (scrive) e la sorgente della webcam (legge).
/// Si lavora su un puntatore: nella webcam è la vista di «Global\WebcamLR.Video», nei test un array fissato.
/// </summary>
/// <remarks>
/// Disposizione (little endian, tutti i campi allineati):
/// <code>
///   0  u32 magia «WLRV» (0x56524C57)        4  u32 versione (1)
///   8  u32 numero di posti (3)              12  u32 byte per posto
///  16  i64 numero dell'ultimo fotogramma completo (0 = nessuno)
///  24  i64 battito dell'app: ms dell'ultima scrittura
///  32  u32 larghezza chiesta dalla sorgente 36  u32 altezza chiesta dalla sorgente
///  40  i64 battito della sorgente: ms dell'ultimo fotogramma dato a un'app (webcam in uso)
///  48  i64 fotogrammi dati alle app (solo per la diagnosi)
///  64 + 64·i  posto i: i64 versione (-1 mentre l'app scrive, poi il numero del fotogramma),
///             u32 larghezza, u32 altezza, i64 ms di scrittura
/// 4096 + i·byte per posto: i dati NV12 del posto i, righe senza margine (passo = larghezza)
/// </code>
/// Il fotogramma n va nel posto n mod 3. Chi legge controlla la versione del posto prima e dopo la copia:
/// se è cambiata, l'app ha riscritto il posto nel frattempo e si riprova (come un seqlock).
/// </remarks>
public sealed unsafe class AnelloFotogrammi
{
    public const uint Magia = 0x56524C57;
    public const uint Versione = 1;
    public const int NumeroPosti = 3;
    public const int DimensioneIntestazione = 4096;
    /// <summary>NV12 1920×1080 arrotondato a 4 KB.</summary>
    public static readonly int BytePerPosto = Arrotonda(FormatiWebcam.Massimo.Byte, 4096);
    public static long DimensioneTotale => DimensioneIntestazione + (long)NumeroPosti * BytePerPosto;

    private const int PosMagia = 0, PosVersione = 4, PosPosti = 8, PosBytePosto = 12;
    private const int PosUltimo = 16, PosBattitoApp = 24, PosLarghezzaChiesta = 32, PosAltezzaChiesta = 36;
    private const int PosBattitoSorgente = 40, PosFotogrammiDati = 48;
    private const int PosIntestazioniPosti = 64, DimensioneIntestazionePosto = 64;

    private readonly byte* inizio;
    /// <summary>Solo per chi scrive: l'ultimo numero usato.</summary>
    private long numeroScritto;
    private long postoInScrittura = -1;

    public AnelloFotogrammi(byte* inizio, long lunghezza)
    {
        if (inizio == null) throw new ArgumentNullException(nameof(inizio));
        if (lunghezza < DimensioneTotale) throw new ArgumentException($"Servono almeno {DimensioneTotale} byte", nameof(lunghezza));
        this.inizio = inizio;
    }

    /// <summary>Vero se l'intestazione è di questa versione: altrimenti non si legge e non si scrive.</summary>
    public bool Valido =>
        U32(PosMagia) == Magia && U32(PosVersione) == Versione
        && U32(PosPosti) == NumeroPosti && U32(PosBytePosto) == (uint)BytePerPosto;

    /// <summary>Chi crea la memoria (la sorgente) la prepara, se non lo è già: un secondo processo non cancella il primo.</summary>
    public void Prepara()
    {
        if (Valido) return;
        new Span<byte>(inizio, DimensioneIntestazione).Clear();
        ScriviU32(PosVersione, Versione);
        ScriviU32(PosPosti, NumeroPosti);
        ScriviU32(PosBytePosto, (uint)BytePerPosto);
        // La magia per ultima: chi la vede trova anche il resto.
        Volatile.Write(ref *(uint*)(inizio + PosMagia), Magia);
    }

    // ── Chi scrive (l'app) ─────────────────────────────────────────

    /// <summary>
    /// Prende il posto per il prossimo fotogramma e lo segna «in scrittura». Si scrivono i dati NV12 nello spazio
    /// restituito (larghezza × altezza × 3/2 byte), poi si chiama <see cref="ConcludiScrittura"/>.
    /// </summary>
    public Span<byte> IniziaScrittura(int larghezza, int altezza)
    {
        ControllaDimensioni(larghezza, altezza);
        // Dopo un riavvio dell'app si riparte da dove era arrivata quella prima, così la sorgente vede numeri nuovi.
        numeroScritto = Math.Max(numeroScritto, Volatile.Read(ref *(long*)(inizio + PosUltimo)));
        var numero = numeroScritto + 1;
        var posto = numero % NumeroPosti;
        var testa = IntestazionePosto(posto);
        Volatile.Write(ref *(long*)testa, -1);
        // Barriera piena: su ARM64 i dati scritti dopo non devono diventare visibili prima del -1.
        Interlocked.MemoryBarrier();
        *(uint*)(testa + 8) = (uint)larghezza;
        *(uint*)(testa + 12) = (uint)altezza;
        postoInScrittura = posto;
        return new Span<byte>(DatiPosto(posto), FormatoWebcam.DimensioneNv12(larghezza, altezza));
    }

    /// <summary>Pubblica il fotogramma: da qui la sorgente lo può leggere.</summary>
    public void ConcludiScrittura(long adessoMs)
    {
        if (postoInScrittura < 0) throw new InvalidOperationException("Nessuna scrittura in corso");
        var numero = numeroScritto + 1;
        var testa = IntestazionePosto(postoInScrittura);
        *(long*)(testa + 16) = adessoMs;
        Volatile.Write(ref *(long*)testa, numero);
        Volatile.Write(ref *(long*)(inizio + PosUltimo), numero);
        Volatile.Write(ref *(long*)(inizio + PosBattitoApp), adessoMs);
        numeroScritto = numero;
        postoInScrittura = -1;
    }

    /// <summary>Scrive un fotogramma già pronto (nei test e quando non serve convertire sul posto).</summary>
    public void Scrivi(ReadOnlySpan<byte> nv12, int larghezza, int altezza, long adessoMs)
    {
        var destinazione = IniziaScrittura(larghezza, altezza);
        nv12[..destinazione.Length].CopyTo(destinazione);
        ConcludiScrittura(adessoMs);
    }

    /// <summary>Cosa chiede la sorgente: le dimensioni del formato scelto dall'app e quando ha dato l'ultimo fotogramma.</summary>
    public (int Larghezza, int Altezza, long BattitoMs) Richiesta() =>
        ((int)U32(PosLarghezzaChiesta), (int)U32(PosAltezzaChiesta), Volatile.Read(ref *(long*)(inizio + PosBattitoSorgente)));

    /// <summary>Vero se un'app sta usando la webcam adesso.</summary>
    public bool InUso(long adessoMs)
    {
        var battito = Richiesta().BattitoMs;
        return battito != 0 && adessoMs - battito < NomiWebcam.InUsoMs;
    }

    // ── Chi legge (la sorgente) ────────────────────────────────────

    /// <summary>La sorgente dice le dimensioni che le servono e che una app sta ricevendo fotogrammi.</summary>
    public void SegnalaRichiesta(int larghezza, int altezza, long adessoMs)
    {
        ScriviU32(PosLarghezzaChiesta, (uint)larghezza);
        ScriviU32(PosAltezzaChiesta, (uint)altezza);
        Volatile.Write(ref *(long*)(inizio + PosBattitoSorgente), adessoMs);
        Interlocked.Increment(ref *(long*)(inizio + PosFotogrammiDati));
    }

    public long FotogrammiDati => Volatile.Read(ref *(long*)(inizio + PosFotogrammiDati));

    public long UltimoNumero => Volatile.Read(ref *(long*)(inizio + PosUltimo));

    /// <summary>
    /// Copia l'ultimo fotogramma completo in <paramref name="destinazione"/> (almeno larghezza × altezza × 3/2 byte
    /// del fotogramma). Falso se non c'è ancora nulla, se l'intestazione non è valida o se l'app riscrive di continuo
    /// lo stesso posto (allora si tiene il fotogramma di prima).
    /// </summary>
    public bool Leggi(Span<byte> destinazione, out InfoFotogramma info)
    {
        info = default;
        if (!Valido) return false;
        for (var tentativo = 0; tentativo < 3; tentativo++)
        {
            var numero = Volatile.Read(ref *(long*)(inizio + PosUltimo));
            if (numero <= 0) return false;
            var testa = IntestazionePosto(numero % NumeroPosti);
            var prima = Volatile.Read(ref *(long*)testa);
            if (prima != numero) continue;
            var larghezza = (int)*(uint*)(testa + 8);
            var altezza = (int)*(uint*)(testa + 12);
            var tempo = *(long*)(testa + 16);
            if (!DimensioniValide(larghezza, altezza)) return false;
            var byteFotogramma = FormatoWebcam.DimensioneNv12(larghezza, altezza);
            if (destinazione.Length < byteFotogramma) throw new ArgumentException("Destinazione troppo piccola", nameof(destinazione));
            new ReadOnlySpan<byte>(DatiPosto(numero % NumeroPosti), byteFotogramma).CopyTo(destinazione);
            Interlocked.MemoryBarrier();
            if (Volatile.Read(ref *(long*)testa) != prima) continue;
            info = new InfoFotogramma(numero, larghezza, altezza, tempo);
            return true;
        }
        return false;
    }

    /// <summary>Un fotogramma è fresco se l'app l'ha scritto meno di un secondo fa.</summary>
    public static bool Fresco(InfoFotogramma info, long adessoMs) =>
        info.Numero > 0 && adessoMs - info.TempoMs < NomiWebcam.FrescoMs;

    public static bool DimensioniValide(int larghezza, int altezza) =>
        larghezza > 0 && altezza > 0 && larghezza % 2 == 0 && altezza % 2 == 0
        && (long)FormatoWebcam.DimensioneNv12(larghezza, altezza) <= BytePerPosto;

    private static void ControllaDimensioni(int larghezza, int altezza)
    {
        if (!DimensioniValide(larghezza, altezza))
            throw new ArgumentException($"Dimensioni non valide per l'anello: {larghezza}×{altezza}");
    }

    private byte* IntestazionePosto(long posto) => inizio + PosIntestazioniPosti + posto * DimensioneIntestazionePosto;
    private byte* DatiPosto(long posto) => inizio + DimensioneIntestazione + posto * BytePerPosto;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    private uint U32(int posizione) => Volatile.Read(ref *(uint*)(inizio + posizione));

    private void ScriviU32(int posizione, uint valore) => Volatile.Write(ref *(uint*)(inizio + posizione), valore);

    private static int Arrotonda(int valore, int multiplo) => (valore + multiplo - 1) / multiplo * multiplo;
}
