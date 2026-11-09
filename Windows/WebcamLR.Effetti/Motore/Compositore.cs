using System.Numerics;
using WebcamLR.Protocollo;

namespace WebcamLR.Effetti;

/// <summary>Un fotogramma da rendere, con quello che l'analisi ha già preparato.</summary>
/// <param name="Quarto">Il fotogramma a un quarto della misura (fatto dall'analisi per la maschera); null = lo fa la resa.</param>
/// <param name="Maschera">La maschera dello stesso istante (o l'ultima buona); null = nessuna.</param>
/// <param name="Volti">I volti (normalizzati) dell'ultima analisi, null se troppo vecchi.</param>
public sealed record IngressoResa(ImmagineBgra Immagine, ImmagineBgra? Meta, ImmagineBgra? Quarto, MascheraPersona? Maschera,
    IReadOnlyList<Rettangolo>? Volti, ulong? QuandoVolti, double Dt);

/// <summary>
/// La resa degli effetti sul processore, nello stesso ordine del Mac: calore, sfondo (con la maschera), ritocco della pelle,
/// luce sul volto, inquadratura automatica, filtro e regolazioni, specchio, scritta e logo. Tiene lo stato nel tempo
/// (volto levigato, molla dell'inquadratura) e le cose disegnate una volta (sfondo alla misura, scritta, tabelle).
/// Non è thread-safe: la usa solo il thread della resa (al suo interno divide le righe tra i processori).
/// </summary>
public sealed class Compositore : IDisposable
{
    /// <summary>Il fondo di Tema (#13211D) quando l'immagine dello sfondo non è ancora pronta.</summary>
    public static readonly (byte R, byte G, byte B) ColoreFondo = (0x13, 0x21, 0x1D);

    private readonly MollaInquadratura inquadratura = new();
    private Rettangolo? voltoLuce;
    private double presenzaLuce;

    // Cose preparate una volta e riusate.
    private (string Chiave, ImmagineBgra Immagine)? sfondoPronto;
    private (string Chiave, ImmagineBgra? Scritta, ImmagineBgra? Logo)? scrittaPronta;
    private (string Chiave, CatenaColore? Catena)? catenaPronta;
    private (double Forza, byte[][]? Tabelle)? calorePronto;
    private (int L, int A, ushort[] Guadagni)? vignettaPronta;
    private readonly byte[] tabellaLuce = RicetteColore.TabellaLuceVolto();

    // Buffer riusati.
    private ImmagineBgra? lavoro;
    private ImmagineBgra? metaPropria, quartoProprio;
    private readonly List<ImmagineBgra> piramide = [];
    private float[] guida = [], guidaAlta = [], rifinitaAlta = [], mascheraLavoro = [], sfocata = [], appoggio = [];
    private byte[] alfa = [];
    private byte[] copiaNitidezza = [];
    private readonly Elaborazione.LavagnaGuidato lavagna = new();
    private byte[] alfaQuarto = [], mascheraMorbida = [];
    private float[] lavagnaColore = [], appoggioColore = [], lavagnaMaschera = [], appoggioMaschera = [];
    private ImmagineBgra? colorePersona;
    private (string Chiave, ImmagineBgra Immagine)? sfondoMorbido;

    // La composizione a piena risoluzione (Qualità 5): sulla scheda video se si apre, altrimenti sul processore.
    private readonly ComposizioneProcessore processore = new();
    private readonly Func<IComposizione>? creaSchedaVideo;
    private IComposizione? schedaVideo;
    private Task<IComposizione>? preparazioneSchedaVideo;
    private bool schedaVideoEsclusa;
    private int erroriSchedaVideo, riaperture;
    private readonly List<CambioComposizione> cambi = [];

    /// <param name="creaSchedaVideo">
    /// La composizione sulla scheda video (<see cref="ComposizioneSchedaVideo.Crea"/>): si chiama in sottofondo la prima
    /// volta che serve; se lancia un errore si resta sul processore. Null: sempre il processore.
    /// </param>
    public Compositore(Func<IComposizione>? creaSchedaVideo = null) => this.creaSchedaVideo = creaSchedaVideo;

    /// <summary>Luce sul volto o inquadratura spente ma ancora in dissolvenza: il motore deve lavorare finché non sono a riposo.</summary>
    public bool InRitorno => inquadratura.InMovimento || presenzaLuce > 0.01;

