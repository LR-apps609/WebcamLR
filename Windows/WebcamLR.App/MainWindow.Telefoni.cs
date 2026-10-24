using System.Collections.Concurrent;
using System.Net.Sockets;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Media.Playback;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// I telefoni collegati (P21, «Più telefoni insieme»), come sul Mac: fino a due telefoni diversi, ognuno con il suo
/// video. Uno è «nella webcam»: si vede grande, va alla webcam per le altre app, a foto e registrazioni, e i comandi a
/// destra valgono per lui. L'altro si vede nel riquadro piccolo in basso a destra (un clic lo mette nella webcam) e nella
/// scheda «Telefoni» a sinistra, con «Nella webcam» e «Scollega». Con un telefono solo la finestra è quella di sempre.
/// Le regole (stesso telefono, secondo telefono, terzo rifiutato, precedenza del cavo) sono in ElencoTelefoni, provate
/// con i test; qui si collegano sessioni, decodificatori e finestra.
/// </summary>
public sealed partial class MainWindow
{
    private readonly ElencoTelefoni telefoni = new();

    /// <summary>
    /// Il decodificatore della finestra di ogni telefono (anteprima grande o riquadro piccolo): un MediaPlayer per telefono,
    /// così passare dall'uno all'altro è immediato. Lo usano anche i thread di rete.
    /// </summary>
    private readonly ConcurrentDictionary<TelefonoCollegato, VideoTelefono> video = new();

    /// <summary>Vero se il riquadro piccolo è aperto; chiuso, l'altro telefono può andare in pausa.</summary>
    private bool riquadroAperto = true;

    // Quello che la finestra mostra è del telefono nella webcam: questi nomi restano quelli di prima del P21,
    // così il resto della finestra non cambia.
    private TelefonoCollegato? Scelto => telefoni.Selezionato;
    private SessioneComputer? sessione => telefoni.SessioneSelezionata;
    private Ciao? telefono => Scelto?.Ciao;
    /// Come è collegato il telefono mostrato (1.2); null se non si sa.
    private TipoCollegamento? collegamento => Scelto?.Collegamento;
    private StatoTelefono? statoTelefono => Scelto?.Stato;
    private Statistiche? statistiche => Scelto?.Statistiche;
    private Capacita? capacitaAttuali => Scelto?.Capacita;
    /// «Avvio: 0,9 s» della sessione mostrata (1.11); null finché il primo fotogramma non è a schermo.
    private string? testoAvvio => Scelto?.TestoAvvio;
    /// La latenza degli ultimi 60 secondi, per il grafico accanto alle statistiche.
    private StoriaLatenza storiaLatenza => Scelto?.StoriaLatenza ?? storiaSenzaTelefono;
    private readonly StoriaLatenza storiaSenzaTelefono = new();
    private SorveglianzaAvvisi sorveglianzaAvvisi => Scelto?.Avvisi ?? avvisiSenzaTelefono;
    private readonly SorveglianzaAvvisi avvisiSenzaTelefono = new();

    /// <summary>Il decodificatore di un telefono per la finestra, e il messaggio se il video non si decodifica.</summary>
    private sealed class VideoTelefono : IDisposable
    {
        public readonly AnteprimaVideo Anteprima = new();
        /// <summary>Il lettore attuale, quando la finestra lo ha ricevuto (thread dell'interfaccia).</summary>
        public MediaPlayer? Lettore;
        public string? Errore;

        public void Dispose() => Anteprima.Dispose();
    }

    // MARK: arrivo di un telefono

