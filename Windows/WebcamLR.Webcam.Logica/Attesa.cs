using System.Globalization;

namespace WebcamLR.Webcam;

/// <summary>
/// Perché la webcam non mostra il video del telefono. L'app lo scrive nella memoria condivisa
/// (<see cref="AnelloFotogrammi.ImpostaAttesa"/>); la webcam disegna la schermata giusta. I valori sono nella memoria
/// condivisa: non cambiarli.
/// </summary>
public enum StatoAttesa : uint
{
    /// <summary>Nessuna attesa: il telefono dovrebbe mandare video. Se il video si ferma, dopo 2 s è «interrotta».</summary>
    Nessuna = 0,
    /// <summary>Nessun telefono collegato: «La webcam non è collegata · Apri WebcamLR sul telefono».</summary>
    NonCollegata = 1,
    /// <summary>Il telefono si è perso durante l'uso: «Collegamento interrotto · Riconnessione in corso…».</summary>
    Interrotta = 2,
    /// <summary>Il telefono è collegato ma in pausa (faccia in giù, dall'utente, pausa intelligente): «Webcam in pausa».</summary>
    Pausa = 3,
    /// <summary>
    /// WebcamLR chiusa (non scrive più il suo stato): «WebcamLR è chiusa · Apri WebcamLR sul computer». L'app non lo scrive
    /// mai: lo decide la webcam da sé (<see cref="ProgrammaAttesa.AppChiusa"/>), quindi la memoria condivisa non cambia.
    /// </summary>
    AppChiusa = 4,
}

/// <summary>
/// Lo stile della schermata di attesa (WebcamLR Pro, come sul Mac). Senza Pro l'app scrive sempre <see cref="WebcamLR"/>:
/// la webcam non sa nulla di Pro e usa lo stile che trova. I valori sono nella memoria condivisa: non cambiarli.
/// </summary>
public enum StileAttesa : uint
{
    /// <summary>Il disegno di WebcamLR: fondo verde quasi nero, logo, titolo e riga sotto.</summary>
    WebcamLR = 0,
    /// <summary>Tutto nero, senza scritte.</summary>
    Nero = 1,
    /// <summary>L'immagine scelta dall'utente (<see cref="AnelloFotogrammi.ScriviImmaginePersonale"/>), che riempie il riquadro, senza scritte.</summary>
    Immagine = 2,
    /// <summary>L'ultima immagine del telefono sfocata e scurita, con il motivo scritto sopra.</summary>
    Sfocata = 3,
}

/// <summary>La lingua dei testi della schermata di attesa: italiano se Windows è in italiano, altrimenti inglese.</summary>
public enum LinguaAttesa : uint
{
    /// <summary>La decide la webcam dalla lingua di Windows (dentro Frame Server: quella del sistema).</summary>
    Automatica = 0,
    Italiano = 1,
    Inglese = 2,
}

/// <summary>
/// I testi della schermata di attesa, uguali a quelli del Mac (Localizable.xcstrings) e a Strumenti/genera_testi_attesa.py.
/// «WebcamLR è chiusa» sul Mac la disegna la webcam virtuale (Mac/FotocameraVirtuale), con «sul Mac» al posto di «sul computer».
/// </summary>
public static class TestiAttesa
{
    public static string? Titolo(StatoAttesa stato, LinguaAttesa lingua) => (stato, Concreta(lingua)) switch
    {
        (StatoAttesa.NonCollegata, LinguaAttesa.Italiano) => "La webcam non è collegata",
        (StatoAttesa.NonCollegata, _) => "The webcam is not connected",
        (StatoAttesa.Interrotta, LinguaAttesa.Italiano) => "Collegamento interrotto",
        (StatoAttesa.Interrotta, _) => "Connection lost",
        (StatoAttesa.Pausa, LinguaAttesa.Italiano) => "Webcam in pausa",
        (StatoAttesa.Pausa, _) => "Webcam paused",
        (StatoAttesa.AppChiusa, LinguaAttesa.Italiano) => "WebcamLR è chiusa",
        (StatoAttesa.AppChiusa, _) => "WebcamLR is closed",
        _ => null,
    };

    /// <summary>La riga sotto il titolo; la pausa non ne ha.</summary>
    public static string? Sottotitolo(StatoAttesa stato, LinguaAttesa lingua) => (stato, Concreta(lingua)) switch
    {
        (StatoAttesa.NonCollegata, LinguaAttesa.Italiano) => "Apri WebcamLR sul telefono",
        (StatoAttesa.NonCollegata, _) => "Open WebcamLR on your phone",
        (StatoAttesa.Interrotta, LinguaAttesa.Italiano) => "Riconnessione in corso…",
        (StatoAttesa.Interrotta, _) => "Reconnecting…",
        (StatoAttesa.AppChiusa, LinguaAttesa.Italiano) => "Apri WebcamLR sul computer",
        (StatoAttesa.AppChiusa, _) => "Open WebcamLR on the computer",
        _ => null,
    };