    /// <summary>
    /// Rende <paramref name="ingresso"/> in <paramref name="uscita"/> (stessa misura). Falso se lo sfondo è acceso ma non
    /// c'è una maschera: allora non si consegna nulla (mai lo sfondo vero al posto di quello scelto).
    /// </summary>
    public bool Rendi(IngressoResa ingresso, StatoEffettiComputer.Istantanea istantanea, LivelloResa livello, ImmagineBgra uscita)
    {
        var imp = istantanea.Impostazioni;
        var src = ingresso.Immagine;
        int l = src.Larghezza, a = src.Altezza;
        if (uscita.Larghezza != l || uscita.Altezza != a) throw new ArgumentException("Uscita di misura diversa", nameof(uscita));
        if (imp.SfondoAcceso && ingresso.Maschera is null) return false;

        var volti = (ingresso.Volti ?? []).Where(v => v.Larghezza > 0.005 && v.Altezza > 0.005).ToList();
        var calore = TabelleCalore(imp.Calore);
        ImmagineBgra corrente = src;

        // 1-2. Calore e sfondo: con lo sfondo il calore va su persona e sfondo sfocato (non sull'immagine sostituita).
        if (imp.SfondoAcceso)
        {
            lavoro = Prepara(lavoro, l, a);
            Sfondo(ingresso, istantanea, livello, calore, lavoro);
            corrente = lavoro;
            calore = null;
        }
        // 3-4. Pelle e luce sul volto: lavorano sul posto, solo attorno ai volti.
        var voltiPixel = volti.Select(v => v.InPixel(l, a)).ToList();
        var luce = PassoLuce(voltiPixel, imp.LuceVolto, ingresso.Dt, l, a);
        var pelle = imp.Pelle > 0.001 && voltiPixel.Count > 0;
        var nitidezza = double.IsFinite(imp.Nitidezza) ? Math.Clamp(imp.Nitidezza, -1, 1) : 0;
        if ((pelle || luce is not null || Math.Abs(nitidezza) > 0.005) && ReferenceEquals(corrente, src))
        {
            lavoro = Prepara(lavoro, l, a);
            src.Dati.AsSpan(0, l * a * 4).CopyTo(lavoro.Dati);
            if (calore is not null) ApplicaTabelle(lavoro, calore);
            calore = null;
            corrente = lavoro;
        }
        if (pelle) RicettePersona.Pelle(corrente, imp.Pelle, voltiPixel, !livello.ConBordoAMeta());
        if (luce is { } volto) RicettePersona.LuceVolto(corrente, volto, presenzaLuce, tabellaLuce);
        if (Math.Abs(nitidezza) > 0.005) RicettePersona.Nitidezza(corrente, nitidezza, ref copiaNitidezza);

        // 5. Inquadratura automatica: la molla con i volti freschi.
        var zoom = inquadratura.Passo(ingresso.Volti is null ? null : volti, ingresso.QuandoVolti, imp.Inquadratura, ingresso.Dt);

        // 6-8. Ritaglio, specchio, calore (se non già fatto), filtro e regolazioni in un passaggio solo.
        var catena = Catena(imp, calore is not null);
        var vignetta = imp.Filtro == Filtri.Cinema && !livello.ConBordoBilineare() ? Vignetta(l, a) : null;
        if (zoom is { } z)
        {
            var (rx, ry, rl, ra) = z.Ritaglio(l, a);
            Elaborazione.Ricampiona(corrente, rx, ry, rl, ra, uscita, imp.Specchia);
        }
        else if (imp.Specchia)
        {
            Elaborazione.PerRighe(a, (inizio, fine) =>
            {
                for (var y = inizio; y < fine; y++)
                {
                    var s = corrente.Dati.AsSpan(y * corrente.Passo, l * 4);
                    var d = uscita.Dati.AsSpan(y * uscita.Passo, l * 4);
                    for (var x = 0; x < l; x++) s.Slice((l - 1 - x) * 4, 4).CopyTo(d.Slice(x * 4, 4));
                }
            });
        }
        else
        {
            corrente.Dati.AsSpan(0, l * a * 4).CopyTo(uscita.Dati);
        }
        if (catena is not null || vignetta is not null)
        {
            Elaborazione.PerRighe(a, (inizio, fine) =>
            {
                for (var y = inizio; y < fine; y++)
                {
                    var riga = uscita.Dati.AsSpan(y * uscita.Passo, l * 4);
                    catena?.Applica(riga);
                    if (vignetta is not null)
                    {
                        var o = y * l;
                        for (var x = 0; x < l; x++)
                        {
                            int g = vignetta[o + x];
                            if (g >= 256) continue;
                            riga[x * 4] = (byte)((riga[x * 4] * g + 128) >> 8);
                            riga[x * 4 + 1] = (byte)((riga[x * 4 + 1] * g + 128) >> 8);
                            riga[x * 4 + 2] = (byte)((riga[x * 4 + 2] * g + 128) >> 8);
                        }
                    }
                }
            });
        }
        // 9. Scritta e logo, dopo lo specchio: si leggono sempre dritti.
        if (imp.ScrittaAccesa) Scritta(uscita, imp, istantanea);
        uscita.Timestamp = src.Timestamp;
        return true;
    }

    /// <summary>Altro video o sessione nuova: lo stato nel tempo riparte da capo.</summary>
    public void Azzera()
    {
        voltoLuce = null;
        presenzaLuce = 0;
        inquadratura.Azzera();
    }

    // MARK: sfondo

    /// <summary>
    /// Raggio (sigma) della sfocatura a 1080p per un'intensità 0…1: 32 × intensità^1,6, come sull'iPhone e sul Mac.
    /// Poco (0,25) ≈ 3,5 px, Medio (0,55) ≈ 12 px, Tanto (1) = 32 px.
    /// </summary>
    public static double SigmaSfocatura(double intensita) => Math.Max(1.5, 32 * Math.Pow(Math.Clamp(intensita, 0, 1), 1.6));

    /// <summary>
    /// Il gradino della piramide (1/4, 1/8, 1/16, 1/32 del lato) su cui sfocare: il più fine in cui la sigma resta al
    /// massimo 3 pixel (la sfocatura costa poco e l'ingrandimento bilineare non si vede sotto una sfocatura così).
    /// </summary>
    public static int GradinoSfocatura(double sigmaPiena)
    {
        var gradino = 0;
        var sigma = sigmaPiena / 4;
        while (sigma > 3 && gradino < 3)
        {
            sigma /= 2;
            gradino++;
        }
        return gradino;
    }