    /// <summary>
    /// Chiamata sul thread di rete (o del cavo): qui niente controlli della finestra, solo SuInterfaccia.
    /// Un collegamento nuovo resta in attesa finché non è accettato (stretta di mano, prova, fiducia): solo allora entra
    /// nell'elenco. Così nessuno sulla rete può far cadere un telefono collegato.
    /// </summary>
    private void Accetta(Socket presa, bool viaCavo, ulong arrivo)
    {
        var nuova = new SessioneComputer(presa, Environment.MachineName, abbinamento, arrivo: arrivo)
        {
            Collegamento = Collegamenti.DellaPresa(presa, viaCavo),
            // Pausa intelligente: subito dopo il benvenuto il telefono sa se la finestra mostra il video.
            AnteprimaVisibile = Volatile.Read(ref anteprimaVisibile),
            // Un terzo telefono non entra, e non fa comparire la domanda «Consentire …?» per nulla.
            Ammetti = telefoni.PuoEntrare,
        };
        // Il telefono dell'elenco di questa sessione, dopo l'accettazione.
        TelefonoCollegato? mio = null;
        void SuInterfaccia(Action<TelefonoCollegato> azione) => coda.TryEnqueue(() =>
        {
            if (Volatile.Read(ref mio) is { } collegato && collegato.Sessione == nuova && telefoni.Contiene(collegato)) azione(collegato);
        });
        var tipo = nuova.Collegamento?.Testo() ?? "rete";
        string provenienza;
        try { provenienza = viaCavo ? "dal cavo USB" : $"da {presa.RemoteEndPoint} ({tipo})"; }
        catch (Exception) { provenienza = tipo; }
        registro.Aggiungi($"Nuova connessione {provenienza}");
        nuova.ConfermaInCorso += (nome, _) => registro.Aggiungi($"«{nome}» è nuovo: chiesta la conferma con il codice");
        nuova.NonAmmesso += ciao =>
        {
            registro.Aggiungi($"«{ciao.Nome}» non entra: già collegati {telefoni.Massimo} telefoni");
            coda.TryEnqueue(() => AvvisaPieno(ciao.Nome));
        };

        // Sul thread di rete, prima del benvenuto: il formato e il video che seguono trovano già il telefono al suo posto.
        nuova.Salutato += accettato =>
        {
            var esito = telefoni.Accogli(nuova, accettato);
            switch (esito.Esito)
            {
                case EsitoArrivo.RestaIlCavo:
                    // Precedenza del cavo: lo stesso telefono già sul cavo non passa al Wi-Fi.
                    registro.Aggiungi($"«{accettato.Nome}» anche in {tipo}: resta il cavo USB");
                    _ = ChiudiSessioneAsync(nuova);
                    return;
                case EsitoArrivo.Pieno:
                    // Due telefoni arrivati insieme con un posto solo: entra il primo.
                    registro.Aggiungi($"«{accettato.Nome}» non entra: già collegati {telefoni.Massimo} telefoni");
                    coda.TryEnqueue(() => AvvisaPieno(accettato.Nome));
                    _ = ChiudiSessioneAsync(nuova);
                    return;
            }
            var collegato = esito.Telefono!;
            Volatile.Write(ref mio, collegato);
            var nuovoTelefono = esito.Esito == EsitoArrivo.Nuovo;
            if (nuovoTelefono) video.GetOrAdd(collegato, CreaVideo);
            registro.Aggiungi($"«{accettato.Nome}» accettato · {tipo}");
            if (esito.Esito == EsitoArrivo.CavoAlPostoDelWiFi) registro.Aggiungi("Il cavo USB prende il posto del Wi-Fi");
            else if (esito.DaChiudere is not null) registro.Aggiungi($"Il collegamento precedente di «{accettato.Nome}» si chiude");
            // Con l'arrivederci, come sul Mac: la sessione sostituita non si ricollega da sola.
            if (esito.DaChiudere is { } vecchia) _ = ChiudiSessioneAsync(vecchia);
            coda.TryEnqueue(() =>
            {
                if (collegato.Sessione == nuova && telefoni.Contiene(collegato)) SuTelefonoAccettato(collegato, nuova, accettato, nuovoTelefono);
            });
        };
        nuova.StatoRicevuto += stato => SuInterfaccia(collegato =>
        {
            var scelto = telefoni.ESelezionato(collegato);
            var eraInPausa = collegato.InPausa;
            collegato.Stato = stato;
            var avviso = collegato.Avvisi.Aggiorna(stato);
            StatoEffetti(collegato, stato);
            if (scelto)
            {
                MostraAvviso(stato, avviso);
                // In pausa o ripreso: la pillola in alto e il velo sopra il video.
                if (eraInPausa != collegato.InPausa) MostraScelto();
                else AggiornaTelefono();
                return;
            }
            // L'altro telefono: la barra sopra il video è del telefono nella webcam, qui basta la notifica.
            if (avviso is { } nuovo && nuovo != AvvisoTelefono.Nessuno)
            {
                var (titolo, messaggio) = SorveglianzaAvvisi.Testi(nuovo, stato);
                Notifica($"{collegato.Nome}: {titolo}", messaggio);
            }
            if (eraInPausa != collegato.InPausa) MostraVideo();
            MostraTelefoni();
        });
        nuova.StatisticheAggiornate += nuove => SuInterfaccia(collegato =>
        {
            collegato.Statistiche = nuove;
            collegato.StoriaLatenza.Aggiungi(nuove.LatenzaMs);
            if (telefoni.ESelezionato(collegato)) AggiornaTelefono();
            MostraTelefoni();
        });
        // Il lettore si crea subito sul thread di rete, così il primo fotogramma chiave non va perso.
        nuova.FormatoRicevuto += formato =>
        {
            if (Volatile.Read(ref mio) is not { } collegato || collegato.Sessione != nuova) return;
            collegato.Formato = formato;
            registro.Aggiungi($"Formato{(telefoni.Conteggio > 1 ? $" di «{collegato.Nome}»" : "")}: {formato.Larghezza}×{formato.Altezza} · {formato.Fps} fps · {(formato.Codec == Codec.Hevc ? "HEVC" : "H.264")}");
            if (!video.TryGetValue(collegato, out var suo)) return;
            var lettore = suo.Anteprima.Avvia(formato.Larghezza, formato.Altezza, formato.Codec);
            // Webcam, foto e registrazioni seguono solo il telefono nella webcam.
            if (telefoni.ESelezionato(collegato))
            {
                uscitaWebcam.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
                FormatoPerRiprese(formato);
            }
            // Un'app usa la webcam a 60 fps e questo formato ne ha meno: forse si chiede di più (P12).
            SuInterfaccia(_ => Valuta60Fps());
            // Senza decodificatore (di solito HEVC senza l'estensione dello Store) la finestra resterebbe nera.
            lettore.MediaFailed += (_, _) => SuInterfaccia(_ =>
            {
                if (suo.Lettore != lettore) return;
                registro.Aggiungi("Il video non si riesce a decodificare");
                suo.Errore = formato.Codec == Codec.Hevc
                    ? "Questo PC non decodifica l'HEVC. Sul telefono scegli H.264 nelle impostazioni, oppure installa «Estensioni video HEVC» da Microsoft Store."
                    : "Il video non si riesce a mostrare. Scollega e ricollega il telefono.";
                MostraVideo();
            });
            SuInterfaccia(_ =>
            {
                suo.Lettore = lettore;
                suo.Errore = null;
                MostraVideo();
            });
        };
        nuova.FotogrammaRicevuto += fotogramma =>
        {
            if (Volatile.Read(ref mio) is not { } collegato || collegato.Sessione != nuova) return;
            if (video.TryGetValue(collegato, out var suo)) suo.Anteprima.Accoda(fotogramma);
            if (!telefoni.ESelezionato(collegato)) return;
            uscitaWebcam.Accoda(fotogramma);
            FotogrammaPerRiprese(fotogramma);
        };
        nuova.CapacitaRicevute += capacita => SuInterfaccia(collegato =>
        {
            collegato.Capacita = capacita;
            CapacitaEffetti(collegato, capacita);
            if (!telefoni.ESelezionato(collegato)) return;
            MostraComandi(capacita);
            Valuta60Fps();
        });
        nuova.Silenzio += () => SuInterfaccia(collegato =>
        {
            registro.Aggiungi($"Nessun dato da 3 secondi{DiChi(collegato)}: riconnessione");
            collegato.InSilenzio = true;
            MostraScelto();
        });
        nuova.Ripresa += () => SuInterfaccia(collegato =>
        {
            registro.Aggiungi($"Dati ripresi{DiChi(collegato)}");
            collegato.InSilenzio = false;
            MostraScelto();
        });
        nuova.Chiusa += () => registro.Aggiungi(nuova.ChiusaDalComputer ? $"Collegamento chiuso dal PC ({tipo})" : $"Collegamento chiuso ({tipo})");
        // Chiusa dal computer (Scollega, rifiutato, sostituito, terzo telefono): sul cavo non si ricollega
        // da sola finché l'iPhone non viene staccato e ricollegato.
        if (viaCavo) nuova.Chiusa += () => { if (nuova.ChiusaDalComputer) cavo.Sospendi(presa); };
        // Accettata: il cavo funziona. Senza, una chiusura prima del «ciao» (il telefono rifiuta il cavo)
        // allunga l'attesa del prossimo tentativo, invece di riprovare ogni 2 secondi per sempre.
        if (viaCavo) nuova.Salutato += _ => cavo.StrettaRiuscita(presa);
        nuova.Chiusa += () =>
        {
            // Solo se era la sessione attuale del suo telefono (non sostituita, non scollegata dal PC): il telefono
            // resta nell'elenco in riconnessione, e viene dimenticato se non torna.
            if (telefoni.Perso(nuova) is not { } collegato) return;
            var perdita = collegato.Perdite;
            coda.TryEnqueue(() =>
            {
                if (!telefoni.Contiene(collegato)) return;
                MostraScelto();
                _ = DimenticaSeNonTornaAsync(collegato, perdita);
            });
        };

        nuova.Avvia();
    }

