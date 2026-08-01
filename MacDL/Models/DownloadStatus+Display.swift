import SwiftUI

extension DownloadStatus {
    var displayIcon: String {
        switch self {
        case .active: "arrow.down.circle.fill"
        case .paused: "pause.circle.fill"
        case .waiting: "clock.fill"
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .active: .blue
        case .paused: .orange
        case .waiting: .secondary
        case .completed: .green
        case .stopped: .gray
        case .error: .red
        }
    }

    var labelKey: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .waiting: "Waiting"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .error: "Error"
        }
    }
}

extension Download {
    static let videoExts: Set<String> = ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v", "webm", "mpg", "mpeg", "3gp", "m2ts", "ogv"]
    static let archiveExts: Set<String> = ["xip", "zip", "tar", "gz", "bz2", "7z", "rar"]
    static let installerExts: Set<String> = ["dmg", "pkg", "apk", "ipa", "deb", "rpm", "app"]
    static let modelExts: Set<String> = ["gguf", "bin", "pt", "safetensors", "onnx", "tflite", "ckpt"]
    static let officeExts: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "epub", "mobi", "pages", "numbers", "keynote"]
    static let textExts: Set<String> = ["txt", "md", "json", "xml", "yaml", "yml", "csv"]
    static let codeExts: Set<String> = ["swift", "py", "pyw", "js", "jsx", "ts", "tsx", "rs", "go", "c", "cpp", "h", "java", "rb", "php", "html", "htm", "css", "scss", "sass", "less", "sql"]
    static let scriptExts: Set<String> = ["sh", "bat", "cmd", "bash", "zsh"]

    static let codeColorMap: [String: Color] = [
        "html": .orange,
        "htm": .orange,
        "css": .blue,
        "scss": .blue,
        "sass": .blue,
        "less": .blue,
        "js": .yellow,
        "jsx": .yellow,
        "ts": .blue,
        "tsx": .blue,
        "py": .green,
        "pyw": .green,
        "swift": .orange,
        "rs": .orange,
        "c": .gray,
        "cpp": .blue,
        "h": .gray,
        "java": .red,
        "rb": .red,
        "php": .indigo,
        "sql": .teal,
    ]
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff", "tif", "ico", "psd"]
    static let audioExts: Set<String> = ["mp3", "flac", "wav", "aac", "m4a", "ogg", "opus", "wma"]
    static let fontExts: Set<String> = ["ttf", "otf", "woff", "woff2"]
    static let diskImageExts: Set<String> = ["iso", "img", "vmdk", "qcow2"]

    var fileTypeIcon: String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "exe" || ext == "msi" { return "pc" }
        if Self.installerExts.contains(ext) { return "app.dashed" }
        if Self.diskImageExts.contains(ext) { return ext == "iso" ? "opticaldisc" : "externaldrive" }
        if Self.videoExts.contains(ext) { return "film" }
        if Self.archiveExts.contains(ext) { return "shippingbox" }
        if Self.modelExts.contains(ext) { return "cpu" }
        if Self.officeExts.contains(ext) { return "doc.richtext" }
        if Self.textExts.contains(ext) { return "doc.text" }
        if Self.codeExts.contains(ext) { return "curlybraces" }
        if Self.scriptExts.contains(ext) { return "terminal" }
        if Self.imageExts.contains(ext) { return "photo" }
        if Self.audioExts.contains(ext) { return "music.note" }
        if Self.fontExts.contains(ext) { return "textformat" }
        if ext == "torrent" { return "arrow.down.doc" }
        return "doc"
    }

    var fileTypeColor: Color {
        let ext = (filename as NSString).pathExtension.lowercased()
        if Self.diskImageExts.contains(ext) { return .indigo }
        if Self.videoExts.contains(ext) { return .purple }
        if Self.archiveExts.contains(ext) || Self.installerExts.contains(ext) || ext == "exe" || ext == "msi" { return .orange }
        if Self.modelExts.contains(ext) { return .mint }
        if Self.officeExts.contains(ext) { return .red }
        if Self.codeExts.contains(ext) { return Self.codeColorMap[ext] ?? .teal }
        if Self.scriptExts.contains(ext) { return .gray }
        if Self.imageExts.contains(ext) { return .blue }
        if Self.audioExts.contains(ext) { return .pink }
        return .secondary
    }
}
