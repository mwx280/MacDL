import Foundation

/// Smooth weighted round-robin scheduler that assigns chunks to sources in
/// proportion to their measured throughput, so a fast source serves more chunks
/// while slower ones still get work (and cooldown-sidelined sources get none).
///
/// Pure and stateful; confined to the caller's serial queue. `pick` is O(n) in
/// the number of sources.
public struct SourceScheduler: Sendable {
    private var currentWeights: [Int64]

    public init(sourceCount: Int) {
        currentWeights = Array(repeating: 0, count: max(0, sourceCount))
    }

    /// Picks the next source index by smooth weighted round-robin. `throughputs`
    /// are the sources' EWMA throughput weights; `available` marks sources that
    /// are not currently in cooldown. Returns `nil` when nothing is available.
    public mutating func pick(throughputs: [Int64], available: [Bool]) -> Int? {
        let count = throughputs.count
        guard count > 0, available.contains(true) else { return nil }
        if currentWeights.count != count {
            currentWeights = Array(repeating: 0, count: count)
        }
        var total: Int64 = 0
        var maxWeight = Int64.min
        var selected = -1
        for i in 0..<count {
            guard available[i] else {
                currentWeights[i] = 0
                continue
            }
            let w = max(throughputs[i], 1)
            currentWeights[i] += w
            total += w
            if currentWeights[i] > maxWeight {
                maxWeight = currentWeights[i]
                selected = i
            }
        }
        guard selected >= 0 else { return nil }
        currentWeights[selected] -= total
        return selected
    }
}