    private void Sfondo(IngressoResa ingresso, StatoEffettiComputer.Istantanea istantanea, LivelloResa livello, byte[][]? calore,
        ImmagineBgra destinazione)
    {
        var imp = istantanea.Impostazioni;
        var src = ingresso.Immagine;
        var maschera = ingresso.Maschera!;
        int l = src.Larghezza, a = src.Altezza;
        var meta = ingresso.Meta;
        var quarto = ingresso.Quarto;
        if (quarto is null)
        {
            meta ??= metaPropria = Elaborazione.Dimezza(src, metaPropria);
            quarto = quartoProprio = Elaborazione.Dimezza(meta, quartoProprio);
        }

        // Il bordo: la maschera rifinita con la guida (luminosità del video), poi la soglia morbida. Pieno: filtro guidato
        // veloce con i coefficienti al quarto e la resa a metà risoluzione; bordo leggero e maschera alterna: tutto al
        // quarto; veloce e minimo: maschera bilineare appena ammorbidita. Oltre il 1080p (4K) anche il pieno resta al quarto.
        var conMeta = livello.ConBordoAMeta() && Math.Min(l, a) <= 1080;
        if (conMeta) meta ??= metaPropria = Elaborazione.Dimezza(src, metaPropria);
        int lq = quarto.Larghezza, aq = quarto.Altezza;
        int lw = conMeta ? meta!.Larghezza : lq, aw = conMeta ? meta!.Altezza : aq;
        mascheraLavoro = Elaborazione.Campiona(maschera.Valori, maschera.Larghezza, maschera.Altezza, lq, aq, mascheraLavoro);
        float[] rifinita;
        if (livello.ConBordoBilineare())
        {
            if (appoggio.Length < lq * aq) appoggio = new float[lq * aq];
            if (sfocata.Length < lq * aq) sfocata = new float[lq * aq];
            Elaborazione.MediaQuadrata(mascheraLavoro, sfocata, lq, aq, 1, appoggio);
            rifinita = sfocata;
        }
        else
        {
            guida = Elaborazione.Luminosita(quarto, guida);
            var raggio = Math.Max(2, (int)Math.Round(2.0 * lq / 480));
            if (conMeta)
            {
                guidaAlta = Elaborazione.Luminosita(meta!, guidaAlta);
                rifinita = rifinitaAlta = Elaborazione.FiltroGuidatoVeloce(guidaAlta, lw, aw, guida, mascheraLavoro, lq, aq, raggio, 1e-3f,
                    lavagna, rifinitaAlta);
            }
            else
            {
                rifinita = Elaborazione.FiltroGuidato(guida, mascheraLavoro, lq, aq, raggio, 1e-3f, lavagna);
            }
        }
        if (alfa.Length != lw * aw) alfa = new byte[lw * aw];
        var sostituito = imp.Sfondo == ModiSfondo.Sostituito;
        // Qualità 8: il verde pieno per il chroma key è uno sfondo sostituito con il bordo netto e senza light wrap.
        var verde = sostituito && imp.ImmagineSfondo == SfondoVerde.Id;
        var intensita = Math.Clamp(imp.IntensitaSfondo, 0, 1);
        // Con «sostituito» e intensità alta il bordo è più netto (larghezza della soglia da 0,8 a 0,2), come sul Mac; con lo
        // sfocato la soglia 0,3–0,7 del banco di qualità (variante D*); con il verde la più stretta.
        if (verde) Elaborazione.SogliaMorbida(rifinita, alfa, SfondoVerde.LarghezzaSoglia);
        else if (sostituito) Elaborazione.SogliaMorbida(rifinita, alfa, (float)(0.8 - 0.6 * intensita));
        else Elaborazione.SogliaMorbida(rifinita, alfa, Elaborazione.LarghezzaSogliaSfocato, Elaborazione.CentroSogliaSfocato);

        // Il fondo: l'immagine scelta alla misura del video, o lo sfondo sfocato senza alone (piccolo).
        PianoComposizione piano;
        if (verde)
        {
            // Il verde pieno alla misura del video (sale sulla scheda video una volta sola). Il bordo pulito resta (toglie il
            // vecchio sfondo dai capelli, che il chroma key vedrebbe come un alone), il light wrap no: niente verde sfocato
            // che entra nella persona.
            var fondoVerde = Verde(l, a);
            piano = new PianoComposizione
            {
                Sorgente = src, Alfa = alfa, LarghezzaAlfa = lw, AltezzaAlfa = aw, Calore = calore,
                FondoPieno = fondoVerde.Immagine, ChiaveFondo = fondoVerde.Chiave,
                ColorePersona = livello.ConBordoBilineare() ? null
                    : ColorePersona(quarto, AlfaAlQuarto(alfa, lw, aw, lq, aq), RegoleBordo.SigmaColorePersona * Math.Min(l, a) / 1080.0 * lq / l),
            };
        }
        else if (sostituito)
        {
            // Come il Mac (personaSuSfondoNuovo): bordo pulito dal vecchio sfondo (non al livello bilineare) e light wrap
            // del nuovo. Tutto in piccolo, a un quarto: il passo a piena risoluzione lo fa la composizione.
            var (fondoPieno, chiaveFondo) = SfondoAllaMisura(istantanea, imp.ImmagineSfondo, l, a);
            var alfaQuarto = AlfaAlQuarto(alfa, lw, aw, lq, aq);
            var unita = Math.Min(l, a) / 1080.0 * lq / l;
            piano = new PianoComposizione
            {
                Sorgente = src, Alfa = alfa, LarghezzaAlfa = lw, AltezzaAlfa = aw, Calore = calore,
                FondoPieno = fondoPieno, ChiaveFondo = chiaveFondo,
                ColorePersona = livello.ConBordoBilineare() ? null : ColorePersona(quarto, alfaQuarto, RegoleBordo.SigmaColorePersona * unita),
                SfondoMorbido = SfondoMorbido(fondoPieno, chiaveFondo, lq, aq, RegoleBordo.SigmaSfondoMorbido * unita),
                MascheraMorbida = MascheraMorbida(alfaQuarto, lq, aq, RegoleBordo.SigmaMascheraMorbida * unita),
                LarghezzaMorbida = lq, AltezzaMorbida = aq,
            };
        }
        else
        {
            // Qualità 7 e 8: lo stile della sfocatura, con quello che regge il livello (il bokeh ai livelli veloci torna normale).
            var stile = StiliSfocatura.AlLivello(imp.Sfocatura, livello);
            piano = new PianoComposizione
            {
                Sorgente = src, Alfa = alfa, LarghezzaAlfa = lw, AltezzaAlfa = aw, Calore = calore,
                FondoPiccolo = stile switch
                {
                    StiliSfocatura.Bokeh => SfocataBokeh(quarto, maschera, intensita, calore, l, a, StiliSfocatura.GradinoBokeh(livello)),
                    StiliSfocatura.Mosaico => SfondoAMosaico(quarto, maschera, intensita, calore, l, a),
                    _ => SfocataSenzaAlone(quarto, maschera, intensita, calore, l, a),
                },
                FondoAQuadretti = stile == StiliSfocatura.Mosaico,
            };
        }
        ComponiConLaMigliore(piano, destinazione);
    }

