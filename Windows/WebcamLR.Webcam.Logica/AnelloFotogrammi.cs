using System.Diagnostics;
using System.Runtime.CompilerServices;

namespace WebcamLR.Webcam;

/// <summary>Un fotogramma letto dall'anello.</summary>
/// <param name="Numero">Cresce di uno a ogni fotogramma scritto dall'app; 0 non esiste.</param>
/// <param name="TempoMs">Quando l'app l'ha scritto, in millisecondi dall'avvio di Windows (Environment.TickCount64, uguale per tutti i processi).</param>
/// <param name="IstanteTick">Lo stesso istante, preciso (Stopwatch.GetTimestamp, uguale per tutti i processi); 0 se l'app non lo scrive.</param>
public readonly record struct InfoFotogramma(long Numero, int Larghezza, int Altezza, long TempoMs, long IstanteTick = 0);

/// <summary>
/// L'anello di fotogrammi nella memoria condivisa tra l'app (scrive) e la sorgente della webcam (legge).
/// Si lavora su un puntatore: nella webcam è la vista di «Global\WebcamLR.Video», nei test un array fissato.
/// </summary>
/// <remarks>
/// Disposizione (little endian, tutti i campi allineati):
/// <code>
///   0  u32 magia «WLRV» (0x56524C57)        4  u32 versione (2)
///   8  u32 numero di posti (3)              12  u32 byte per posto
///  16  i64 numero dell'ultimo fotogramma completo (0 = nessuno)
///  24  i64 battito dell'app: ms dell'ultima scrittura
///  32  u32 larghezza chiesta dalla sorgente 36  u32 altezza chiesta dalla sorgente
///  40  i64 battito della sorgente: ms dell'ultimo fotogramma dato a un'app (webcam in uso)
///  48  i64 fotogrammi dati alle app (solo per la diagnosi)
///  56  u32 fotogrammi al secondo chiesti dalla sorgente (30 o 60)
///  64 + 64·i  posto i: i64 versione (-1 mentre l'app scrive, poi il numero del fotogramma),
///             u32 larghezza, u32 altezza, i64 ms di scrittura,
///             i64 istante preciso della scrittura (Stopwatch, uguale per tutti i processi; 0 = app che non lo scrive)
/// 256 u32 stato della schermata di attesa (StatoAttesa)   260 u32 stile (StileAttesa)
/// 264 i64 battito dello stato: ms dell'ultima ImpostaAttesa dell'app (0 = WebcamLR chiusa)
/// 272 u32 lingua (LinguaAttesa)
/// 280 i64 versione dell'immagine personale (0 = nessuna, -1 mentre l'app scrive)
/// 288 u32 larghezza dell'immagine personale              292 u32 altezza
/// 296 i64 attesa nella sorgente: µs dalla scrittura dell'app alla consegna a un'app di chiamata (mediana di un secondo)
/// 304 i64 istante preciso (Stopwatch) in cui la sorgente ha scritto l'attesa (0 = sorgente che non la scrive)
/// 4096 + i·byte per posto: i dati NV12 del posto i, righe senza margine (passo = larghezza)
/// 4096 + 3·byte per posto: l'immagine personale in NV12, al massimo 1920×1080
/// </code>
/// I posti sono grandi per il 4K (3840×2160 NV12, 12,4 MB): con tre posti la memoria è di circa 37 MB, presa una
/// volta sola dalla sorgente; Windows dà le pagine solo quando si scrivono, quindi a 1080p se ne usa un quarto.
/// Versione 2 (P12): posti da 4K e fps chiesti. Versione 3: stato, stile e lingua della schermata di attesa e
/// l'immagine personale. Con una sorgente o un'app di un'altra versione l'intestazione non è valida e non si scambia
/// nulla (la webcam mostra l'immagine di attesa) finché la webcam non è reinstallata. L'istante preciso dei posti e
/// l'attesa nella sorgente (27 ottobre, per il ritardo «da vetro a uscita») stanno in byte che le versioni di prima
/// lasciano a zero: niente versione nuova, chi non li conosce non li tocca e chi li conosce legge 0 = «non si sa».
/// Il fotogramma n va nel posto n mod 3. Chi legge controlla la versione del posto prima e dopo la copia:
/// se è cambiata, l'app ha riscritto il posto nel frattempo e si riprova (come un seqlock).
/// </remarks>
public sealed unsafe class AnelloFotogrammi
{
    public const uint Magia = 0x56524C57;
    public const uint Versione = 3;
    public const int NumeroPosti = 3;
    public const int DimensioneIntestazione = 4096;
    /// <summary>NV12 3840×2160 (il formato più grande) arrotondato a 4 KB.</summary>
    public static readonly int BytePerPosto = Arrotonda(FormatiWebcam.Massimo.Byte, 4096);
    /// <summary>L'immagine personale della schermata di attesa: NV12 fino a 1920×1080, arrotondato a 4 KB.</summary>
    public static readonly int ByteImmagine = Arrotonda(FormatoWebcam.DimensioneNv12(LarghezzaMassimaImmagine, AltezzaMassimaImmagine), 4096);
    public const int LarghezzaMassimaImmagine = 1920;
    public const int AltezzaMassimaImmagine = 1080;
    public static long DimensioneTotale => DimensioneIntestazione + (long)NumeroPosti * BytePerPosto + ByteImmagine;

