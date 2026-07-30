import Foundation

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .binary
    return f
}()

func formatSpeed(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes) + "/s"
}

func formatSize(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes)
}