    /// <summary>Nel registro, con due telefoni: « di «iPhone di Sara»».</summary>
    private string DiChi(TelefonoCollegato collegato) => telefoni.Conteggio > 1 ? $" da «{collegato.Nome}»" : "";

    private VideoTelefono CreaVideo(TelefonoCollegato collegato)
    {
        var nuovo = new VideoTelefono();
        // Il primo fotogramma a schermo chiude la misura dell'avvio (1.11) della sessione attuale di quel telefono.
        nuovo.Anteprima.PrimaImmagine += () =>
        {
            if (collegato.Sessione is not { } attuale || !attuale.Avvio.Mostrato()) return;
            if (attuale.Avvio.Riga is { } riga) registro.Aggiungi(riga);
            var testo = attuale.Avvio.Testo;
            coda.TryEnqueue(() =>
            {
                if (collegato.Sessione != attuale) return;
                collegato.TestoAvvio = testo;
                if (telefoni.ESelezionato(collegato)) AggiornaTelefono();
            });
        };
        return nuovo;
    }

    /// <summary>Sul thread dell'interfaccia, dopo l'accettazione: il telefono nuovo, o lo stesso che torna.</summary>
    private void SuTelefonoAccettato(TelefonoCollegato collegato, SessioneComputer nuova, Ciao ciao, bool nuovoTelefono)
    {
        var scelto = telefoni.ESelezionato(collegato);
        if (!nuovoTelefono)
        {
            // Lo stesso telefono torna, forse con una sessione nuova ripartita in automatico: gli si rimandano i comandi
            // che la finestra ricorda per lui, così i due restano d'accordo. Gli effetti restano salvati sul telefono e
            // arrivano con il primo stato; il gobbo invece vive solo nella sessione: si rimanda completo.
            _ = ComandaAsync(nuova, collegato.Comandi.PerRicollegamento());
            RimandaGobbo(collegato, nuova);
        }
        else if (telefoni.Conteggio > 1)
        {
            registro.Aggiungi($"Due telefoni collegati: «{Scelto?.Nome}» è nella webcam");
            Notifica("Secondo telefono collegato", $"{ciao.Nome} è collegato a questo PC. Per usarlo nella webcam, sceglilo in «Telefoni».");
        }
        else
        {
            Notifica("Telefono collegato", $"{ciao.Nome} è collegato a questo PC.");
        }
        // La misura dell'avvio è di questa sessione: arriva con il suo primo fotogramma a schermo.
        collegato.TestoAvvio = nuova.Avvio.Testo;
        if (scelto)
        {
            // Una webcam già in uso: anche il telefono appena arrivato nella webcam mostra «IN ONDA».
            if (inOnda) Segnala(nuova);
            richiesta60Fps.Azzera();
            if (nuovoTelefono)
            {
                // Il primo telefono: comandi ed effetti come all'apertura, i suoi.
                ImpostaComandi(collegato.Comandi);
                MostraEffettiDelScelto();
                BarraAvvisoTelefono.IsOpen = false;
            }
        }
        // La finestra può essere cambiata mentre il telefono entrava: la sessione manda solo se il valore è nuovo.
        AggiornaAnteprimaVisibile();
        MostraScelto();
    }

