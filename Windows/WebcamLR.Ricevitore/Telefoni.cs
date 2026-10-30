using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// I comandi della fotocamera che la finestra mostra per un telefono (P21): con due telefoni la colonna di destra
/// passa da uno all'altro, e ognuno ritrova i suoi. Al ricollegamento dello stesso telefono si rimandano
/// (Documenti/Protocollo.md, «comando»). L'obiettivo no: arriva sempre dallo «stato» del telefono.
/// </summary>
public sealed record ComandiFotocamera(double Zoom, bool Torcia, double Esposizione, bool BiancoAutomatico, double Bianco,
    bool Manuale, double Iso, int Tempo)
{
    /// <summary>Come all'apertura della finestra: tutto automatico.</summary>
    public static ComandiFotocamera Iniziali { get; } = new(1, false, 0, true, 5000, false, 400, 50);

    /// <summary>Un comando mandato al telefono: i campi presenti cambiano, gli altri restano.</summary>
    public ComandiFotocamera Applica(Comando comando)
    {
        var nuovi = this;
        // Cambiando obiettivo lo zoom riparte da 1, come fa la finestra.
        if (comando.Obiettivo is not null) nuovi = nuovi with { Zoom = 1 };
        if (comando.Zoom is double zoom) nuovi = nuovi with { Zoom = zoom };
        if (comando.Torcia is bool torcia) nuovi = nuovi with { Torcia = torcia };
        if (comando.Esposizione is double esposizione) nuovi = nuovi with { Esposizione = esposizione };
        if (comando.Bianco is int bianco)
            nuovi = bianco == 0 ? nuovi with { BiancoAutomatico = true } : nuovi with { BiancoAutomatico = false, Bianco = bianco };
        if (comando.Iso is double iso) nuovi = iso > 0 ? nuovi with { Iso = iso, Manuale = true } : nuovi;
        if (comando.Tempo is int tempo) nuovi = tempo > 0 ? nuovi with { Tempo = tempo, Manuale = true } : nuovi;
        // ISO e tempo entrambi a 0: si torna all'esposizione automatica (Protocollo.md).
        if (comando is { Iso: 0, Tempo: 0 }) nuovi = nuovi with { Manuale = false };
        return nuovi;
    }

    /// <summary>Per lo stesso telefono che torna: in un solo comando quello che la finestra mostra.</summary>
    public Comando PerRicollegamento() => new(Zoom: Zoom, Torcia: Torcia, Esposizione: Math.Round(Esposizione, 1),
        Bianco: BiancoAutomatico ? 0 : (int)Bianco, Iso: Manuale ? Math.Round(Iso) : 0, Tempo: Manuale ? Tempo : 0);
}

/// <summary>
/// Un telefono collegato al computer (P21, «Più telefoni insieme»): la sessione attuale (null mentre si aspetta che
/// torni), come è collegato, gli ultimi stato, capacità e statistiche, e ciò che la finestra ricorda per lui
/// (comandi, effetti, gobbo, latenza, avvisi). Lo stesso telefono si riconosce dal codice di sicurezza
/// (Documenti/Protocollo.md, «Riconoscere il telefono»), non dal nome.
/// La sessione e il formato si leggono anche dai thread di rete; il resto lo usa solo il thread dell'interfaccia.
/// </summary>
public sealed class TelefonoCollegato
{
    private SessioneComputer? sessione;
    private FormatoVideo? formato;

    private readonly Func<long> orologio;

    /// <param name="orologio">Millisecondi, per la pausa e la tolleranza del sottofondo (quello dell'elenco).</param>
    internal TelefonoCollegato(string impronta, Ciao ciao, SessioneComputer sessione, Func<long>? orologio = null)
    {
        this.orologio = orologio ?? (() => Environment.TickCount64);
        Impronta = impronta;
        Ciao = ciao;
        this.sessione = sessione;
        Collegamento = sessione.Collegamento;
    }

    /// <summary>Il codice di sicurezza del telefono: non cambia finché il telefono resta nell'elenco.</summary>
    public string Impronta { get; }

    /// <summary>Nome, piattaforma e versione, dall'ultimo «ciao».</summary>
    public Ciao Ciao { get; internal set; }

