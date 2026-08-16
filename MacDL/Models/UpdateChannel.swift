import Foundation

/// Which GitHub release channel the updater follows.
enum UpdateChannel: String, CaseIterable {
    case stable
    case preview

    /// Localization key for the channel's display name.
    nonisolated var displayKey: String {
        switch self {
        case .stable: "Stable"
        case .preview: "Preview"
        }
    }

    /// The channel the running build belongs to, read from the Info.plist key
    /// `MacDLReleaseChannel` (set at build time). Defaults to preview.
    static var buildChannel: UpdateChannel {
        let raw = Bundle.main.infoDictionary?["MacDLReleaseChannel"] as? String
        return UpdateChannel(rawValue: raw ?? "") ?? .preview
    }
}
