using WebcamLR.Protocollo;

namespace WebcamLR.Ricevitore;

/// <summary>
/// Qualità 15 (Documenti/Protocollo.md, «Qualità a scelta»): Auto, Alta o Massima per il flusso dal telefono. Si sceglie
/// sul PC, nel menu della qualità sopra il video, e vale per tutti i telefoni che la sanno fare
/// (<see cref="Capacita.SceltaQualita"/>). Il PC la salva e la rimanda a ogni sessione; il telefono la conferma in
/// <see cref="StatoTelefono.Qualita"/>. Come Mac/Sorgenti/QualitaScelta.swift.
/// </summary>
public static class QualitaScelta
{
    /// <summary>Il telefono accetta <see cref="Comando.Qualita"/>: solo allora il menu mostra la scelta.</summary>
    public static bool Disponibile(Capacita? capacita) => capacita?.SceltaQualita == true;

    /// <summary>Quella in uso sul telefono (<see cref="StatoTelefono.Qualita"/>, l'unica fonte di verità), altrimenti quella scelta sul PC.</summary>
    public static string InUso(StatoTelefono? stato, string scelta) => LivelliQualita.Normalizza(stato?.Qualita ?? scelta);

    /// <summary>
    /// Il <c>formato</c> da chiedere prima di <see cref="Comando.Qualita"/>: con Massima, al telefono nella webcam, la
    /// scelta più alta del menu (così il codec è quello giusto, HEVC per il 4K) e il telefono si riconfigura una volta
    /// sola. Null negli altri casi, o se il telefono manda già quello.
    /// </summary>
    public static FormatoVideo? FormatoPrima(string livello, bool selezionato, Capacita? capacita, FormatoVideo? attuale)
    {
        if (LivelliQualita.Normalizza(livello) != LivelliQualita.Massima || !selezionato || capacita is null) return null;
        var pro = RegolePro.Attivo(capacita);
        var (libere, _) = OpzioneQualita.Menu(capacita, bloccoPro: !pro);
        if (libere.Count == 0) return null;
        var piuAlta = libere[^1];
        return OpzioneQualita.Richiesta(piuAlta.Larghezza, piuAlta.Altezza, piuAlta.Fps, attuale, capacita.Formati, pro);
    }

    /// <summary>
    /// Una risoluzione scelta dal menu mentre il telefono è in Massima: il telefono non la seguirebbe, quindi si passa
    /// ad Alta (prima il <c>formato</c>, poi il comando). Null se non serve cambiare.
    /// </summary>
    public static string? DopoUnaRisoluzione(Capacita? capacita, StatoTelefono? stato, string scelta) =>
        Disponibile(capacita) && InUso(stato, scelta) == LivelliQualita.Massima ? LivelliQualita.Alta : null;

    /// <summary>Entrare in Massima o uscirne cambia la risoluzione: mentre si registra si chiede prima.</summary>
    public static bool CambiaRisoluzione(string da, string a) =>
        LivelliQualita.Normalizza(da) != LivelliQualita.Normalizza(a)
        && (LivelliQualita.Normalizza(da) == LivelliQualita.Massima || LivelliQualita.Normalizza(a) == LivelliQualita.Massima);

    /// <summary>«Auto», «Alta», «Massima».</summary>
    public static string Nome(string livello) => LivelliQualita.Normalizza(livello) switch
    {
        LivelliQualita.Alta => TestiRicevitore.T("QualitaScelta_Alta"),
        LivelliQualita.Massima => TestiRicevitore.T("QualitaScelta_Massima"),
        _ => TestiRicevitore.T("QualitaScelta_Auto"),
    };

    /// <summary>La nota breve accanto alla scelta nel menu.</summary>
    public static string Nota(string livello) => LivelliQualita.Normalizza(livello) switch
    {
        LivelliQualita.Alta => TestiRicevitore.T("QualitaScelta_NotaAlta"),
        LivelliQualita.Massima => TestiRicevitore.T("QualitaScelta_NotaMassima"),
        _ => TestiRicevitore.T("QualitaScelta_NotaAuto"),
    };
}