    // MARK: bokeh, mosaico e verde (Qualità 7 e 8)

    private readonly RicetteSfondo.LavagnaBokeh lavagnaBokeh = new();
    private ImmagineBgra? bokehPronto, mosaicoPronto;
    private float[] personaPiccola = [];
    private (string Chiave, ImmagineBgra Immagine)? verdePronto;

    /// <summary>
    /// Il bokeh (<see cref="RicetteSfondo.Bokeh"/>) a un quarto (gradino 0) o a un ottavo (gradino 1) della misura, più in
    /// piccolo se il disco è grande (<see cref="RicetteSfondo.GradinoDisco"/>), con il disco di
    /// <see cref="RicetteSfondo.RaggioBokeh"/> portato a quella misura.
    /// </summary>
    private ImmagineBgra SfocataBokeh(ImmagineBgra quarto, MascheraPersona maschera, double intensita, byte[][]? calore,
        int larghezzaPiena, int altezzaPiena, int gradino)
    {
        var raggioPieno = RicetteSfondo.RaggioBokeh(intensita, Math.Min(larghezzaPiena, altezzaPiena));
        gradino = RicetteSfondo.GradinoDisco(raggioPieno, gradino);
        var livello = quarto;
        while (piramide.Count < gradino) piramide.Add(null!);
        for (var i = 0; i < gradino; i++)
        {
            piramide[i] = Elaborazione.Dimezza(livello, piramide[i]);
            livello = piramide[i];
        }
        var raggio = raggioPieno * livello.Larghezza / larghezzaPiena;
        personaPiccola = Elaborazione.Campiona(maschera.Valori, maschera.Larghezza, maschera.Altezza, livello.Larghezza, livello.Altezza,
            personaPiccola);
        bokehPronto = RicetteSfondo.Bokeh(livello, personaPiccola, raggio, calore, bokehPronto, lavagnaBokeh);
        return bokehPronto;
    }

    /// <summary>Il mosaico (<see cref="RicetteSfondo.Mosaico"/>) contato sul quarto: un pixel per quadretto.</summary>
    private ImmagineBgra SfondoAMosaico(ImmagineBgra quarto, MascheraPersona maschera, double intensita, byte[][]? calore,
        int larghezzaPiena, int altezzaPiena)
    {
        var (colonne, righe) = RicetteSfondo.Griglia(larghezzaPiena, altezzaPiena, intensita);
        personaPiccola = Elaborazione.Campiona(maschera.Valori, maschera.Larghezza, maschera.Altezza, quarto.Larghezza, quarto.Altezza,
            personaPiccola);
        mosaicoPronto = RicetteSfondo.Mosaico(quarto, personaPiccola, colonne, righe, calore, mosaicoPronto);
        return mosaicoPronto;
    }

    /// <summary>Il verde pieno (#00B140) alla misura del video, fatto una volta per misura, con la sua chiave.</summary>
    private (ImmagineBgra Immagine, string Chiave) Verde(int l, int a)
    {
        var chiave = $"{SfondoVerde.Id}-{l}x{a}";
        if (verdePronto is { } pronto && pronto.Chiave == chiave) return (pronto.Immagine, chiave);
        var immagine = new ImmagineBgra(l, a);
        var (r, g, b) = SfondoVerde.Colore;
        for (var i = 0; i < l * a; i++)
        {
            immagine.Dati[i * 4] = b;
            immagine.Dati[i * 4 + 1] = g;
            immagine.Dati[i * 4 + 2] = r;
            immagine.Dati[i * 4 + 3] = 255;
        }
        verdePronto = (chiave, immagine);
        return (immagine, chiave);
    }

    // MARK: composizione sulla scheda video o sul processore (Qualità 5)

    /// <summary>Errori di fila della scheda video dopo i quali la si lascia (driver aggiornato, sospensione, TDR).</summary>
    public const int ErroriSchedaVideoPerLasciare = 3;

    /// <summary>Quante volte si riapre la scheda video persa durante il funzionamento, poi resta il processore.</summary>
    public const int RiapertureSchedaVideo = 1;

    /// <summary>
    /// Il passo a piena risoluzione sulla scheda video se c'è e funziona, altrimenti sul processore. La scheda video si
    /// apre in sottofondo la prima volta che serve (compila lo shader e si confronta con il processore): intanto, e se
    /// non si apre, lavora il processore. Un errore della scheda video rifà lo stesso fotogramma sul processore; dopo
    /// <see cref="ErroriSchedaVideoPerLasciare"/> di fila la si chiude e si riapre una volta sola.
    /// </summary>
    private void ComponiConLaMigliore(PianoComposizione piano, ImmagineBgra destinazione)
    {
        PreparaSchedaVideo();
        if (schedaVideo is { } gpu)
        {
            try
            {
                gpu.Componi(piano, destinazione);
                erroriSchedaVideo = 0;
                return;
            }
            catch (Exception errore)
            {
                if (++erroriSchedaVideo >= ErroriSchedaVideoPerLasciare)
                {
                    try { gpu.Dispose(); }
                    catch (Exception) { }
                    schedaVideo = null;
                    erroriSchedaVideo = 0;
                    var riapre = riaperture++ < RiapertureSchedaVideo;
                    if (!riapre) schedaVideoEsclusa = true;
                    preparazioneSchedaVideo = null;
                    cambi.Add(new CambioComposizione(false, processore.Descrizione,
                        $"{(riapre ? "scheda video persa, si riapre" : "scheda video persa")}: {errore.Message}"));
                }
            }
        }
        processore.Componi(piano, destinazione);
    }

