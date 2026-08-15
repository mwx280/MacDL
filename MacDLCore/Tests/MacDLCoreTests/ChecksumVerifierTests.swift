import Testing
import Foundation
@testable import MacDLCore

@Suite struct ChecksumVerifierTests {
    @Test func sha256MatchesKnownValue() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdl-checksum-test.bin")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try ChecksumVerifier.sha256Hex(ofFile: url)
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func sha256OfEmptyFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdl-checksum-empty.bin")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try ChecksumVerifier.sha256Hex(ofFile: url)
        #expect(digest == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func normalizeStripsSha256Prefix() {
        #expect(ChecksumVerifier.normalize("sha256:ABC") == "abc")
        #expect(ChecksumVerifier.normalize("SHA256:ABC") == "abc")
        #expect(ChecksumVerifier.normalize("sha-256:ABC") == "abc")
    }

    @Test func normalizeLowercasesAndTrims() {
        #expect(ChecksumVerifier.normalize("  ABCDEF  ") == "abcdef")
    }

    @Test func normalizeKeepsUnknownPrefix() {
        // An unrecognized tag is kept as part of the string (treated as a raw value).
        #expect(ChecksumVerifier.normalize("md5:ABC") == "md5:abc")
    }
}
