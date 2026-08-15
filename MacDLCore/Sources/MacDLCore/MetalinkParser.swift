import Foundation

/// A parsed Metalink document: a list of mirror URLs plus optional checksum and
/// size, so a download can start from several sources at once (fed into the
/// multi-source engine) and be verified on completion.
public struct MetalinkFile: Equatable, Sendable {
    /// Mirror URLs listed in the document, in order (first is used as primary).
    public let urls: [URL]
    /// SHA-256 digest in lowercase hex, when the document carries one.
    public let checksum: String?
    /// Declared file size in bytes, when present.
    public let size: Int64?
    /// Declared file name, when present.
    public let filename: String?

    public init(urls: [URL], checksum: String?, size: Int64?, filename: String?) {
        self.urls = urls
        self.checksum = checksum
        self.size = size
        self.filename = filename
    }
}

/// Parses Metalink (RFC 5854 / v4) documents into ``MetalinkFile``. Handles both
/// the modern `<metalink>` layout and the legacy `<files>/<resources>` layout,
/// since both place `<url>` elements under a `<file>` node.
public enum MetalinkParser {
    public static func parse(_ data: Data) -> MetalinkFile? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let urls = delegate.urls.compactMap { URL(string: $0) }
        guard !urls.isEmpty else { return nil }
        return MetalinkFile(urls: urls, checksum: delegate.sha256, size: delegate.size,
                            filename: delegate.filename)
    }

    /// True when a URL looks like a Metalink document (by file extension).
    public static func isMetalinkURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "metalink" || ext == "meta4"
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var urls: [String] = []
        var sha256: String?
        var size: Int64?
        var filename: String?

        private var currentText = ""
        private var currentHashType: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            currentText = ""
            if elementName == "file" {
                filename = attributeDict["name"] ?? filename
            }
            if elementName == "hash" {
                currentHashType = attributeDict["type"]?.lowercased()
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "url":
                let u = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !u.isEmpty { urls.append(u) }
            case "hash":
                let h = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if currentHashType == "sha-256" || currentHashType == "sha256" {
                    sha256 = h
                }
                currentHashType = nil
            case "size":
                size = Int64(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                break
            }
        }
    }
}
