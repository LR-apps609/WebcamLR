using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using WebcamLR.Protocollo;
using WebcamLR.Ricevitore;

namespace WebcamLR;

/// <summary>
/// Qualità 15 (Documenti/Protocollo.md, «Qualità a scelta»): Auto, Alta e Massima nel menu della qualità, sotto le
/// risoluzioni, solo con un telefono che dichiara <c>sceltaQualita</c>. La scelta resta salvata sul PC e va a ogni
/// telefono, alla prima <c>capacita</c> di ogni sessione; la spunta segue <c>stato.qualita</c>. Come sul Mac
/// (Mac/Sorgenti/QualitaScelta.swift). La logica è in <see cref="QualitaScelta"/>.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>La scelta con la spunta quando le voci sono state fatte: cambiata, si rifanno.</summary>
    private string? livelloMostrato;

    /// <summary>Alla <c>capacita</c> di un telefono: la scelta salvata, una volta per sessione (anche Auto).</summary>
    private void MandaQualitaSeServe(TelefonoCollegato collegato)
    {
        if (collegato.Sessione is not { } attiva || collegato.QualitaInviata(attiva)) return;
        MandaQualita(Preferenze.QualitaFlusso, collegato);
    }

    /// <summary>Dal menu: salva e manda a ogni telefono collegato che la sa fare.</summary>
    private void ScegliQualita(string livello)
    {
        Preferenze.QualitaFlusso = LivelliQualita.Normalizza(livello);
        foreach (var collegato in telefoni.Telefoni) MandaQualita(Preferenze.QualitaFlusso, collegato);
        livelloMostrato = null;
        MostraLivelliQualita();
    }

    /// <summary>Con Massima, al telefono nella webcam prima il <c>formato</c> più alto del menu, poi il comando.</summary>
    private void MandaQualita(string livello, TelefonoCollegato collegato)
    {
        if (collegato.Sessione is not { } attiva || !QualitaScelta.Disponibile(collegato.Capacita)) return;
        collegato.SegnaQualitaInviata(attiva);
        if (QualitaScelta.FormatoPrima(livello, telefoni.ESelezionato(collegato), collegato.Capacita, collegato.Formato) is { } formato)
        {
            registro.Aggiungi(Testi.T("Formato_Chiesto", formato.Larghezza, formato.Altezza, formato.Fps));
            ChiediFormato(collegato, attiva, formato);
        }
        registro.Aggiungi(Testi.T("Registro_QualitaChiesta", collegato.Nome, QualitaScelta.Nome(livello)));
        _ = ComandaAsync(attiva, new Comando(Qualita: livello));
    }

    /// <summary>Le tre voci, dal menu della qualità (<see cref="MostraQualita"/>).</summary>
    private void MostraLivelliQualita()
    {
        var disponibile = Scelto is { Sessione: not null } && QualitaScelta.Disponibile(capacitaAttuali);
        SezioneLivelli.Visibility = Visibile(disponibile);
        if (!disponibile)
        {
            livelloMostrato = null;
            return;
        }
        var inUso = QualitaScelta.InUso(statoTelefono, Preferenze.QualitaFlusso);
        if (livelloMostrato == inUso && ElencoLivelli.Children.Count > 0) return;
        livelloMostrato = inUso;
        ElencoLivelli.Children.Clear();
        foreach (var livello in LivelliQualita.Tutti)
            ElencoLivelli.Children.Add(VoceLivello(livello, livello == inUso));
    }

    /// <summary>Una voce: «Alta», la nota breve e la spunta se è quella in uso (come <see cref="VoceQualita"/>).</summary>
    private Button VoceLivello(string livello, bool scelta)
    {
        var riga = new Grid { ColumnSpacing = Token.SpazioStretto };
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        riga.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var nome = QualitaScelta.Nome(livello);
        riga.Children.Add(new TextBlock
        {
            Text = nome,
            FontSize = Token.MisuraCorpo,
            Foreground = Pennello("Testo"),
            VerticalAlignment = VerticalAlignment.Center,
        });
        var nota = new TextBlock
        {
            Text = QualitaScelta.Nota(livello),
            FontSize = Token.MisuraNota,
            Foreground = Pennello("TestoSecondario"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        Grid.SetColumn(nota, 1);
        riga.Children.Add(nota);
        if (scelta)
        {
            var segno = new FontIcon { Glyph = "", FontSize = Token.MisuraCorpoPiccolo, Foreground = Pennello("Accento"), VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(segno, 2);
            riga.Children.Add(segno);
        }
        var voce = new Button
        {
            Style = (Style)Application.Current.Resources["VoceMenu"],
            Content = riga,
            Background = scelta ? Pennello("PannelloChiaro") : null,
        };
        AutomationProperties.SetName(voce, scelta ? Testi.T("Voce_Scelta", nome) : nome);
        voce.Click += (_, _) => SuLivelloScelto(livello);
        return voce;
    }

    private void SuLivelloScelto(string livello)
    {
        FinestraNumeri.Hide();
        var inUso = QualitaScelta.InUso(statoTelefono, Preferenze.QualitaFlusso);
        if (livello == inUso) return;
        // Entrare in Massima o uscirne cambia la risoluzione: la registrazione si chiude, quindi prima si chiede.
        PrimaDiFermareLaRegistrazione(() => ScegliQualita(livello), cambiaIlVideo: QualitaScelta.CambiaRisoluzione(inUso, livello));
    }
}