    /// <summary>Un comando a una sessione precisa; un errore di rete qui non conta.</summary>
    private static async Task ComandaAsync(SessioneComputer attiva, Comando comando)
    {
        try { await attiva.ComandaAsync(comando); }
        catch (Exception) { }
    }

    /// <summary>Il terzo telefono non entra: lo si dice sopra il video (e con una notifica), con cosa fare.</summary>
    private void AvvisaPieno(string nome)
    {
        var messaggio = ElencoTelefoni.MessaggioPieno(nome);
        BarraTelefoni.Title = ElencoTelefoni.TitoloPieno;
        BarraTelefoni.Message = messaggio;
        BarraTelefoni.IsOpen = true;
        Notifica(ElencoTelefoni.TitoloPieno, messaggio);
    }

    // MARK: quale telefono nella webcam

    /// <summary>Lo stato del telefono nella webcam, per la pillola in alto, l'icona e il resto della finestra.</summary>
    private StatoCollegamento StatoDelScelto => Scelto switch
    {
        null => StatoCollegamento.NessunTelefono,
        { InRiconnessione: true } => StatoCollegamento.Riconnessione,
        _ => StatoCollegamento.Collegato,
    };

    /// <summary>Ridisegna la finestra per il telefono nella webcam (Mostra aggiorna anche video, riquadro e scheda).</summary>
    private void MostraScelto() => Mostra(StatoDelScelto);

