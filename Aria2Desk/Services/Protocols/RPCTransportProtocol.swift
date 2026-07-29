protocol RPCTransportProtocol {
    var status: RPCConnectionStatus { get }
    func testConnection() async -> Bool
}
