import Foundation
import CryptoKit

/// Streaming SHA-256 over a file, used to verify a completed download against
/// an expected checksum before it is renamed to its final name.
public enum ChecksumVerifier {
    /// Returns the lowercase hex SHA-256 digest of the file's contents.
    public static func sha256Hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Normalizes an expected checksum: lowercases it and strips an optional
    /// leading algorithm tag such as `sha256:` or `SHA256:`.
    public static func normalize(_ checksum: String) -> String {
        let lower = checksum.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let colon = lower.firstIndex(of: ":") {
            let prefix = lower[..<colon]
            if prefix == "sha256" || prefix == "sha-256" {
                return String(lower[lower.index(after: colon)...])
            }
        }
        return lower
    }
}
