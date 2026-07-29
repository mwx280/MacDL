import Darwin

final class PortAllocator: PortAllocatorProtocol {
    static let shared = PortAllocator()
    private init() {}

    func findAvailablePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 6800 }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0
            }
        }) else { return 6800 }

        var addrOut = sockaddr_in()
        var addrLen = len
        guard withUnsafeMutablePointer(to: &addrOut, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &addrLen) == 0
            }
        }) else { return 6800 }

        return Int(addrOut.sin_port.bigEndian)
    }
}
