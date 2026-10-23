using System.Diagnostics;

namespace WebcamLR.Protocollo;

/// <summary>Orologio monotono del computer, in microsecondi (vedi «Latenza» in Documenti/Protocollo.md).</summary>
public static class Orologio
{
    public static ulong Adesso() => (ulong)(Stopwatch.GetTimestamp() * (1_000_000.0 / Stopwatch.Frequency));
}
