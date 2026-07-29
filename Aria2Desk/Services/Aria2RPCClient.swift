import Foundation
import Observation

@Observable
final class Aria2RPCClient {
    static let shared = Aria2RPCClient(
        engine: Aria2Engine.shared,
        transport: RPCTransport.shared
    )

    let engine: EngineServiceProtocol
    let transport: RPCTransport

    var engineState: EngineState { engine.engineState }
    var status: RPCConnectionStatus { transport.status }
    var rpcPort: Int { engine.rpcPort }
    var config: RPCConfig { transport.config }

    init(engine: EngineServiceProtocol, transport: RPCTransport) {
        self.engine = engine
        self.transport = transport
    }

    func startEngine() {
        engine.start()
        if case .running = engine.engineState {
            transport.rpcPort = engine.rpcPort
            transport.autoConnect()
        }
    }

    func restartEngine() {
        engine.restart()
        if case .running = engine.engineState {
            transport.rpcPort = engine.rpcPort
            transport.autoConnect()
        }
    }

    func stopEngine() {
        engine.stop()
        transport.disconnect()
    }

    func testConnection() async -> Bool {
        await transport.testConnection()
    }

    func disconnect() {
        transport.disconnect()
    }
}
