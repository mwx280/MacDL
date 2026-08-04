import Foundation
import MacDLCore

enum FileTypeFilter: String, CaseIterable {
    case all
    case video
    case document
    case archive
    case image
    case audio
    case code
    case other

    var labelKey: String {
        switch self {
        case .all: "All"
        case .video: "Video"
        case .document: "Document"
        case .archive: "Archive"
        case .image: "Image"
        case .audio: "Audio"
        case .code: "Code"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .video: "film"
        case .document: "doc.text"
        case .archive: "shippingbox"
        case .image: "photo"
        case .audio: "music.note"
        case .code: "curlybraces"
        case .other: "doc"
        }
    }

    func matches(_ file: Download) -> Bool {
        guard self != .all else { return true }
        let ext = (file.filename as NSString).pathExtension.lowercased()
        switch self {
        case .video: return Download.videoExts.contains(ext)
        case .document: return Download.officeExts.contains(ext) || Download.textExts.contains(ext) || Download.fontExts.contains(ext)
        case .archive: return Download.archiveExts.contains(ext) || Download.installerExts.contains(ext) || Download.diskImageExts.contains(ext) || Download.executableExts.contains(ext)
        case .image: return Download.imageExts.contains(ext)
        case .audio: return Download.audioExts.contains(ext)
        case .code: return Download.codeExts.contains(ext) || Download.scriptExts.contains(ext) || Download.modelExts.contains(ext)
        case .other: return !Self.allKnown.contains(ext)
        case .all: return true
        }
    }

    /// Every extension the app recognizes (icon/color aware). `.other` is
    /// reserved for genuinely unknown extensions, so a known type like `.ttf`
    /// or `.iso` is never mislabeled as "Other".
    private static var allKnown: Set<String> {
        Download.videoExts
            .union(Download.officeExts)
            .union(Download.textExts)
            .union(Download.fontExts)
            .union(Download.archiveExts)
            .union(Download.installerExts)
            .union(Download.diskImageExts)
            .union(Download.imageExts)
            .union(Download.audioExts)
            .union(Download.codeExts)
            .union(Download.scriptExts)
            .union(Download.modelExts)
            .union(Download.executableExts)
            .union(Download.torrentExts)
    }
}
