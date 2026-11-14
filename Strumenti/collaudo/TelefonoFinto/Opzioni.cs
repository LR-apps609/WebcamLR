using System.Globalization;
using WebcamLR.Protocollo;

namespace WebcamLR.Collaudo;

/// <summary>Le opzioni della riga di comando del telefono finto.</summary>
public sealed class Opzioni
{
    public const string Testo = """
        TelefonoFinto: un iPhone simulato che si collega a WebcamLR su questa macchina e manda video sintetico
        (un'immagine che si muove, con un orologio). Protocollo 2 vero: stretta di mano, cifratura, abbinamento.

        Opzioni:
          --nome "<nome>"            nome del telefono (di serie «iPhone finto»)
          --android                  si presenta come telefono Android
          --indirizzo <ip>           di serie 127.0.0.1
          --porta <n>                di serie 52740
          --durata <s>               quanto resta collegato in tutto (di serie 60; 0 = finché non lo si ferma)
          --interrompi-dopo <s>      dopo s secondi simula la caduta della rete
          --modo-interruzione <m>    «silenzio» (di serie: il telefono tace, la connessione resta aperta, come un Wi-Fi
                                     che sparisce) o «chiusura» (connessione chiusa di colpo, senza arrivederci)
          --riconnetti-dopo <s>      dopo l'interruzione si ricollega: in «silenzio» tace s secondi, in «chiusura» aspetta s
          --riconnetti-sempre        se la connessione cade o il computer chiude, riprova ogni 2 secondi fino alla durata
          --risoluzione <LxA>        risoluzione massima e iniziale (di serie 1280x720); con questa opzione il telefono non
                                     segue il formato chiesto dal computer
          --fps <n>                  fotogrammi al secondo (di serie 30)
          --qr <file>                legge il QR code di WebcamLR da una schermata PNG o BMP: indirizzo, porta, impronta
                                     del computer e gettone (il telefono entra senza conferma)
          --collegamento <testo>     come --qr, ma con il testo «webcamlr://collega?...»
          --gettone <g>              gettone di abbinamento (quello del QR)
          --gettone-sbagliato        manda un gettone inventato: il computer deve chiedere conferma («Consenti?»)
          --identita <file>          file della chiave del telefono (di serie una per nome nella cartella temporanea)
          --identita-nuova           una chiave nuova: per il computer è un telefono mai visto
          --attesa-abbinamento <s>   quanto aspettare il «benvenuto» (di serie 75: la conferma sul PC scade a 60)
          --pro                      il telefono ha WebcamLR Pro
          --effetti-sul-telefono     non offre gli effetti sul computer (capacita.effettiSulComputer falso)
          --senza-video              si collega ma non manda video
          --audio                    ha un microfono utilizzabile (capacita.audio): a «comando audio» manda AAC-LC 48 kHz
                                     mono (tono.aac a ciclo: 440 Hz che sale e scende, un bip a 1 kHz a ogni secondo)
          --microfono-spento-dopo <s> dopo s secondi di audio il microfono si spegne «dal telefono» (stato.audio falso)
          --microfono-negato         come un telefono senza permesso del microfono: capacita.audio falso (di serie)
          --ignora-pausa             non va in pausa quando il computer manda «pausa-automatica»
          --batteria <n>             batteria in stato (di serie 80; -1 = non nota); --in-carica
          --temperatura <t>          normale, calda, molto-calda, critica
          --registro <file>          scrive le righe anche in questo file
          --ferma <file>             si chiude bene (con arrivederci) quando questo file compare
          --aiuto

        Righe da cercare nel registro: «ACCETTATO», «CODICE 1234», «RIFIUTATO», «INTERRUZIONE», «FINE».
        Codice di uscita: 0 finito, 2 rifiutato, 3 errore di rete, 4 chiuso dal computer, 5 interrotto, 6 QR illeggibile,
        64 opzioni sbagliate.
        """;

    public bool Aiuto { get; private set; }
    public string Nome { get; private set; } = "iPhone finto";
    public Piattaforma Piattaforma { get; private set; } = Piattaforma.Iphone;
    public string Indirizzo { get; private set; } = "127.0.0.1";
    public int Porta { get; private set; } = Servizio.PortaPredefinita;
    public TimeSpan Durata { get; private set; } = TimeSpan.FromSeconds(60);
    public TimeSpan? InterrompiDopo { get; private set; }
    public string ModoInterruzione { get; private set; } = "silenzio";
    public TimeSpan? RiconnettiDopo { get; private set; }
    public bool RiconnettiSempre { get; private set; }
    public int Larghezza { get; private set; } = 1280;
    public int Altezza { get; private set; } = 720;
    public bool FormatoFisso { get; private set; }
    public int Fps { get; private set; } = 30;
    public string? FileQr { get; private set; }
    public string? Collegamento { get; private set; }
    public string? Gettone { get; private set; }
    public string? ImprontaAttesa { get; private set; }
    public string? FileIdentita { get; private set; }
    public bool IdentitaNuova { get; private set; }
    public int AttesaAbbinamento { get; private set; } = 75;
    public bool Pro { get; private set; }
    public bool EffettiSulComputer { get; private set; } = true;
    public bool SenzaVideo { get; private set; }
    public bool Audio { get; private set; }
    public TimeSpan? MicrofonoSpentoDopo { get; private set; }
    public bool RispettaPausa { get; private set; } = true;
    public int Batteria { get; private set; } = 80;
    public bool InCarica { get; private set; }
    public Temperatura Temperatura { get; private set; } = Temperatura.Normale;
    public string? FileRegistro { get; private set; }
    public string? FileFerma { get; private set; }