    public string Nome => Ciao.Nome;

    /// <summary>La sessione attuale; null mentre il collegamento è perso e si aspetta che il telefono torni.</summary>
    public SessioneComputer? Sessione
    {
        get => Volatile.Read(ref sessione);
        internal set => Volatile.Write(ref sessione, value);
    }

    /// <summary>Wi-Fi, cavo USB, cavo di rete o hotspot, della sessione più recente.</summary>
    public TipoCollegamento? Collegamento { get; internal set; }

    /// <summary>Il formato del video che il telefono sta mandando; lo scrive il thread di rete.</summary>
    public FormatoVideo? Formato
    {
        get => Volatile.Read(ref formato);
        set => Volatile.Write(ref formato, value);
    }

    /// <summary>
    /// L'ultimo <c>formato</c> chiesto dal PC in questa sessione (menu della qualità, profilo, 60 fps per un'app): se il
    /// telefono manda meno, l'etichetta della qualità dice perché (<see cref="OpzioneQualita.MotivoRiduzione"/>).
    /// Null = nessuna richiesta. Solo dal thread dell'interfaccia.
    /// </summary>
    public FormatoVideo? FormatoChiesto { get; set; }

    /// <summary>Nessun dato da 3 secondi: la finestra mostra «Riconnessione» anche se la sessione c'è ancora.</summary>
    public bool InSilenzio { get; set; }

    /// <summary>
    /// Collegamento perso, o in silenzio: si aspetta che il telefono torni. Non con l'ultimo motivo «sottofondo», per
    /// <see cref="TolleranzaSottofondo.Durata"/>: allora il telefono resta «In pausa» con il motivo.
    /// </summary>
    public bool InRiconnessione => (Sessione is null || InSilenzio) && !InSottofondo;

    /// <summary>L'ultimo stato dice «sottofondo», da meno di <see cref="TolleranzaSottofondo.Durata"/>.</summary>
    public bool InSottofondo => Pausa.Tollerato(orologio());

    /// <summary>Da quando è in pausa e da quando è in sottofondo, dagli stati ricevuti.</summary>
    public StoriaPausa Pausa { get; } = new();

    /// <summary>L'ultimo stato del telefono; impostarlo aggiorna <see cref="Pausa"/> (vedi <see cref="AggiornaStato"/>).</summary>
    public StatoTelefono? Stato
    {
        get => stato;
        set => AggiornaStato(value);
    }
    private StatoTelefono? stato;

    /// <summary>Il nuovo stato: dice se una pausa è appena iniziata (con il motivo) o finita (con la durata).</summary>
    public CambioPausa AggiornaStato(StatoTelefono? nuovo)
    {
        stato = nuovo;
        return Pausa.Aggiorna(nuovo, orologio());
    }

    /// <summary>
    /// Quanto aspettare, dopo la perdita del collegamento, prima di dimenticare il telefono: <paramref name="normale"/>,
    /// o di più se è in sottofondo (fino alla fine della tolleranza).
    /// </summary>
    public TimeSpan AttesaPrimaDiDimenticare(TimeSpan normale)
    {
        var resto = TimeSpan.FromMilliseconds(TolleranzaSottofondo.RestoMs(Pausa.SottofondoDalMs, orologio()));
        return resto > normale ? resto : normale;
    }
    public Capacita? Capacita { get; set; }
    public Statistiche? Statistiche { get; set; }

    /// <summary>L'ultimo <c>formato-audio</c> del telefono (W2), per il microfono quando questo telefono viene scelto dopo.</summary>
    public FormatoAudio? FormatoAudio
    {
        get => Volatile.Read(ref formatoAudio);
        set => Volatile.Write(ref formatoAudio, value);
    }
    private FormatoAudio? formatoAudio;

    /// <summary>A questa sessione del telefono è già stato chiesto l'audio (<c>comando.audio = true</c>).</summary>
    public bool AudioComandato { get; set; }
    /// <summary>«Avvio: 0,9 s» della sessione attuale (1.11); null finché il primo fotogramma non è a schermo.</summary>
    public string? TestoAvvio { get; set; }

    /// <summary>Vero se il telefono è in pausa adesso (pausa intelligente).</summary>
    public bool InPausa => PausaIntelligente.InPausa(Stato);

