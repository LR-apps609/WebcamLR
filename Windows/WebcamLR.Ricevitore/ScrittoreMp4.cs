using System.Buffers.Binary;
using System.Text;
using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>Cosa è successo a un fotogramma dato allo <see cref="ScrittoreMp4"/>.</summary>
public enum EsitoCampione
{
    Scritto,
    /// <summary>Il file comincia da un fotogramma chiave con i parametri del codec: fino ad allora non si scrive nulla.</summary>
    InAttesaDiChiave,
    /// <summary>Parametri del codec diversi (misura, obiettivo, codec): il file va chiuso qui.</summary>
    FormatoCambiato,
}

/// <summary>
/// Scrive il video del telefono in un file MP4 così come arriva, già compresso (H.264 o HEVC): nessuna ricompressione,
/// quindi niente processore, niente scheda video e la qualità di partenza (P18, come il Mac con AVAssetWriter senza
/// impostazioni d'uscita). Solo C# (ISO/IEC 14496-12 e 14496-15), provato su Linux.
/// </summary>
/// <remarks>
/// Disposizione: <c>ftyp</c>, poi <c>mdat</c> con dimensione a 64 bit (sistemata alla fine) e i fotogrammi uno dopo
/// l'altro, con le unità NAL precedute dalla lunghezza su 4 byte al posto dei codici di inizio; alla chiusura
/// <c>moov</c> con una sola traccia video. Parametri del codec e delimitatori stanno nel record di configurazione
/// (<c>avcC</c>/<c>hvcC</c>, voce <c>avc1</c>/<c>hvc1</c>), non nei campioni. Tempi dai timestamp del telefono
/// (microsecondi) in 90 kHz; l'iPhone non riordina i fotogrammi (AllowFrameReordering spento), quindi l'ordine di
/// decodifica è quello di presentazione e non serve <c>ctts</c>. Un campione per blocco (<c>stco</c>, o <c>co64</c>
/// oltre i 4 GB). Le tabelle restano in memoria: circa 16 byte a fotogramma, 1,7 MB per un'ora a 30 fps.
/// </remarks>
public sealed class ScrittoreMp4
{
    public const int ScalaTempi = 90_000;
    private const uint ScalaFilmato = 1_000;

    private readonly Stream uscita;
    private readonly Codec codec;
    private readonly int larghezza;
    private readonly int altezza;
    private readonly ulong creazione;
    private ParametriVideo? parametri;
    private long inizioMdat = -1;
    private long scritti;
    private ulong primoTimestamp;
    private bool concluso;

    private readonly List<uint> dimensioni = [];
    private readonly List<long> posizioni = [];
    private readonly List<long> tempi = [];
    private readonly List<uint> chiavi = [];

