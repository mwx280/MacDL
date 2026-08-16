import SwiftUI
import AppKit
import Observation
import MacDLCore

@MainActor
@Observable
final class ContentViewModel {
    // One instance for the whole app session: reopening a window reuses it, so
    // downloads keep their real state instead of being forced to paused.
    static let shared = ContentViewModel()
    static var current: ContentViewModel?
    private static var terminationSaved = false

    // All download lifecycle logic lives in the service; this view model keeps
    // only the SwiftUI-facing state (selection, filters) and forwards calls.
    let service: DownloadService

    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all

    var downloads: [Download] {
        get { service.downloads }
        set { service.downloads = newValue }
    }
    /// Downloads currently in the range-probe/detection phase (transient, not persisted).
    var probingDownloads: Set<UUID> {
        get { service.probingDownloads }
        set { service.probingDownloads = newValue }
    }

    private var termObserver: NSObjectProtocol?
    private var redownloadObserver: NSObjectProtocol?
    private var fileCheckTimer: Timer?

    init(
        engine: DownloadEngineProtocol = DownloadEngine.shared,
        persistence: DownloadPersistence = .shared,
        settings: SettingsStore = .shared,
        notifier: DownloadNotifier = .shared
    ) {
        service = DownloadService(engine: engine, persistence: persistence, settings: settings, notifier: notifier)
        Self.current = self
    }

    // MARK: - App services

    /// Sets up the app-wide observers and file-check timer. Called exactly once
    /// from the real app (MacDLApp). Tests must NOT call this per-instance:
    /// the global .requestRedownload observer and the repeating timer would
    /// leak across suites in the parallel test host and corrupt each other's
    /// downloads.
    func startAppServices() {
        guard termObserver == nil, redownloadObserver == nil, fileCheckTimer == nil else { return }
        redownloadObserver = NotificationCenter.default.addObserver(
            forName: .requestRedownload,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Extract the Sendable payload before hopping, then run on the main
            // queue (guaranteed by queue: .main).
            let url = note.object as? String
            MainActor.assumeIsolated {
                guard let self, let url else { return }
                self.service.addDownload(url: url, allowDuplicate: true)
            }
        }
        termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard !Self.terminationSaved else { return }
                Self.terminationSaved = true
                self.fileCheckTimer?.invalidate()
                self.fileCheckTimer = nil
                self.service.prepareForTermination()
            }
        }
        fileCheckTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so isolation is guaranteed.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.service.checkFilesAndPersistIfNeeded()
            }
        }
    }

    /// Tears down the observers/timer installed by startAppServices(). Tests call
    /// this after exercising the app flow so nothing leaks into other suites.
    func stopAppServices() {
        if let observer = redownloadObserver {
            NotificationCenter.default.removeObserver(observer)
            redownloadObserver = nil
        }
        if let observer = termObserver {
            NotificationCenter.default.removeObserver(observer)
            termObserver = nil
        }
        fileCheckTimer?.invalidate()
        fileCheckTimer = nil
    }

    // MARK: - Filtering

    func filteredDownloads(for item: SidebarItem?) -> [Download] {
        let statusFiltered: [Download]
        switch item {
        case .none, .all: statusFiltered = downloads
        case .active: statusFiltered = downloads.filter { $0.status == .active }
        case .waiting: statusFiltered = downloads.filter { $0.status == .waiting }
        case .completed: statusFiltered = downloads.filter { $0.status == .completed }
        case .stopped: statusFiltered = downloads.filter { $0.status == .stopped || $0.status == .error }
        }
        guard fileTypeFilter != .all else { return statusFiltered }
        return statusFiltered.filter { fileTypeFilter.matches($0) }
    }

    // MARK: - Clipboard / Links

    /// Pulls http/https URLs out of arbitrary text (whitespace / newline separated).
    static func downloadLinks(from text: String) -> [String] {
        DownloadService.downloadLinks(from: text)
    }

    func downloadFromClipboard() {
        service.downloadFromClipboard()
    }

    func handleDownloadLinks(_ text: String) {
        service.handleDownloadLinks(text)
    }

    // MARK: - Download actions (forwarded to the service)

    func addDownload(url: String, savePath: String? = nil, saveBookmark: Data? = nil, dlLimit: Int = 0, connections: Int? = nil, allowDuplicate: Bool = false) {
        service.addDownload(url: url, savePath: savePath, saveBookmark: saveBookmark, dlLimit: dlLimit, connections: connections, allowDuplicate: allowDuplicate)
    }

    func pauseDownload(id: UUID) {
        service.pauseDownload(id: id)
    }

    func resumeDownload(id: UUID) {
        service.resumeDownload(id: id)
    }

    func deleteDownload(id: UUID) {
        service.deleteDownload(id: id)
    }

    func retryDownload(id: UUID) {
        service.retryDownload(id: id)
    }

    /// Confirmation prompt for re-downloading a finished file. Injectable so tests
    /// can decide without presenting an NSAlert. `fileExists` tells whether the
    /// destination file is already on disk (the dialog warns it will be overwritten).
    var redownloadConfirmation: (Download, Bool) -> Bool = { download, fileExists in
        DialogPresenter.confirmRedownload(filename: download.filename, fileExists: fileExists)
    }

    func redownloadDownload(id: UUID) {
        service.redownloadDownload(id: id, confirmation: redownloadConfirmation)
    }

    func setDownloadLimit(id: UUID, limit: Int) {
        service.setDownloadLimit(id: id, limit: limit)
    }

    func setMaxChunks(id: UUID, count: Int) {
        service.setMaxChunks(id: id, count: count)
    }

    func pauseAll() {
        let ids = downloads.filter { selectedDownloads.contains($0.id) && $0.status == .active }.map(\.id)
        for id in ids { service.pauseDownload(id: id) }
    }

    func resumeAll() {
        let ids = downloads.filter { selectedDownloads.contains($0.id) && ($0.status == .paused || $0.status == .waiting) }.map(\.id)
        for id in ids { service.resumeDownload(id: id) }
    }

    func pauseAllDownloads() {
        service.pauseAllDownloads()
    }

    func resumeAllDownloads() {
        service.resumeAllDownloads()
    }

    func setPriorityDownload(id: UUID) {
        service.setPriorityDownload(id: id)
    }

    func cancelPriorityDownload(id: UUID) {
        service.cancelPriorityDownload(id: id)
    }

    func confirmDelete() {
        let result = DialogPresenter.confirmBulkDelete(count: selectedDownloads.count)
        if result.confirmed {
            service.clearSelected(ids: selectedDownloads, deleteFiles: result.deleteFiles)
            selectedDownloads.removeAll()
        }
    }
}