    /// <summary>Apre la scheda video in sottofondo (una volta), e la prende quando è pronta.</summary>
    private void PreparaSchedaVideo()
    {
        if (creaSchedaVideo is null || schedaVideo is not null || schedaVideoEsclusa) return;
        if (preparazioneSchedaVideo is null)
        {
            var crea = creaSchedaVideo;
            preparazioneSchedaVideo = Task.Run(crea);
            return;
        }
        if (!preparazioneSchedaVideo.IsCompleted) return;
        var compito = preparazioneSchedaVideo;
        preparazioneSchedaVideo = null;
        if (compito.IsCompletedSuccessfully)
        {
            schedaVideo = compito.Result;
            erroriSchedaVideo = 0;
            cambi.Add(new CambioComposizione(true, schedaVideo.Descrizione, null));
        }
        else
        {
            // Non si apre (niente Direct3D 11, shader che non compila, risultato diverso dal processore): non si riprova.
            schedaVideoEsclusa = true;
            var motivo = compito.Exception?.InnerException?.Message ?? "non si apre";
            cambi.Add(new CambioComposizione(false, processore.Descrizione, motivo));
        }
    }

    /// <summary>Dove si fa adesso il passo a piena risoluzione dello sfondo.</summary>
    public bool ComponeSullaSchedaVideo => schedaVideo is not null;

    /// <summary>I cambi (scheda video presa o lasciata) dall'ultima chiamata, per il registro.</summary>
    public IReadOnlyList<CambioComposizione> PrendiCambi()
    {
        if (cambi.Count == 0) return [];
        var presi = cambi.ToList();
        cambi.Clear();
        return presi;
    }

    public void Dispose()
    {
        schedaVideo?.Dispose();
        schedaVideo = null;
        if (preparazioneSchedaVideo is { } compito)
        {
            compito.ContinueWith(t =>
            {
                if (t.IsCompletedSuccessfully) t.Result.Dispose();
                else _ = t.Exception;
            }, TaskScheduler.Default);
        }
        preparazioneSchedaVideo = null;
        schedaVideoEsclusa = true;
    }

    // MARK: bordo pulito e light wrap (sostituito)

    /// <summary>L'alfa (0–255) a un quarto: com'è se è già lì, altrimenti media di 2×2 (come Dimezza).</summary>
    private byte[] AlfaAlQuarto(byte[] alfa, int lw, int aw, int lq, int aq)
    {
        if (lw == lq && aw == aq) return alfa;
        if (alfaQuarto.Length != lq * aq) alfaQuarto = new byte[lq * aq];
        for (var y = 0; y < aq; y++)
        {
            var r0 = Math.Min(2 * y, aw - 1) * lw;
            var r1 = Math.Min(2 * y + 1, aw - 1) * lw;
            for (var x = 0; x < lq; x++)
            {
                int c0 = Math.Min(2 * x, lw - 1), c1 = Math.Min(2 * x + 1, lw - 1);
                alfaQuarto[y * lq + x] = (byte)((alfa[r0 + c0] + alfa[r0 + c1] + alfa[r1 + c0] + alfa[r1 + c1] + 2) >> 2);
            }
        }
        return alfaQuarto;
    }

    /// <summary>
    /// Il colore dell'interno sicuro della persona, piccolo: media pesata (<see cref="RegoleBordo.PesoInterno"/>) con il
    /// nucleo gaussiano, divisa per il peso sfocato (mediaNormalizzata del Mac).
    /// </summary>
    private ImmagineBgra ColorePersona(ImmagineBgra quarto, byte[] alfaQuarto, double sigma)
    {
        int l = quarto.Larghezza, a = quarto.Altezza, n = l * a;
        if (lavagnaColore.Length < n * 4) lavagnaColore = new float[n * 4];
        if (appoggioColore.Length < n * 4) appoggioColore = new float[n * 4];
        var s = quarto.Dati;
        for (var i = 0; i < n; i++)
        {
            var w = RegoleBordo.PesoInterno(alfaQuarto[i] * (1f / 255f));
            lavagnaColore[i * 4] = s[i * 4] * w;
            lavagnaColore[i * 4 + 1] = s[i * 4 + 1] * w;
            lavagnaColore[i * 4 + 2] = s[i * 4 + 2] * w;
            lavagnaColore[i * 4 + 3] = w;
        }
        Elaborazione.Gaussiana(lavagnaColore, l, a, 4, sigma, appoggioColore);
        colorePersona = Prepara(colorePersona, l, a);
        var d = colorePersona.Dati;
        for (var i = 0; i < n; i++)
        {
            var inv = 1f / Math.Max(lavagnaColore[i * 4 + 3], 1e-4f);
            d[i * 4] = (byte)Math.Min(255f, lavagnaColore[i * 4] * inv + 0.5f);
            d[i * 4 + 1] = (byte)Math.Min(255f, lavagnaColore[i * 4 + 1] * inv + 0.5f);
            d[i * 4 + 2] = (byte)Math.Min(255f, lavagnaColore[i * 4 + 2] * inv + 0.5f);
            d[i * 4 + 3] = 255;
        }
        return colorePersona;
    }

