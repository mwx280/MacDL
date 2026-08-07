import Testing
import Foundation
@testable import MacDL

@MainActor @Suite(.serialized) struct MacDLURLTests {
    private func link(_ raw: String) -> URL {
        URL(string: raw)!
    }

    @Test func extractsEncodedHttpTarget() throws {
        let target = MacDLURL.downloadURL(from: link("macdl://add?url=https%3A%2F%2Fexample.com%2Ffile.zip"))
        #expect(target == "https://example.com/file.zip")
    }

    @Test func extractsEncodedHttpsTarget() throws {
        let target = MacDLURL.downloadURL(from: link("macdl://add?url=https%3A%2F%2Fcdn.example.com%2Fa%20b.bin"))
        #expect(target == "https://cdn.example.com/a b.bin")
    }

    @Test func extractsPlainTargetWithoutEncoding() throws {
        let target = MacDLURL.downloadURL(from: link("macdl://add?url=https://example.com/d.bin"))
        #expect(target == "https://example.com/d.bin")
    }

    @Test func rejectsNonHttpScheme() throws {
        #expect(MacDLURL.downloadURL(from: link("macdl://add?url=ftp%3A%2F%2Fexample.com%2Fa.bin")) == nil)
        #expect(MacDLURL.downloadURL(from: link("macdl://add?url=file%3A%2F%2F%2Ftmp%2Fa.bin")) == nil)
    }

    @Test func rejectsMissingUrlParameter() throws {
        #expect(MacDLURL.downloadURL(from: link("macdl://add")) == nil)
        #expect(MacDLURL.downloadURL(from: link("macdl://add?other=x")) == nil)
    }

    @Test func rejectsOtherScheme() throws {
        #expect(MacDLURL.downloadURL(from: link("https://example.com")) == nil)
        #expect(MacDLURL.downloadURL(from: link("other://add?url=x")) == nil)
    }

    @Test func rejectsTargetWithoutHost() throws {
        #expect(MacDLURL.downloadURL(from: link("macdl://add?url=https%3A%2F%2F%2Fpath")) == nil)
    }
}
