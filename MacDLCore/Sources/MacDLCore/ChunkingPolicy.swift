import Foundation

/// Pure, deterministic chunk-size selection for the "smart" engine. Mirrors the
/// `AutoConnectionPolicy` philosophy: one sampled signal stream (file size, RTT,
/// single-connection rate) drives how the file is split, so large files are not
/// chopped into hundreds of thousands of tiny chunks and small files keep enough
/// chunks to parallelize.
///
/// Confined to the caller's serial queue; no timers or I/O, so it is fully
/// unit-testable.
public enum ChunkingPolicy {
    /// Picks a chunk size from the file size, probe latency and measured
    /// single-connection throughput:
    /// - Larger files use larger chunks to cap the chunk count (scheduling
    ///   overhead) at a sane level.
    /// - Higher RTT favors larger chunks to amortize round-trips.
    /// - Very low throughput favors smaller chunks for finer resume/retry
    ///   granularity and faster feedback.
    public static func chunkSize(totalSize: Int64, rtt: TimeInterval, singleConnRate: Int64) -> Int64 {
        var size: Int64
        if totalSize < 1_048_576 { size = 128 * 1024 }              // < 1 MiB
        else if totalSize < 64 * 1_048_576 { size = 256 * 1024 }     // < 64 MiB
        else if totalSize < 512 * 1_048_576 { size = 1_048_576 }     // < 512 MiB
        else { size = 4 * 1_048_576 }                                // ≥ 512 MiB

        // High RTT: bigger chunks amortize per-request round-trips.
        if rtt >= 0.15 { size = max(size, 1_048_576) }
        else if rtt >= 0.05 { size = max(size, 512 * 1024) }

        // Very slow single connection: smaller chunks give finer resume/retry
        // granularity and faster progress feedback.
        if singleConnRate > 0, singleConnRate < 256 * 1024 {
            size = min(size, 256 * 1024)
        }
        return max(64 * 1024, size)
    }
}
