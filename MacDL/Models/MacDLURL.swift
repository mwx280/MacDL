import Foundation

// Parses macdl:// deep links. The canonical forms are
//   macdl://add?url=<percent-encoded http(s) URL>   add a download
//   macdl://clipboard                                download the current clipboard link
// which other apps (widgets, bookmarklets, Shortcuts, terminals) use to hand a
// download to MacDL. Any other host or missing/invalid target yields nil.
enum MacDLURL {
    static func downloadURL(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "macdl" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value
        else { return nil }
        let decoded = raw.removingPercentEncoding ?? raw
        guard let target = URL(string: decoded),
              let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              target.host != nil
        else { return nil }
        return decoded
    }

    /// True when the link asks MacDL to pick up the current clipboard URL.
    static func isClipboardAction(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "macdl" && url.host?.lowercased() == "clipboard"
    }
}
