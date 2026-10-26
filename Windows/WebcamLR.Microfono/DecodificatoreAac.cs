using System.Runtime.InteropServices;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR.Microfono;

/// <summary>
/// Il decodificatore AAC-LC di Windows (Media Foundation, «Microsoft AAC Audio Decoder MFT», CLSID_CMSAACDecMFT): un
/// componente di sistema, nessuna libreria esterna. Riceve un frame AAC grezzo alla volta (senza ADTS, come nel
/// protocollo) e dà campioni float. La configurazione del telefono (AudioSpecificConfig) va nel tipo d'ingresso come
/// chiede la documentazione di Microsoft («AAC Decoder»): MF_MT_USER_DATA = la parte di HEAACWAVEINFO dopo WAVEFORMATEX
/// (12 byte) seguita dall'AudioSpecificConfig.
/// Non è sicuro fra thread: lo usa solo MicrofonoTelefono, sotto il suo blocco.
/// </summary>
public sealed unsafe class DecodificatoreAac : IDecodificatoreAudio
{
    private static readonly Guid ClsidDecodificatoreAac = new("32d186a7-218f-4c75-8876-dd77273a8999");
    private static readonly Guid MF_MT_MAJOR_TYPE = new("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    private static readonly Guid MF_MT_SUBTYPE = new("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    private static readonly Guid MF_MT_AUDIO_NUM_CHANNELS = new("37e48bf5-645e-4c5b-89de-ada9e29b696a");
    private static readonly Guid MF_MT_AUDIO_SAMPLES_PER_SECOND = new("5faeeae7-0290-4c31-9e8a-c534f68d9dba");
    private static readonly Guid MF_MT_AUDIO_BITS_PER_SAMPLE = new("f2deb57f-40fa-4764-aa33-ed4f2d1ff669");
    private static readonly Guid MF_MT_AAC_PAYLOAD_TYPE = new("bfbabe79-7434-4d1c-94f0-72a3b9e17188");
    private static readonly Guid MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION = new("7632f0e6-9538-4d61-acda-ea29c8c14456");
    private static readonly Guid MF_MT_USER_DATA = new("b6bc765f-4c3b-40a4-bd51-2535b66fe09d");
    private static readonly Guid MFMediaType_Audio = new("73647561-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFAudioFormat_AAC = new("00001610-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFAudioFormat_Float = new("00000003-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFAudioFormat_PCM = new("00000001-0000-0010-8000-00aa00389b71");

    private const uint MF_VERSION = 0x00020070;
    private const uint MFSTARTUP_LITE = 1;
    private const int MF_E_TRANSFORM_NEED_MORE_INPUT = unchecked((int)0xC00D6D72);
    private const int MF_E_TRANSFORM_STREAM_CHANGE = unchecked((int)0xC00D6D61);
    private const int MF_E_NOTACCEPTING = unchecked((int)0xC00D36B5);
    private const uint MFT_MESSAGE_NOTIFY_BEGIN_STREAMING = 0x10000000;
    private const uint MFT_MESSAGE_NOTIFY_START_OF_STREAM = 0x10000003;
    private const uint MFT_MESSAGE_COMMAND_FLUSH = 0;
    private const uint MFT_OUTPUT_STREAM_PROVIDES_SAMPLES = 0x100;
    /// <summary>Un frame AAC dura 1024 campioni: 21,33 ms in unità da 100 ns a 48 kHz (solo per i tempi del campione).</summary>
    private const long DurataFrame = 213_333;
    private const int SpazioIngresso = 8_192;

    private readonly IMFTransform trasformazione = null!;
    private readonly IMFSample campioneIngresso = null!;
    private readonly IMFMediaBuffer bufferIngresso = null!;
    private IMFSample? campioneUscita;
    private IMFMediaBuffer? bufferUscita;
    private nint puntatoreUscita;
    private bool forniscePropri;
    private bool inFloat;
    private long tempo;
    private bool chiuso;

    public int Frequenza { get; private set; }
    public int Canali { get; private set; }

    /// <summary>Un decodificatore per il formato del telefono, oppure null (codec diverso da AAC-LC, o Windows dice di no).</summary>
    public static DecodificatoreAac? Crea(FormatoAudio formato)
    {
        if (formato.Codec != FormatoAudio.AacLC) return null;
        try { return new DecodificatoreAac(formato); }
        catch (Exception errore) when (errore is COMException or InvalidCastException or ArgumentException or TypeLoadException)
        {
            return null;
        }
    }

    private DecodificatoreAac(FormatoAudio formato)
    {
        Controlla(MFStartup(MF_VERSION, MFSTARTUP_LITE));
        try
        {
            var tipo = Type.GetTypeFromCLSID(ClsidDecodificatoreAac, throwOnError: true)!;
            trasformazione = (IMFTransform)Activator.CreateInstance(tipo)!;

            var frequenza = formato.Frequenza > 0 ? formato.Frequenza : 48_000;
            var canali = Math.Max(1, formato.Canali);
            Controlla(MFCreateMediaType(out var ingresso));
            try
            {
                ImpostaGuid(ingresso, MF_MT_MAJOR_TYPE, MFMediaType_Audio);
                ImpostaGuid(ingresso, MF_MT_SUBTYPE, MFAudioFormat_AAC);
                ImpostaIntero(ingresso, MF_MT_AUDIO_SAMPLES_PER_SECOND, (uint)frequenza);
                ImpostaIntero(ingresso, MF_MT_AUDIO_NUM_CHANNELS, (uint)canali);
                // 0 = flusso grezzo (raw AAC), un frame per campione: proprio i pacchetti di tipo 3.
                ImpostaIntero(ingresso, MF_MT_AAC_PAYLOAD_TYPE, 0);
                // 0x29 = AAC Profile L2, il valore predefinito della documentazione: copre AAC-LC fino a 48 kHz stereo.
                ImpostaIntero(ingresso, MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29);
                var datiUtente = DatiUtente(formato.Configurazione);
                var bloccati = GCHandle.Alloc(datiUtente, GCHandleType.Pinned);
                try
                {
                    var chiave = MF_MT_USER_DATA;
                    Controlla(ingresso.SetBlob(ref chiave, bloccati.AddrOfPinnedObject(), (uint)datiUtente.Length));
                }
                finally { bloccati.Free(); }
                Controlla(trasformazione.SetInputType(0, ingresso, 0));
            }
            finally { Marshal.ReleaseComObject(ingresso); }

            ScegliUscita();

            Controlla(MFCreateSample(out campioneIngresso));
            Controlla(MFCreateMemoryBuffer(SpazioIngresso, out bufferIngresso));
            Controlla(campioneIngresso.AddBuffer(bufferIngresso));
            trasformazione.ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
            trasformazione.ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
        }
        catch
        {
            Libera();
            throw;
        }
    }

    public int Decodifica(ReadOnlySpan<byte> frame, Span<float> uscita)
    {
        if (chiuso || frame.IsEmpty || frame.Length > SpazioIngresso) return -1;
        Controlla(bufferIngresso.Lock(out var dati, out _, out _));
        try { frame.CopyTo(new Span<byte>((void*)dati, frame.Length)); }
        finally { bufferIngresso.Unlock(); }
        Controlla(bufferIngresso.SetCurrentLength((uint)frame.Length));
        campioneIngresso.SetSampleTime(tempo);
        campioneIngresso.SetSampleDuration(DurataFrame);
        tempo += DurataFrame;

        var scritti = 0;
        var esito = trasformazione.ProcessInput(0, campioneIngresso, 0);
        if (esito == MF_E_NOTACCEPTING)
        {
            // Ha ancora uscita da dare: prima si svuota, poi si riprova.
            if (!Svuota(uscita, ref scritti)) return -1;
            esito = trasformazione.ProcessInput(0, campioneIngresso, 0);
        }
        if (esito < 0) return -1;
        return Svuota(uscita, ref scritti) ? scritti : -1;
    }

    public void Dispose()
    {
        if (chiuso) return;
        chiuso = true;
        try { trasformazione?.ProcessMessage(MFT_MESSAGE_COMMAND_FLUSH, 0); }
        catch (Exception) { }
        Libera();
    }

    // MARK: uscita

    /// <summary>Float a 32 bit se il decodificatore lo offre, altrimenti PCM a 16 bit (convertito qui).</summary>
    private void ScegliUscita()
    {
        IMFMediaType? scelto = null;
        var sceltoFloat = false;
        for (uint indice = 0; ; indice++)
        {
            if (trasformazione.GetOutputAvailableType(0, indice, out var tipo) < 0) break;
            var chiave = MF_MT_SUBTYPE;
            tipo.GetGUID(ref chiave, out var sottotipo);
            var bit = LeggiIntero(tipo, MF_MT_AUDIO_BITS_PER_SAMPLE);
            if (sottotipo == MFAudioFormat_Float && !sceltoFloat)
            {
                if (scelto is not null) Marshal.ReleaseComObject(scelto);
                scelto = tipo;
                sceltoFloat = true;
            }
            else if (sottotipo == MFAudioFormat_PCM && bit == 16 && scelto is null)
            {
                scelto = tipo;
            }
            else
            {
                Marshal.ReleaseComObject(tipo);
            }
        }
        if (scelto is null) throw new COMException("Il decodificatore AAC non offre un'uscita PCM", unchecked((int)0x80004005));
        try
        {
            Controlla(trasformazione.SetOutputType(0, scelto, 0));
            inFloat = sceltoFloat;
            Frequenza = (int)LeggiIntero(scelto, MF_MT_AUDIO_SAMPLES_PER_SECOND);
            Canali = (int)Math.Max(1, LeggiIntero(scelto, MF_MT_AUDIO_NUM_CHANNELS));
            if (Frequenza <= 0) Frequenza = 48_000;
        }
        finally { Marshal.ReleaseComObject(scelto); }

        Controlla(trasformazione.GetOutputStreamInfo(0, out var info));
        forniscePropri = (info.dwFlags & MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) != 0;
        if (!forniscePropri && campioneUscita is null)
        {
            // Spazio per un frame abbondante: 2048 campioni, 8 canali, 4 byte.
            var spazio = Math.Max(info.cbSize, 2048u * 8 * 4);
            Controlla(MFCreateSample(out var campione));
            campioneUscita = campione;
            Controlla(MFCreateMemoryBuffer(spazio, out var buffer));
            bufferUscita = buffer;
            Controlla(campione.AddBuffer(buffer));
            puntatoreUscita = Marshal.GetComInterfaceForObject(campione, typeof(IMFSample));
        }
    }

    /// <summary>Prende tutta l'uscita pronta; falso se il decodificatore dà un errore.</summary>
    private bool Svuota(Span<float> uscita, ref int scritti)
    {
        for (var giri = 0; giri < 16; giri++)
        {
            if (!forniscePropri) bufferUscita!.SetCurrentLength(0);
            var dati = new DatiUscitaMft { dwStreamID = 0, pSample = forniscePropri ? 0 : puntatoreUscita };
            var esito = trasformazione.ProcessOutput(0, 1, ref dati, out _);
            if (dati.pEvents != 0) Marshal.Release(dati.pEvents);
            if (esito == MF_E_TRANSFORM_NEED_MORE_INPUT) return true;
            if (esito == MF_E_TRANSFORM_STREAM_CHANGE)
            {
                // Il decodificatore ha capito meglio il formato (per esempio dalla configurazione): si rifà l'uscita.
                ScegliUscita();
                continue;
            }
            if (esito < 0) return false;
            if (forniscePropri)
            {
                if (dati.pSample == 0) continue;
                var proprio = (IMFSample)Marshal.GetObjectForIUnknown(dati.pSample);
                Marshal.Release(dati.pSample);
                try { Copia(proprio, uscita, ref scritti); }
                finally { Marshal.ReleaseComObject(proprio); }
            }
            else
            {
                Copia(campioneUscita!, uscita, ref scritti);
            }
        }
        return true;
    }

    private void Copia(IMFSample campione, Span<float> uscita, ref int scritti)
    {
        if (campione.ConvertToContiguousBuffer(out var puntatore) < 0 || puntatore == 0) return;
        var buffer = (IMFMediaBuffer)Marshal.GetObjectForIUnknown(puntatore);
        Marshal.Release(puntatore);
        try
        {
            if (buffer.Lock(out var dati, out _, out var lunghezza) < 0) return;
            try
            {
                var spazio = uscita.Length - scritti;
                if (inFloat)
                {
                    var quanti = Math.Min((int)(lunghezza / 4), spazio);
                    new ReadOnlySpan<float>((void*)dati, quanti).CopyTo(uscita.Slice(scritti, quanti));
                    scritti += quanti;
                }
                else
                {
                    var quanti = Math.Min((int)(lunghezza / 2), spazio);
                    var interi = new ReadOnlySpan<short>((void*)dati, quanti);
                    for (var i = 0; i < quanti; i++) uscita[scritti + i] = interi[i] / 32_768f;
                    scritti += quanti;
                }
            }
            finally { buffer.Unlock(); }
        }
        finally { Marshal.ReleaseComObject(buffer); }
    }

    // MARK: aiuti

    /// <summary>HEAACWAVEINFO dopo WAVEFORMATEX (payload 0 = grezzo, profilo 0x29, tipo 0, riservati 0) + AudioSpecificConfig.</summary>
    internal static byte[] DatiUtente(string configurazioneBase64)
    {
        byte[] configurazione;
        try { configurazione = Convert.FromBase64String(configurazioneBase64 ?? ""); }
        catch (FormatException) { configurazione = []; }
        // Senza configurazione: quella di AAC-LC 48 kHz mono, la sola che i telefoni mandano (Protocollo.md).
        if (configurazione.Length == 0) configurazione = FormatoAudio.ConfigurazioneAAC48kMono.ToArray();
        var dati = new byte[12 + configurazione.Length];
        dati[2] = 0x29; // wAudioProfileLevelIndication (little endian: 0x0029), come MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION
        configurazione.CopyTo(dati, 12);
        return dati;
    }

    private static void ImpostaGuid(IMFMediaType tipo, Guid chiave, Guid valore) => Controlla(tipo.SetGUID(ref chiave, ref valore));
    private static void ImpostaIntero(IMFMediaType tipo, Guid chiave, uint valore) => Controlla(tipo.SetUINT32(ref chiave, valore));

    private static uint LeggiIntero(IMFMediaType tipo, Guid chiave) => tipo.GetUINT32(ref chiave, out var valore) >= 0 ? valore : 0;

    private static void Controlla(int esito)
    {
        if (esito < 0) Marshal.ThrowExceptionForHR(esito);
    }

    private void Libera()
    {
        if (puntatoreUscita != 0) { Marshal.Release(puntatoreUscita); puntatoreUscita = 0; }
        foreach (var oggetto in new object?[] { bufferUscita, campioneUscita, bufferIngresso, campioneIngresso, trasformazione })
        {
            if (oggetto is not null && Marshal.IsComObject(oggetto))
            {
                try { Marshal.ReleaseComObject(oggetto); }
                catch (Exception) { }
            }
        }
        bufferUscita = null;
        campioneUscita = null;
        MFShutdown();
    }

    [DllImport("mfplat.dll")] private static extern int MFStartup(uint version, uint flags);
    [DllImport("mfplat.dll")] private static extern int MFShutdown();
    [DllImport("mfplat.dll")] private static extern int MFCreateMediaType(out IMFMediaType tipo);
    [DllImport("mfplat.dll")] private static extern int MFCreateSample(out IMFSample campione);
    [DllImport("mfplat.dll")] private static extern int MFCreateMemoryBuffer(uint lunghezzaMassima, out IMFMediaBuffer buffer);
}
