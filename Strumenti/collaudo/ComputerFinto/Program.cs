// Il «computer finto» del collaudo Android (Strumenti/collaudo/android/LEGGIMI.md, «In onda»).
// Usa il cuore vero del ricevitore Windows: Ascoltatore (porta 52740), SessioneComputer (stretta di mano, prova,
// abbinamento, benvenuto, ping, statistiche) e Abbinamento (gettone del QR code o conferma con il codice).
// Nella cartella --uscita scrive:
//   eventi.log        ciò che succede, con l'ora (collegamenti, codice, formato, pause, silenzi, chiusure)
//   collegamento.txt  il link del QR code (webcamlr://collega?…), rifatto quando il gettone cambia
//   codice.txt        l'ultimo codice di conferma chiesto
//   stato.txt         una riga: attesa | conferma | collegato | video | interrotto | fermo
//   statistiche.csv   ogni secondo: larghezza, altezza, fps, Mbit/s, latenza, codec, pacchetti audio
//   video.h264/.hevc  il flusso ricevuto (Annex B), fino a --massimo-video MB
//   fotogrammi/       un fotogramma chiave ogni --ogni secondi, decodificato in PNG con ffmpeg se c'è
//   riepilogo.txt     alla fine: sessioni, fotogrammi, byte
//   audio.aac         l'audio ricevuto (AAC-LC con intestazioni ADTS), se il telefono ne manda
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

var opzioni = Opzioni.Leggi(args);
if (opzioni is null)
{
    Console.Error.WriteLine(Opzioni.Uso);
    return 2;
}
var computer = new Computer(opzioni);
using var fine = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; fine.Cancel(); };
using var segnale = PosixSignalRegistration.Create(PosixSignal.SIGTERM, contesto => { contesto.Cancel = true; fine.Cancel(); });
if (opzioni.Durata > 0) fine.CancelAfter(TimeSpan.FromSeconds(opzioni.Durata));
await computer.EseguiAsync(fine.Token);
return 0;

sealed record Opzioni(
    int Porta, string Nome, string Uscita, string Indirizzo, int? PortaCavo, double? InterrompiDopo, double Pausa,
    bool Rifiuta, bool InOnda, double Ogni, double AttesaConferma, int MassimoVideoMb, double Durata,
    double? ChiediAudio = null, double? SpegniAudio = null)
{
    public const string Uso = """
        Uso: ComputerFinto [opzioni]
          --porta <n>              porta d'ascolto (52740)
          --nome <testo>           nome del computer («PC di collaudo»)
          --uscita <cartella>      dove scrivere eventi, statistiche e fotogrammi («computer-finto»)
          --indirizzo <ip>         indirizzo nel link del QR code (10.0.2.2: il computer visto dall'emulatore)
          --cavo <porta>           prova ogni secondo 127.0.0.1:<porta> (un «adb forward» verso la 52741 del telefono)
          --interrompi-dopo <s>    secondi dopo il primo video: chiude tutto di colpo, come una caduta di rete
          --pausa <s>              quanto resta irraggiungibile dopo l'interruzione (15)
          --rifiuta                rifiuta ogni telefono (risponde «arrivederci»)
          --senza-in-onda          non dice al telefono che un'app usa la webcam (niente rosso «IN ONDA»)
          --ogni <s>               un fotogramma salvato ogni <s> secondi (5)
          --attesa-conferma <s>    dopo quanto consente da solo un telefono nuovo con il codice (2)
          --massimo-video <MB>     quanti MB di video salvare al massimo (40)
          --durata <s>             si ferma da solo dopo <s> secondi (0 = mai)
          --chiedi-audio <s>       <s> secondi dopo il collegamento manda «comando audio vero» (come l'interruttore del PC)
          --spegni-audio <s>       <s> secondi dopo il collegamento manda «comando audio falso»
        """;

    public static Opzioni? Leggi(string[] args)
    {
        var o = new Opzioni(Servizio.PortaPredefinita, "PC di collaudo", "computer-finto", "10.0.2.2", null, null, 15,
            false, true, 5, 2, 40, 0);
        static double Numero(string testo) => double.Parse(testo, CultureInfo.InvariantCulture);
        try
        {
            for (var i = 0; i < args.Length; i++)
            {
                string Valore() => args[++i];
                o = args[i] switch
                {
                    "--porta" => o with { Porta = int.Parse(Valore(), CultureInfo.InvariantCulture) },
                    "--nome" => o with { Nome = Valore() },
                    "--uscita" => o with { Uscita = Valore() },
                    "--indirizzo" => o with { Indirizzo = Valore() },
                    "--cavo" => o with { PortaCavo = int.Parse(Valore(), CultureInfo.InvariantCulture) },
                    "--interrompi-dopo" => o with { InterrompiDopo = Numero(Valore()) },
                    "--pausa" => o with { Pausa = Numero(Valore()) },
                    "--rifiuta" => o with { Rifiuta = true },
                    "--senza-in-onda" => o with { InOnda = false },
                    "--ogni" => o with { Ogni = Numero(Valore()) },
                    "--attesa-conferma" => o with { AttesaConferma = Numero(Valore()) },
                    "--massimo-video" => o with { MassimoVideoMb = int.Parse(Valore(), CultureInfo.InvariantCulture) },
                    "--durata" => o with { Durata = Numero(Valore()) },
                    "--chiedi-audio" => o with { ChiediAudio = Numero(Valore()) },
                    "--spegni-audio" => o with { SpegniAudio = Numero(Valore()) },
                    _ => throw new ArgumentException(args[i]),
                };
            }
        }
        catch (Exception)
        {
            return null;
        }
        return o;
    }
}

