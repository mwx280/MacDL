import Foundation

public protocol DownloadEngineProtocol {
    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk])
    func resume(id: UUID) -> Bool
    func pause(id: UUID)
    func cancel(id: UUID)
    func cleanup(id: UUID)
    func setSpeedLimit(id: UUID, limit: Int64)
    func setMaxConcurrent(id: UUID, max: Int)
    var hasActiveTasks: Bool { get }
    func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void)
    func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void)
    func setChunksChangeHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void)
    func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void)
    func setPhaseHandler(for id: UUID, handler: @escaping (Bool) -> Void)
}
