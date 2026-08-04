import Foundation

// Named engine tuning constants (replaces scattered magic numbers).
public enum EngineConstants {
    // Chunk scheduling / retry
    public static let maxChunkRetries = 3
    public static let retryBackoffBase: TimeInterval = 1.0
    public static let retryBackoffCap: TimeInterval = 10.0

    // Token bucket
    public static let bucketPollInterval: TimeInterval = 0.02
    public static let bucketTokenCapMultiplier = 2.0
    public static let bucketTokenMinCap: Double = 1_048_576 // 1 MiB

    // Chunk writer
    public static let chunkBufferCap = 8 * 1024 * 1024
    public static let chunkWriteSize = 64 * 1024
    public static let drainPollInterval: TimeInterval = 0.01
    public static let speedSampleInterval: TimeInterval = 0.3

    // Networking
    public static let requestTimeout: TimeInterval = 30
    public static let resourceTimeout: TimeInterval = 86_400

    // Progress / logging cadence
    public static let speedReportInterval: TimeInterval = 1.0
    public static let statusLogInterval: TimeInterval = 3.0
    public static let progressSaveInterval: TimeInterval = 5.0
}