sealed class Computer
{
    private readonly Opzioni opzioni;
    private readonly string uscita;
    private readonly object blocco = new();
    private readonly Abbinamento abbinamento;
    private readonly IdentitaDispositivo identita;
    private readonly List<SessioneComputer> sessioni = [];
    private Ascoltatore? ascolto;
    private int numeroSessione;
    private bool interrotto;
    private DateTime? primoVideo;
    private long fotogrammiTotali;
    private long byteTotali;
    private int fotogrammiSalvati;
    private FileStream? video;
    private string estensioneVideo = "h264";
    private DateTime ultimoSalvato = DateTime.MinValue;
    private bool vuoleChiave;
    private byte[]? ultimaChiaveConParametri;
    private readonly List<Task> decodifiche = [];

    public Computer(Opzioni opzioni)
    {
        this.opzioni = opzioni;
        uscita = Path.GetFullPath(opzioni.Uscita);
        Directory.CreateDirectory(Path.Combine(uscita, "fotogrammi"));
        // La stessa identità a ogni avvio nella stessa cartella: il telefono ritrova il computer che conosce.
        var fileChiave = Path.Combine(uscita, "identita.key");
        identita = File.Exists(fileChiave) ? IdentitaDispositivo.DaPkcs8(File.ReadAllBytes(fileChiave)) : IdentitaDispositivo.Nuova();
        File.WriteAllBytes(fileChiave, identita.EsportaPkcs8());
        abbinamento = new Abbinamento(identita)
        {
            ChiediConferma = async (nome, codice, annullato) =>
            {
                File.WriteAllText(Path.Combine(uscita, "codice.txt"), codice + "\n");
                Scrivi($"CONFERMA chiesta da «{nome}», codice {codice}: consento tra {opzioni.AttesaConferma} s");
                await Task.Delay(TimeSpan.FromSeconds(opzioni.AttesaConferma), annullato);
                return true;
            },
        };
        abbinamento.GettoneCambiato += ScriviCollegamento;
        if (!File.Exists(Path.Combine(uscita, "statistiche.csv")))
            File.WriteAllText(Path.Combine(uscita, "statistiche.csv"), "ora,sessione,larghezza,altezza,fps,mbit_s,latenza_ms,codec,audio\n");
    }