    private const int PosMagia = 0, PosVersione = 4, PosPosti = 8, PosBytePosto = 12;
    private const int PosUltimo = 16, PosBattitoApp = 24, PosLarghezzaChiesta = 32, PosAltezzaChiesta = 36;
    private const int PosBattitoSorgente = 40, PosFotogrammiDati = 48, PosFpsChiesti = 56;
    private const int PosIntestazioniPosti = 64, DimensioneIntestazionePosto = 64;
    private const int PosStatoAttesa = 256, PosStileAttesa = 260, PosBattitoStato = 264, PosLingua = 272;
    private const int PosVersioneImmagine = 280, PosLarghezzaImmagine = 288, PosAltezzaImmagine = 292;
    private const int PosAttesaSorgente = 296, PosIstanteAttesa = 304;

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
    /// <param name="istanteTick">L'istante preciso (Stopwatch); 0 = adesso.</param>
    public void ConcludiScrittura(long adessoMs, long istanteTick = 0)
    {
        if (postoInScrittura < 0) throw new InvalidOperationException("Nessuna scrittura in corso");
        var numero = numeroScritto + 1;
        var testa = IntestazionePosto(postoInScrittura);
        *(long*)(testa + 16) = adessoMs;
        *(long*)(testa + 24) = istanteTick != 0 ? istanteTick : Stopwatch.GetTimestamp();
        Volatile.Write(ref *(long*)testa, numero);
        Volatile.Write(ref *(long*)(inizio + PosUltimo), numero);
        Volatile.Write(ref *(long*)(inizio + PosBattitoApp), adessoMs);
        numeroScritto = numero;
        postoInScrittura = -1;
    }

    /// <summary>Scrive un fotogramma già pronto (nei test e quando non serve convertire sul posto).</summary>
    public void Scrivi(ReadOnlySpan<byte> nv12, int larghezza, int altezza, long adessoMs, long istanteTick = 0)
    {
        var destinazione = IniziaScrittura(larghezza, altezza);
        nv12[..destinazione.Length].CopyTo(destinazione);
        ConcludiScrittura(adessoMs, istanteTick);
    }

    /// <summary>Cosa chiede la sorgente: le dimensioni del formato scelto dall'app e quando ha dato l'ultimo fotogramma.</summary>
    public (int Larghezza, int Altezza, long BattitoMs) Richiesta() =>
        ((int)U32(PosLarghezzaChiesta), (int)U32(PosAltezzaChiesta), Volatile.Read(ref *(long*)(inizio + PosBattitoSorgente)));

    /// <summary>I fotogrammi al secondo del formato scelto da un'app (0 se nessuna l'ha ancora aperta).</summary>
    public int FpsChiesti => (int)U32(PosFpsChiesti);

    /// <summary>Vero se un'app sta usando la webcam adesso.</summary>
    public bool InUso(long adessoMs)
    {
        var battito = Richiesta().BattitoMs;
        return battito != 0 && adessoMs - battito < NomiWebcam.InUsoMs;
    }

    // ── Schermata di attesa: l'app scrive, la webcam legge ─────────

    /// <summary>
    /// L'app dice alla webcam perché il video non c'è, con quale stile e in che lingua. Va chiamata appena qualcosa
    /// cambia e comunque almeno una volta al secondo (fa da battito): se non arriva per <see cref="NomiWebcam.StatoAppMs"/>,
    /// la webcam considera WebcamLR chiusa e, dopo 2 secondi con l'ultima immagine, mostra «La webcam non è collegata».
    /// </summary>
    public void ImpostaAttesa(StatoAttesa stato, StileAttesa stile, LinguaAttesa lingua, long adessoMs)
    {
        ScriviU32(PosStatoAttesa, (uint)stato);
        ScriviU32(PosStileAttesa, (uint)stile);
        ScriviU32(PosLingua, (uint)lingua);
        Volatile.Write(ref *(long*)(inizio + PosBattitoStato), Math.Max(1, adessoMs));
    }