    /// <param name="uscita">Uno stream scrivibile e con posizione (un file): alla fine si torna indietro a sistemare <c>mdat</c>.</param>
    /// <param name="larghezza">Misura del video dal messaggio «formato» del telefono.</param>
    /// <param name="creazione">Data di creazione scritta nel file.</param>
    public ScrittoreMp4(Stream uscita, Codec codec, int larghezza, int altezza, DateTime creazione)
    {
        if (!uscita.CanWrite || !uscita.CanSeek) throw new ArgumentException("Serve uno stream scrivibile e con posizione", nameof(uscita));
        this.uscita = uscita;
        this.codec = codec;
        this.larghezza = larghezza;
        this.altezza = altezza;
        // Secondi dal 1° gennaio 1904, come vuole il formato.
        this.creazione = (ulong)Math.Max(0, (creazione.ToUniversalTime() - new DateTime(1904, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds);
    }

    public int Campioni => dimensioni.Count;

    /// <summary>Byte scritti nel file finora.</summary>
    public long Byte => scritti;

    public ParametriVideo? Parametri => parametri;

    /// <summary>La durata del video scritto, dai timestamp del telefono (l'ultimo fotogramma dura quanto il precedente).</summary>
    public TimeSpan Durata => TimeSpan.FromSeconds((double)DurataInTempi() / ScalaTempi);

    /// <summary>Un fotogramma Annex B come arriva dal telefono.</summary>
    public EsitoCampione Aggiungi(ReadOnlySpan<byte> dati, bool chiave, ulong timestampMicrosecondi)
    {
        if (concluso) throw new InvalidOperationException("File già chiuso");
        var unita = AnnexB.Unita(dati);
        if (chiave)
        {
            var nuovi = ParametriVideo.Da(codec, dati, unita);
            if (parametri is null)
            {
                if (nuovi is null) return EsitoCampione.InAttesaDiChiave;
                parametri = nuovi;
                primoTimestamp = timestampMicrosecondi;
                ScriviInizio();
            }
            else if (nuovi is not null && !nuovi.Uguali(parametri))
            {
                return EsitoCampione.FormatoCambiato;
            }
        }
        if (parametri is null) return EsitoCampione.InAttesaDiChiave;

        // Il campione: ogni unità con la sua lunghezza davanti, tranne parametri e delimitatori.
        var posizione = scritti;
        uint dimensione = 0;
        Span<byte> lunghezza = stackalloc byte[4];
        foreach (var (inizio, quanti) in unita)
        {
            var nal = dati.Slice(inizio, quanti);
            if (ParametriVideo.FuoriDalCampione(codec, nal[0])) continue;
            BinaryPrimitives.WriteUInt32BigEndian(lunghezza, (uint)nal.Length);
            Scrivi(lunghezza);
            Scrivi(nal);
            dimensione += 4 + (uint)nal.Length;
        }
        if (dimensione == 0) return EsitoCampione.Scritto;

        // Tempi in 90 kHz dall'inizio, sempre crescenti (un timestamp fuori posto non rompe il file).
        var micro = timestampMicrosecondi >= primoTimestamp ? timestampMicrosecondi - primoTimestamp : 0;
        var tempo = (long)(micro * ScalaTempi / 1_000_000);
        if (tempi.Count > 0 && tempo <= tempi[^1]) tempo = tempi[^1] + 1;
        dimensioni.Add(dimensione);
        posizioni.Add(posizione);
        tempi.Add(tempo);
        if (chiave) chiavi.Add((uint)dimensioni.Count);
        return EsitoCampione.Scritto;
    }

    /// <summary>Scrive <c>moov</c> e la dimensione vera di <c>mdat</c>. Senza fotogrammi non scrive nulla (il file resta vuoto).</summary>
    public void Concludi()
    {
        if (concluso) return;
        concluso = true;
        if (inizioMdat < 0)
        {
            uscita.Flush();
            return;
        }
        var fineMdat = scritti;
        var moov = Moov();
        Scrivi(moov);
        // La dimensione di mdat (64 bit, dopo «1» e «mdat»).
        uscita.Position = inizioMdat + 8;
        Span<byte> dimensione = stackalloc byte[8];
        BinaryPrimitives.WriteUInt64BigEndian(dimensione, (ulong)(fineMdat - inizioMdat));
        uscita.Write(dimensione);
        uscita.Position = scritti;
        uscita.Flush();
    }

    private void ScriviInizio()
    {
        var ftyp = new Scatole();
        ftyp.Apri("ftyp");
        ftyp.Tipo("isom");
        ftyp.U32(0x200);
        ftyp.Tipo("isom");
        ftyp.Tipo("iso2");
        if (codec == Codec.H264) ftyp.Tipo("avc1");
        ftyp.Tipo("mp41");
        ftyp.Chiudi();
        Scrivi(ftyp.Byte());
        inizioMdat = scritti;
        // size = 1: la dimensione vera è nei 64 bit dopo il tipo, scritti alla fine.
        var mdat = new Scatole();
        mdat.U32(1);
        mdat.Tipo("mdat");
        mdat.U64(0);
        Scrivi(mdat.Byte());
    }

    private void Scrivi(ReadOnlySpan<byte> dati)
    {
        uscita.Write(dati);
        scritti += dati.Length;
    }

    private long DurataInTempi()
    {
        if (tempi.Count == 0) return 0;
        return tempi[^1] - tempi[0] + UltimoIntervallo();
    }

    private long UltimoIntervallo() => tempi.Count >= 2 ? tempi[^1] - tempi[^2] : ScalaTempi / 30;

    private byte[] Moov()
    {
        var durataMedia = (ulong)DurataInTempi();
        var durataFilmato = durataMedia * ScalaFilmato / ScalaTempi;
        var s = new Scatole();
        s.Apri("moov");

        s.ApriPiena("mvhd", 1, 0);
        s.U64(creazione); s.U64(creazione);
        s.U32(ScalaFilmato);
        s.U64(durataFilmato);
        s.U32(0x00010000); // velocità 1,0
        s.U16(0x0100);     // volume 1,0
        s.U16(0); s.U32(0); s.U32(0);
        Matrice(s);
        for (var i = 0; i < 6; i++) s.U32(0);
        s.U32(2);          // prossimo numero di traccia
        s.Chiudi();

        s.Apri("trak");
        s.ApriPiena("tkhd", 1, 3); // attiva, nel filmato
        s.U64(creazione); s.U64(creazione);
        s.U32(1); s.U32(0);
        s.U64(durataFilmato);
        s.U32(0); s.U32(0);
        s.U16(0); s.U16(0); s.U16(0); s.U16(0); // livello, gruppo, volume (video: 0), riservato
        Matrice(s);
        s.U32((uint)larghezza << 16);
        s.U32((uint)altezza << 16);
        s.Chiudi();

        s.Apri("mdia");
        s.ApriPiena("mdhd", 1, 0);
        s.U64(creazione); s.U64(creazione);
        s.U32(ScalaTempi);
        s.U64(durataMedia);
        s.U16(0x55C4); // «und»
        s.U16(0);
        s.Chiudi();

        s.ApriPiena("hdlr", 0, 0);
        s.U32(0);
        s.Tipo("vide");
        s.U32(0); s.U32(0); s.U32(0);
        s.Testo("WebcamLR");
        s.Chiudi();

        s.Apri("minf");
        s.ApriPiena("vmhd", 0, 1);
        s.U16(0); s.U16(0); s.U16(0); s.U16(0);
        s.Chiudi();
        s.Apri("dinf");
        s.ApriPiena("dref", 0, 0);
        s.U32(1);
        s.ApriPiena("url ", 0, 1); // i dati sono in questo file
        s.Chiudi();
        s.Chiudi();
        s.Chiudi();

        s.Apri("stbl");
        Stsd(s);

        s.ApriPiena("stts", 0, 0);
        var corse = Corse();
        s.U32((uint)corse.Count);
        foreach (var (quanti, intervallo) in corse) { s.U32(quanti); s.U32(intervallo); }
        s.Chiudi();

        s.ApriPiena("stss", 0, 0);
        s.U32((uint)chiavi.Count);
        foreach (var numero in chiavi) s.U32(numero);
        s.Chiudi();

        s.ApriPiena("stsc", 0, 0);
        s.U32(1);
        s.U32(1); s.U32(1); s.U32(1); // dal primo blocco: un campione per blocco, descrizione 1
        s.Chiudi();

        s.ApriPiena("stsz", 0, 0);
        s.U32(0);
        s.U32((uint)dimensioni.Count);
        foreach (var d in dimensioni) s.U32(d);
        s.Chiudi();

        var grande = posizioni.Count > 0 && posizioni[^1] > uint.MaxValue;
        s.ApriPiena(grande ? "co64" : "stco", 0, 0);
        s.U32((uint)posizioni.Count);
        foreach (var p in posizioni)
        {
            if (grande) s.U64((ulong)p); else s.U32((uint)p);
        }
        s.Chiudi();

        s.Chiudi(); // stbl
        s.Chiudi(); // minf
        s.Chiudi(); // mdia
        s.Chiudi(); // trak
        s.Chiudi(); // moov
        return s.Byte();
    }

    private void Stsd(Scatole s)
    {
        s.ApriPiena("stsd", 0, 0);
        s.U32(1);
        s.Apri(codec == Codec.Hevc ? "hvc1" : "avc1");
        for (var i = 0; i < 6; i++) s.U8(0);
        s.U16(1);                  // data_reference_index
        s.U16(0); s.U16(0);
        s.U32(0); s.U32(0); s.U32(0);
        s.U16((ushort)larghezza);
        s.U16((ushort)altezza);
        s.U32(0x00480000); s.U32(0x00480000); // 72 dpi
        s.U32(0);
        s.U16(1);                  // un fotogramma per campione
        var nome = new byte[32];
        var testo = Encoding.ASCII.GetBytes("WebcamLR");
        nome[0] = (byte)testo.Length;
        testo.CopyTo(nome, 1);
        s.Byte(nome);
        s.U16(0x0018);             // profondità: colore
        s.U16(0xFFFF);
        s.Apri(codec == Codec.Hevc ? "hvcC" : "avcC");
        s.Byte(parametri!.RecordConfigurazione());
        s.Chiudi();
        s.Apri("pasp");            // pixel quadrati
        s.U32(1); s.U32(1);
        s.Chiudi();
        s.Chiudi();
        s.Chiudi();
    }

    /// <summary>Le durate dei campioni raggruppate per stts: (quanti campioni, durata di ciascuno).</summary>
    private List<(uint Quanti, uint Intervallo)> Corse()
    {
        var corse = new List<(uint, uint)>();
        for (var i = 0; i < tempi.Count; i++)
        {
            var intervallo = (uint)Math.Min(uint.MaxValue, i + 1 < tempi.Count ? tempi[i + 1] - tempi[i] : UltimoIntervallo());
            if (corse.Count > 0 && corse[^1].Item2 == intervallo) corse[^1] = (corse[^1].Item1 + 1, intervallo);
            else corse.Add((1, intervallo));
        }
        return corse;
    }

    private static void Matrice(Scatole s)
    {
        foreach (var v in new uint[] { 0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000 }) s.U32(v);
    }

    /// <summary>Costruisce scatole annidate in memoria, big-endian, sistemando le dimensioni alla chiusura.</summary>
    private sealed class Scatole
    {
        private readonly MemoryStream dati = new();
        private readonly Stack<long> aperte = new();

        public void Apri(string tipo)
        {
            aperte.Push(dati.Position);
            U32(0);
            Tipo(tipo);
        }

        public void ApriPiena(string tipo, byte versione, uint flag)
        {
            Apri(tipo);
            U32(((uint)versione << 24) | (flag & 0xFFFFFF));
        }

        public void Chiudi()
        {
            var inizio = aperte.Pop();
            var fine = dati.Position;
            dati.Position = inizio;
            U32((uint)(fine - inizio));
            dati.Position = fine;
        }

        public void Tipo(string tipo) => dati.Write(Encoding.ASCII.GetBytes(tipo));
        public void Testo(string testo) { dati.Write(Encoding.UTF8.GetBytes(testo)); dati.WriteByte(0); }
        public void U8(byte v) => dati.WriteByte(v);
        public void Byte(byte[] v) => dati.Write(v);

        public void U16(ushort v)
        {
            Span<byte> b = stackalloc byte[2];
            BinaryPrimitives.WriteUInt16BigEndian(b, v);
            dati.Write(b);
        }

        public void U32(uint v)
        {
            Span<byte> b = stackalloc byte[4];
            BinaryPrimitives.WriteUInt32BigEndian(b, v);
            dati.Write(b);
        }

        public void U64(ulong v)
        {
            Span<byte> b = stackalloc byte[8];
            BinaryPrimitives.WriteUInt64BigEndian(b, v);
            dati.Write(b);
        }

        public byte[] Byte() => dati.ToArray();
    }
}
