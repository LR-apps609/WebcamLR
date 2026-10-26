using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Microfono;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Il microfono del telefono su Windows (W2), nella colonna Uscite come sul Mac: interruttore, livello, nota. Su Windows
/// non c'è un microfono «WebcamLR (microfono)»: servirebbe un driver audio firmato (Documenti/Microfono Windows.md).
/// L'audio del telefono, decodificato e messo a tempo con il video (MicrofonoTelefono), va all'uscita audio scelta: con
/// un cavo audio virtuale che l'utente ha già (VB-CABLE, Voicemeeter) le app di chiamata e OBS lo ricevono come
/// microfono. Gratis per tutti: non è di WebcamLR Pro. Il microfono segue il telefono nella webcam (P21).
/// </summary>
public sealed partial class MainWindow
{
    private const int TaccheMicrofono = 12;

    /// <summary>Decodifica, buffer anti-jitter e livello; lo usano i thread di rete e quello dell'uscita audio.</summary>
    private readonly MicrofonoTelefono microfono = new(formato => DecodificatoreAac.Crea(formato));
    /// <summary>L'interruttore (1 acceso): letto anche dai thread di rete.</summary>
    private int microfonoAcceso;
    /// <summary>Il telefono da cui arriva l'audio: quello nella webcam. Letto anche dai thread di rete.</summary>
    private TelefonoCollegato? telefonoMicrofono;
    private UscitaAudio? uscitaAudio;
    private IReadOnlyList<DispositivoAudio> usciteAudio = [];
    private string? erroreUscitaAudio;
    private double livelloMicrofono;
    /// <summary>Cresce a ogni apertura o chiusura dell'uscita: un'apertura vecchia arrivata tardi si butta.</summary>
    private int generazioneUscita;
    private bool impostandoMicrofono;

    private bool MicrofonoAcceso => Volatile.Read(ref microfonoAcceso) == 1;

    /// <summary>All'avvio: le tacche del livello, la scelta salvata e l'elenco delle uscite audio.</summary>
    private void InizializzaMicrofono()
    {
        for (var i = 0; i < TaccheMicrofono; i++)
        {
            LivelloMicrofono.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var tacca = new Microsoft.UI.Xaml.Shapes.Rectangle { RadiusX = 1.5, RadiusY = 1.5, Fill = Pennello("PannelloChiaro") };
            Grid.SetColumn(tacca, i);
            LivelloMicrofono.Children.Add(tacca);
        }
        GuidaMicrofono.NavigateUri = new Uri(InfoApp.GuidaMicrofonoWindows);
        microfono.Livello += livello => coda.TryEnqueue(() =>
        {
            // Spento da qui: un livello rimasto in coda non riaccende l'indicatore.
            livelloMicrofono = MicrofonoAcceso ? livello : 0;
            MostraLivelloMicrofono();
        });
        microfono.Errore += testo => registro.Aggiungi(testo);
        Volatile.Write(ref microfonoAcceso, Preferenze.MicrofonoTelefono ? 1 : 0);
        impostandoMicrofono = true;
        InterruttoreMicrofono.IsOn = MicrofonoAcceso;
        impostandoMicrofono = false;
        AggiornaUsciteAudio();
        if (MicrofonoAcceso) _ = ApriUscitaAudioAsync();
        MostraMicrofono();
    }

    /// <summary>Alla chiusura dell'app.</summary>
    private void ChiudiMicrofono()
    {
        generazioneUscita++;
        ChiudiUscitaAudio();
        microfono.Dispose();
    }

    // MARK: dalla sessione (thread di rete)

    /// <summary>Formato e pacchetti audio di una sessione; solo quelli del telefono del microfono, a interruttore acceso.</summary>
    private void CollegaMicrofono(SessioneComputer nuova, Func<TelefonoCollegato?> suo)
    {
        nuova.FormatoAudioRicevuto += formato =>
        {
            if (suo() is not { } collegato || collegato.Sessione != nuova) return;
            collegato.FormatoAudio = formato;
            registro.Aggiungi(Testi.T("Registro_FormatoAudio", DiChi(collegato), formato.Codec, formato.Frequenza, formato.Canali,
                formato.Canali == 1 ? Testi.T("Audio_Canale") : Testi.T("Audio_Canali")));
            if (Volatile.Read(ref telefonoMicrofono) == collegato) microfono.Imposta(formato);
        };
        nuova.AudioRicevuto += audio =>
        {
            if (!MicrofonoAcceso || suo() is not { } collegato || collegato.Sessione != nuova) return;
            if (Volatile.Read(ref telefonoMicrofono) != collegato) return;
            // La stessa differenza di orologi del video: audio e immagini restano allineati.
            microfono.Ricevi(audio, nuova.ScartoOrologi, nuova.LatenzaVideoMs);
        };
    }

    // MARK: telefono scelto