    /// <summary>WebcamLR si chiude: la webcam tiene l'ultima immagine 2 secondi e poi mostra «La webcam non è collegata».</summary>
    public void SegnalaChiusura()
    {
        ScriviU32(PosStatoAttesa, (uint)StatoAttesa.NonCollegata);
        Volatile.Write(ref *(long*)(inizio + PosBattitoStato), 0);
    }

    /// <summary>Quello che l'app ha scritto con <see cref="ImpostaAttesa"/>; battito 0 se non ha mai scritto o si è chiusa.</summary>
    public (StatoAttesa Stato, StileAttesa Stile, LinguaAttesa Lingua, long BattitoMs) LeggiAttesa()
    {
        var stato = U32(PosStatoAttesa);
        var stile = U32(PosStileAttesa);
        var lingua = U32(PosLingua);
        return (stato <= (uint)StatoAttesa.Pausa ? (StatoAttesa)stato : StatoAttesa.NonCollegata,
            stile <= (uint)StileAttesa.Sfocata ? (StileAttesa)stile : StileAttesa.WebcamLR,
            lingua <= (uint)LinguaAttesa.Inglese ? (LinguaAttesa)lingua : LinguaAttesa.Automatica,
            Volatile.Read(ref *(long*)(inizio + PosBattitoStato)));
    }

    /// <summary>Vero se WebcamLR ha scritto il suo stato da poco.</summary>
    public static bool AppViva(long battitoMs, long adessoMs) => battitoMs > 0 && adessoMs - battitoMs < NomiWebcam.StatoAppMs;

    /// <summary>
    /// L'immagine personale dello stile <see cref="StileAttesa.Immagine"/>, in NV12, al massimo
    /// <see cref="LarghezzaMassimaImmagine"/>×<see cref="AltezzaMassimaImmagine"/> (misure pari): la webcam non può
    /// leggere i file dell'utente (Frame Server gira come LocalService). Va riscritta ogni volta che l'app apre la memoria
    /// condivisa: la webcam la crea vuota quando Windows la carica. Per un'immagine BGRA c'è <see cref="ScriviImmaginePersonaleBgra"/>.
    /// </summary>
    public void ScriviImmaginePersonale(ReadOnlySpan<byte> nv12, int larghezza, int altezza)
    {
        if (larghezza <= 0 || altezza <= 0 || larghezza % 2 != 0 || altezza % 2 != 0
            || larghezza > LarghezzaMassimaImmagine || altezza > AltezzaMassimaImmagine)
            throw new ArgumentException($"Immagine personale non valida: {larghezza}×{altezza} (pari, al massimo {LarghezzaMassimaImmagine}×{AltezzaMassimaImmagine})");
        var byteImmagine = FormatoWebcam.DimensioneNv12(larghezza, altezza);
        if (nv12.Length < byteImmagine) throw new ArgumentException("Immagine personale troppo corta", nameof(nv12));
        var versione = Math.Max(0, Volatile.Read(ref *(long*)(inizio + PosVersioneImmagine)));
        Volatile.Write(ref *(long*)(inizio + PosVersioneImmagine), -1);
        Interlocked.MemoryBarrier();
        ScriviU32(PosLarghezzaImmagine, (uint)larghezza);
        ScriviU32(PosAltezzaImmagine, (uint)altezza);
        nv12[..byteImmagine].CopyTo(new Span<byte>(DatiImmagine, byteImmagine));
        Volatile.Write(ref *(long*)(inizio + PosVersioneImmagine), versione + 1);
    }

    /// <summary>
    /// Come <see cref="ScriviImmaginePersonale"/> da un'immagine BGRA (come la dà Windows), rimpicciolita se serve
    /// per stare in 1920×1080 con le proporzioni giuste. La webcam la adatta poi a ogni formato riempiendo il riquadro.
    /// </summary>
    public void ScriviImmaginePersonaleBgra(ReadOnlySpan<byte> bgra, int larghezza, int altezza, int passo)
    {
        var scala = Math.Min(1.0, Math.Min((double)LarghezzaMassimaImmagine / larghezza, (double)AltezzaMassimaImmagine / altezza));
        var l = Math.Max(2, (int)(larghezza * scala) & ~1);
        var a = Math.Max(2, (int)(altezza * scala) & ~1);
        var nv12 = new byte[FormatoWebcam.DimensioneNv12(l, a)];
        ConversioneVideo.BgraInNv12(bgra, larghezza, altezza, passo, Riquadro.Intero(larghezza, altezza), nv12, l, a, Riquadro.Intero(l, a), specchia: false);
        ScriviImmaginePersonale(nv12, l, a);
    }