    public ComandiFotocamera Comandi { get; set; } = ComandiFotocamera.Iniziali;
    /// <summary>I comandi della fotocamera seguono lo «stato» del telefono (1.14), tranne quelli appena mandati dal PC.</summary>
    public AllineamentoFotocamera Allineamento { get; } = new();
    /// <summary>L'ultimo profilo pronto scelto per questo telefono (Riunione, Lezione…); null se nessuno.</summary>
    public string? ProfiloPronto { get; set; }
    public ControlloEffetti Effetti { get; } = new();
    /// <summary>Con gli effetti sul computer: il telefono come telecomando (<c>effetti</c>, <c>chiedi-effetto</c>), per sessione.</summary>
    public TelecomandoEffetti Telecomando { get; } = new();
    public MemoriaGobbo Gobbo { get; } = new();
    public StoriaLatenza StoriaLatenza { get; } = new();
    /// <summary>Quando scrivere nel registro i numeri ricevuti (ogni 10 secondi, con gli effetti accesi).</summary>
    public NumeriNelRegistro Numeri { get; } = new();
    /// <summary>Ogni 30 secondi le tappe del ritardo da vetro a uscita nel registro.</summary>
    public RitardoNelRegistro Ritardi { get; } = new();
    public SorveglianzaAvvisi Avvisi { get; } = new();

    /// <summary>La strada scelta (Automatico, Wi-Fi, Cavo USB) e la regola «niente sbalzi» per questo telefono.</summary>
    public RegolaCollegamento Regola { get; } = new();

    /// <summary>Le strade che il telefono conosce, dal suo ultimo stato; null se non le manda (telefono di prima).</summary>
    public StradeTelefono? Strade { get; set; }

    /// <summary>Il telefono sa cambiare strada e accetta la preferenza (<c>capacita.sceltaCollegamento</c>).</summary>
    public bool SaScegliereStrada => ContrattoCollegamento.SaScegliere(Capacita);

    /// <summary>
    /// Dallo «stato» del telefono: le strade che conosce e la sua preferenza, che vale anche per le sessioni che arrivano
    /// (con «wifi» il Wi-Fi dello stesso telefono prende il posto del cavo, anche il tethering USB di Android).
    /// </summary>
    /// <returns>Vero se la preferenza è cambiata (allora il cavo lasciato per il Wi-Fi può tornare).</returns>
    public bool AggiornaStrade(StatoTelefono stato, long adessoMs)
    {
        Strade = ContrattoCollegamento.Strade(stato);
        return Regola.DalTelefono(Strade?.Preferenza, adessoMs);
    }

    /// <summary>
    /// Cresce a ogni perdita del collegamento: se il telefono torna e si perde di nuovo, conta solo l'attesa
    /// dell'ultima (altrimenti quella vecchia lo dimenticherebbe pochi secondi dopo la seconda perdita).
    /// </summary>
    public int Perdite { get; set; }

    public override string ToString() => Nome;
}

/// <summary>Cosa succede a un telefono appena accettato (stretta di mano, prova, fiducia), rispetto a quelli già collegati.</summary>
public enum EsitoArrivo
{
    /// <summary>Un telefono diverso, e c'è posto: si aggiunge all'elenco.</summary>
    Nuovo,
    /// <summary>Lo stesso telefono (stesso codice di sicurezza): la sessione nuova prende il posto di quella vecchia.</summary>
    StessoTelefono,
    /// <summary>Lo stesso telefono, arrivato con il cavo mentre era in Wi-Fi: il cavo prende il posto del Wi-Fi.</summary>
    CavoAlPostoDelWiFi,
    /// <summary>Lo stesso telefono arriva in Wi-Fi ma è già collegato con il cavo: resta il cavo, la sessione nuova si chiude.</summary>
    RestaIlCavo,
    /// <summary>
    /// Lo stesso telefono arriva con il cavo ma resta il Wi-Fi: scelto a mano, o il cavo arriva nei 30 secondi dopo un
    /// cambio (<see cref="RegolaCollegamento"/>). La sessione nuova si chiude; il cavo può tornare (non è «Scollega»).
    /// </summary>
    RestaIlWiFi,
    /// <summary>Lo stesso telefono, con «Wi-Fi» scelto a mano, torna in Wi-Fi mentre usava il cavo: il Wi-Fi prende il posto del cavo.</summary>
    WiFiAlPostoDelCavo,
    /// <summary>Un telefono diverso, ma ce ne sono già <see cref="ElencoTelefoni.Massimo"/>: si chiude con l'avviso.</summary>
    Pieno,
    /// <summary>Un telefono diverso, ma quello nella webcam non ha WebcamLR Pro: due telefoni insieme sono di Pro.</summary>
    SenzaPro,
}