    /// <summary>
    /// Il telefono nella webcam è cambiato (o è tornato con una sessione nuova): quello di prima smette di mandare l'audio,
    /// quello nuovo lo manda se l'interruttore è acceso.
    /// </summary>
    private void MicrofonoSegueScelto(bool sessioneNuova = false)
    {
        var nuovo = Scelto;
        var vecchio = Volatile.Read(ref telefonoMicrofono);
        if (vecchio != nuovo || sessioneNuova)
        {
            if (vecchio is { AudioComandato: true } prima && prima != nuovo && prima.Sessione is { } sua)
            {
                _ = ComandaAsync(sua, new Comando(Audio: false));
                prima.AudioComandato = false;
            }
            Volatile.Write(ref telefonoMicrofono, nuovo);
            microfono.Ferma();
            livelloMicrofono = 0;
            if (nuovo?.FormatoAudio is { } formato) microfono.Imposta(formato);
        }
        ChiediAudioSeServe();
        MostraMicrofono();
    }

    /// <summary>A interruttore acceso, chiede l'audio al telefono scelto appena dice di saperlo fare (<c>capacita.audio</c>).</summary>
    private void ChiediAudioSeServe()
    {
        if (!MicrofonoAcceso || Scelto is not { } scelto || scelto.Capacita?.Audio != true || scelto.AudioComandato) return;
        if (scelto.Sessione is not { } attiva) return;
        scelto.AudioComandato = true;
        _ = ComandaAsync(attiva, new Comando(Audio: true));
    }

    /// <summary>
    /// Il microfono è stato acceso o spento sul telefono scelto (<c>stato.audio</c> è cambiato): l'interruttore lo segue,
    /// così l'audio non si scarta qui e non si aspetta un audio che non arriverà.
    /// </summary>
    private void MicrofonoDalTelefono(TelefonoCollegato collegato, bool? prima, bool? adesso)
    {
        if (adesso is not bool acceso || prima is not bool primaAcceso || acceso == primaAcceso) return;
        collegato.AudioComandato = acceso;
        if (acceso != MicrofonoAcceso) ImpostaMicrofono(acceso, dalTelefono: true);
    }

    // MARK: interruttore e uscita

    private void SuInterruttoreMicrofono(object sender, RoutedEventArgs e)
    {
        if (impostandoMicrofono) return;
        ImpostaMicrofono(InterruttoreMicrofono.IsOn, dalTelefono: false);
    }

    private void ImpostaMicrofono(bool acceso, bool dalTelefono)
    {
        if (acceso != MicrofonoAcceso)
        {
            Volatile.Write(ref microfonoAcceso, acceso ? 1 : 0);
            Preferenze.MicrofonoTelefono = acceso;
            registro.Aggiungi(dalTelefono
                ? (acceso ? Testi.T("Registro_MicrofonoAccesoDalTelefono") : Testi.T("Registro_MicrofonoSpentoDalTelefono"))
                : (acceso ? Testi.T("Registro_MicrofonoAcceso") : Testi.T("Registro_MicrofonoSpento")));
            if (!dalTelefono && Scelto is { } scelto && scelto.Capacita?.Audio == true && scelto.Sessione is { } attiva)
            {
                _ = ComandaAsync(attiva, new Comando(Audio: acceso));
                scelto.AudioComandato = acceso;
            }
            if (acceso)
            {
                AggiornaUsciteAudio();
                _ = ApriUscitaAudioAsync();
            }
            else
            {
                generazioneUscita++;
                ChiudiUscitaAudio();
                erroreUscitaAudio = null;
                microfono.Ferma();
                livelloMicrofono = 0;
            }
        }
        if (InterruttoreMicrofono.IsOn != acceso)
        {
            impostandoMicrofono = true;
            InterruttoreMicrofono.IsOn = acceso;
            impostandoMicrofono = false;
        }
        MostraMicrofono();
    }

    /// <summary>L'elenco si rilegge ogni volta che si apre: un cavo installato o una cuffia collegata compaiono subito.</summary>
    private void SuApriUsciteAudio(object? sender, object e) => AggiornaUsciteAudio();

    private void SuUscitaAudio(object sender, SelectionChangedEventArgs e)
    {
        if (impostandoMicrofono) return;
        var indice = SceltaUscitaMicrofono.SelectedIndex;
        if (indice < 0) return;
        // La prima voce è «nessuna uscita»: si salva vuota, così non si sceglie più un cavo da solo.
        Preferenze.UscitaMicrofono = indice == 0 || indice > usciteAudio.Count ? "" : usciteAudio[indice - 1].Id;
        if (UscitaScelta()?.Id == uscitaAudio?.Dispositivo.Id && erroreUscitaAudio is null)
        {
            MostraMicrofono();
            return;
        }
        if (MicrofonoAcceso) _ = ApriUscitaAudioAsync();
        else MostraMicrofono();
    }