    /// <summary>Lo sfondo nuovo ridotto a un quarto e sfocato, per il light wrap: si rifà solo quando cambia lo sfondo.</summary>
    private ImmagineBgra SfondoMorbido(ImmagineBgra fondoPieno, string chiave, int lq, int aq, double sigma)
    {
        var chiaveMorbido = $"{chiave}|{lq}x{aq}|{sigma:0.###}";
        if (sfondoMorbido is { } pronto && pronto.Chiave == chiaveMorbido) return pronto.Immagine;
        var meta = Elaborazione.Dimezza(fondoPieno);
        var piccolo = Elaborazione.Dimezza(meta);
        if (piccolo.Larghezza != lq || piccolo.Altezza != aq)
        {
            var esatto = new ImmagineBgra(lq, aq);
            Elaborazione.Ricampiona(piccolo, 0, 0, piccolo.Larghezza, piccolo.Altezza, esatto, false);
            piccolo = esatto;
        }
        int n = lq * aq;
        var piano = new float[n * 4];
        for (var i = 0; i < n * 4; i++) piano[i] = piccolo.Dati[i];
        Elaborazione.Gaussiana(piano, lq, aq, 4, sigma, new float[n * 4]);
        for (var i = 0; i < n * 4; i++) piccolo.Dati[i] = (byte)Math.Min(255f, piano[i] + 0.5f);
        for (var i = 3; i < n * 4; i += 4) piccolo.Dati[i] = 255;
        sfondoMorbido = (chiaveMorbido, piccolo);
        return piccolo;
    }

    /// <summary>La maschera a un quarto sfocata (0–255), per trovare l'orlo interno della persona (light wrap).</summary>
    private byte[] MascheraMorbida(byte[] alfaQuarto, int lq, int aq, double sigma)
    {
        var n = lq * aq;
        if (lavagnaMaschera.Length < n) lavagnaMaschera = new float[n];
        if (appoggioMaschera.Length < n) appoggioMaschera = new float[n];
        for (var i = 0; i < n; i++) lavagnaMaschera[i] = alfaQuarto[i];
        Elaborazione.Gaussiana(lavagnaMaschera, lq, aq, 1, sigma, appoggioMaschera);
        if (mascheraMorbida.Length != n) mascheraMorbida = new byte[n];
        for (var i = 0; i < n; i++) mascheraMorbida[i] = (byte)Math.Min(255f, lavagnaMaschera[i] + 0.5f);
        return mascheraMorbida;
    }

    /// <summary>
    /// Lo sfondo sfocato senza la persona (sfocatura normalizzata, niente alone), piccolo: la persona (allargata) esce
    /// dall'immagine come alfa, si sfoca con il nucleo gaussiano e si divide per l'alfa sfocato, così ogni punto prende
    /// colore solo dallo sfondo vicino (EffettoSfondo.swift dell'iPhone, sfocataSenzaAlone del Mac).
    /// </summary>
    private ImmagineBgra SfocataSenzaAlone(ImmagineBgra quarto, MascheraPersona maschera, double intensita, byte[][]? calore,
        int larghezzaPiena, int altezzaPiena)
    {
        var sigma = SigmaSfocatura(intensita) * Math.Min(larghezzaPiena, altezzaPiena) / 1080.0;
        var gradino = GradinoSfocatura(sigma);
        var livello = quarto;
        while (piramide.Count < gradino) piramide.Add(null!);
        for (var i = 0; i < gradino; i++)
        {
            piramide[i] = Elaborazione.Dimezza(livello, piramide[i]);
            livello = piramide[i];
        }
        var scala = (double)livello.Larghezza / larghezzaPiena;
        var sigmaPiccola = sigma * scala;
        int l = livello.Larghezza, a = livello.Altezza, n = l * a;
        var persona = Elaborazione.Campiona(maschera.Valori, maschera.Larghezza, maschera.Altezza, l, a);
        if (sfocata.Length < n * 4) sfocata = new float[n * 4];
        if (appoggio.Length < n * 4) appoggio = new float[n * 4];
        var s = livello.Dati;
        for (var i = 0; i < n; i++)
        {
            // Persona allargata (come sul Mac: 2m − 0,3, al massimo 0,99): il bordo non sporca lo sfondo.
            var w = 1f - Math.Clamp(2f * persona[i] - 0.3f, 0f, 0.99f);
            byte b = s[i * 4], g = s[i * 4 + 1], r = s[i * 4 + 2];
            if (calore is not null)
            {
                b = calore[2][b];
                g = calore[1][g];
                r = calore[0][r];
            }
            sfocata[i * 4] = b * w;
            sfocata[i * 4 + 1] = g * w;
            sfocata[i * 4 + 2] = r * w;
            sfocata[i * 4 + 3] = w;
        }
        Elaborazione.Gaussiana(sfocata, l, a, 4, sigmaPiccola, appoggio);
        var uscita = new ImmagineBgra(l, a);
        var d = uscita.Dati;
        for (var i = 0; i < n; i++)
        {
            var w = sfocata[i * 4 + 3];
            if (w > 0.02f)
            {
                var inv = 1f / w;
                d[i * 4] = (byte)Math.Min(255f, sfocata[i * 4] * inv + 0.5f);
                d[i * 4 + 1] = (byte)Math.Min(255f, sfocata[i * 4 + 1] * inv + 0.5f);
                d[i * 4 + 2] = (byte)Math.Min(255f, sfocata[i * 4 + 2] * inv + 0.5f);
            }
            else
            {
                // Dentro una persona grande non c'è sfondo vicino: il colore sfocato con la persona (non si vede, è coperto).
                d[i * 4] = s[i * 4];
                d[i * 4 + 1] = s[i * 4 + 1];
                d[i * 4 + 2] = s[i * 4 + 2];
            }
            d[i * 4 + 3] = 255;
        }
        return uscita;
    }

