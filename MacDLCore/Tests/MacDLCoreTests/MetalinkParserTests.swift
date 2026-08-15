import Testing
import Foundation
@testable import MacDLCore

@Suite struct MetalinkParserTests {
    @Test func parsesRFC5854Metalink() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <metalink xmlns="urn:ietf:params:xml:ns:metalink">
          <file name="example.dmg">
            <size>1048576</size>
            <hash type="sha-256">ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad</hash>
            <url>https://mirror1.example.com/example.dmg</url>
            <url>https://mirror2.example.com/example.dmg</url>
          </file>
        </metalink>
        """
        let parsed = MetalinkParser.parse(Data(xml.utf8))
        #expect(parsed != nil)
        #expect(parsed?.urls.map(\.absoluteString) == [
            "https://mirror1.example.com/example.dmg",
            "https://mirror2.example.com/example.dmg",
        ])
        #expect(parsed?.checksum == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(parsed?.size == 1048576)
        #expect(parsed?.filename == "example.dmg")
    }

    @Test func parsesLegacyV4Metalink() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <metalink version="3.0" xmlns="http://www.metalinker.org/">
          <files>
            <file name="example.zip">
              <resources>
                <url>https://cdn1.example.com/example.zip</url>
                <url>https://cdn2.example.com/example.zip</url>
              </resources>
              <hash type="sha-256">e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855</hash>
            </file>
          </files>
        </metalink>
        """
        let parsed = MetalinkParser.parse(Data(xml.utf8))
        #expect(parsed != nil)
        #expect(parsed?.urls.count == 2)
        #expect(parsed?.checksum == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(parsed?.filename == "example.zip")
    }

    @Test func ignoresNonSha256Hashes() {
        let xml = """
        <metalink xmlns="urn:ietf:params:xml:ns:metalink">
          <file name="f.bin">
            <hash type="md5">abc</hash>
            <url>https://m.example.com/f.bin</url>
          </file>
        </metalink>
        """
        let parsed = MetalinkParser.parse(Data(xml.utf8))
        #expect(parsed?.urls.count == 1)
        #expect(parsed?.checksum == nil)
    }

    @Test func rejectsDocumentsWithoutUrls() {
        let xml = "<metalink xmlns=\"urn:ietf:params:xml:ns:metalink\"><file name=\"f\"/></metalink>"
        #expect(MetalinkParser.parse(Data(xml.utf8)) == nil)
    }

    @Test func rejectsMalformedXML() {
        #expect(MetalinkParser.parse(Data("<metalink><file></metalink>".utf8)) == nil)
    }

    @Test func detectsMetalinkURLs() {
        #expect(MetalinkParser.isMetalinkURL(URL(string: "https://x.example/f.metalink")!))
        #expect(MetalinkParser.isMetalinkURL(URL(string: "https://x.example/f.meta4")!))
        #expect(!MetalinkParser.isMetalinkURL(URL(string: "https://x.example/f.dmg")!))
    }
}
