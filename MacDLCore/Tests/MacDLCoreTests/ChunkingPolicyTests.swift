import Testing
import Foundation
@testable import MacDLCore

@Suite struct ChunkingPolicyTests {
    @Test func smallFilesUseSmallChunks() {
        #expect(ChunkingPolicy.chunkSize(totalSize: 500_000, rtt: 0, singleConnRate: 0) == 128 * 1024)
    }

    @Test func mediumFilesKeepDefault() {
        #expect(ChunkingPolicy.chunkSize(totalSize: 10 * 1_048_576, rtt: 0, singleConnRate: 0) == 256 * 1024)
    }

    @Test func largeFilesUseLargeChunks() {
        #expect(ChunkingPolicy.chunkSize(totalSize: 200 * 1_048_576, rtt: 0, singleConnRate: 0) == 1_048_576)
    }

    @Test func hugeFilesUseLargestChunks() {
        #expect(ChunkingPolicy.chunkSize(totalSize: 5 * 1_073_741_824, rtt: 0, singleConnRate: 0) == 4 * 1_048_576)
    }

    @Test func highRTTBumpsChunkSize() {
        // Medium file + high RTT → chunk size raised to 1 MiB.
        #expect(ChunkingPolicy.chunkSize(totalSize: 10 * 1_048_576, rtt: 0.2, singleConnRate: 0) == 1_048_576)
    }

    @Test func lowThroughputCapsChunkSize() {
        // Large file but a very slow link → capped down to 256 KiB.
        #expect(ChunkingPolicy.chunkSize(totalSize: 200 * 1_048_576, rtt: 0, singleConnRate: 100 * 1024) == 256 * 1024)
    }

    @Test func neverBelowMinimum() {
        #expect(ChunkingPolicy.chunkSize(totalSize: 100, rtt: 0, singleConnRate: 1) >= 64 * 1024)
    }

    @Test func zeroRateFallsBackToSizeAndRTTOnly() {
        // Zero/unknown rate must not crash and must ignore the throughput cap.
        #expect(ChunkingPolicy.chunkSize(totalSize: 200 * 1_048_576, rtt: 0, singleConnRate: 0) == 1_048_576)
    }
}