    /// <summary>
    /// L'utente sceglie il telefono per la webcam (scheda «Telefoni» o clic sul riquadro piccolo). La registrazione in
    /// corso si chiude e si salva: è di un solo video.
    /// </summary>
    private void ScegliTelefono(TelefonoCollegato? collegato)
    {
        if (collegato is null || telefoni.ESelezionato(collegato) || !telefoni.Contiene(collegato)) return;
        PrimaDelCambio(Riprese.TelefonoCambiato);
        if (!telefoni.Seleziona(collegato)) return;
        registro.Aggiungi($"«{collegato.Nome}» nella webcam");
        DopoIlCambio();
    }

    /// <summary>Mentre il telefono di prima è ancora quello scelto: cursori in attesa, «IN ONDA», foto e registrazione.</summary>
    private void PrimaDelCambio(string fraseRegistrazione)
    {
        MandaEffettiInAttesa();
        // Il rosso «IN ONDA» resta solo sul telefono che va davvero alle app.
        if (inOnda && sessione is { } vecchia) InviaInOnda(vecchia, false);
        FermaRiprese(fraseRegistrazione);
    }

    /// <summary>Il telefono scelto è cambiato (o non c'è più): webcam, foto, comandi, effetti e finestra seguono lui.</summary>
    private void DopoIlCambio()
    {
        richiesta60Fps.Azzera();
        BarraAvvisoTelefono.IsOpen = false;
        if (Scelto is not { } scelto)
        {
            // Nessun telefono: tutto come all'apertura.
            uscitaWebcam.Ferma();
            istantanee.Ferma();
            AzzeraComandi();
            MostraObiettiviDiEsempio();
            MostraEffettiDelScelto();
            Mostra(StatoCollegamento.NessunTelefono);
            return;
        }
        // Webcam e foto ripartono dal prossimo fotogramma chiave del telefono scelto.
        if (scelto.Formato is { } formato)
        {
            uscitaWebcam.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
            FormatoPerRiprese(formato);
        }
        else
        {
            uscitaWebcam.Ferma();
            istantanee.Ferma();
        }
        if (scelto.Capacita is { } capacita) MostraComandi(capacita);
        else MostraObiettiviDiEsempio();
        ImpostaComandi(scelto.Comandi);
        MostraEffettiDelScelto();
        if (scelto.Stato is { } stato) MostraAvviso(stato, null);
        if (inOnda && scelto.Sessione is { } attiva) Segnala(attiva);
        // Il telefono scelto si vede grande, l'altro solo nel riquadro: la pausa intelligente di ognuno cambia.
        AggiornaAnteprimaVisibile();
        Valuta60Fps();
        MostraScelto();
    }

    /// <summary>«IN ONDA» acceso o spento su un telefono preciso. Un errore di rete qui non conta.</summary>
    private static void InviaInOnda(SessioneComputer attiva, bool acceso) => _ = Task.Run(async () =>
    {
        try { await attiva.SegnalaAsync(new InOnda(acceso)); }
        catch (Exception) { }
    });