    /// <summary>
    /// L'immagine dello sfondo sostituito alla misura del video, disegnata una volta; il fondo di Tema finché non c'è. Con
    /// la sua chiave (versione e misura), per non ricaricarla sulla scheda video a ogni fotogramma.
    /// </summary>
    private (ImmagineBgra Immagine, string Chiave) SfondoAllaMisura(StatoEffettiComputer.Istantanea istantanea, string? voluta, int l, int a)
    {
        var sfondo = istantanea.Sfondo;
        var valida = sfondo is { } s && (voluta is null || s.Id == voluta);
        var chiave = valida ? $"{sfondo!.Value.Versione}-{l}x{a}" : $"fondo-{l}x{a}";
        if (sfondoPronto is { } pronto && pronto.Chiave == chiave) return (pronto.Immagine, chiave);
        ImmagineBgra immagine;
        if (valida) immagine = Elaborazione.Riempi(sfondo!.Value.Immagine, l, a);
        else
        {
            immagine = new ImmagineBgra(l, a);
            for (var i = 0; i < l * a; i++)
            {
                immagine.Dati[i * 4] = ColoreFondo.B;
                immagine.Dati[i * 4 + 1] = ColoreFondo.G;
                immagine.Dati[i * 4 + 2] = ColoreFondo.R;
                immagine.Dati[i * 4 + 3] = 255;
            }
        }
        sfondoPronto = (chiave, immagine);
        return (immagine, chiave);
    }

    /// <summary>sopra × alfa + sotto × (1 − alfa), byte per byte, con i vettori del processore; il risultato in <paramref name="sopra"/>.</summary>
    public static void Miscela(Span<byte> sopra, ReadOnlySpan<byte> sotto, ReadOnlySpan<byte> alfa)
    {
        var i = 0;
        if (Vector.IsHardwareAccelerated && sopra.Length >= Vector<byte>.Count)
        {
            var bianco = new Vector<ushort>(255);
            var arrotonda = new Vector<ushort>(128);
            for (; i <= sopra.Length - Vector<byte>.Count; i += Vector<byte>.Count)
            {
                Vector.Widen(new Vector<byte>(sopra.Slice(i)), out var s0, out var s1);
                Vector.Widen(new Vector<byte>(sotto.Slice(i)), out var t0, out var t1);
                Vector.Widen(new Vector<byte>(alfa.Slice(i)), out var a0, out var a1);
                var r0 = s0 * a0 + t0 * (bianco - a0) + arrotonda;
                var r1 = s1 * a1 + t1 * (bianco - a1) + arrotonda;
                // Diviso 255: (v + (v >> 8)) >> 8.
                r0 = Vector.ShiftRightLogical(r0 + Vector.ShiftRightLogical(r0, 8), 8);
                r1 = Vector.ShiftRightLogical(r1 + Vector.ShiftRightLogical(r1, 8), 8);
                Vector.Narrow(r0, r1).CopyTo(sopra.Slice(i));
            }
        }
        for (; i < sopra.Length; i++)
        {
            var v = sopra[i] * alfa[i] + sotto[i] * (255 - alfa[i]) + 128;
            sopra[i] = (byte)((v + (v >> 8)) >> 8);
        }
    }

    // MARK: luce sul volto

    /// <summary>
    /// Il volto della luce, levigato (25% del nuovo per fotogramma), con una dissolvenza di mezzo secondo quando compare,
    /// sparisce, o la luce si accende e si spegne. Null se non c'è niente da schiarire.
    /// </summary>
    private Rettangolo? PassoLuce(List<Rettangolo> volti, bool acceso, double dt, int l, int a)
    {
        var passo = dt / 0.5;
        var trovato = acceso
            ? volti.Where(v => v.Altezza > 8 && v.X < l && v.Y < a && v.Destra > 0 && v.Basso > 0)
                .OrderByDescending(v => v.Larghezza * v.Altezza).Cast<Rettangolo?>().FirstOrDefault()
            : null;
        if (trovato is { } t)
        {
            if (voltoLuce is { } vecchio)
            {
                const double peso = 0.25;
                voltoLuce = new Rettangolo(vecchio.X + (t.X - vecchio.X) * peso, vecchio.Y + (t.Y - vecchio.Y) * peso,
                    vecchio.Larghezza + (t.Larghezza - vecchio.Larghezza) * peso, vecchio.Altezza + (t.Altezza - vecchio.Altezza) * peso);
            }
            else
            {
                voltoLuce = t;
            }
            presenzaLuce = Math.Min(presenzaLuce + passo, 1);
        }
        else
        {
            presenzaLuce = Math.Max(presenzaLuce - passo, 0);
        }
        if (voltoLuce is null || presenzaLuce <= 0.01)
        {
            if (presenzaLuce <= 0.01) voltoLuce = null;
            return null;
        }
        return voltoLuce;
    }

    // MARK: tabelle e scritta

    private byte[][]? TabelleCalore(double forza)
    {
        if (calorePronto is { } p && p.Forza == forza) return p.Tabelle;
        byte[][]? tabelle = null;
        if (RicetteColore.Calore(forza) is { } stadio && CatenaColore.Da([stadio]) is { TabellePerCanale: { } t }) tabelle = t;
        calorePronto = (forza, tabelle);
        return tabelle;
    }

    private CatenaColore? Catena(ImpostazioniMotore imp, bool conCalore)
    {
        var chiave = $"{imp.Filtro}|{imp.Luminosita}|{imp.Contrasto}|{imp.Saturazione}|{(conCalore ? imp.Calore : 0)}";
        if (catenaPronta is { } p && p.Chiave == chiave) return p.Catena;
        var stadi = new List<StadioColore>();
        if (conCalore && RicetteColore.Calore(imp.Calore) is { } calore) stadi.Add(calore);
        stadi.AddRange(RicetteColore.Filtro(imp.Filtro));
        if (RicetteColore.Regolazioni(imp.Luminosita, imp.Contrasto, imp.Saturazione) is { } r) stadi.Add(r);
        var catena = CatenaColore.Da(stadi);
        catenaPronta = (chiave, catena);
        return catena;
    }

