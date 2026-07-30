import Testing
import Foundation
@testable import Aria2Desk

let testDownloads: [Download] = [
    Download(filename: "ubuntu.iso", url: "https://example.com/ubuntu.iso", totalSize: 1000, downloadedSize: 500, downloadSpeed: 100, status: .active),
    Download(filename: "movie.mkv", url: "https://example.com/movie.mkv", totalSize: 2000, downloadedSize: 2000, downloadSpeed: 0, status: .completed),
    Download(filename: "doc.pdf", url: "https://example.com/doc.pdf", totalSize: 500, downloadedSize: 300, downloadSpeed: 0, status: .paused),
    Download(filename: "error.log", url: "https://example.com/error.log", totalSize: 100, downloadedSize: 50, downloadSpeed: 0, status: .error),
]

@Suite struct ContentViewModelTests {
    @Test func filteredDownloadsAll() {
        let vm = ContentViewModel()
        vm.downloads = testDownloads
        let result = vm.filteredDownloads(for: .all)
        #expect(result.count == vm.downloads.count)
    }

    @Test func filteredDownloadsActive() {
        let vm = ContentViewModel()
        vm.downloads = testDownloads
        let result = vm.filteredDownloads(for: .active)
        #expect(result.allSatisfy { $0.status == .active })
    }

    @Test func filteredDownloadsCompleted() {
        let vm = ContentViewModel()
        vm.downloads = testDownloads
        let result = vm.filteredDownloads(for: .completed)
        #expect(result.allSatisfy { $0.status == .completed })
    }

    @Test func pauseAllChangesStatus() {
        let vm = ContentViewModel()
        vm.downloads = testDownloads
        let activeIds = vm.downloads.filter { $0.status == .active }.map(\.id)
        guard !activeIds.isEmpty else { return }
        for id in activeIds {
            if let idx = vm.downloads.firstIndex(where: { $0.id == id }) {
                vm.downloads[idx].status = .paused
            }
        }
        for id in activeIds {
            let d = vm.downloads.first { $0.id == id }
            #expect(d?.status == .paused)
        }
    }

    @Test func resumeAllChangesStatus() {
        let vm = ContentViewModel()
        vm.downloads = testDownloads
        let pausedIds = vm.downloads.filter { $0.status == .paused || $0.status == .waiting }.map(\.id)
        guard !pausedIds.isEmpty else { return }
        for id in pausedIds {
            if let idx = vm.downloads.firstIndex(where: { $0.id == id }) {
                vm.downloads[idx].status = .active
            }
        }
        for id in pausedIds {
            let d = vm.downloads.first { $0.id == id }
            #expect(d?.status == .active)
        }
    }

    @Test func addDownloadIncreasesCount() {
        let vm = ContentViewModel()
        let d = Download(filename: "archive.zip", url: "https://example.com/archive.zip", status: .active)
        let before = vm.downloads.count
        vm.downloads.append(d)
        #expect(vm.downloads.count == before + 1)
        #expect(vm.downloads.last?.filename == "archive.zip")
        #expect(vm.downloads.last?.status == .active)
    }

    @Test func addDownloadWithNoPathInURL() {
        let vm = ContentViewModel()
        let d = Download(filename: "magnet.torrent", url: "magnet:?xt=urn:btih:abc123", status: .active)
        let before = vm.downloads.count
        vm.downloads.append(d)
        #expect(vm.downloads.count == before + 1)
    }

    @Test func filteredDownloadsEmptyForInvalidSidebar() {
        let vm = ContentViewModel()
        vm.downloads = []
        for item in SidebarItem.allCases {
            let result = vm.filteredDownloads(for: item)
            #expect(result.isEmpty)
        }
    }

    @Test func deleteDownloadRemovesFromList() {
        let vm = ContentViewModel()
        vm.downloads = testDownloads
        let before = vm.downloads.count
        guard let first = vm.downloads.first else { return }
        vm.deleteDownload(id: first.id)
        #expect(vm.downloads.count == before - 1)
        #expect(vm.downloads.allSatisfy { $0.id != first.id })
    }
}