    /// <summary>Le uscite di Windows nella tendina, con la scelta salvata (o il primo cavo virtuale) selezionata.</summary>
    private void AggiornaUsciteAudio()
    {
        var lette = UscitaAudio.Dispositivi();
        // Uguale a prima: la tendina resta com'è (svuotarla mentre si apre la richiuderebbe).
        if (lette.SequenceEqual(usciteAudio) && SceltaUscitaMicrofono.Items.Count == lette.Count + 1) return;
        usciteAudio = lette;
        var scelta = UsciteAudio.Scelta(usciteAudio, Preferenze.UscitaMicrofono);
        impostandoMicrofono = true;
        try
        {
            SceltaUscitaMicrofono.Items.Clear();
            SceltaUscitaMicrofono.Items.Add(new ComboBoxItem { Content = Testi.T("Microfono_NessunaUscita") });
            foreach (var dispositivo in usciteAudio) SceltaUscitaMicrofono.Items.Add(new ComboBoxItem { Content = dispositivo.Nome });
            SceltaUscitaMicrofono.SelectedIndex = scelta is null ? 0 : 1 + usciteAudio.ToList().FindIndex(d => d.Id == scelta.Id);
        }
        finally { impostandoMicrofono = false; }
    }

    private DispositivoAudio? UscitaScelta()
    {
        var indice = SceltaUscitaMicrofono.SelectedIndex;
        return indice >= 1 && indice <= usciteAudio.Count ? usciteAudio[indice - 1] : null;
    }

    /// <summary>Apre l'uscita scelta (chiudendo quella di prima); senza uscita scelta resta solo il livello.</summary>
    private async Task ApriUscitaAudioAsync()
    {
        var generazione = ++generazioneUscita;
        ChiudiUscitaAudio();
        erroreUscitaAudio = null;
        var scelta = UscitaScelta();
        if (scelta is null || !MicrofonoAcceso)
        {
            MostraMicrofono();
            return;
        }
        var (aperta, errore) = await UscitaAudio.ApriAsync(scelta, microfono.Leggi);
        if (generazione != generazioneUscita || !MicrofonoAcceso)
        {
            aperta?.Dispose();
            return;
        }
        if (aperta is null)
        {
            erroreUscitaAudio = errore;
            registro.Aggiungi(Testi.T("Registro_UscitaNonAperta", scelta.Nome, errore));
        }
        else
        {
            uscitaAudio = aperta;
            registro.Aggiungi(Testi.T("Registro_MicrofonoVerso", scelta.Nome));
            aperta.Interrotta += motivo => coda.TryEnqueue(() =>
            {
                if (uscitaAudio != aperta) return;
                ChiudiUscitaAudio();
                erroreUscitaAudio = motivo;
                registro.Aggiungi(Testi.T("Registro_UscitaInterrotta", scelta.Nome, motivo));
                MostraMicrofono();
            });
        }
        MostraMicrofono();
    }

    private void ChiudiUscitaAudio()
    {
        var vecchia = uscitaAudio;
        uscitaAudio = null;
        vecchia?.Dispose();
        microfono.RiprendiLettura();
    }

    // MARK: la riga

    private void MostraMicrofono()
    {
        var scelto = Scelto;
        var vista = StatoMicrofono.Descrivi(scelto is { InRiconnessione: false }, scelto?.Capacita?.Audio, MicrofonoAcceso,
            microfono.AudioInArrivo, UscitaScelta(), usciteAudio.Any(d => UsciteAudio.ECavoVirtuale(d.Nome)), erroreUscitaAudio);
        var colore = Pennello(vista.Attivo ? "Verde" : "TestoSecondario");
        IconaMicrofono.Foreground = colore;
        StatoMicrofonoTesto.Text = vista.Stato;
        StatoMicrofonoTesto.Foreground = colore;
        TestoMicrofono.Foreground = Pennello(vista.Utilizzabile ? "Testo" : "TestoSecondario");
        InterruttoreMicrofono.IsEnabled = vista.Utilizzabile;
        NotaMicrofono.Text = vista.Nota ?? "";
        NotaMicrofono.Visibility = Visibile(vista.Nota is not null);
        RigaMicrofono.Opacity = scelto is null ? 0.6 : 1;
        if (!vista.Attivo) livelloMicrofono = 0;
        MostraLivelloMicrofono();
    }

    /// <summary>Dodici tacche nell'accento, le ultime due in ambra: oltre il 90% il suono rischia di saturare.</summary>
    private void MostraLivelloMicrofono()
    {
        var accese = (int)Math.Round(Math.Clamp(livelloMicrofono, 0, 1) * TaccheMicrofono);
        for (var i = 0; i < LivelloMicrofono.Children.Count; i++)
        {
            if (LivelloMicrofono.Children[i] is not Microsoft.UI.Xaml.Shapes.Rectangle tacca) continue;
            tacca.Fill = Pennello(i >= accese ? "PannelloChiaro" : i >= TaccheMicrofono - 2 ? "Ambra" : "Accento");
        }
    }
}
