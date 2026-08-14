import Foundation

// In-memory virtual file: deterministically generates pattern bytes by offset; supports 206/200/416 and server-size-change simulation.
final class FakeURLProtocol: URLProtocol {
    nonisolated(unsafe) static var virtualFileSize: Int64 = 1024 * 1024
    nonisolated(unsafe) static var serverTotalOverride: Int64? = nil
    // If set, Range requests whose start offset >= this value get this status
    // code (simulates the server rate-limiting or ignoring Range after the probe).
    nonisolated(unsafe) static var statusOverrideAfterStart: Int?
    // Fail the first N whole-file (no Range) requests with a transport error,
    // to exercise single-stream retry.
    nonisolated(unsafe) static var failWholeFileTimes = 0
    // Fail the next N requests of any kind with a transport error and no HTTP
    // response (simulates an unreachable server), for probe-failure tests.
    nonisolated(unsafe) static var failAllTimes = 0
    // When > 0, each request delivers its body in slices at this byte/second
    // rate (independently per connection), so N connections yield ~N× throughput.
    nonisolated(unsafe) static var perConnectionRate: Int64 = 0
    // Peak number of concurrently in-flight requests observed.
    nonisolated(unsafe) static var peakRequests = 0
    private static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private nonisolated(unsafe) static var activeRequests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.activeRequests += 1
        Self.peakRequests = max(Self.peakRequests, Self.activeRequests)
        Self.lock.unlock()

        guard let url = request.url else { return }
        let total = Self.serverTotalOverride ?? Self.virtualFileSize
        let rangeHeader = request.value(forHTTPHeaderField: "Range")

        // Simulate a transient connection failure for whole-file (single-stream) requests.
        if rangeHeader == nil, Self.failWholeFileTimes > 0 {
            Self.failWholeFileTimes -= 1
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }

        // Simulate an unreachable server: every request fails with a transport
        // error and no HTTP response ever arrives.
        if Self.failAllTimes > 0 {
            Self.failAllTimes -= 1
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }

        var status = 200
        var headers: [String: String] = ["Content-Length": "\(total)"]
        var start: Int64 = 0
        var end: Int64 = total - 1
        var data = Data(count: Int(total))

        if let rangeHeader, rangeHeader.hasPrefix("bytes=") {
            let parts = rangeHeader.dropFirst(6).split(separator: "-").map { String($0) }
            if parts.count == 2, let a = Int64(parts[0]), let b = Int64(parts[1]), a >= 0, a <= b, a < total {
                start = a
                end = min(b, total - 1)
                // Optional override: simulate 429 / 200-for-Range on later chunks.
                if let override = Self.statusOverrideAfterStart, start >= override {
                    status = override
                    headers["Content-Range"] = "bytes \(start)-\(end)/\(total)"
                    headers["Content-Length"] = "\(end - start + 1)"
                    data = Data(count: Int(end - start + 1))
                } else {
                    status = 206
                    headers["Content-Range"] = "bytes \(start)-\(end)/\(total)"
                    headers["Accept-Ranges"] = "bytes"
                    headers["Content-Length"] = "\(end - start + 1)"
                    data = Data(count: Int(end - start + 1))
                }
            } else {
                status = 416
                headers["Content-Range"] = "bytes */\(total)"
                headers["Content-Length"] = "0"
                data = Data()
            }
        }

        if let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) {
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        }
        guard !data.isEmpty else {
            Self.finish(self)
            return
        }
        for i in data.indices {
            data[i] = UInt8((start + Int64(i)) % 251)
        }
        if Self.perConnectionRate > 0 {
            // Deliver the body in slices on a background thread, throttled to
            // perConnectionRate. Each connection is throttled independently.
            let slices = data
            let rate = Self.perConnectionRate
            DispatchQueue.global().async {
                let slice = 64 * 1024
                var offset = 0
                while offset < slices.count {
                    let end = min(offset + slice, slices.count)
                    self.client?.urlProtocol(self, didLoad: slices[offset..<end])
                    let bytes = end - offset
                    offset = end
                    if bytes > 0 {
                        Thread.sleep(forTimeInterval: Double(bytes) / Double(rate))
                    }
                }
                Self.finish(self)
            }
        } else {
            client?.urlProtocol(self, didLoad: data)
            Self.finish(self)
        }
    }

    private static func finish(_ proto: FakeURLProtocol) {
        proto.client?.urlProtocolDidFinishLoading(proto)
        lock.lock()
        activeRequests = max(0, activeRequests - 1)
        lock.unlock()
    }

    override func stopLoading() {}

    static func reset() {
        virtualFileSize = 1024 * 1024
        serverTotalOverride = nil
        statusOverrideAfterStart = nil
        failWholeFileTimes = 0
        failAllTimes = 0
        perConnectionRate = 0
        peakRequests = 0
        lock.lock()
        requests.removeAll()
        activeRequests = 0
        lock.unlock()
    }
}
