import Foundation

// Probes whether a server supports Range-based resume for a single URL.
// Isolated from the view layer so the 206/2xx/429/5xx mapping is unit-testable
// and reusable (new-download sheet, download list, etc.).
enum ResumeProbeService {
    /// - 206 -> true (resumable)
    /// - other 2xx -> false (definitively not resumable)
    /// - 429 / 5xx / timeout -> nil (transient, unknown)
    /// - other 4xx -> false
    static func detectResumeSupport(url: URL, completion: @escaping (Bool?) -> Void) {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { _, response, error in
            let result: Bool?
            if error == nil, let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 206: result = true
                case 200..<300: result = false
                case 429: result = nil // rate-limited: transient, not 'not resumable'
                case 500..<600: result = nil // server error: transient
                default: result = false // other 4xx: truly not resumable
                }
            } else {
                result = nil
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
