import Foundation

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .binary
    return f
}()

let speedOptions = [0, 102400, 512000, 1_048_576, 2_097_152, 5_242_880, 10_485_760, 52_428_800, 104_857_600]

func formatSpeed(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes) + "/s"
}

func formatSize(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes)
}

func speedLabel(_ bytesPerSecond: Int) -> String {
    if bytesPerSecond == 0 { return LanguageManager.shared.localized("Unlimited") }
    if bytesPerSecond < 1_048_576 { return "\(bytesPerSecond / 1024) KB/s" }
    return "\(bytesPerSecond / 1_048_576) MB/s"
}

func formatRemainingTime(_ seconds: TimeInterval) -> String {
    let s = max(Int(seconds), 0)
    if s < 60 {
        return String(format: LanguageManager.shared.localized("About %d seconds"), s)
    }
    let minutes = s / 60
    if minutes < 60 {
        return String(format: LanguageManager.shared.localized("About %d minutes"), minutes)
    }
    return String(format: LanguageManager.shared.localized("About %d hours"), minutes / 60)
}