/// <summary>L'esito, il telefono dell'elenco (null se la sessione non entra) e la sessione da chiudere con «arrivederci».</summary>
public sealed record Arrivo(EsitoArrivo Esito, TelefonoCollegato? Telefono, SessioneComputer? DaChiudere);

/// <summary>
/// I telefoni collegati insieme (P21): fino a <see cref="Massimo"/>, telefoni diversi (codici di sicurezza diversi),
/// ognuno con il suo video. Uno è «nella webcam»: va alla webcam per le altre app, a foto e registrazioni, e i comandi
/// della colonna di destra valgono per lui. Il primo che arriva ci va da solo; il secondo resta accanto finché l'utente
/// non lo sceglie, così una chiamata in corso non cambia immagine da sola.
/// Regole dell'arrivo: stesso codice di sicurezza → la sessione nuova sostituisce la vecchia (con la precedenza del
/// cavo, Documenti/Protocollo.md «Precedenza»); codice diverso → secondo telefono; oltre il massimo → rifiutato con
/// l'avviso «Già collegati due telefoni». Un telefono che si sta ricollegando tiene il suo posto finché non viene
/// dimenticato. Thread-safe: gli arrivi e le chiusure vengono dai thread di rete, il resto dall'interfaccia.
/// </summary>
public sealed class ElencoTelefoni
{
    /// <summary>Pensato per N telefoni; per ora due, come sul Mac.</summary>
    public const int MassimoPredefinito = 2;

    public static string TitoloPieno => TestiRicevitore.T("Telefoni_TitoloPieno");

    private readonly object blocco = new();
    private readonly List<TelefonoCollegato> telefoni = [];
    private TelefonoCollegato? selezionato;

    public ElencoTelefoni(int massimo = MassimoPredefinito)
    {
        if (massimo < 1) throw new ArgumentOutOfRangeException(nameof(massimo));
        Massimo = massimo;
    }

    public int Massimo { get; }

    /// <summary>
    /// WebcamLR Pro (come sul Mac): vero = un secondo telefono entra solo se quello nella webcam ha sbloccato Pro
    /// (<c>capacita.pro</c>). Lo stesso telefono che torna entra sempre.
    /// </summary>
    public bool RichiedePro { get; set; }

    /// <summary>Il telefono nella webcam ha Pro (dalle ultime capacità). Dentro il blocco.</summary>
    private bool SecondoConsentito() => !RichiedePro || telefoni.Count == 0 || RegolePro.Attivo(selezionato?.Capacita);

    /// <summary>Vero se un telefono nuovo resta fuori solo perché quello nella webcam è gratis (per l'avviso giusto).</summary>
    public bool FuoriPerPro(string impronta)
    {
        lock (blocco)
            return telefoni.All(t => t.Impronta != impronta) && telefoni.Count < Massimo && !SecondoConsentito();
    }

    /// <summary>I telefoni nell'ordine in cui sono arrivati (una copia).</summary>
    public IReadOnlyList<TelefonoCollegato> Telefoni
    {
        get { lock (blocco) return [.. telefoni]; }
    }

    public int Conteggio
    {
        get { lock (blocco) return telefoni.Count; }
    }

    /// <summary>Il telefono «nella webcam»; null solo senza telefoni.</summary>
    public TelefonoCollegato? Selezionato
    {
        get { lock (blocco) return selezionato; }
    }

    /// <summary>Il primo telefono che non è nella webcam (con due telefoni, l'altro); null se non c'è.</summary>
    public TelefonoCollegato? Altro
    {
        get { lock (blocco) return telefoni.FirstOrDefault(t => t != selezionato); }
    }