    /// <summary>Uscendo dalla modalità avanzata anche gli altri telefoni tornano all'esposizione e al bianco automatici.</summary>
    private void AutomaticoAgliAltri()
    {
        foreach (var altro in telefoni.Telefoni)
        {
            if (telefoni.ESelezionato(altro) || altro.Sessione is not { } attiva) continue;
            var comandi = altro.Comandi;
            if (!comandi.Manuale && comandi.BiancoAutomatico) continue;
            var comando = new Comando(Iso: comandi.Manuale ? 0 : null, Tempo: comandi.Manuale ? 0 : null, Bianco: comandi.BiancoAutomatico ? null : 0);
            altro.Comandi = comandi.Applica(comando);
            _ = ComandaAsync(attiva, comando);
        }
    }

    // MARK: scollega e dimentica

    /// <summary>«Scollega il telefono» sotto il video: il telefono nella webcam.</summary>
    private void SuScollega(object sender, RoutedEventArgs e)
    {
        if (Scelto is { } scelto) _ = ScollegaAsync(scelto);
    }

    /// <summary>
    /// Chiusura voluta: il telefono riceve l'arrivederci e la finestra si aggiorna subito. Senza telefono indicato (menu
    /// dell'icona) si scollegano tutti. Durante la riconnessione la sessione non c'è più: si dimentica e basta.
    /// </summary>
    private async Task ScollegaAsync(TelefonoCollegato? solo = null)
    {
        foreach (var collegato in solo is null ? telefoni.Telefoni : [solo])
        {
            registro.Aggiungi($"«{collegato.Nome}» scollegato dal PC");
            if (Dimentica(collegato) is { } chiusa) await ChiudiSessioneAsync(chiusa);
        }
    }

    /// <summary>Arrivederci al telefono, poi chiusura. Un errore di rete qui non deve chiudere l'app.</summary>
    private static async Task ChiudiSessioneAsync(SessioneComputer chiusa)
    {
        try
        {
            await chiusa.ChiudiAsync();
            await chiusa.DisposeAsync();
        }
        catch (Exception) { }
    }

    /// <summary>
    /// Toglie il telefono dall'elenco e ferma il suo video; se era nella webcam ci va l'altro, o la finestra torna
    /// all'attesa. Restituisce la sessione da chiudere, se c'è.
    /// </summary>
    private SessioneComputer? Dimentica(TelefonoCollegato collegato)
    {
        var eraScelto = telefoni.ESelezionato(collegato);
        if (eraScelto) PrimaDelCambio(Riprese.TelefonoScollegato);
        var sessioneChiusa = telefoni.Rimuovi(collegato);
        if (video.TryRemove(collegato, out var suo))
        {
            if (ReferenceEquals(Video.MediaPlayer, suo.Lettore)) Video.SetMediaPlayer(null);
            if (ReferenceEquals(VideoPiccolo.MediaPlayer, suo.Lettore)) VideoPiccolo.SetMediaPlayer(null);
            suo.Dispose();
        }
        if (telefoni.Conteggio < telefoni.Massimo) BarraTelefoni.IsOpen = false;
        if (eraScelto) DopoIlCambio();
        else MostraScelto();
        return sessioneChiusa;
    }

    private async Task DimenticaSeNonTornaAsync(TelefonoCollegato collegato, int perdita)
    {
        await Task.Delay(AttesaRiconnessione);
        // Tornato, perso di nuovo (conta solo l'attesa dell'ultima perdita) o già scollegato: niente da fare.
        if (!telefoni.Contiene(collegato) || collegato.Perdite != perdita || collegato.Sessione is not null) return;
        registro.Aggiungi($"«{collegato.Nome}» non è tornato in {AttesaRiconnessione.TotalSeconds:0} secondi");
        Dimentica(collegato);
        Notifica("Telefono perso", $"{collegato.Nome} non risponde più. Riapri WebcamLR sul telefono per ricollegarlo.");
    }

    /// <summary>All'uscita: tutte le sessioni e tutti i decodificatori.</summary>
    private async Task ChiudiTuttiAsync()
    {
        foreach (var suo in video.Values) suo.Dispose();
        video.Clear();
        foreach (var collegato in telefoni.Telefoni)
        {
            if (collegato.Sessione is { } attiva) await attiva.DisposeAsync();
        }
    }

