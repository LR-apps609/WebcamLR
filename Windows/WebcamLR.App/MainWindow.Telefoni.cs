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
/// destra valgono per lui. L'altro, la «CAM 2», compare solo quando si collega: un riquadro in basso a destra dentro il video
/// («Usa prospettiva», o un clic, lo mette nella webcam), e una scheda in «Telefoni» a sinistra con «Nella webcam» e
/// «Scollega». Con un telefono solo la finestra è quella di sempre.
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

    /// <summary>Vero se il riquadro piccolo è aperto (va al telefono come «anteprima»).</summary>
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
        // Da vetro a uscita, ogni secondo dal thread della sessione: l'anteprima di questo telefono e, se è quello nella
        // webcam e un'app la usa, la webcam (Protocollo.md, «Latenza»).
        nuova.MisuraUscita = () =>
        {
            if (Volatile.Read(ref mio) is not { } collegato) return default;
            int? anteprima = video.TryGetValue(collegato, out var suo) ? suo.Anteprima.Ritardo.Valore(Orologio.Adesso()) : null;
            // Con gli effetti accesi l'anteprima è l'immagine del motore: da vetro a quella.
            if (SulComputer && telefoni.ESelezionato(collegato) && motoreVideo.Attivo
                && motoreVideo.RitardoAnteprima.Valore(Orologio.Adesso()) is int elaborata) anteprima = elaborata;
            int? webcam = telefoni.ESelezionato(collegato) && uscitaWebcam.InUso ? uscitaWebcam.RitardoMs : null;
            return (anteprima, webcam);
        };
        void SuInterfaccia(Action<TelefonoCollegato> azione) => coda.TryEnqueue(() =>
        {
            if (Volatile.Read(ref mio) is { } collegato && collegato.Sessione == nuova && telefoni.Contiene(collegato)) azione(collegato);
        });
        var tipo = nuova.Collegamento?.Testo() ?? Testi.T("Registro_Rete");
        string provenienza;
        try { provenienza = viaCavo ? Testi.T("Registro_DalCavo") : Testi.T("Registro_DaIndirizzo", presa.RemoteEndPoint, tipo); }
        catch (Exception) { provenienza = tipo; }
        registro.Aggiungi(Testi.T("Registro_NuovaConnessione", provenienza));
        nuova.ConfermaInCorso += (nome, _) => registro.Aggiungi(Testi.T("Registro_ChiestaConferma", nome));
        nuova.NonAmmesso += ciao =>
        {
            // WebcamLR Pro: con il telefono nella webcam gratis il secondo non entra; altrimenti i posti sono pieni.
            var perPro = nuova.ImprontaTelefono is { } impronta && telefoni.FuoriPerPro(impronta);
            registro.Aggiungi(perPro ? Testi.T("Registro_NonEntraPro", ciao.Nome)
                : Testi.T("Registro_NonEntraPieno", ciao.Nome, telefoni.Massimo));
            coda.TryEnqueue(() => AvvisaPieno(ciao.Nome, perPro));
        };

        // Sul thread di rete, prima del benvenuto: il formato e il video che seguono trovano già il telefono al suo posto.
        nuova.Salutato += accettato =>
        {
            var esito = telefoni.Accogli(nuova, accettato);
            switch (esito.Esito)
            {
                case EsitoArrivo.RestaIlCavo:
                    // Precedenza del cavo: lo stesso telefono già sul cavo non passa al Wi-Fi.
                    registro.Aggiungi(Testi.T("Registro_RestaCavo", accettato.Nome, tipo));
                    _ = ChiudiSessioneAsync(nuova);
                    return;
                case EsitoArrivo.RestaIlWiFi:
                    // «Wi-Fi» scelto a mano, o il cavo arriva subito dopo un cambio: resta il Wi-Fi. Il cavo si ferma
                    // ma non come «Scollega»: torna se la scelta cambia o se il Wi-Fi si stacca.
                    registro.Aggiungi(Testi.T("Registro_RestaWiFi", accettato.Nome));
                    nuova.LasciataPerScelta = true;
                    _ = ChiudiSessioneAsync(nuova);
                    // In «Automatico» il cavo è stato solo rimandato (i 30 secondi dopo un cambio): poi si riprova.
                    if (esito.Telefono?.Regola.Preferenza == PreferenzaCollegamento.Automatico)
                        _ = Task.Delay(RegolaCollegamento.PausaDopoCambio).ContinueWith(_ => cavo.RiprendiScelti(), TaskScheduler.Default);
                    return;
                case EsitoArrivo.Pieno:
                    // Due telefoni arrivati insieme con un posto solo: entra il primo.
                    registro.Aggiungi(Testi.T("Registro_NonEntraPieno", accettato.Nome, telefoni.Massimo));
                    coda.TryEnqueue(() => AvvisaPieno(accettato.Nome));
                    _ = ChiudiSessioneAsync(nuova);
                    return;
                case EsitoArrivo.SenzaPro:
                    registro.Aggiungi(Testi.T("Registro_NonEntraPro", accettato.Nome));
                    coda.TryEnqueue(() => AvvisaPieno(accettato.Nome, perPro: true));
                    _ = ChiudiSessioneAsync(nuova);
                    return;
            }
            var collegato = esito.Telefono!;
            Volatile.Write(ref mio, collegato);
            var nuovoTelefono = esito.Esito == EsitoArrivo.Nuovo;
            if (nuovoTelefono) video.GetOrAdd(collegato, CreaVideo);
            registro.Aggiungi(Testi.T("Registro_Accettato", accettato.Nome, tipo));
            if (esito.Esito == EsitoArrivo.CavoAlPostoDelWiFi) registro.Aggiungi(Testi.T("Registro_CavoAlPostoWiFi"));
            else if (esito.Esito == EsitoArrivo.WiFiAlPostoDelCavo) registro.Aggiungi(Testi.T("Registro_WiFiAlPostoCavo"));
            else if (esito.DaChiudere is not null) registro.Aggiungi(Testi.T("Registro_SiChiudePrecedente", accettato.Nome));
            // Il cavo lasciato per il Wi-Fi scelto non è «Scollega»: torna se la scelta cambia.
            if (esito.Esito == EsitoArrivo.WiFiAlPostoDelCavo && esito.DaChiudere is { } lasciata) lasciata.LasciataPerScelta = true;
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
            var viaCavoPrima = ContrattoCollegamento.ViaCavo(collegato.Stato, collegato.Collegamento);
            var obiettivoPrima = collegato.Stato?.Obiettivo;
            var audioPrima = collegato.Stato?.Audio;
            var sistemaPrima = EffettiDelSistema.Di(collegato.Stato);
            var cambioPausa = collegato.AggiornaStato(stato);
            RegistraPausa(collegato, cambioPausa, scelto);
            // Le strade che il telefono conosce e la sua preferenza, per l'etichetta sul video. Se il telefono l'ha cambiata
            // da sé, il cavo lasciato per il Wi-Fi torna, quando ora serve.
            if (collegato.AggiornaStrade(stato, telefoni.Orologio()) && collegato.Regola.Preferenza != PreferenzaCollegamento.WiFi)
                cavo.RiprendiScelti();
            var avviso = collegato.Avvisi.Aggiorna(stato);
            StatoEffetti(collegato, stato, EffettiDelSistema.Di(stato) != sistemaPrima);
            // Obiettivo, Ritratto o Luce da studio cambiati: il telecomando lo sa (anche se non è nella webcam).
            MandaEffetti(collegato);
            // Zoom, torcia, esposizione, bianco, ISO e tempo seguono il telefono (1.14), tranne quelli appena mandati da qui.
            var comandiPrima = collegato.Comandi;
            collegato.Comandi = collegato.Allineamento.Allinea(collegato.Comandi, stato, obiettivoPrima, collegato.Capacita, AdessoMs);
            if (scelto)
            {
                if (collegato.Comandi != comandiPrima || obiettivoPrima != stato.Obiettivo) MostraComandiDelTelefono(collegato);
                // Frontale ↔ posteriore: «Specchia» e «Sfondo» grigi o di nuovo usabili, anche se gli effetti non cambiano.
                if (obiettivoPrima != stato.Obiettivo) MostraPulsantiVideo();
                MostraAvviso(stato, avviso);
                MicrofonoDalTelefono(collegato, audioPrima, stato.Audio);
                // In pausa o ripreso (o un altro motivo), o un'altra strada (Wi-Fi ↔ USB): la pillola in alto e il velo sopra il video.
                if (eraInPausa != collegato.InPausa || !cambioPausa.Nessuno || viaCavoPrima != ContrattoCollegamento.ViaCavo(stato, collegato.Collegamento)) MostraScelto();
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
            // Ogni 10 secondi con gli effetti accesi, accanto alle «Prestazioni» del telefono: fps reali e Mbit/s in arrivo.
            if (collegato.Sessione is not null && collegato.Numeri.Conta(collegato.Stato))
                registro.Aggiungi(Testi.T("Registro_Numeri", DiChi(collegato), nuove.Fps, nuove.MegabitAlSecondo));
            // Ogni 30 secondi con il video: le tappe da vetro a uscita e il ritardo dell'audio, da mandare dopo una prova.
            if (collegato.Ritardi.Conta(nuove))
            {
                var webcamQui = telefoni.ESelezionato(collegato) && uscitaWebcam.InUso;
                int? audio = MicrofonoAcceso && Volatile.Read(ref telefonoMicrofono) == collegato ? (int)(microfono.Ritardo / 1000) : null;
                registro.Aggiungi(Testi.T("Registro_Ritardo", DiChi(collegato), RitardoNelRegistro.Testo(nuove.ArrivoMs),
                    RitardoNelRegistro.Testo(nuove.AnteprimaMs), RitardoNelRegistro.Testo(nuove.WebcamMs),
                    RitardoNelRegistro.Testo(webcamQui ? uscitaWebcam.AttesaSorgenteMs : null),
                    webcamQui ? uscitaWebcam.RecuperatoMs : 0, RitardoNelRegistro.Testo(audio)));
            }
            if (telefoni.ESelezionato(collegato))
            {
                // Il motore effetti: i suoi avvisi e, ogni 30 secondi, i suoi tempi nel registro.
                RegistraMotore(collegato);
                AggiornaTelefono();
                MostraMicrofono();
            }
            MostraTelefoni();
        });
        // Il lettore si crea subito sul thread di rete, così il primo fotogramma chiave non va perso.
        nuova.FormatoRicevuto += formato =>
        {
            if (Volatile.Read(ref mio) is not { } collegato || collegato.Sessione != nuova) return;
            collegato.Formato = formato;
            registro.Aggiungi(Testi.T("Registro_Formato", DiChi(collegato), formato.Larghezza, formato.Altezza, formato.Fps, (formato.Codec == Codec.Hevc ? "HEVC" : "H.264")));
            if (!video.TryGetValue(collegato, out var suo)) return;
            MediaPlayer lettore;
            try { lettore = suo.Anteprima.Avvia(formato.Larghezza, formato.Altezza, formato.Codec); }
            catch (Exception errore)
            {
                // Un formato che Windows non accetta non deve far cadere il collegamento: si dice e si aspetta il prossimo.
                App.ScriviErrore(errore);
                SuInterfaccia(_ =>
                {
                    suo.Errore = Testi.T("Video_NonSiMostraScollega");
                    MostraVideo();
                });
                return;
            }
            // Webcam, foto e registrazioni seguono solo il telefono nella webcam.
            if (telefoni.ESelezionato(collegato))
            {
                uscitaWebcam.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
                FormatoPerRiprese(formato);
                // Con gli effetti sul computer il motore ha il suo decodificatore, da cui prendono webcam, foto e registrazione.
                if (SulComputer) motoreVideo.Formato(formato.Larghezza, formato.Altezza, formato.Codec);
            }
            // Un'app usa la webcam a 60 fps e questo formato ne ha meno: forse si chiede di più (P12).
            SuInterfaccia(_ => Valuta60Fps());
            // Senza decodificatore (di solito HEVC senza l'estensione dello Store) la finestra resterebbe nera.
            lettore.MediaFailed += (_, _) => SuInterfaccia(_ =>
            {
                if (suo.Lettore != lettore) return;
                registro.Aggiungi(Testi.T("Video_NonSiDecodifica"));
                suo.Errore = formato.Codec == Codec.Hevc
                    ? Testi.T("Video_SenzaHevc")
                    : Testi.T("Video_NonSiMostraScollega");
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
            // La differenza tra gli orologi va con il fotogramma: serve per il ritardo da vetro a uscita.
            var scarto = nuova.ScartoOrologi;
            if (video.TryGetValue(collegato, out var suo)) suo.Anteprima.Accoda(fotogramma, scarto);
            if (!telefoni.ESelezionato(collegato)) return;
            uscitaWebcam.Accoda(fotogramma, scarto);
            if (SulComputer) motoreVideo.Accoda(fotogramma, scarto);
            FotogrammaPerRiprese(fotogramma);
        };
        nuova.CapacitaRicevute += capacita => SuInterfaccia(collegato =>
        {
            collegato.Capacita = capacita;
            CapacitaEffetti(collegato, capacita);
            // Effetti sul computer: alla prima della sessione telecomando o spegnimento; poi `effetti` se Pro è cambiato.
            DecidiEffetti(collegato, capacita);
            MandaEffetti(collegato);
            if (!telefoni.ESelezionato(collegato)) return;
            MostraComandi(capacita);
            Valuta60Fps();
            // Il microfono: l'audio si chiede appena il telefono dice di saperlo mandare (W2).
            ChiediAudioSeServe();
            MostraMicrofono();
        });
        CollegaMicrofono(nuova, () => Volatile.Read(ref mio));
        // «Usa questa prospettiva» toccato sul telefono (CAM 2): come il pulsante sul riquadro.
        nuova.ProspettivaChiesta += () => SuInterfaccia(collegato =>
        {
            registro.Aggiungi(Testi.T("Registro_ProspettivaDalTelefono", collegato.Nome));
            ScegliTelefono(collegato);
        });
        // Un tocco su Specchia, Sfoca o Luce del telefono telecomando (effetti sul computer).
        nuova.EffettoChiesto += richiesta => SuInterfaccia(collegato => ApplicaEffettoChiesto(collegato, richiesta));
        nuova.Silenzio += () => SuInterfaccia(collegato =>
        {
            registro.Aggiungi(Testi.T("Registro_NessunDato", DiChi(collegato)));
            collegato.InSilenzio = true;
            MostraScelto();
        });
        nuova.Ripresa += () => SuInterfaccia(collegato =>
        {
            registro.Aggiungi(Testi.T("Registro_DatiRipresi", DiChi(collegato)));
            collegato.InSilenzio = false;
            MostraScelto();
        });
        nuova.Chiusa += () => registro.Aggiungi(nuova.ChiusaDalComputer ? Testi.T("Registro_ChiusoDalPC", tipo) : Testi.T("Registro_Chiuso", tipo));
        // Chiusa dal computer (Scollega, rifiutato, sostituito, terzo telefono): sul cavo non si ricollega
        // da sola finché l'iPhone non viene staccato e ricollegato.
        // Lasciata per la strada scelta (resta il Wi-Fi): il cavo torna quando la scelta cambia o il Wi-Fi si stacca.
        if (viaCavo) nuova.Chiusa += () => { if (nuova.ChiusaDalComputer) cavo.Sospendi(presa, perScelta: nuova.LasciataPerScelta); };
        // Accettata: il cavo funziona. Senza, una chiusura prima del «ciao» (il telefono rifiuta il cavo)
        // allunga l'attesa del prossimo tentativo, invece di riprovare ogni 2 secondi per sempre.
        if (viaCavo) nuova.Salutato += _ => cavo.StrettaRiuscita(presa);
        nuova.Chiusa += () =>
        {
            // Solo se era la sessione attuale del suo telefono (non sostituita, non scollegata dal PC): il telefono
            // resta nell'elenco in riconnessione, e viene dimenticato se non torna.
            if (telefoni.Perso(nuova) is not { } collegato) return;
            // La strada in uso si è staccata: il cavo lasciato per il Wi-Fi torna, così il video non si perde.
            cavo.RiprendiScelti();
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

    /// <summary>Nel registro, con due telefoni: « da «iPhone di Sara»».</summary>
    private string DiChi(TelefonoCollegato collegato) => telefoni.Conteggio > 1 ? Testi.T("Registro_DiChi", collegato.Nome) : "";

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
        // Effetti sul computer: si decide alla prima `capacita` di questa sessione (DecidiEffetti): telecomando, o un
        // telefono di prima che spegne i suoi effetti di immagine.
        collegato.Telecomando.NuovaSessione();
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
            registro.Aggiungi(Testi.T("Registro_DueTelefoni", Scelto?.Nome));
            Notifica(Testi.T("Notifica_SecondoTelefono"), Testi.T("Notifica_SecondoTelefonoTesto", ciao.Nome));
        }
        else
        {
            Notifica(Testi.T("Notifica_TelefonoCollegato"), Testi.T("Notifica_TelefonoCollegatoTesto", ciao.Nome));
        }
        // La misura dell'avvio è di questa sessione: arriva con il suo primo fotogramma a schermo.
        collegato.TestoAvvio = nuova.Avvio.Testo;
        // Sessione nuova: l'audio va chiesto di nuovo (subito se il telefono aveva già detto di saperlo mandare).
        collegato.AudioComandato = false;
        if (scelto) MicrofonoSegueScelto(sessioneNuova: true);
        if (scelto)
        {
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
        // «IN ONDA» e la scelta (CAM 1 o CAM 2) a tutti: la sessione nuova non li sa ancora, e i telefoni ora sono due.
        SegnalaATutti();
        MostraScelto();
    }

    /// <summary>Un comando a una sessione precisa; un errore di rete qui non conta.</summary>
    private static async Task ComandaAsync(SessioneComputer attiva, Comando comando)
    {
        try { await attiva.ComandaAsync(comando); }
        catch (Exception) { }
    }

    /// <summary>
    /// Il terzo telefono non entra, o il secondo senza WebcamLR Pro sul telefono nella webcam: lo si dice sopra il video
    /// (e con una notifica), con cosa fare.
    /// </summary>
    private void AvvisaPieno(string nome, bool perPro = false)
    {
        var titolo = perPro ? RegolePro.TitoloSecondoTelefono : ElencoTelefoni.TitoloPieno;
        var messaggio = perPro ? RegolePro.MessaggioSecondoTelefono(nome) : ElencoTelefoni.MessaggioPieno(nome);
        BarraTelefoni.Title = titolo;
        BarraTelefoni.Message = messaggio;
        BarraTelefoni.IsOpen = true;
        Notifica(titolo, messaggio);
    }

    // MARK: quale telefono nella webcam

    /// <summary>Lo stato del telefono nella webcam, per la pillola in alto, l'icona e il resto della finestra.</summary>
    private FaseCollegamento StatoDelScelto => Scelto switch
    {
        null => FaseCollegamento.NessunTelefono,
        { InRiconnessione: true } => FaseCollegamento.Riconnessione,
        _ => FaseCollegamento.Collegato,
    };

    /// <summary>Ridisegna la finestra per il telefono nella webcam (Mostra aggiorna anche video, riquadro e scheda).</summary>
    private void MostraScelto() => Mostra(StatoDelScelto);

    /// <summary>
    /// L'utente sceglie il telefono per la webcam (scheda «Telefoni», «Usa prospettiva», clic sul riquadro piccolo o
    /// «Usa questa prospettiva» sul telefono). La registrazione in corso si chiude e si salva, perché è di un solo video:
    /// prima si chiede (windows.md 1.6); con «Annulla» la scheda torna com'era.
    /// </summary>
    private void ScegliTelefono(TelefonoCollegato? collegato)
    {
        if (collegato is null || telefoni.ESelezionato(collegato) || !telefoni.Contiene(collegato)) return;
        PrimaDiFermareLaRegistrazione(() => MettiNellaWebcam(collegato), MostraTelefoni);
    }

    private void MettiNellaWebcam(TelefonoCollegato collegato)
    {
        // Durante la domanda il telefono può essere andato via, o essere già nella webcam.
        if (telefoni.ESelezionato(collegato) || !telefoni.Contiene(collegato))
        {
            MostraTelefoni();
            return;
        }
        PrimaDelCambio(Riprese.TelefonoCambiato);
        if (!telefoni.Seleziona(collegato)) return;
        registro.Aggiungi(Testi.T("Registro_NellaWebcam", collegato.Nome));
        DopoIlCambio();
    }

    /// <summary>Mentre il telefono di prima è ancora quello scelto: cursori in attesa, «IN ONDA», foto e registrazione.</summary>
    private void PrimaDelCambio(string fraseRegistrazione)
    {
        MandaEffettiInAttesa();
        FermaRiprese(fraseRegistrazione);
    }

    /// <summary>Il telefono scelto è cambiato (o non c'è più): webcam, foto, comandi, effetti e finestra seguono lui.</summary>
    private void DopoIlCambio()
    {
        richiesta60Fps.Azzera();
        obiettivoInAttesa = null;
        BarraAvvisoTelefono.IsOpen = false;
        if (Scelto is not { } scelto)
        {
            // Nessun telefono: tutto come all'apertura.
            uscitaWebcam.Ferma();
            istantanee.Ferma();
            AzzeraComandi();
            MostraObiettiviDiEsempio();
            MostraEffettiDelScelto();
            MicrofonoSegueScelto();
            Mostra(FaseCollegamento.NessunTelefono);
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
        // Il rosso «IN ONDA» solo sul telefono che va davvero alle app, e a ognuno la scelta nuova.
        SegnalaATutti();
        // Il telefono scelto si vede grande, l'altro solo nel riquadro: la pausa intelligente di ognuno cambia.
        AggiornaAnteprimaVisibile();
        Valuta60Fps();
        MicrofonoSegueScelto();
        MostraScelto();
    }

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
            registro.Aggiungi(Testi.T("Registro_ScollegatoDalPC", collegato.Nome));
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
        // In sottofondo il telefono può restare via fino alla fine della tolleranza (10 minuti), sempre «In pausa».
        var attesa = collegato.AttesaPrimaDiDimenticare(AttesaRiconnessione);
        await Task.Delay(attesa);
        // Tornato, perso di nuovo (conta solo l'attesa dell'ultima perdita) o già scollegato: niente da fare.
        if (!telefoni.Contiene(collegato) || collegato.Perdite != perdita || collegato.Sessione is not null) return;
        registro.Aggiungi(Testi.T("Registro_NonTornato", collegato.Nome, attesa.TotalSeconds));
        Dimentica(collegato);
        Notifica(Testi.T("Notifica_TelefonoPerso"), Testi.T("Notifica_TelefonoPersoTesto", collegato.Nome));
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
        var piccoloVisibile = altro is not null && riquadroAperto && !SoloVideo;

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
        // L'immagine del motore sta sopra il video del lettore, solo finché c'è il video.
        if (grande is null && SulComputer) NascondiElaborata();
        if (suoScelto?.Errore is { } errore) MessaggioAnteprima.Text = errore;

        RiquadroPiccolo.Visibility = Visibile(piccoloVisibile);
        PulsanteMostraRiquadro.Visibility = Visibile(altro is not null && !riquadroAperto && !InMini);
        if (!piccoloVisibile || altro is null) return;
        NomePiccolo.Text = Testi.T("Cam_Due", altro.Nome);
        // «Usa prospettiva» solo quando l'altro telefono c'è davvero (non mentre si ricollega).
        PulsanteUsaProspettiva.Visibility = Visibile(!altro.InRiconnessione);
        AutomationProperties.SetName(PulsanteUsaProspettiva, Testi.T("Riquadro_UsaProspettivaNome", altro.Nome));
        var testo = altro.InRiconnessione ? Testi.T("Telefoni_MiRicollegoA", altro.Nome)
            : altro.InPausa ? Testi.T("Telefoni_InPausaMotivo", PausaIntelligente.Motivo(altro.Stato!.Pausa))
            : suoAltro?.Errore is not null ? Testi.T("Video_NonSiMostra")
            : piccolo is null ? Testi.T("Video_InAttesa")
            : "";
        StatoPiccolo.Text = testo;
        VideoPiccolo.Visibility = Visibile(piccolo is not null && testo.Length == 0);
        AutomationProperties.SetName(RiquadroPiccolo, Testi.T("Riquadro_ClicPerWebcam", altro.Nome));
    }

    /// <summary>Clic sul riquadro piccolo: quel telefono va nella webcam (il pulsante per chiuderlo a parte).</summary>
    private void SuRiquadroPiccolo(object sender, TappedRoutedEventArgs e)
    {
        for (var elemento = e.OriginalSource as DependencyObject; elemento is not null && elemento != RiquadroPiccolo;
             elemento = VisualTreeHelper.GetParent(elemento))
        {
            if (elemento == PulsanteChiudiRiquadro || elemento == PulsanteUsaProspettiva) return;
        }
        e.Handled = true;
        ScegliTelefono(telefoni.Altro);
    }

    /// <summary>«Usa prospettiva» sulla CAM 2: quel telefono va nella webcam, l'altro passa nel riquadro.</summary>
    private void SuUsaProspettiva(object sender, RoutedEventArgs e) => ScegliTelefono(telefoni.Altro);

    /// <summary>Chiude il riquadro piccolo. Solo i telefoni di prima del 27 ottobre andavano in pausa senza riquadro e senza app.</summary>
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

    // MARK: «Dispositivi» (colonna di sinistra)

    /// <summary>Una scheda con due telefoni: nome, batteria, dettagli, «Nella webcam» e «Scollega».</summary>
    private sealed record RigaTelefono(TelefonoCollegato Telefono, Border Scheda, Microsoft.UI.Xaml.Shapes.Ellipse Punto, TextBlock Nome,
        TextBlock Batteria, TextBlock Dettagli, TextBlock Caldo, RadioButton Webcam);

    private readonly List<RigaTelefono> righeTelefoni = [];
    /// Vero mentre la scheda imposta «Nella webcam» da codice: quel cambio non è una scelta dell'utente.
    private bool aggiornoRighe;
    /// <summary>I telefoni fidati non collegati mostrati adesso, per non rifare l'elenco ogni secondo.</summary>
    private List<string> notiMostrati = [];

    /// <summary>
    /// «Dispositivi», come sul Mac: con un telefono solo la scheda di sempre; con due, una scheda per telefono con la
    /// scelta «Nella webcam» (nell'accento, come ogni selezione) e «Scollega». Sotto, i telefoni fidati non collegati.
    /// </summary>
    private void MostraTelefoni()
    {
        if (ElencoSchedeTelefoni is null) return;
        var elenco = telefoni.Telefoni;
        var due = elenco.Count > 1;
        SchedaTelefono.Visibility = Visibile(elenco.Count == 1);
        ElencoSchedeTelefoni.Visibility = Visibile(due);
        MostraTelefoniNoti(elenco);
        // Il QR in fondo a sinistra: «Collega il tuo smartphone», o «Collega un altro smartphone» con un telefono.
        TitoloQR.Text = elenco.Count == 0 ? Testi.T("QR_CollegaIlTuo") : Testi.T("QR_CollegaUnAltro");
        ImmagineQR.Width = ImmagineQR.Height = elenco.Count == 0 ? 160 : 128;
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
            riga.Punto.Fill = Pennello(riga.Telefono.InRiconnessione ? "Ambra" : "Verde");
            riga.Dettagli.Text = DettagliScheda(riga.Telefono);
            MostraBatteria(riga.Batteria, riga.Telefono.Stato);
            MostraCaldo(riga.Caldo, riga.Telefono.Stato);
            riga.Webcam.IsChecked = scelto;
            riga.Webcam.Foreground = Pennello(scelto ? "AccentoChiaro" : "TestoTenue");
            riga.Scheda.Background = Pennello(scelto ? "AccentoTenue" : "Pannello");
            riga.Scheda.BorderBrush = Pennello(scelto ? "Accento" : "LineaTenue");
            AutomationProperties.SetName(riga.Scheda, scelto ? Testi.T("Telefoni_NellaWebcamNome", riga.Telefono.Nome) : riga.Telefono.Nome);
        }
        aggiornoRighe = false;
    }

    private RigaTelefono CreaRiga(TelefonoCollegato collegato)
    {
        var punto = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center };
        var icona = new FontIcon { Glyph = "", FontSize = 12, Foreground = Pennello("SalviaChiara"), VerticalAlignment = VerticalAlignment.Center };
        var nome = new TextBlock
        {
            FontFamily = (FontFamily)Application.Current.Resources["CorpoForte"],
            FontSize = 13.5,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var batteria = new TextBlock { FontFamily = (FontFamily)Application.Current.Resources["Numeri"], FontSize = 11, VerticalAlignment = VerticalAlignment.Center };
        var intestazione = new Grid { ColumnSpacing = 8 };
        foreach (var larghezza in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            intestazione.ColumnDefinitions.Add(new ColumnDefinition { Width = larghezza });
        intestazione.Children.Add(punto);
        Grid.SetColumn(icona, 1);
        intestazione.Children.Add(icona);
        Grid.SetColumn(nome, 2);
        intestazione.Children.Add(nome);
        Grid.SetColumn(batteria, 3);
        intestazione.Children.Add(batteria);
        var dettagli = new TextBlock
        {
            FontFamily = (FontFamily)Application.Current.Resources["Numeri"],
            FontSize = 11,
            Foreground = Pennello("TestoSecondario"),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(16, 0, 0, 0),
        };
        var caldo = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(16, 0, 0, 0), Visibility = Visibility.Collapsed };
        var webcam = new RadioButton { Content = Testi.T("Telefoni_NellaWebcam"), GroupName = "TelefonoNellaWebcam", MinWidth = 0, FontSize = 12.5 };
        ToolTipService.SetToolTip(webcam, Testi.T("Telefoni_NellaWebcamSpiegazione"));
        webcam.Checked += (_, _) => { if (!aggiornoRighe) ScegliTelefono(collegato); };
        var scollega = new HyperlinkButton { Content = Testi.T("Scollega"), Padding = new Thickness(0), FontSize = 12.5, Foreground = Pennello("TestoTenue"), VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(scollega, Testi.T("Telefoni_ScollegaSpiegazione", collegato.Nome));
        AutomationProperties.SetName(scollega, Testi.T("Telefoni_ScollegaNome", collegato.Nome));
        scollega.Click += (_, _) => _ = ScollegaAsync(collegato);
        var azioni = new Grid { ColumnSpacing = 8, Margin = new Thickness(16, 0, 0, 0) };
        azioni.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        azioni.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        azioni.Children.Add(webcam);
        Grid.SetColumn(scollega, 1);
        azioni.Children.Add(scollega);
        var scheda = new Border
        {
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(10),
            Child = new StackPanel { Spacing = 6, Children = { intestazione, dettagli, caldo, azioni } },
        };
        return new RigaTelefono(collegato, scheda, punto, nome, batteria, dettagli, caldo, webcam);
    }

    /// <summary>
    /// I telefoni fidati che ora non sono collegati, in una riga come nel disegno: «Conosciuti: iPhone di Ledion, Galaxy ·
    /// si ricollegano da soli». Si possono togliere da Account › Telefoni conosciuti.
    /// </summary>
    private void MostraTelefoniNoti(IReadOnlyList<TelefonoCollegato> collegati)
    {
        var impronte = collegati.Select(t => t.Impronta).ToHashSet();
        var noti = abbinamento.Fidati.Where(f => !impronte.Contains(f.Impronta)).Select(f => f.Nome).Order().Take(5).ToList();
        if (noti.SequenceEqual(notiMostrati)) return;
        notiMostrati = noti;
        TestoTelefoniNoti.Text = noti.Count == 0 ? "" : Testi.T("Telefoni_Conosciuti", string.Join(", ", noti));
        TestoTelefoniNoti.Visibility = Visibile(noti.Count > 0);
        ToolTipService.SetToolTip(TestoTelefoniNoti, noti.Count == 0 ? null : Testi.T("Telefoni_FidatoSpiegazione"));
    }
}