    /// <summary>La sessione del telefono nella webcam; null senza telefoni o mentre si aspetta che torni.</summary>
    public SessioneComputer? SessioneSelezionata => Selezionato?.Sessione;

    public bool Contiene(TelefonoCollegato telefono)
    {
        lock (blocco) return telefoni.Contains(telefono);
    }

    public bool ESelezionato(TelefonoCollegato telefono)
    {
        lock (blocco) return selezionato == telefono;
    }

    /// <summary>
    /// L'«in-onda» per un telefono (Protocollo.md, «Più telefoni: la prospettiva»): il rosso solo su quello nella webcam,
    /// e <c>selezionato</c> sempre, così l'altro mostra «CAM 2» e «Usa questa prospettiva». Da mandare a ogni telefono a
    /// ogni cambio della scelta e di «in onda».
    /// </summary>
    public InOnda InOndaPer(TelefonoCollegato telefono, bool webcamInUso)
    {
        var scelto = ESelezionato(telefono);
        return new InOnda(webcamInUso && scelto, Selezionato: scelto);
    }

    /// <summary>Il telefono con questo codice di sicurezza, se è nell'elenco.</summary>
    public TelefonoCollegato? Con(string? impronta)
    {
        if (impronta is null) return null;
        lock (blocco) return telefoni.FirstOrDefault(t => t.Impronta == impronta);
    }

    /// <summary>Il telefono di cui questa è la sessione attuale.</summary>
    public TelefonoCollegato? Di(SessioneComputer sessione)
    {
        lock (blocco) return telefoni.FirstOrDefault(t => t.Sessione == sessione);
    }

    /// <summary>
    /// Prima della fiducia (e della domanda «Consentire …?»): vero se il telefono può entrare, cioè se è già nell'elenco
    /// o se c'è posto. Così un terzo telefono non fa comparire la domanda per nulla. La decisione vera è in <see cref="Accogli"/>.
    /// </summary>
    public bool PuoEntrare(string impronta)
    {
        lock (blocco) return (telefoni.Count < Massimo && SecondoConsentito()) || telefoni.Any(t => t.Impronta == impronta);
    }

    /// <summary>L'orologio della regola dei 30 secondi (<see cref="RegolaCollegamento"/>), in millisecondi; nei test si cambia.</summary>
    public Func<long> Orologio { get; set; } = () => Environment.TickCount64;

    /// <summary>
    /// Un telefono appena accettato (prima del «benvenuto»): decide e aggiorna l'elenco in un colpo solo, così cavo e
    /// Wi-Fi dello stesso telefono che arrivano insieme non si scavalcano. La sessione nel risultato, se c'è, va chiusa.
    /// Tra cavo e Wi-Fi dello stesso telefono decide <see cref="RegolaCollegamento"/>: di serie il cavo vince sul Wi-Fi
    /// (Documenti/Protocollo.md «Precedenza»), con la pausa di 30 secondi dopo un cambio e la scelta fatta a mano.
    /// </summary>
    public Arrivo Accogli(SessioneComputer nuova, Ciao ciao)
    {
        var impronta = nuova.ImprontaTelefono ?? throw new InvalidOperationException("Sessione senza codice di sicurezza");
        lock (blocco)
        {
            if (telefoni.FirstOrDefault(t => t.Impronta == impronta) is { } stesso)
            {
                var vecchia = stesso.Sessione;
                if (vecchia == nuova) return new Arrivo(EsitoArrivo.StessoTelefono, stesso, null);
                // Precedenza del cavo: lo stesso telefono già sul cavo non passa al Wi-Fi (il cavo si ricollegherebbe
                // e i due collegamenti si caccerebbero a vicenda), se non scelto a mano. Il contrario sì, tranne nei
                // 30 secondi dopo un cambio o con «Wi-Fi» scelto a mano.
                // In sottofondo la sessione di prima può essere ancora aperta ma muta: non trattiene quella nuova
                // (come sul Mac), altrimenti il telefono tornato su un'altra strada resterebbe fuori fino a 10 minuti.
                var attiva = vecchia is { Terminata: false } && !stesso.InSottofondo;
                var inUsoViaCavo = vecchia?.ViaCavo ?? stesso.Collegamento == TipoCollegamento.CavoUsb;
                if (stesso.Regola.Decidi(nuova.ViaCavo, inUsoViaCavo, attiva, Orologio(), stesso.SaScegliereStrada) == DecisioneStrada.TieniQuellaInUso)
                    return new Arrivo(nuova.ViaCavo ? EsitoArrivo.RestaIlWiFi : EsitoArrivo.RestaIlCavo, stesso, nuova);
                var esito = !attiva || nuova.ViaCavo == inUsoViaCavo ? EsitoArrivo.StessoTelefono
                    : nuova.ViaCavo ? EsitoArrivo.CavoAlPostoDelWiFi : EsitoArrivo.WiFiAlPostoDelCavo;
                stesso.Sessione = nuova;
                // Sessione nuova: le richieste di formato si rifanno da capo.
                stesso.FormatoChiesto = null;
                stesso.Ciao = ciao;
                stesso.Collegamento = nuova.Collegamento;
                stesso.InSilenzio = false;
                return new Arrivo(esito, stesso, vecchia);
            }
            if (telefoni.Count >= Massimo) return new Arrivo(EsitoArrivo.Pieno, null, nuova);
            if (!SecondoConsentito()) return new Arrivo(EsitoArrivo.SenzaPro, null, nuova);
            var telefono = new TelefonoCollegato(impronta, ciao, nuova, () => Orologio());
            telefoni.Add(telefono);
            selezionato ??= telefono;
            return new Arrivo(EsitoArrivo.Nuovo, telefono, null);
        }
    }

