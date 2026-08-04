import Foundation

// In-memory virtual file: deterministically generates pattern bytes by offset; supports 206/200/416 and server-size-change simulation.
final class FakeURLProtocol: URLProtocol {
    nonisolated(unsafe) static var virtualFileSize: Int64 = 1024 * 1024
    nonisolated(unsafe) static var serverTotalOverride: Int64? = nil
    // If set, Range requests whose start offset >= this value get this status
    // code (simulates the server rate-limiting or ignoring Range after the probe).
    nonisolated(unsafe) static var statusOverrideAfterStart: Int?
    private static let lock = NSLock()
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()

        guard let url = request.url else { return }
        let total = Self.serverTotalOverride ?? Self.virtualFileSize
        let rangeHeader = request.value(forHTTPHeaderField: "Range")

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
        if !data.isEmpty {
            for i in data.indices {
                data[i] = UInt8((start + Int64(i)) % 251)
            }
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        virtualFileSize = 1024 * 1024
        serverTotalOverride = nil
        statusOverrideAfterStart = nil
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }
}
