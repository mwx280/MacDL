import Foundation
import AppKit
import MacDLCore

// All direct interaction with the download engine lives here: starting tasks,
// installing progress/completion/resume-support handlers, pause/resume/cancel,
// speed limits, sandbox access and the Finder progress badge.
//
// Handlers mutate DownloadStore; completion is handed back to DownloadService
// via onTaskCompletion for the business logic (rename, notifications, priority,
// next-waiting promotion) so this type stays purely "engine glue".
// Main-actor isolated: engine callbacks are dispatched to main in installHandlers,
// so the bookkeeping sets need no lock.
@MainActor
final class DownloadEngineCoordinator {
    let progress: ProgressPublisher

    /// Called on the main thread when an engine task finishes (success or failure).
    var onTaskCompletion: ((UUID, Result<Void, Error>) -> Void)?
    /// Called on the main thread when a task enters/leaves the probe phase.
    var onPhaseChange: ((UUID, Bool) -> Void)?
    /// Called on the main thread when the engine promotes a queued download to
    /// running, so the app can flip its status to active.
    var onPromotion: ((UUID) -> Void)?
    /// Called on the main thread when the engine pauses a download for priority.
    var onPriorityPaused: ((UUID) -> Void)?
    /// Called on the main thread when the engine restores a priority-paused
    /// download.
    var onPriorityResumed: ((UUID) -> Void)?
    /// Called on the main thread when the system link state changes
    /// (`true` = network available).
    var onNetworkChange: ((Bool) -> Void)?

    private let engine: DownloadEngineProtocol
    private let store: DownloadStore
    private let notifier: DownloadNotifier
    private let settings: SettingsStore
    private var startedNotified: Set<UUID> = []
    private var engineTrackedDownloads: Set<UUID> = []
    private var needsProgressSave = false
    private var lastProgressSaveTime: Date = .distantPast
    private nonisolated(unsafe) var capObserver: NSObjectProtocol?

    init(engine: DownloadEngineProtocol, store: DownloadStore, notifier: DownloadNotifier, settings: SettingsStore) {
        self.engine = engine
        self.store = store
        self.notifier = notifier
        self.settings = settings
        self.progress = ProgressPublisher()
        engine.setMaxConcurrentDownloads(settings.maxConcurrentDownloads)
        engine.setPromotionHandler { [weak self] id in
            self?.hopToMain { self?.onPromotion?(id) }
        }
        engine.setPriorityPausedHandler { [weak self] id in
            self?.hopToMain { self?.onPriorityPaused?(id) }
        }
        engine.setPriorityResumedHandler { [weak self] id in
            self?.hopToMain { self?.onPriorityResumed?(id) }
        }
        engine.setNetworkChangeHandler { [weak self] satisfied in
            self?.hopToMain { self?.onNetworkChange?(satisfied) }
        }
        capObserver = NotificationCenter.default.addObserver(
            forName: .maxConcurrentDownloadsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncMaxConcurrentDownloads()
        }
    }

    deinit {
        if let capObserver {
            NotificationCenter.default.removeObserver(capObserver)
        }
    }

    /// Pushes the current max-concurrent-downloads setting to the engine's
    /// scheduler (also re-syncs after the setting changes).
    func syncMaxConcurrentDownloads() {
        engine.setMaxConcurrentDownloads(settings.maxConcurrentDownloads)
    }

    /// Starts monitoring the system link so downloads hold while it is down and
    /// resume when it returns.
    func startMonitoringNetwork() {
        engine.startMonitoringNetwork()
    }

    // MARK: - Task lifecycle