    /// <summary>
    /// La sessione si è chiusa da sola (rete, telefono chiuso): se era quella attuale del suo telefono, il telefono resta
    /// nell'elenco in attesa che torni. Restituisce il telefono, o null se la sessione era già stata sostituita o tolta.
    /// </summary>
    public TelefonoCollegato? Perso(SessioneComputer chiusa)
    {
        lock (blocco)
        {
            var telefono = telefoni.FirstOrDefault(t => t.Sessione == chiusa);
            if (telefono is null) return null;
            telefono.Sessione = null;
            telefono.InSilenzio = false;
            telefono.Perdite++;
            return telefono;
        }
    }

    /// <summary>Il telefono va nella webcam. Falso se non è nell'elenco o se c'era già.</summary>
    public bool Seleziona(TelefonoCollegato telefono)
    {
        lock (blocco)
        {
            if (!telefoni.Contains(telefono) || selezionato == telefono) return false;
            selezionato = telefono;
            return true;
        }
    }

    /// <summary>Con due telefoni: l'altro va nella webcam (il clic sul riquadro piccolo). Restituisce il nuovo scelto.</summary>
    public TelefonoCollegato? Scambia()
    {
        lock (blocco)
        {
            if (telefoni.FirstOrDefault(t => t != selezionato) is not { } altro) return null;
            selezionato = altro;
            return altro;
        }
    }

    /// <summary>
    /// Toglie il telefono (Scollega, o non è tornato in tempo). Se era nella webcam ci va il primo degli altri.
    /// Restituisce la sessione da chiudere con «arrivederci», se c'è.
    /// </summary>
    public SessioneComputer? Rimuovi(TelefonoCollegato telefono)
    {
        lock (blocco)
        {
            if (!telefoni.Remove(telefono)) return null;
            if (selezionato == telefono) selezionato = telefoni.FirstOrDefault();
            var sessione = telefono.Sessione;
            telefono.Sessione = null;
            return sessione;
        }
    }

    /// <summary>Il messaggio per il telefono rifiutato perché ce ne sono già due: dice cosa fare.</summary>
    public static string MessaggioPieno(string? nome) =>
        TestiRicevitore.T("Telefoni_MessaggioPieno", NomeInFrase(nome));

    /// <summary>Il nome tra virgolette, o «Il telefono» se manca: il soggetto dei messaggi di rifiuto.</summary>
    internal static string NomeInFrase(string? nome) =>
        string.IsNullOrWhiteSpace(nome) ? TestiRicevitore.T("Telefoni_IlTelefono") : TestiRicevitore.T("Telefoni_NomeTraVirgolette", nome.Trim());
}