    public async Task EseguiAsync(CancellationToken fine)
    {
        Scrivi($"AVVIO «{opzioni.Nome}», impronta {identita.Impronta[..8]}…" + (opzioni.Rifiuta ? ", RIFIUTA tutti" : ""));
        ApriAscolto();
        Stato("attesa");
        var cavo = opzioni.PortaCavo is int portaCavo ? CavoAsync(portaCavo, fine) : Task.CompletedTask;
        try { await Task.Delay(Timeout.Infinite, fine); } catch (OperationCanceledException) { }
        Scrivi("FERMO: chiudo le sessioni con «arrivederci»");
        ascolto?.Dispose();
        SessioneComputer[] aperte;
        lock (blocco) aperte = [.. sessioni];
        foreach (var sessione in aperte)
        {
            try { await sessione.ChiudiAsync(); } catch (Exception) { }
            await sessione.DisposeAsync();
        }
        try { await cavo; } catch (Exception) { }
        Task[] attese;
        lock (blocco) attese = [.. decodifiche];
        await Task.WhenAll(attese);
        lock (blocco) video?.Dispose();
        Stato("fermo");
        var riepilogo = $"sessioni {numeroSessione}\nfotogrammi ricevuti {fotogrammiTotali}\nbyte video {byteTotali}\nfotogrammi salvati {fotogrammiSalvati}\n";
        File.WriteAllText(Path.Combine(uscita, "riepilogo.txt"), riepilogo);
        Scrivi("RIEPILOGO " + riepilogo.Replace('\n', ' ').Trim());
    }

    private FileStream? audio;

    /// <summary>Un frame AAC-LC grezzo con l'intestazione ADTS (48 kHz, mono), così ffmpeg lo legge.</summary>
    private void SalvaAudio(byte[] dati)
    {
        lock (blocco)
        {
            audio ??= new FileStream(Path.Combine(uscita, "audio.aac"), FileMode.Create);
            if (audio.Length > 2_000_000) return;
            var l = dati.Length + 7;
            // profilo LC (1), frequenza 48 kHz (indice 3), 1 canale
            byte[] testa = [0xFF, 0xF1, (byte)((1 << 6) | (3 << 2)), (byte)((1 << 6) | (l >> 11)), (byte)((l >> 3) & 0xFF), (byte)(((l & 7) << 5) | 0x1F), 0xFC];
            audio.Write(testa);
            audio.Write(dati);
            audio.Flush();
        }
    }

    private void ComandoAudioDopo(SessioneComputer sessione, int numero, double secondi, bool acceso)
    {
        sessione.Salutato += _ => _ = Task.Run(async () =>
        {
            await Task.Delay(TimeSpan.FromSeconds(secondi));
            if (sessione.Terminata) return;
            try { await sessione.ComandaAsync(new Comando(Audio: acceso)); Scrivi($"#{numero} COMANDO audio {(acceso ? "vero" : "falso")} mandato"); }
            catch (Exception errore) { Scrivi($"#{numero} COMANDO audio non mandato: {errore.Message}"); }
        });
    }

    private void ApriAscolto()
    {
        var nuovo = new Ascoltatore(IPAddress.Any, opzioni.Porta);
        nuovo.NuovoTelefono += presa => Accogli(presa, "Wi-Fi");
        nuovo.Riaperto += porta => { Scrivi($"ASCOLTO riaperto sulla porta {porta}"); ScriviCollegamento(); };
        ascolto = nuovo;
        Scrivi($"ASCOLTO sulla porta {nuovo.Porta}");
        ScriviCollegamento();
    }

