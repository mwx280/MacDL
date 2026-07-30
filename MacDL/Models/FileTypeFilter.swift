import Foundation

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
        case .video: return ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v"].contains(ext)
        case .document: return ["pdf", "txt", "md", "json", "xml", "yaml", "yml", "csv"].contains(ext)
        case .archive: return ["zip", "tar", "gz", "bz2", "7z", "rar", "xip"].contains(ext)
        case .image: return ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext)
        case .audio: return ["mp3", "flac", "wav", "aac"].contains(ext)
        case .code: return ["gguf", "bin", "pt", "safetensors", "swift", "py", "js", "ts", "rs", "go", "c", "cpp", "h"].contains(ext)
        case .other: return !["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v", "pdf", "txt", "md", "json", "xml", "yaml", "yml", "csv", "zip", "tar", "gz", "bz2", "7z", "rar", "xip", "jpg", "jpeg", "png", "gif", "webp", "heic", "mp3", "flac", "wav", "aac", "gguf", "bin", "pt", "safetensors", "swift", "py", "js", "ts", "rs", "go", "c", "cpp", "h"].contains(ext)
        case .all: return true
        }
    }
}