    // MARK: video grande e riquadro piccolo

    /// <summary>
    /// Il telefono nella webcam nel video grande, l'altro nel riquadro piccolo (solo nella finestra intera e se non è
    /// stato chiuso). I lettori passano da un riquadro all'altro senza ripartire.
    /// </summary>
    private void MostraVideo()
    {
        if (VideoPiccolo is null) return;
        var scelto = Scelto;
        var altro = telefoni.Altro;
        var suoScelto = scelto is null ? null : video.GetValueOrDefault(scelto);
        var suoAltro = altro is null ? null : video.GetValueOrDefault(altro);
        var piccoloVisibile = altro is not null && riquadroAperto && !InMini;
        var grande = suoScelto is { Errore: null } ? suoScelto.Lettore : null;
        var piccolo = piccoloVisibile && suoAltro is { Errore: null } ? suoAltro.Lettore : null;
        if (!ReferenceEquals(Video.MediaPlayer, grande) || !ReferenceEquals(VideoPiccolo.MediaPlayer, piccolo))
        {
            // Un lettore sta in un solo riquadro alla volta: prima si staccano tutti e due.
            Video.SetMediaPlayer(null);
            VideoPiccolo.SetMediaPlayer(null);
            Video.SetMediaPlayer(grande);
            VideoPiccolo.SetMediaPlayer(piccolo);
        }
        Video.Visibility = Visibile(grande is not null);
        Segnaposto.Opacity = grande is null ? 1 : 0;
        if (suoScelto?.Errore is { } errore) MessaggioAnteprima.Text = errore;

        RiquadroPiccolo.Visibility = Visibile(piccoloVisibile);
        PulsanteMostraRiquadro.Visibility = Visibile(altro is not null && !riquadroAperto && !InMini);
        if (!piccoloVisibile || altro is null) return;
        SpecchioPiccolo.ScaleX = Specchio.ScaleX;
        NomePiccolo.Text = altro.Nome;
        var testo = altro.InRiconnessione ? $"Mi ricollego a {altro.Nome}…"
            : altro.InPausa ? $"In pausa · {PausaIntelligente.Motivo(altro.Stato!.Pausa)}"
            : suoAltro?.Errore is not null ? "Il video non si riesce a mostrare."
            : piccolo is null ? "In attesa del video…"
            : "";
        StatoPiccolo.Text = testo;
        VideoPiccolo.Visibility = Visibile(piccolo is not null && testo.Length == 0);
        AutomationProperties.SetName(RiquadroPiccolo, $"{altro.Nome}: clic per metterlo nella webcam");
    }

    /// <summary>Clic sul riquadro piccolo: quel telefono va nella webcam (il pulsante per chiuderlo a parte).</summary>
    private void SuRiquadroPiccolo(object sender, TappedRoutedEventArgs e)
    {
        for (var elemento = e.OriginalSource as DependencyObject; elemento is not null && elemento != RiquadroPiccolo;
             elemento = VisualTreeHelper.GetParent(elemento))
        {
            if (elemento == PulsanteChiudiRiquadro) return;
        }
        e.Handled = true;
        ScegliTelefono(telefoni.Altro);
    }

    /// <summary>Chiude il riquadro piccolo: nessuno guarda l'altro telefono, che può andare in pausa (se nessuna app lo usa).</summary>
    private void SuChiudiRiquadro(object sender, RoutedEventArgs e)
    {
        ImpostaRiquadro(false);
    }

    private void SuMostraRiquadro(object sender, RoutedEventArgs e) => ImpostaRiquadro(true);

    private void ImpostaRiquadro(bool aperto)
    {
        riquadroAperto = aperto;
        AggiornaAnteprimaVisibile();
        MostraVideo();
    }

    // MARK: scheda «Telefoni»

    /// <summary>Una riga della scheda «Telefoni»: nome, dettagli, «Nella webcam» e «Scollega».</summary>
    private sealed record RigaTelefono(TelefonoCollegato Telefono, Border Scheda, TextBlock Nome, TextBlock Dettagli, RadioButton Webcam);