    private void ScriviCollegamento()
    {
        var porta = (ushort)(ascolto?.Porta ?? opzioni.Porta);
        var link = new Associazione([opzioni.Indirizzo], porta, opzioni.Nome, Servizio.VersioneProtocollo, identita.Impronta,
            abbinamento.Gettone).Testo;
        File.WriteAllText(Path.Combine(uscita, "collegamento.txt"), link + "\n");
        File.WriteAllText(Path.Combine(uscita, "porta.txt"), porta + "\n");
        Scrivi($"QR {link}");
    }

    /// <summary>La via del cavo: un «adb forward tcp:&lt;porta&gt; tcp:52741», provato ogni secondo come fa ClienteAdb.</summary>
    private async Task CavoAsync(int porta, CancellationToken fine)
    {
        Scrivi($"CAVO: provo 127.0.0.1:{porta} ogni secondo");
        while (!fine.IsCancellationRequested)
        {
            SessioneComputer? sessione = null;
            bool sospeso;
            lock (blocco) sospeso = interrotto;
            if (!sospeso)
            {
                var presa = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
                try
                {
                    await presa.ConnectAsync(new IPEndPoint(IPAddress.Loopback, porta), fine);
                    sessione = Accogli(presa, "cavo USB (adb)", silenzioso: true);
                }
                catch (Exception)
                {
                    presa.Dispose();
                }
            }
            if (sessione is not null)
            {
                while (!sessione.Terminata && !fine.IsCancellationRequested)
                {
                    try { await Task.Delay(500, fine); } catch (OperationCanceledException) { }
                }
            }
            try { await Task.Delay(1000, fine); } catch (OperationCanceledException) { }
        }
    }