    /// Starts a download immediately, bypassing the concurrency cap (resume /
    /// retry semantics).
    func start(id: UUID, url sourceURL: URL, dest: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk]) {
        engineTrackedDownloads.insert(id)
        store.ensureChunks(for: id)
        if let d = store.downloads.first(where: { $0.id == id }) {
            notifyStartedIfNeeded(id, download: d)
        }
        let p = resolvedParameters(for: id, url: sourceURL, dest: dest, speedLimit: speedLimit, chunkSize: chunkSize, maxConcurrent: maxConcurrent, chunks: chunks)
        engine.start(id: id, url: sourceURL, destinationURL: dest, speedLimit: speedLimit,
                     chunkSize: p.chunkSize,
                     maxConcurrent: p.maxConcurrent,
                     chunks: p.chunks,
                     mirrors: p.mirrors)
        installHandlers(for: id)
    }

    /// Schedules a download against the global concurrency cap. Returns `true`
    /// when it started now, `false` when it was queued.
    @discardableResult
    func schedule(id: UUID, url sourceURL: URL, dest: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk]) -> Bool {
        engineTrackedDownloads.insert(id)
        store.ensureChunks(for: id)
        let p = resolvedParameters(for: id, url: sourceURL, dest: dest, speedLimit: speedLimit, chunkSize: chunkSize, maxConcurrent: maxConcurrent, chunks: chunks)
        let started = engine.schedule(id: id, url: sourceURL, destinationURL: dest, speedLimit: speedLimit,
                                      chunkSize: p.chunkSize,
                                      maxConcurrent: p.maxConcurrent,
                                      chunks: p.chunks,
                                      mirrors: p.mirrors)
        installHandlers(for: id)
        if started, let d = store.downloads.first(where: { $0.id == id }) {
            notifyStartedIfNeeded(id, download: d)
        }
        return started
    }

    /// Registers a download into the engine's waiting queue without starting it
    /// (restoring persisted waiting downloads on launch).
    func enqueue(id: UUID, url sourceURL: URL, dest: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk]) {
        engineTrackedDownloads.insert(id)
        store.ensureChunks(for: id)
        let p = resolvedParameters(for: id, url: sourceURL, dest: dest, speedLimit: speedLimit, chunkSize: chunkSize, maxConcurrent: maxConcurrent, chunks: chunks)
        engine.enqueue(id: id, url: sourceURL, destinationURL: dest, speedLimit: speedLimit,
                       chunkSize: p.chunkSize,
                       maxConcurrent: p.maxConcurrent,
                       chunks: p.chunks,
                       mirrors: p.mirrors)
        installHandlers(for: id)
    }

    /// Resolves the effective engine start parameters from the store's model
    /// (mirrors, dynamic chunk size, per-download connection cap).
    private func resolvedParameters(for id: UUID, url: URL, dest: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk]) -> (chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL]) {
        let cfg = store.downloads.first { $0.id == id }
        let mirrors = (cfg?.mirrors ?? []).compactMap { URL(string: $0) }
        return (cfg?.chunkSize ?? chunkSize,
                cfg?.maxConcurrentChunks ?? maxConcurrent,
                cfg?.chunks ?? chunks,
                mirrors)
    }

    func pause(_ id: UUID) {
        engine.pause(id: id)
    }

    // MARK: - Priority

    func setPriorityDownload(id: UUID) {
        engine.setPriorityDownload(id)
    }

    func endPriority(excluding skip: UUID?) {
        engine.endPriority(excluding: skip)
    }

    func registerPriorityPaused(_ ids: Set<UUID>) {
        engine.registerPriorityPaused(ids)
    }

    @discardableResult
    func resume(_ id: UUID) -> Bool {
        engine.resume(id: id)
    }

    func cancel(_ id: UUID) {
        engine.cancel(id: id)
    }

    func cleanup(_ id: UUID) {
        engine.cleanup(id: id)
    }

    func setSpeedLimit(id: UUID, limit: Int) {
        engine.setSpeedLimit(id: id, limit: Int64(limit))
    }

    func setMaxConcurrent(id: UUID, count: Int) {
        engine.setMaxConcurrent(id: id, max: count)
    }

    var hasActiveEngineTasks: Bool {
        engine.hasActiveTasks
    }

    func isTracked(_ id: UUID) -> Bool {
        engineTrackedDownloads.contains(id)
    }

    func untrack(_ id: UUID) {
        engineTrackedDownloads.remove(id)
    }

    // MARK: - Sandbox + notifications

    func beginAccess(for download: Download) -> Bool {
        SandboxAccess.shared.beginAccess(for: download)
    }

    func endAccess(for id: UUID) {
        SandboxAccess.shared.endAccess(for: id)
    }

    /// Posts the "started" banner at most once per download.
    func notifyStartedIfNeeded(_ id: UUID, download: Download) {
        if startedNotified.insert(id).inserted {
            notifier.notifyStarted(download)
        }
    }

    // MARK: - Progress persistence throttling

    func markNeedsProgressSave() {
        needsProgressSave = true
    }

    func persistProgressIfNeeded() {
        guard needsProgressSave else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProgressSaveTime) >= EngineConstants.progressSaveInterval else { return }
        lastProgressSaveTime = now
        needsProgressSave = false
        store.save("periodicProgressSave")
    }

    func saveImmediately() {
        store.save()
    }

    // MARK: - Error text

    /// Catalog key for a `DownloadError`, or nil when the message can't be
    /// re-derived from a bare key (status-code / network errors embed runtime
    /// values and stay persisted as a fully localized `errorMessage`).
    func errorKey(for error: Error) -> String? {
        guard let dl = error as? DownloadError else { return nil }
        switch dl {
        case .cancelled: return "Cancelled"
        case .fileDeleted: return "Download file has been deleted"
        case .rangeNotSatisfiable: return "Server does not support this download range"
        case .fileChanged: return "File changed on server, resume not possible"
        case .httpStatus, .network: return nil
        }
    }

    func localizedMessage(for error: Error) -> String {
        guard let dl = error as? DownloadError else { return error.localizedDescription }
        switch dl {
        case .cancelled:
            return LanguageManager.shared.localized("Cancelled")
        case .fileDeleted:
            return LanguageManager.shared.localized("Download file has been deleted")
        case .rangeNotSatisfiable:
            return LanguageManager.shared.localized("Server does not support this download range")
        case .fileChanged:
            return LanguageManager.shared.localized("File changed on server, resume not possible")
        case .httpStatus(let code):
            let reason = LanguageManager.shared.localized(Self.httpStatusReason(code))
            return "\(reason) (HTTP \(code))"
        case .network(let e):
            return String(format: LanguageManager.shared.localized("Network error: %@"), e.localizedDescription)
        }
    }

    /// Human-readable catalog key for a bare HTTP status code, so users see a
    /// plain-language reason instead of just "HTTP 404".
    private static func httpStatusReason(_ code: Int) -> String {
        switch code {
        case 401: return "Authentication required"
        case 403: return "Access denied"
        case 404: return "File not found"
        case 408: return "Request timed out"
        case 429: return "Too many requests"
        case 500...599: return "Server error"
        default: return "HTTP error"
        }
    }

    // MARK: - Engine handlers

    /// Dispatches a `@MainActor` block to the main queue without allocating a
    /// `Task` per callback. Engine callbacks fire from background queues, so the
    /// explicit main-queue hop is equivalent to `Task { @MainActor ... }` but
    /// cheaper at the progress-callback cadence.
    private nonisolated func hopToMain(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(work)
        }
    }

    private func installHandlers(for id: UUID) {
        engine.setProgressHandler(for: id) { [weak self] bytes, total, speed in
            self?.hopToMain {
                self?.handleProgress(id: id, bytes: bytes, total: total, speed: speed)
            }
        }

        engine.setChunksChangeHandler(for: id) { [weak self] chunks in
            self?.hopToMain {
                // Copy into a fresh buffer so the engine's own writes never share
                // this array (sharing triggers a full-array copy-on-write).
                self?.store.update(id) { $0.chunks = chunks.map { $0 } }
            }
        }

        engine.setChunksUpdateHandler(for: id) { [weak self] updates in
            self?.hopToMain {
                self?.store.update(id) { download in
                    for update in updates where update.index < download.chunks.count {
                        download.chunks[update.index] = update
                    }
                }
            }
        }

        engine.setResumeSupportHandler(for: id) { [weak self] supports in
            self?.hopToMain {
                self?.handleResumeSupport(id: id, supports: supports)
            }
        }

        engine.setPhaseHandler(for: id) { [weak self] isProbing in
            self?.hopToMain {
                self?.onPhaseChange?(id, isProbing)
            }
        }

        engine.setChunkSizeHandler(for: id) { [weak self] chunkSize in
            self?.hopToMain {
                guard let self else { return }
                self.store.update(id) { download in
                    if download.chunkSize != chunkSize {
                        download.chunkSize = chunkSize
                    }
                }
                self.store.save("chunkSizeHandler")
            }
        }

        engine.setRetryingHandler(for: id) { [weak self] retrying in
            self?.hopToMain {
                self?.store.update(id) { $0.isRetrying = retrying }
            }
        }

        engine.setCompletionHandler(for: id) { [weak self] result in
            self?.hopToMain {
                guard let self else { return }
                self.engineTrackedDownloads.remove(id)
                self.engine.cleanup(id: id)
                self.onTaskCompletion?(id, result)
            }
        }
    }

    private func handleProgress(id: UUID, bytes: Int64, total: Int64, speed: Int64) {
        guard let idx = store.index(of: id) else { return }
        let prevTotal = store.downloads[idx].totalSize
        store.downloads[idx].totalSize = max(total, store.downloads[idx].totalSize)
        store.downloads[idx].downloadedSize = max(bytes, store.downloads[idx].downloadedSize)
        store.downloads[idx].downloadSpeed = speed
        needsProgressSave = true
        // Defer publishing until the file size is known (avoids a broken 0-total Progress).
        if total > 0, !progress.isPublished(for: id) {
            progress.publish(for: store.downloads[idx], fileURL: DownloadPath.staging(for: store.downloads[idx]))
        }
        progress.update(for: id, download: store.downloads[idx])
        if prevTotal == 0 {
            store.save("progressHandler")
        }
    }

    private func handleResumeSupport(id: UUID, supports: Bool) {
        guard let idx = store.index(of: id) else { return }
        if store.downloads[idx].supportsResume != supports {
            store.downloads[idx].supportsResume = supports
            store.save()
        }
    }
}
