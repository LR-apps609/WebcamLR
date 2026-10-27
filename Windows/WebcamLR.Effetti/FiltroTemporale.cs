namespace WebcamLR.Effetti;

/// <summary>
/// Filtro nel tempo della maschera, senza ritardo (lo stesso di Android, AnalisiImmagine.kt): dove la maschera cambia
/// poco (il tremolio del bordo tra un fotogramma e l'altro) resta un filo di quella di prima, dove cambia molto (la
/// persona si muove) vale subito la nuova. Così niente scie e niente fotogrammi di attesa.
/// </summary>
public sealed class FiltroTemporale
{
    /// <summary>Peso della maschera nuova quando non cambia nulla.</summary>
    public const float PesoMinimo = 0.7f;

    /// <summary>Di quanto sale il peso della nuova per ogni unità di differenza (a 0,1 di differenza vale già 1).</summary>
    public const float Pendenza = 3f;

    private float[]? precedente;

    /// <summary>Filtra <paramref name="maschera"/> sul posto (valori in [0, 1]) e la ricorda per la prossima.</summary>
    public void Applica(Span<float> maschera)
    {
        if (precedente is null || precedente.Length != maschera.Length)
        {
            precedente = maschera.ToArray();
            return;
        }
        for (var i = 0; i < maschera.Length; i++)
        {
            var nuova = maschera[i];
            var peso = MathF.Min(1f, PesoMinimo + Pendenza * MathF.Abs(nuova - precedente[i]));
            var v = nuova * peso + precedente[i] * (1f - peso);
            maschera[i] = v;
            precedente[i] = v;
        }
    }

    /// <summary>Dimentica la maschera di prima (cambio di telefono, di modello, scena nuova).</summary>
    public void Dimentica() => precedente = null;
}
