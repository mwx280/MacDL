import Foundation

func formatSpeed(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .binary
    return f.string(fromByteCount: bytes) + "/s"
}

func formatSize(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .binary
    return f.string(fromByteCount: bytes)
}
