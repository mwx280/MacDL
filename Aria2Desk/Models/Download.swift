import Foundation

enum DownloadStatus: String {
    case active
    case paused
    case waiting
    case completed
    case stopped
    case error

    var icon: String {
        switch self {
        case .active: "arrow.down.circle"
        case .paused: "pause.circle"
        case .waiting: "clock"
        case .completed: "checkmark.circle"
        case .stopped: "stop.circle"
        case .error: "exclamationmark.circle"
        }
    }
}

struct Download: Identifiable {
    let id: UUID
    let filename: String
    let url: String
    let totalSize: Int64
    var downloadedSize: Int64
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    var status: DownloadStatus
    var addedAt: Date

    var progress: Double {
        totalSize > 0 ? min(Double(downloadedSize) / Double(totalSize), 1.0) : 0
    }
}

extension Download {
    static var mock: [Download] {
        [
            Download(
                id: UUID(),
                filename: "Ubuntu-26.04-LTS-Desktop-arm64.iso",
                url: "https://releases.ubuntu.com/26.04/ubuntu-26.04-desktop-arm64.iso",
                totalSize: 5_889_376_256,
                downloadedSize: 2_345_678_848,
                downloadSpeed: 12_582_912,
                uploadSpeed: 1_048_576,
                status: .active,
                addedAt: Date().addingTimeInterval(-3600)
            ),
            Download(
                id: UUID(),
                filename: "The.Matrix.Resurrections.2021.2160p.mkv",
                url: "magnet:?xt=urn:btih:...",
                totalSize: 15_032_385_536,
                downloadedSize: 15_032_385_536,
                downloadSpeed: 0,
                uploadSpeed: 2_621_440,
                status: .completed,
                addedAt: Date().addingTimeInterval(-86400)
            ),
            Download(
                id: UUID(),
                filename: "Xcode_26.6.xip",
                url: "https://developer.apple.com/download/Xcode_26.6.xip",
                totalSize: 2_147_483_648,
                downloadedSize: 1_073_741_824,
                downloadSpeed: 0,
                uploadSpeed: 0,
                status: .paused,
                addedAt: Date().addingTimeInterval(-7200)
            ),
            Download(
                id: UUID(),
                filename: "openjdk-24.0.2_macos-aarch64_bin.tar.gz",
                url: "https://download.java.net/openjdk/24.0.2/openjdk-24.0.2_macos-aarch64_bin.tar.gz",
                totalSize: 197_568_000,
                downloadedSize: 167_342_756,
                downloadSpeed: 3_145_728,
                uploadSpeed: 524_288,
                status: .active,
                addedAt: Date().addingTimeInterval(-1800)
            ),
            Download(
                id: UUID(),
                filename: "llama-3-70b-instruct.Q4_K_M.gguf",
                url: "https://huggingface.co/meta-llama/llama-3-70b-instruct-gguf/resolve/main/llama-3-70b-instruct.Q4_K_M.gguf",
                totalSize: 41_943_040_000,
                downloadedSize: 10_485_760_000,
                downloadSpeed: 8_388_608,
                uploadSpeed: 2_097_152,
                status: .active,
                addedAt: Date().addingTimeInterval(-21600)
            ),
            Download(
                id: UUID(),
                filename: "Microsoft_Visual_Studio_Code_1.92_arm64.dmg",
                url: "https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64",
                totalSize: 314_572_800,
                downloadedSize: 314_572_800,
                downloadSpeed: 0,
                uploadSpeed: 0,
                status: .completed,
                addedAt: Date().addingTimeInterval(-172800)
            ),
            Download(
                id: UUID(),
                filename: "macOS_26.5_Sequoia_beta.dmg",
                url: "https://swcdn.apple.com/content/...",
                totalSize: 12_884_901_888,
                downloadedSize: 1_048_576,
                downloadSpeed: 0,
                uploadSpeed: 0,
                status: .stopped,
                addedAt: Date().addingTimeInterval(-43200)
            ),
        ]
    }
}