    public static Opzioni Leggi(string[] argomenti)
    {
        var o = new Opzioni();
        for (var i = 0; i < argomenti.Length; i++)
        {
            var nome = argomenti[i];
            string Valore() => i + 1 < argomenti.Length ? argomenti[++i] : throw new ArgumentException($"{nome}: manca il valore");
            double Secondi() => double.TryParse(Valore(), NumberStyles.Float, CultureInfo.InvariantCulture, out var s) && s >= 0
                ? s : throw new ArgumentException($"{nome}: servono dei secondi (es. 10 o 2.5)");
            int Intero() => int.TryParse(Valore(), out var n) ? n : throw new ArgumentException($"{nome}: serve un numero intero");
            switch (nome)
            {
                case "--aiuto" or "-h" or "--help" or "/?": o.Aiuto = true; break;
                case "--nome": o.Nome = Valore(); break;
                case "--android": o.Piattaforma = Piattaforma.Android; break;
                case "--indirizzo": o.Indirizzo = Valore(); break;
                case "--porta": o.Porta = Intero(); break;
                case "--durata":
                    var durata = Secondi();
                    o.Durata = durata == 0 ? TimeSpan.FromDays(1) : TimeSpan.FromSeconds(durata);
                    break;
                case "--interrompi-dopo": o.InterrompiDopo = TimeSpan.FromSeconds(Secondi()); break;
                case "--modo-interruzione":
                    o.ModoInterruzione = Valore();
                    if (o.ModoInterruzione is not ("silenzio" or "chiusura"))
                        throw new ArgumentException("--modo-interruzione: «silenzio» o «chiusura»");
                    break;
                case "--riconnetti-dopo": o.RiconnettiDopo = TimeSpan.FromSeconds(Secondi()); break;
                case "--riconnetti-sempre": o.RiconnettiSempre = true; break;
                case "--risoluzione":
                    var parti = Valore().ToLowerInvariant().Replace('×', 'x').Split('x');
                    if (parti.Length != 2 || !int.TryParse(parti[0], out var l) || !int.TryParse(parti[1], out var a)
                        || l < 16 || a < 16 || l % 2 != 0 || a % 2 != 0 || l > 3840 || a > 2160)
                        throw new ArgumentException("--risoluzione: LxA, pari, da 16x16 a 3840x2160 (es. 1280x720)");
                    (o.Larghezza, o.Altezza, o.FormatoFisso) = (l, a, true);
                    break;
                case "--fps":
                    o.Fps = Intero();
                    if (o.Fps is < 1 or > 60) throw new ArgumentException("--fps: da 1 a 60");
                    break;
                case "--qr": o.FileQr = Valore(); break;
                case "--collegamento": o.Collegamento = Valore(); break;
                case "--gettone": o.Gettone = Valore(); break;
                case "--gettone-sbagliato": o.Gettone = Sicurezza.NuovoGettone(); break;
                case "--identita": o.FileIdentita = Valore(); break;
                case "--identita-nuova": o.IdentitaNuova = true; break;
                case "--attesa-abbinamento": o.AttesaAbbinamento = Intero(); break;
                case "--pro": o.Pro = true; break;
                case "--effetti-sul-telefono": o.EffettiSulComputer = false; break;
                case "--senza-video": o.SenzaVideo = true; break;
                case "--audio": o.Audio = true; break;
                case "--microfono-negato": o.Audio = false; break;
                case "--microfono-spento-dopo": o.MicrofonoSpentoDopo = TimeSpan.FromSeconds(Secondi()); break;
                case "--ignora-pausa": o.RispettaPausa = false; break;
                case "--batteria": o.Batteria = Intero(); break;
                case "--in-carica": o.InCarica = true; break;
                case "--temperatura":
                    o.Temperatura = Valore() switch
                    {
                        "normale" => Temperatura.Normale,
                        "calda" => Temperatura.Calda,
                        "molto-calda" => Temperatura.MoltoCalda,
                        "critica" => Temperatura.Critica,
                        _ => throw new ArgumentException("--temperatura: normale, calda, molto-calda o critica"),
                    };
                    break;
                case "--registro": o.FileRegistro = Valore(); break;
                case "--ferma": o.FileFerma = Valore(); break;
                default: throw new ArgumentException($"opzione sconosciuta: {nome}");
            }
        }
        if (o.FileQr is not null && o.Collegamento is not null) throw new ArgumentException("--qr e --collegamento insieme");
        return o;
    }

    /// <summary>
    /// Dal QR: il primo indirizzo se non se n'è scelto un altro (in collaudo il computer è questo: 127.0.0.1 resta), la
    /// porta, l'impronta da controllare e il gettone (salvo --gettone-sbagliato o --gettone).
    /// </summary>
    public void ApplicaQr(Associazione associazione)
    {
        Porta = associazione.Porta;
        ImprontaAttesa = associazione.Impronta;
        Gettone ??= associazione.Gettone;
    }
}
