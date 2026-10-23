#if canImport(Darwin)
import Darwin

/// L'orologio del protocollo: tempo di sistema dall'avvio, in microsecondi.
/// È la stessa base dei timestamp della fotocamera (host time di CoreMedia, `mach_absolute_time`).
public enum Orologio {
    public static func adesso() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000
    }

    /// Converte secondi dell'host time (per esempio un `CMTime` della fotocamera) in microsecondi.
    public static func microsecondi(daSecondi secondi: Double) -> UInt64 {
        secondi > 0 ? UInt64(secondi * 1_000_000) : 0
    }
}
#endif
