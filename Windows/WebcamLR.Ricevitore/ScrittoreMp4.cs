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
/// <para>MP4 <b>frammentato</b> (1.0 beta 2, windows.md 1.3: mai perdere una registrazione), con la stessa disposizione di
/// ffmpeg con <c>-movflags frag_keyframe+empty_moov+default_base_moof</c>: <c>ftyp</c>, poi un <c>moov</c> senza campioni
/// (tabelle vuote e <c>mvex</c>/<c>trex</c>), poi una coppia <c>moof</c>+<c>mdat</c> per ogni frammento di almeno
/// <see cref="DurataFrammento"/>, che comincia sempre da un fotogramma chiave; alla chiusura normale <c>mfra</c>, l'indice
/// dei frammenti per la ricerca. Ogni frammento si scrive intero e poi si manda al disco: un file interrotto in qualsiasi
/// punto (crash, spegnimento, disco pieno) si legge fino all'ultimo frammento completo, e dopo un errore
/// <see cref="ChiudiDopoErrore"/> toglie il pezzo rimasto a metà.</para>
/// <para>Le unità NAL sono precedute dalla lunghezza su 4 byte al posto dei codici di inizio; parametri del codec e
/// delimitatori stanno nel record di configurazione (<c>avcC</c>/<c>hvcC</c>, voce <c>avc1</c>/<c>hvc1</c>), non nei
/// campioni. Tempi dai timestamp del telefono (microsecondi) in 90 kHz; l'iPhone non riordina i fotogrammi
/// (AllowFrameReordering spento), quindi l'ordine di decodifica è quello di presentazione e non servono scarti di
/// composizione. In memoria resta solo il frammento in corso: il telefono manda un fotogramma chiave almeno ogni 10 s,
/// quindi al massimo qualche decina di MB in 4K.</para>
/// </remarks>
public sealed class ScrittoreMp4
{
    public const int ScalaTempi = 90_000;
    private const uint ScalaFilmato = 1_000;
    private const uint Traccia = 1;

    /// <summary>Un frammento si chiude al primo fotogramma chiave dopo almeno questo tempo.</summary>
    public static readonly TimeSpan DurataFrammento = TimeSpan.FromSeconds(2);
    /// <summary>In 90 kHz, con 10 ms di tolleranza: 60 fotogrammi da 33 333 µs fanno 1,99998 s e valgono 2 s.</summary>
    private static readonly long DurataFrammentoInTempi = (long)(DurataFrammento.TotalSeconds * ScalaTempi) - ScalaTempi / 100;

    /// <summary>sample_flags di <c>trun</c> per un fotogramma chiave: non dipende da altri.</summary>
    public const uint FlagChiave = 0x0200_0000;
    /// <summary>sample_flags di <c>trun</c> per gli altri: dipende da altri, non è un punto da cui partire.</summary>
    public const uint FlagNonChiave = 0x0101_0000;

    private readonly Stream uscita;
    private readonly Codec codec;
    private readonly int larghezza;
    private readonly int altezza;
    private readonly ulong creazione;
    private ParametriVideo? parametri;
    private ulong primoTimestamp;
    private bool concluso;

    /// <summary>Byte mandati al flusso (anche un frammento rimasto a metà per un errore).</summary>
    private long scritti;
    /// <summary>Fine dell'ultimo pezzo scritto per intero: ftyp e moov, poi ogni frammento.</summary>
    private long fineSalvata;
    /// <summary>Fine dell'ultimo frammento completo, in 90 kHz.</summary>
    private long tempoSalvato;
    private uint frammentiScritti;
    private long ultimoTempo = -1;
    private long ultimoIntervallo = ScalaTempi / 30;
    private int campioni;

    /// <summary>Il frammento in corso: i dati del futuro mdat e, per ogni campione, dimensione, tempo e chiave.</summary>
    private readonly MemoryStream datiFrammento = new();
    private readonly List<(uint Dimensione, long Tempo, bool Chiave)> campioniFrammento = [];
    /// <summary>Per mfra: tempo d'inizio e posizione di ogni moof.</summary>
    private readonly List<(long Tempo, long Posizione)> indice = [];

