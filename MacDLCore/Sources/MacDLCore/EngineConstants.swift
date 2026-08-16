import Foundation

// Named engine tuning constants (replaces scattered magic numbers).
/// Central place for the engine's tuning knobs: chunk scheduling, retry
/// backoff, buffer sizes, timeouts and reporting cadence.
public enum EngineConstants {
    // Chunk scheduling / retry
    public static let maxChunkRetries = 3
    public static let retryBackoffBase: TimeInterval = 1.0
    public static let retryBackoffCap: TimeInterval = 10.0

    // Auto connection adaptation
    public static let maxAutoConnections = 16
    public static let autoEvaluationInterval: TimeInterval = 3.0

    // Source failover / cooldown
    public static let sourceFailureThreshold = 3
    public static let sourceCooldownInterval: TimeInterval = 30.0
    public static let sourceCooldownCap: TimeInterval = 600.0

    // Rate-limit degradation recovery
    public static let rateLimitRecoveryBase: TimeInterval = 60.0
    public static let rateLimitRecoveryCap: TimeInterval = 600.0

    // Token bucket
    public static let bucketTokenCapMultiplier = 2.0
    public static let bucketTokenMinCap: Double = 1_048_576 // 1 MiB

    // Chunk writer
    public static let chunkBufferCap = 8 * 1024 * 1024
    public static let chunkWriteSize = 64 * 1024
    public static let drainPollInterval: TimeInterval = 0.01
    public static let speedSampleInterval: TimeInterval = 0.3

    // Networking
    public static let requestTimeout: TimeInterval = 15
    public static let resourceTimeout: TimeInterval = 86_400
    public static let maxSingleStreamRetries = 1
    public static let singleStreamRetryDelay: TimeInterval = 2.0

    // Stall detection: a download whose aggregate throughput has been zero for
    // `stallTimeout` is treated as a silent network drop and its active tasks
    // are cancelled so the chunks retry instead of waiting out the URLSession
    // request timeout. Checked at `stallCheckInterval`.
    public static let stallTimeout: TimeInterval = 5
    public static let stallCheckInterval: TimeInterval = 2
    // How long without bytes before a retryable network failure surfaces the
    // "retrying" state. Keeps a single chunk hiccup among flowing chunks from
    // flipping the whole row into the network-interrupted treatment.
    public static let retryingGraceInterval: TimeInterval = 1.0

    // Progress / logging cadence
    public static let speedReportInterval: TimeInterval = 1.0
    public static let statusLogInterval: TimeInterval = 3.0
    public static let progressSaveInterval: TimeInterval = 5.0
    public static let chunksChangedInterval: TimeInterval = 0.5
}