    private readonly List<RigaTelefono> righeTelefoni = [];
    /// Vero mentre la scheda imposta «Nella webcam» da codice: quel cambio non è una scelta dell'utente.
    private bool aggiornoRighe;

    /// <summary>
    /// Con un telefono solo resta la scheda «TELEFONO» di sempre; con due, «TELEFONI» e una riga per telefono, con la
    /// scelta «Nella webcam» (in ciano, come ogni selezione) e «Scollega».
    /// </summary>
    private void MostraTelefoni()
    {
        if (ElencoSchedeTelefoni is null) return;
        var elenco = telefoni.Telefoni;
        var due = elenco.Count > 1;
        EtichettaTelefoni.Text = due ? "TELEFONI" : "TELEFONO";
        SchedaTelefono.Visibility = Visibile(!due);
        ElencoSchedeTelefoni.Visibility = Visibile(due);
        if (!due)
        {
            righeTelefoni.Clear();
            ElencoSchedeTelefoni.Children.Clear();
            return;
        }
        if (!righeTelefoni.Select(r => r.Telefono).SequenceEqual(elenco))
        {
            righeTelefoni.Clear();
            ElencoSchedeTelefoni.Children.Clear();
            foreach (var collegato in elenco)
            {
                var riga = CreaRiga(collegato);
                righeTelefoni.Add(riga);
                ElencoSchedeTelefoni.Children.Add(riga.Scheda);
            }
        }
        aggiornoRighe = true;
        foreach (var riga in righeTelefoni)
        {
            var scelto = telefoni.ESelezionato(riga.Telefono);
            riga.Nome.Text = riga.Telefono.Nome;
            riga.Dettagli.Text = DettagliRiga(riga.Telefono);
            riga.Webcam.IsChecked = scelto;
            riga.Scheda.BorderBrush = scelto ? Pennello("Ciano") : Pennello("Linea");
            AutomationProperties.SetName(riga.Scheda, scelto ? $"{riga.Telefono.Nome}, nella webcam" : riga.Telefono.Nome);
        }
        aggiornoRighe = false;
    }

    private RigaTelefono CreaRiga(TelefonoCollegato collegato)
    {
        var nome = new TextBlock { FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis };
        var dettagli = new TextBlock
        {
            FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
            FontSize = 12,
            Foreground = Pennello("TestoSecondario"),
            TextWrapping = TextWrapping.Wrap,
        };
        var webcam = new RadioButton { Content = "Nella webcam", GroupName = "TelefonoNellaWebcam", MinWidth = 0 };
        ToolTipService.SetToolTip(webcam, "Questo telefono va alla webcam per le altre app, a foto e registrazioni; i comandi a destra valgono per lui");
        webcam.Checked += (_, _) => { if (!aggiornoRighe) ScegliTelefono(collegato); };
        var scollega = new Button { Content = "Scollega", Padding = new Thickness(10, 2, 10, 4), VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(scollega, "Chiude il collegamento con questo telefono: non si ricollega da solo");
        AutomationProperties.SetName(scollega, $"Scollega {collegato.Nome}");
        scollega.Click += (_, _) => _ = ScollegaAsync(collegato);
        var azioni = new Grid { ColumnSpacing = 8 };
        azioni.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        azioni.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        azioni.Children.Add(webcam);
        Grid.SetColumn(scollega, 1);
        azioni.Children.Add(scollega);
        var scheda = new Border
        {
            Background = Pennello("Scheda"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(10, 8, 10, 8),
            Child = new StackPanel { Spacing = 4, Children = { nome, dettagli, azioni } },
        };
        return new RigaTelefono(collegato, scheda, nome, dettagli, webcam);
    }

    /// <summary>«Cavo USB · 80%», oppure cosa sta succedendo (riconnessione, pausa).</summary>
    private static string DettagliRiga(TelefonoCollegato collegato)
    {
        var parti = new List<string>();
        if (collegato.InRiconnessione) parti.Add("Mi ricollego…");
        else if (collegato.InPausa) parti.Add("In pausa");
        else if (collegato.Collegamento is { } tipo) parti.Add(tipo.Testo());
        if (collegato.Stato is { Batteria: >= 0 } stato) parti.Add($"{stato.Batteria}%");
        return string.Join(" · ", parti);
    }
}