    /// <summary>La chiave della maschera disegnata in Risorse/TestiAttesa.bin: «it.titolo.NonCollegata».</summary>
    public static string Chiave(StatoAttesa stato, LinguaAttesa lingua, bool titolo) =>
        $"{(Concreta(lingua) == LinguaAttesa.Italiano ? "it" : "en")}.{(titolo ? "titolo" : "sottotitolo")}.{stato}";

    /// <summary>Automatica vale inglese: chi disegna deve averla già risolta con <see cref="Lingue"/>.</summary>
    private static LinguaAttesa Concreta(LinguaAttesa lingua) => lingua == LinguaAttesa.Italiano ? LinguaAttesa.Italiano : LinguaAttesa.Inglese;
}

public static class Lingue
{
    /// <summary>Italiano per ogni cultura italiana (it-IT, it-CH…), inglese per tutte le altre.</summary>
    public static LinguaAttesa DaCultura(CultureInfo cultura) => DaNome(cultura.Name);

    public static LinguaAttesa DaNome(string? nome) =>
        nome is not null && (nome.Equals("it", StringComparison.OrdinalIgnoreCase) || nome.StartsWith("it-", StringComparison.OrdinalIgnoreCase))
            ? LinguaAttesa.Italiano : LinguaAttesa.Inglese;

    /// <summary>Da un LANGID di Windows (GetUserDefaultUILanguage): la lingua principale sono i 10 bit bassi, 0x10 è l'italiano.</summary>
    public static LinguaAttesa DaLangId(int langId) => (langId & 0x3FF) == 0x10 ? LinguaAttesa.Italiano : LinguaAttesa.Inglese;

    /// <summary>Quella scritta dall'app, se c'è; altrimenti quella del sistema.</summary>
    public static LinguaAttesa Risolvi(LinguaAttesa scritta, LinguaAttesa sistema) =>
        scritta is LinguaAttesa.Italiano or LinguaAttesa.Inglese ? scritta
        : sistema is LinguaAttesa.Italiano ? LinguaAttesa.Italiano : LinguaAttesa.Inglese;
}

/// <summary>Un colore sRGB a 8 bit.</summary>
public readonly record struct ColoreStile(byte Rosso, byte Verde, byte Blu)
{
    public string Esadecimale => $"#{Rosso:X2}{Verde:X2}{Blu:X2}";

    public static ColoreStile Da(uint esadecimale) => new((byte)(esadecimale >> 16), (byte)(esadecimale >> 8), (byte)esadecimale);
}

/// <summary>
/// I colori di Stile (Stile/Sources/Stile/Tema.swift e LogoWebcamLR in Componenti.swift) che servono alla schermata di
/// attesa: la webcam non vede né Stile né App.xaml. Un test controlla che restino uguali a quelli di Stile.
/// </summary>
public static class ColoriStile
{
    /// <summary>La sfumatura del logo, dall'angolo in alto a sinistra (Tema.sfumaturaChiara) a quello in basso a destra.</summary>
    public static readonly ColoreStile SfumaturaChiara = ColoreStile.Da(0x30453E);
    public static readonly ColoreStile SfumaturaScura = ColoreStile.Da(0x0D1B18);
    /// <summary>Tema.fondo: le bande ai lati del video.</summary>
    public static readonly ColoreStile Fondo = ColoreStile.Da(0x13211D);
    public static readonly ColoreStile Testo = ColoreStile.Da(0xE6EEEA);
    public static readonly ColoreStile TestoSecondario = ColoreStile.Da(0x9DB0A7);

    /// <summary>I nove quadratini del logo, riga per riga dall'alto (LogoWebcamLR.celle); il centro è il corallo.</summary>
    public static readonly ColoreStile[,] CelleLogo =
    {
        { ColoreStile.Da(0x8FA199), ColoreStile.Da(0xB2BFB7), ColoreStile.Da(0x627A71) },
        { ColoreStile.Da(0xACBAB2), ColoreStile.Da(0xE67A67), ColoreStile.Da(0x768D84) },
        { ColoreStile.Da(0x83988F), ColoreStile.Da(0x96A89F), ColoreStile.Da(0x50685F) },
    };
}