    /// <summary>La vignettatura di «Cinema» (CIVignetteEffect con raggio 0,4 della diagonale e intensità 0,35), come guadagno 0–256.</summary>
    private ushort[] Vignetta(int l, int a)
    {
        if (vignettaPronta is { } p && p.L == l && p.A == a) return p.Guadagni;
        var guadagni = new ushort[l * a];
        var raggio = Math.Sqrt((double)l * l + (double)a * a) * 0.4;
        for (var y = 0; y < a; y++)
        {
            for (var x = 0; x < l; x++)
            {
                var d = Math.Sqrt(Math.Pow(x + 0.5 - l / 2.0, 2) + Math.Pow(y + 0.5 - a / 2.0, 2)) / raggio;
                var t = Math.Clamp((d - 0.5) / 1.0, 0, 1);
                var g = 1 - 0.35 * t * t * (3 - 2 * t);
                guadagni[y * l + x] = (ushort)Math.Round(g * 256);
            }
        }
        vignettaPronta = (l, a, guadagni);
        return guadagni;
    }

    /// <summary>Margini di sicurezza: 4,5% dei lati in orizzontale, 6% in verticale (la barra delle app di chiamata).</summary>
    public static (int X, int Y) Margini(int l, int a) => ((int)Math.Round(l * 0.045), (int)Math.Round(a * 0.06));

    /// <summary>
    /// La misura del logo: al massimo il 9% del lato corto in altezza e il 22% della larghezza, proporzioni tenute
    /// (logo del Mac e dell'iPhone).
    /// </summary>
    public static (int L, int A) MisuraLogo(int logoL, int logoA, int l, int a)
    {
        var scala = Math.Min(Math.Min(l, a) * 0.09 / logoA, l * 0.22 / logoL);
        return (Math.Max(1, (int)Math.Round(logoL * scala)), Math.Max(1, (int)Math.Round(logoA * scala)));
    }

    private void Scritta(ImmagineBgra uscita, ImpostazioniMotore imp, StatoEffettiComputer.Istantanea istantanea)
    {
        int l = uscita.Larghezza, a = uscita.Altezza;
        var nome = imp.Nome.Trim();
        var ruolo = imp.Ruolo.Trim();
        var versioneLogo = imp.Logo ? istantanea.Logo?.Versione ?? -1 : -1;
        var chiave = $"{nome}|{ruolo}|{versioneLogo}|{l}x{a}|{istantanea.Scritta?.GetHashCode()}";
        if (scrittaPronta?.Chiave != chiave)
        {
            ImmagineBgra? barra = null;
            if (nome.Length > 0)
            {
                try { barra = istantanea.Scritta?.Disegna(nome, ruolo, l, a); }
                catch (Exception) { barra = null; }
            }
            ImmagineBgra? logo = null;
            if (imp.Logo && istantanea.Logo is { } sorgente)
            {
                var (ll, la) = MisuraLogo(sorgente.Immagine.Larghezza, sorgente.Immagine.Altezza, l, a);
                logo = new ImmagineBgra(ll, la);
                Elaborazione.Ricampiona(sorgente.Immagine, 0, 0, sorgente.Immagine.Larghezza, sorgente.Immagine.Altezza, logo, false);
                Premoltiplica(logo);
            }
            scrittaPronta = (chiave, barra, logo);
        }
        var (mx, my) = Margini(l, a);
        if (scrittaPronta?.Scritta is { } disegnata) Sovrapponi(uscita, disegnata, mx, a - my - disegnata.Altezza);
        if (scrittaPronta?.Logo is { } logoPronto) Sovrapponi(uscita, logoPronto, l - mx - logoPronto.Larghezza, my);
    }

    /// <summary>Dall'alfa diritto (PNG) all'alfa premoltiplicato.</summary>
    public static void Premoltiplica(ImmagineBgra immagine)
    {
        var d = immagine.Dati;
        for (var i = 0; i < immagine.Larghezza * immagine.Altezza * 4; i += 4)
        {
            int alfa = d[i + 3];
            d[i] = (byte)((d[i] * alfa + 127) / 255);
            d[i + 1] = (byte)((d[i + 1] * alfa + 127) / 255);
            d[i + 2] = (byte)((d[i + 2] * alfa + 127) / 255);
        }
    }

    /// <summary>Un'immagine con l'alfa premoltiplicato sopra la destinazione, in (x, y); la parte fuori si taglia.</summary>
    public static void Sovrapponi(ImmagineBgra destinazione, ImmagineBgra sopra, int x, int y)
    {
        for (var r = 0; r < sopra.Altezza; r++)
        {
            var yd = y + r;
            if (yd < 0 || yd >= destinazione.Altezza) continue;
            for (var c = 0; c < sopra.Larghezza; c++)
            {
                var xd = x + c;
                if (xd < 0 || xd >= destinazione.Larghezza) continue;
                var s = r * sopra.Passo + c * 4;
                int alfa = sopra.Dati[s + 3];
                if (alfa == 0) continue;
                var d = yd * destinazione.Passo + xd * 4;
                var resto = 255 - alfa;
                for (var k = 0; k < 3; k++)
                    destinazione.Dati[d + k] = (byte)Math.Min(255, sopra.Dati[s + k] + (destinazione.Dati[d + k] * resto + 127) / 255);
            }
        }
    }

    private static void ApplicaTabelle(ImmagineBgra immagine, byte[][] tabelle)
    {
        Elaborazione.PerRighe(immagine.Altezza, (inizio, fine) =>
        {
            for (var y = inizio; y < fine; y++)
            {
                var riga = immagine.Dati.AsSpan(y * immagine.Passo, immagine.Passo);
                for (var x = 0; x < riga.Length; x += 4)
                {
                    riga[x] = tabelle[2][riga[x]];
                    riga[x + 1] = tabelle[1][riga[x + 1]];
                    riga[x + 2] = tabelle[0][riga[x + 2]];
                }
            }
        });
    }

    private static ImmagineBgra Prepara(ImmagineBgra? esistente, int l, int a) =>
        esistente is { } e && e.Larghezza == l && e.Altezza == a ? e : new ImmagineBgra(l, a);
}
