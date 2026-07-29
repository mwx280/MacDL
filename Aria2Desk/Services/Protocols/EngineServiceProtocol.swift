protocol EngineServiceProtocol {
    var engineState: EngineState { get }
    var rpcPort: Int { get }
    func start()
    func stop()
    func restart()
}
