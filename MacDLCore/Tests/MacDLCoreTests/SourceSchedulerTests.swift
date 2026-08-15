import Testing
import Foundation
@testable import MacDLCore

@Suite struct SourceSchedulerTests {
    @Test func returnsNilWhenNothingAvailable() {
        var s = SourceScheduler(sourceCount: 2)
        #expect(s.pick(throughputs: [100, 50], available: [false, false]) == nil)
        #expect(s.pick(throughputs: [], available: []) == nil)
    }

    @Test func fastSourceServesMoreChunks() {
        var s = SourceScheduler(sourceCount: 2)
        var counts = [0, 0]
        for _ in 0..<20 {
            if let i = s.pick(throughputs: [1000, 1], available: [true, true]) {
                counts[i] += 1
            }
        }
        // The fast source (weight 1000) must serve the overwhelming majority.
        #expect(counts[0] > counts[1])
        #expect(counts[0] >= 15)
    }

    @Test func unavailableSourceIsSkipped() {
        var s = SourceScheduler(sourceCount: 2)
        // Only source 1 is available.
        for _ in 0..<10 {
            #expect(s.pick(throughputs: [1000, 1], available: [false, true]) == 1)
        }
    }

    @Test func equalWeightsAlternateRoughly() {
        var s = SourceScheduler(sourceCount: 2)
        var counts = [0, 0]
        for _ in 0..<20 {
            if let i = s.pick(throughputs: [100, 100], available: [true, true]) {
                counts[i] += 1
            }
        }
        #expect(counts[0] == 10)
        #expect(counts[1] == 10)
    }
}