    /// <summary>Toglie l'immagine personale: lo stile «immagine» torna al disegno di WebcamLR.</summary>
    public void TogliImmaginePersonale() => Volatile.Write(ref *(long*)(inizio + PosVersioneImmagine), 0);

    /// <summary>La versione dell'immagine personale: 0 se non c'è, cresce a ogni scrittura. Costa una lettura.</summary>
    public long VersioneImmagine => Volatile.Read(ref *(long*)(inizio + PosVersioneImmagine));

    /// <summary>Copia l'immagine personale; null se non c'è o se l'app la sta riscrivendo proprio adesso (si riprova dopo).</summary>
    public (ImmagineNv12 Immagine, long Versione)? LeggiImmaginePersonale()
    {
        var prima = Volatile.Read(ref *(long*)(inizio + PosVersioneImmagine));
        if (prima <= 0) return null;
        var larghezza = (int)U32(PosLarghezzaImmagine);
        var altezza = (int)U32(PosAltezzaImmagine);
        if (larghezza <= 0 || altezza <= 0 || larghezza % 2 != 0 || altezza % 2 != 0
            || larghezza > LarghezzaMassimaImmagine || altezza > AltezzaMassimaImmagine) return null;
        var dati = new ReadOnlySpan<byte>(DatiImmagine, FormatoWebcam.DimensioneNv12(larghezza, altezza)).ToArray();
        Interlocked.MemoryBarrier();
        if (Volatile.Read(ref *(long*)(inizio + PosVersioneImmagine)) != prima) return null;
        return (new ImmagineNv12(larghezza, altezza, dati), prima);
    }

    private byte* DatiImmagine => inizio + DimensioneIntestazione + (long)NumeroPosti * BytePerPosto;

    // ── Chi legge (la sorgente) ────────────────────────────────────

    /// <summary>La sorgente dice le dimensioni che le servono e che una app sta ricevendo fotogrammi.</summary>
    public void SegnalaRichiesta(int larghezza, int altezza, long adessoMs, int fps = 30)
    {
        ScriviU32(PosLarghezzaChiesta, (uint)larghezza);
        ScriviU32(PosAltezzaChiesta, (uint)altezza);
        ScriviU32(PosFpsChiesti, (uint)fps);
        Volatile.Write(ref *(long*)(inizio + PosBattitoSorgente), adessoMs);
        Interlocked.Increment(ref *(long*)(inizio + PosFotogrammiDati));
    }

    public long FotogrammiDati => Volatile.Read(ref *(long*)(inizio + PosFotogrammiDati));

    /// <summary>La sorgente scrive quanto aspetta un fotogramma dell'app prima della consegna (µs), una volta al secondo.</summary>
    public void ScriviAttesaSorgente(long microsecondi, long adessoTick)
    {
        Volatile.Write(ref *(long*)(inizio + PosAttesaSorgente), Math.Max(0, microsecondi));
        Volatile.Write(ref *(long*)(inizio + PosIstanteAttesa), adessoTick);
    }

    /// <summary>
    /// L'attesa nella sorgente (µs) scritta da meno di 2 secondi; null se la sorgente non la scrive (versione di prima,
    /// o nessuna app usa la webcam).
    /// </summary>
    public long? AttesaSorgente(long adessoTick, long frequenza)
    {
        var istante = Volatile.Read(ref *(long*)(inizio + PosIstanteAttesa));
        if (istante == 0 || adessoTick - istante > 2 * frequenza || adessoTick < istante) return null;
        return Volatile.Read(ref *(long*)(inizio + PosAttesaSorgente));
    }

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
            var istante = *(long*)(testa + 24);
            if (!DimensioniValide(larghezza, altezza)) return false;
            var byteFotogramma = FormatoWebcam.DimensioneNv12(larghezza, altezza);
            if (destinazione.Length < byteFotogramma) throw new ArgumentException("Destinazione troppo piccola", nameof(destinazione));
            new ReadOnlySpan<byte>(DatiPosto(numero % NumeroPosti), byteFotogramma).CopyTo(destinazione);
            Interlocked.MemoryBarrier();
            if (Volatile.Read(ref *(long*)testa) != prima) continue;
            info = new InfoFotogramma(numero, larghezza, altezza, tempo, istante);
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