    /// <param name="uscita">Uno stream scrivibile (un file). Se è un FileStream, ogni frammento si manda fino al disco.</param>
    /// <param name="larghezza">Misura del video dal messaggio «formato» del telefono.</param>
    /// <param name="creazione">Data di creazione scritta nel file.</param>
    public ScrittoreMp4(Stream uscita, Codec codec, int larghezza, int altezza, DateTime creazione)
    {
        if (!uscita.CanWrite) throw new ArgumentException("Serve uno stream scrivibile", nameof(uscita));
        this.uscita = uscita;
        this.codec = codec;
        this.larghezza = larghezza;
        this.altezza = altezza;
        // Secondi dal 1° gennaio 1904, come vuole il formato.
        this.creazione = (ulong)Math.Max(0, (creazione.ToUniversalTime() - new DateTime(1904, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds);
    }

    /// <summary>Fotogrammi accettati, anche quelli del frammento ancora in memoria.</summary>
    public int Campioni => campioni;

    /// <summary>Frammenti già scritti per intero nel file.</summary>
    public int Frammenti => (int)frammentiScritti;

    /// <summary>Circa i byte del file a fine registrazione: quelli scritti più il frammento in memoria.</summary>
    public long Byte => scritti + datiFrammento.Length;

    /// <summary>Byte del file che si leggono di sicuro: fino all'ultimo pezzo completo.</summary>
    public long ByteSalvati => fineSalvata;

    public ParametriVideo? Parametri => parametri;

    /// <summary>La durata del video ricevuto, dai timestamp del telefono (l'ultimo fotogramma dura quanto il precedente).</summary>
    public TimeSpan Durata => InSecondi(campioni == 0 ? 0 : ultimoTempo + ultimoIntervallo);

    /// <summary>La durata già nel file in frammenti completi: quella che resta anche se il computer si spegne adesso.</summary>
    public TimeSpan DurataSalvata => InSecondi(tempoSalvato);

    private static TimeSpan InSecondi(long tempi) => TimeSpan.FromSeconds((double)tempi / ScalaTempi);

    /// <summary>Un fotogramma Annex B come arriva dal telefono. Un errore del disco arriva come eccezione.</summary>
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

        // Tempi in 90 kHz dall'inizio, sempre crescenti (un timestamp fuori posto non rompe il file).
        var micro = timestampMicrosecondi >= primoTimestamp ? timestampMicrosecondi - primoTimestamp : 0;
        var tempo = (long)(micro * ScalaTempi / 1_000_000);
        if (ultimoTempo >= 0 && tempo <= ultimoTempo) tempo = ultimoTempo + 1;

        // Il campione: ogni unità con la sua lunghezza davanti, tranne parametri e delimitatori.
        var inizioCampione = datiFrammento.Length;
        uint dimensione = 0;
        Span<byte> lunghezza = stackalloc byte[4];
        foreach (var (inizio, quanti) in unita)
        {
            var nal = dati.Slice(inizio, quanti);
            if (ParametriVideo.FuoriDalCampione(codec, nal[0])) continue;
            BinaryPrimitives.WriteUInt32BigEndian(lunghezza, (uint)nal.Length);
            datiFrammento.Write(lunghezza);
            datiFrammento.Write(nal);
            dimensione += 4 + (uint)nal.Length;
        }
        if (dimensione == 0) return EsitoCampione.Scritto;

        // Un fotogramma chiave dopo almeno DurataFrammento chiude il frammento in corso: il nuovo comincia da lui.
        if (chiave && campioniFrammento.Count > 0 && tempo - campioniFrammento[0].Tempo >= DurataFrammentoInTempi)
        {
            var campione = datiFrammento.GetBuffer().AsSpan((int)inizioCampione, (int)dimensione).ToArray();
            datiFrammento.SetLength(inizioCampione);
            ScriviFrammento(tempo);
            datiFrammento.Write(campione);
        }

        if (ultimoTempo >= 0) ultimoIntervallo = tempo - ultimoTempo;
        ultimoTempo = tempo;
        campioniFrammento.Add((dimensione, tempo, chiave));
        campioni++;
        return EsitoCampione.Scritto;
    }

    /// <summary>
    /// Scrive l'ultimo frammento e l'indice <c>mfra</c>. Senza fotogrammi non scrive nulla (il file resta vuoto).
    /// Un errore del disco arriva come eccezione: allora <see cref="ChiudiDopoErrore"/>.
    /// </summary>
    public void Concludi()
    {
        if (concluso) return;
        concluso = true;
        if (parametri is null)
        {
            uscita.Flush();
            return;
        }
        if (campioniFrammento.Count > 0) ScriviFrammento(null);
        Scrivi(Mfra());
        Manda();
        fineSalvata = scritti;
    }

    /// <summary>
    /// Dopo un errore di scrittura (di solito il disco pieno): il file si ferma all'ultimo frammento completo, togliendo
    /// il pezzo scritto a metà, e non si scrive più. Restituisce la durata salvata. Se nemmeno il taglio riesce, il pezzo
    /// a metà resta in fondo: i lettori si fermano prima.
    /// </summary>
    public TimeSpan ChiudiDopoErrore()
    {
        concluso = true;
        datiFrammento.SetLength(0);
        campioniFrammento.Clear();
        try
        {
            if (uscita.CanSeek && uscita.Length > fineSalvata) uscita.SetLength(fineSalvata);
            scritti = fineSalvata;
        }
        catch (Exception errore) when (errore is IOException or NotSupportedException or UnauthorizedAccessException or ObjectDisposedException) { }
        return DurataSalvata;
    }

    private void ScriviInizio()
    {
        var s = new Scatole();
        s.Apri("ftyp");
        s.Tipo("iso5");
        s.U32(0x200);
        s.Tipo("iso5");
        s.Tipo("iso6");
        s.Tipo("mp41");
        s.Chiudi();
        Moov(s);
        Scrivi(s.Byte());
        Manda();
        fineSalvata = scritti;
    }

    /// <summary>
    /// Il frammento in memoria come <c>moof</c>+<c>mdat</c>. Ogni campione dura fino al successivo; l'ultimo fino a
    /// <paramref name="tempoDopo"/> (il fotogramma chiave del frammento dopo) o, alla fine, quanto il precedente.
    /// </summary>
    private void ScriviFrammento(long? tempoDopo)
    {
        var n = campioniFrammento.Count;
        var inizio = campioniFrammento[0].Tempo;
        var durate = new uint[n];
        for (var i = 0; i < n; i++)
        {
            var fine = i + 1 < n ? campioniFrammento[i + 1].Tempo
                : tempoDopo ?? campioniFrammento[i].Tempo + (i >= 1 ? campioniFrammento[i].Tempo - campioniFrammento[i - 1].Tempo : ultimoIntervallo);
            durate[i] = (uint)Math.Clamp(fine - campioniFrammento[i].Tempo, 1, uint.MaxValue);
        }
        var fineFrammento = campioniFrammento[^1].Tempo + durate[^1];

        var s = new Scatole();
        s.Apri("moof");
        s.ApriPiena("mfhd", 0, 0);
        s.U32(frammentiScritti + 1);       // sequence_number, da 1
        s.Chiudi();
        s.Apri("traf");
        s.ApriPiena("tfhd", 0, 0x020000);  // default-base-is-moof: gli scostamenti partono dall'inizio di moof
        s.U32(Traccia);
        s.Chiudi();
        s.ApriPiena("tfdt", 1, 0);
        s.U64((ulong)inizio);              // base_media_decode_time
        s.Chiudi();
        // data-offset, poi durata, dimensione e flag per ogni campione.
        s.ApriPiena("trun", 0, 0x000701);
        s.U32((uint)n);
        var posizioneScostamento = s.Posizione;
        s.U32(0);
        for (var i = 0; i < n; i++)
        {
            s.U32(durate[i]);
            s.U32(campioniFrammento[i].Dimensione);
            s.U32(campioniFrammento[i].Chiave ? FlagChiave : FlagNonChiave);
        }
        s.Chiudi(); // trun
        s.Chiudi(); // traf
        s.Chiudi(); // moof
        var moof = s.Byte();
        // I dati del primo campione: subito dopo moof e l'intestazione di mdat.
        BinaryPrimitives.WriteUInt32BigEndian(moof.AsSpan((int)posizioneScostamento), (uint)(moof.Length + 8));

        var posizioneMoof = scritti;
        Span<byte> intestazione = stackalloc byte[8];
        BinaryPrimitives.WriteUInt32BigEndian(intestazione, (uint)(8 + datiFrammento.Length));
        Encoding.ASCII.GetBytes("mdat", intestazione[4..]);
        Scrivi(moof);
        Scrivi(intestazione);
        Scrivi(datiFrammento.GetBuffer().AsSpan(0, (int)datiFrammento.Length));
        Manda();

        // Solo adesso il frammento è nel file per intero.
        fineSalvata = scritti;
        tempoSalvato = fineFrammento;
        frammentiScritti++;
        indice.Add((inizio, posizioneMoof));
        datiFrammento.SetLength(0);
        campioniFrammento.Clear();
    }

    private void Scrivi(ReadOnlySpan<byte> dati)
    {
        uscita.Write(dati);
        scritti += dati.Length;
    }

    /// <summary>Fino al disco, non solo a Windows: anche uno spegnimento lascia il frammento.</summary>
    private void Manda()
    {
        if (uscita is FileStream file) file.Flush(flushToDisk: true);
        else uscita.Flush();
    }

    /// <summary>Il moov iniziale: la descrizione della traccia, tabelle dei campioni vuote e mvex/trex.</summary>
    private void Moov(Scatole s)
    {
        s.Apri("moov");

        s.ApriPiena("mvhd", 1, 0);
        s.U64(creazione); s.U64(creazione);
        s.U32(ScalaFilmato);
        s.U64(0);          // durata: la dicono i frammenti
        s.U32(0x00010000); // velocità 1,0
        s.U16(0x0100);     // volume 1,0
        s.U16(0); s.U32(0); s.U32(0);
        Matrice(s);
        for (var i = 0; i < 6; i++) s.U32(0);
        s.U32(Traccia + 1); // prossimo numero di traccia
        s.Chiudi();

        s.Apri("trak");
        s.ApriPiena("tkhd", 1, 3); // attiva, nel filmato
        s.U64(creazione); s.U64(creazione);
        s.U32(Traccia); s.U32(0);
        s.U64(0);
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
        s.U64(0);
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
        // Tabelle vuote: i campioni sono nei frammenti.
        s.ApriPiena("stts", 0, 0); s.U32(0); s.Chiudi();
        s.ApriPiena("stsc", 0, 0); s.U32(0); s.Chiudi();
        s.ApriPiena("stsz", 0, 0); s.U32(0); s.U32(0); s.Chiudi();
        s.ApriPiena("stco", 0, 0); s.U32(0); s.Chiudi();
        s.Chiudi(); // stbl
        s.Chiudi(); // minf
        s.Chiudi(); // mdia
        s.Chiudi(); // trak

        s.Apri("mvex");
        s.ApriPiena("trex", 0, 0);
        s.U32(Traccia);
        s.U32(1);  // default_sample_description_index
        s.U32(0);  // durata, dimensione e flag predefiniti: ogni trun li porta campione per campione
        s.U32(0);
        s.U32(0);
        s.Chiudi();
        s.Chiudi(); // mvex

        s.Chiudi(); // moov
    }

    /// <summary>L'indice dei frammenti in fondo al file: tempo e posizione di ogni moof, tutti da un fotogramma chiave.</summary>
    private byte[] Mfra()
    {
        var s = new Scatole();
        s.Apri("mfra");
        s.ApriPiena("tfra", 1, 0);
        s.U32(Traccia);
        s.U32(0); // numeri di traf, trun e campione su un byte ciascuno
        s.U32((uint)indice.Count);
        foreach (var (tempo, posizione) in indice)
        {
            s.U64((ulong)tempo);
            s.U64((ulong)posizione);
            s.U8(1); s.U8(1); s.U8(1);
        }
        s.Chiudi();
        s.ApriPiena("mfro", 0, 0);
        var posizioneDimensione = s.Posizione;
        s.U32(0);
        s.Chiudi();
        s.Chiudi(); // mfra
        var mfra = s.Byte();
        BinaryPrimitives.WriteUInt32BigEndian(mfra.AsSpan((int)posizioneDimensione), (uint)mfra.Length);
        return mfra;
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

    private static void Matrice(Scatole s)
    {
        foreach (var v in new uint[] { 0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000 }) s.U32(v);
    }

    /// <summary>Costruisce scatole annidate in memoria, big-endian, sistemando le dimensioni alla chiusura.</summary>
    private sealed class Scatole
    {
        private readonly MemoryStream dati = new();
        private readonly Stack<long> aperte = new();

        public long Posizione => dati.Position;

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
