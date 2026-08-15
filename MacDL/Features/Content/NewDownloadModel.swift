import Foundation
import AppKit
import Observation
import MacDLCore

// Parsing, validation, resume probing and per-task settings for the new-download
// sheet, isolated from the view so it is unit-testable. The probe service is
// injectable; tests pass a stub instead of hitting the network.
@MainActor
@Observable
final class NewDownloadModel {
    var text = ""
    var resumeStatus: [String: Bool] = [:]
    var limits: [String: Int] = [:]
    var connectionsByURL: [String: Int] = [:]
    var clipboardHasURL = false
    private(set) var probedURLs: Set<String> = []

    var defaultConnections: Int
    var defaultSpeedLimit: Int
    private let probe: (URL, @escaping @MainActor (Bool?) -> Void) -> Void

    init(defaultConnections: Int = 16,
         defaultSpeedLimit: Int = 0,
         probe: @escaping (URL, @escaping @MainActor (Bool?) -> Void) -> Void = { url, completion in
             ResumeProbeService.detectResumeSupport(url: url, completion: completion)
         }) {
        self.defaultConnections = defaultConnections
        self.defaultSpeedLimit = defaultSpeedLimit
        self.probe = probe
    }

    // MARK: - Parsing / validation

    var queueLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func isValid(_ line: String) -> Bool {
        guard let url = URL(string: line),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil
        else { return false }
        return true
    }

    static func containsValidURL(in text: String) -> Bool {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { isValid($0) }
    }

    var hasInvalidLinks: Bool { invalidCount > 0 }

    var invalidCount: Int {
        queueLines.filter { !Self.isValid($0) }.count
    }

    var validCount: Int {
        queueLines.filter { Self.isValid($0) }.count
    }

    struct TaskInfo: Identifiable, Equatable {
        let url: String
        let name: String
        let host: String
        let icon: String
        var id: String { url }
    }

    var validTasks: [TaskInfo] {
        queueLines.compactMap { line in
            guard Self.isValid(line), let url = URL(string: line) else { return nil }
            let name = url.lastPathComponent
            let filename = name.isEmpty ? (url.host ?? line) : name
            let icon = Download(filename: filename, url: line).fileTypeIcon
            return TaskInfo(url: line, name: filename, host: url.host ?? "", icon: icon)
        }
    }

    var duplicatedNames: Set<String> {
        var seen = Set<String>()
        var dupes = Set<String>()
        for task in validTasks {
            if seen.contains(task.name) { dupes.insert(task.name) }
            seen.insert(task.name)
        }
        return dupes
    }

    func connections(for url: String) -> Int {
        connectionsByURL[url] ?? defaultConnections
    }

    func speedLimit(for url: String) -> Int {
        limits[url] ?? defaultSpeedLimit
    }

    // MARK: - Resume probing

    /// Probes resume support for every not-yet-probed valid URL.
    func detectResumeSupport() {
        for task in validTasks where !probedURLs.contains(task.url) {
            probedURLs.insert(task.url)
            resumeStatus[task.url] = nil
            guard let url = URL(string: task.url) else { continue }
            probe(url) { [weak self] result in
                self?.resumeStatus[task.url] = result
            }
        }
    }

    // MARK: - Actions

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        text = pb.string(forType: .string) ?? text
        detectClipboard()
    }

    func detectClipboard() {
        guard text.isEmpty else {
            clipboardHasURL = false
            return
        }
        guard let str = NSPasteboard.general.string(forType: .string) else {
            clipboardHasURL = false
            return
        }
        clipboardHasURL = Self.containsValidURL(in: str)
    }

    func appendURLs(_ raw: [String]) {
        let lines = raw
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        var merged = text
        if !merged.isEmpty { merged += "\n" }
        merged += lines.joined(separator: "\n")
        text = merged
        detectClipboard()
    }

    func removeTask(_ url: String) {
        var lines = queueLines
        if let idx = lines.firstIndex(of: url) { lines.remove(at: idx) }
        text = lines.joined(separator: "\n")
        connectionsByURL[url] = nil
        limits[url] = nil
        detectClipboard()
    }
}
