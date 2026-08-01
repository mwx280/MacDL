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
    var fileTypeIcon: String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "iso" { return "opticaldisc" }
        if ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v"].contains(ext) { return "film" }
        if ["xip", "zip", "tar", "gz", "bz2", "7z", "rar"].contains(ext) { return "shippingbox" }
        if ["dmg", "pkg"].contains(ext) { return "app.dashed" }
        if ext == "exe" { return "pc" }
        if ["gguf", "bin", "pt", "safetensors"].contains(ext) { return "cpu" }
        if ext == "pdf" { return "doc.richtext" }
        if ["txt", "md", "json", "xml", "yaml", "yml", "csv"].contains(ext) { return "doc.text" }
        if ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext) { return "photo" }
        if ["mp3", "flac", "wav", "aac"].contains(ext) { return "music.note" }
        return "doc"
    }

    var fileTypeColor: Color {
        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "iso" { return .indigo }
        if ["mkv", "mp4", "avi", "mov"].contains(ext) { return .purple }
        if ["xip", "zip", "tar", "gz", "dmg", "exe"].contains(ext) { return .orange }
        if ["gguf", "bin", "pt"].contains(ext) { return .mint }
        if ext == "pdf" { return .red }
        if ["jpg", "jpeg", "png", "gif"].contains(ext) { return .blue }
        if ["mp3", "flac", "wav"].contains(ext) { return .pink }
        return .secondary
    }
}