    private SessioneComputer Accogli(Socket presa, string via, bool silenzioso = false)
    {
        var numero = Interlocked.Increment(ref numeroSessione);
        var remoto = presa.RemoteEndPoint?.ToString() ?? "?";
        var sessione = new SessioneComputer(presa, opzioni.Nome, abbinamento)
        {
            Collegamento = via.StartsWith("cavo") ? TipoCollegamento.CavoUsb : TipoCollegamento.WiFi,
            Ammetti = opzioni.Rifiuta ? _ => false : null,
        };
        var salutato = false;
        bool? audioStato = null;
        long pacchettiAudio = 0;
        if (!silenzioso) Scrivi($"#{numero} CONNESSIONE da {remoto} via {via}");
        sessione.ConfermaInCorso += (nome, codice) => { Stato("conferma"); Scrivi($"#{numero} CODICE {codice} per «{nome}»"); };
        sessione.NonAmmesso += ciao => Scrivi($"#{numero} RIFIUTATO «{ciao.Nome}» (--rifiuta)");
        sessione.RifiutatoDaPoco += ciao => Scrivi($"#{numero} RIFIUTATO DA POCO «{ciao.Nome}»");
        sessione.Salutato += ciao =>
        {
            salutato = true;
            if (silenzioso) Scrivi($"#{numero} CONNESSIONE dal cavo ({remoto})");
            Scrivi($"#{numero} COLLEGATO «{ciao.Nome}» ({ciao.Piattaforma}, app {ciao.VersioneApp}) via {via}");
            Stato("collegato");
            if (opzioni.InOnda)
            {
                _ = Task.Run(async () =>
                {
                    await Task.Delay(1500);
                    try { await sessione.SegnalaAsync(new InOnda(true, "Collaudo")); Scrivi($"#{numero} IN ONDA segnalato al telefono"); }
                    catch (Exception) { }
                });
            }
        };
        sessione.FormatoRicevuto += formato =>
        {
            lock (blocco)
            {
                if (video is null)
                {
                    estensioneVideo = formato.Codec == Codec.Hevc ? "hevc" : "h264";
                    video = new FileStream(Path.Combine(uscita, "video." + estensioneVideo), FileMode.Create);
                }
            }
            Scrivi($"#{numero} FORMATO {formato.Codec} {formato.Larghezza}x{formato.Altezza} {formato.Fps} fps");
        };
        sessione.StatoRicevuto += stato =>
        {
            if (stato.Pausa is not null) Scrivi($"#{numero} PAUSA {stato.Pausa}");
            if (stato.Audio != audioStato)
            {
                audioStato = stato.Audio;
                Scrivi($"#{numero} STATO audio {(stato.Audio is { } a ? (a ? "vero (il telefono manda l'audio)" : "falso") : "assente")}");
            }
        };
        sessione.CapacitaRicevute += c => Scrivi($"#{numero} CAPACITÀ ricevute (audio {(c.Audio is { } a ? a.ToString().ToLowerInvariant() : "assente")}, pro {c.Pro})");
        sessione.FormatoAudioRicevuto += f => Scrivi($"#{numero} FORMATO-AUDIO {f.Codec} {f.Frequenza} Hz {f.Canali} canali, configurazione {f.Configurazione}");
        sessione.AudioRicevuto += pacchetto =>
        {
            var n = Interlocked.Increment(ref pacchettiAudio);
            if (n == 1) Scrivi($"#{numero} AUDIO: primo pacchetto ({pacchetto.Dati.Length} byte)");
            else if (n % 470 == 0) Scrivi($"#{numero} AUDIO: {n} pacchetti ricevuti");
            SalvaAudio(pacchetto.Dati);
        };
        if (opzioni.ChiediAudio is { } chiedi) ComandoAudioDopo(sessione, numero, chiedi, true);
        if (opzioni.SpegniAudio is { } spegni) ComandoAudioDopo(sessione, numero, spegni, false);
        sessione.StatisticheAggiornate += s =>
        {
            var riga = string.Create(CultureInfo.InvariantCulture,
                $"{DateTime.Now:HH:mm:ss},{numero},{s.Larghezza},{s.Altezza},{s.Fps},{s.MegabitAlSecondo:0.00},{s.LatenzaMs},{s.Codec},{s.PacchettiAudio}\n");
            lock (blocco) File.AppendAllText(Path.Combine(uscita, "statistiche.csv"), riga);
        };
        var videoDiSessione = false;
        sessione.FotogrammaRicevuto += f =>
        {
            // «video» a ogni sessione nuova (anche dopo un ricollegamento): attendi_computer video lo aspetta.
            if (!videoDiSessione)
            {
                videoDiSessione = true;
                Stato("video");
                Scrivi($"#{numero} VIDEO: primo fotogramma della sessione ({f.Dati.Length} byte)");
            }
            Fotogramma(sessione, f);
        };
        sessione.Silenzio += () => Scrivi($"#{numero} SILENZIO da 3 secondi");
        sessione.Ripresa += () => Scrivi($"#{numero} RIPRESA");
        sessione.Chiusa += () =>
        {
            lock (blocco) sessioni.Remove(sessione);
            if (!silenzioso || salutato)
            {
                var chi = sessione.ChiusaDalTelefono ? "dal telefono" : sessione.ChiusaDalComputer ? "dal computer" : "la connessione è caduta";
                Scrivi($"#{numero} CHIUSA ({chi})");
            }
            bool restano;
            lock (blocco) restano = sessioni.Count > 0;
            if (!restano && salutato) Stato(interrotto ? "interrotto" : "attesa");
        };
        lock (blocco) sessioni.Add(sessione);
        sessione.Avvia();
        return sessione;
    }

    private void Fotogramma(SessioneComputer sessione, FotogrammaVideo f)
    {
        var primo = false;
        var adesso = DateTime.Now;
        string? daDecodificare = null;
        lock (blocco)
        {
            fotogrammiTotali++;
            byteTotali += f.Dati.Length;
            if (primoVideo is null)
            {
                primoVideo = adesso;
                primo = true;
            }
            if (video is not null && video.Length < opzioni.MassimoVideoMb * 1024L * 1024L) video.Write(f.Dati);
            if (f.Chiave && f.ConParametri) ultimaChiaveConParametri = f.Dati;
            if (adesso - ultimoSalvato >= TimeSpan.FromSeconds(opzioni.Ogni))
            {
                if (f.Chiave)
                {
                    // Un fotogramma chiave da solo si decodifica: con i parametri davanti se non li ha.
                    var dati = f.ConParametri || ultimaChiaveConParametri is null ? f.Dati : [.. ultimaChiaveConParametri, .. f.Dati];
                    fotogrammiSalvati++;
                    var nome = Path.Combine(uscita, "fotogrammi",
                        $"{fotogrammiSalvati:000}-{(int)(adesso - primoVideo.Value).TotalSeconds:000}s.{estensioneVideo}");
                    File.WriteAllBytes(nome, dati);
                    daDecodificare = nome;
                    ultimoSalvato = adesso;
                    vuoleChiave = false;
                }
                else if (!vuoleChiave)
                {
                    vuoleChiave = true;
                    _ = sessione.ChiediChiaveAsync();
                }
            }
        }
        if (primo && opzioni.InterrompiDopo is double secondi) _ = InterrompiAsync(secondi);
        if (daDecodificare is not null)
        {
            var lavoro = Task.Run(() => Decodifica(daDecodificare));
            lock (blocco) decodifiche.Add(lavoro);
        }
    }

    /// <summary>Con ffmpeg (se c'è) il fotogramma salvato diventa PNG; l'ultimo decodificato è quello giusto.</summary>
    private void Decodifica(string file)
    {
        var png = Path.ChangeExtension(file, ".png");
        try
        {
            var avvio = new ProcessStartInfo("ffmpeg")
            {
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            foreach (var a in new[] { "-loglevel", "error", "-y", "-f", estensioneVideo, "-i", file, "-update", "1", png })
                avvio.ArgumentList.Add(a);
            using var processo = Process.Start(avvio)!;
            processo.StandardOutput.ReadToEnd();
            var errori = processo.StandardError.ReadToEnd();
            processo.WaitForExit(20_000);
            if (File.Exists(png) && new FileInfo(png).Length > 0) File.Delete(file);
            else Scrivi($"DECODIFICA non riuscita per {Path.GetFileName(file)}: {errori.Split('\n')[0].Trim()}");
        }
        catch (Exception errore)
        {
            Scrivi($"DECODIFICA saltata (ffmpeg non disponibile?): {errore.Message}");
        }
    }

    /// <summary>--interrompi-dopo: tutto chiuso di colpo, senza «arrivederci», e porta chiusa per --pausa secondi.</summary>
    private async Task InterrompiAsync(double secondi)
    {
        await Task.Delay(TimeSpan.FromSeconds(secondi));
        SessioneComputer[] aperte;
        lock (blocco)
        {
            interrotto = true;
            aperte = [.. sessioni];
        }
        Scrivi($"INTERROMPO: caduta di rete simulata per {opzioni.Pausa} s ({aperte.Length} sessioni chiuse senza «arrivederci»)");
        Stato("interrotto");
        ascolto?.Dispose();
        foreach (var sessione in aperte) await sessione.DisposeAsync();
        await Task.Delay(TimeSpan.FromSeconds(opzioni.Pausa));
        lock (blocco) interrotto = false;
        ApriAscolto();
        Stato("attesa");
        Scrivi("RIPRISTINO: di nuovo raggiungibile");
    }

    private void Stato(string stato) => File.WriteAllText(Path.Combine(uscita, "stato.txt"), stato + "\n");

    private void Scrivi(string testo)
    {
        var riga = $"{DateTime.Now:HH:mm:ss.fff}  {testo}";
        lock (blocco) File.AppendAllText(Path.Combine(uscita, "eventi.log"), riga + "\n");
        Console.WriteLine(riga);
    }
}
