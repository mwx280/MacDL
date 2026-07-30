import Testing
import Foundation
@testable import Aria2Desk

@Suite struct ContentViewModelTests {
    @Test func filteredDownloadsAll() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let result = vm.filteredDownloads(for: .all)
        #expect(result.count == vm.downloads.count)
    }

    @Test func filteredDownloadsActive() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let result = vm.filteredDownloads(for: .active)
        #expect(result.allSatisfy { $0.status == .active })
    }

    @Test func filteredDownloadsCompleted() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let result = vm.filteredDownloads(for: .completed)
        #expect(result.allSatisfy { $0.status == .completed })
    }

    @Test func pauseAllChangesStatus() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let activeIds = Set(vm.downloads.filter { $0.status == .active }.map(\.id))
        guard !activeIds.isEmpty else { return }
        vm.selectedDownloads = activeIds
        vm.pauseAll()
        for id in activeIds {
            let d = vm.downloads.first { $0.id == id }
            #expect(d?.status == .paused)
        }
    }

    @Test func resumeAllChangesStatus() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let pausedIds = Set(vm.downloads.filter { $0.status == .paused || $0.status == .waiting }.map(\.id))
        guard !pausedIds.isEmpty else { return }
        vm.selectedDownloads = pausedIds
        vm.resumeAll()
        for id in pausedIds {
            let d = vm.downloads.first { $0.id == id }
            #expect(d?.status == .active)
        }
    }

    @Test func addDownloadIncreasesCount() {
        let vm = ContentViewModel()
        let before = vm.downloads.count
        vm.addDownload(url: "https://example.com/file.zip")
        #expect(vm.downloads.count == before + 1)
        #expect(vm.downloads.last?.filename == "file.zip")
        #expect(vm.downloads.last?.status == .waiting)
    }

    @Test func addDownloadWithNoPathInURL() {
        let vm = ContentViewModel()
        let before = vm.downloads.count
        vm.addDownload(url: "magnet:?xt=urn:btih:abc123")
        #expect(vm.downloads.count == before + 1)
    }

    @Test func computeTotalSpeed() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let expected = vm.downloads.reduce(0) { $0 + $1.downloadSpeed }
        #expect(vm.totalSpeed == expected)
    }

    @Test func computeTotalUpload() {
        let vm = ContentViewModel()
        vm.downloads = PreviewContent.downloads
        let expected = vm.downloads.reduce(0) { $0 + $1.uploadSpeed }
        #expect(vm.totalUpload == expected)
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
        vm.downloads = PreviewContent.downloads
        let before = vm.downloads.count
        guard let first = vm.downloads.first else { return }
        vm.deleteDownload(id: first.id)
        #expect(vm.downloads.count == before - 1)
        #expect(vm.downloads.allSatisfy { $0.id != first.id })
    }

    @Test func gidMapping() {
        let vm = ContentViewModel()
        let d = Download(gid: "abc123", filename: "test.zip", url: "https://example.com/test.zip")
        vm.downloads = [d]
        #expect(vm.downloads.first?.gid == "abc123")
    }

    @Test func statusAria2Mapping() {
        #expect(DownloadStatus(aria2Status: "active") == .active)
        #expect(DownloadStatus(aria2Status: "paused") == .paused)
        #expect(DownloadStatus(aria2Status: "waiting") == .waiting)
        #expect(DownloadStatus(aria2Status: "complete") == .completed)
        #expect(DownloadStatus(aria2Status: "error") == .error)
        #expect(DownloadStatus(aria2Status: "removed") == .stopped)
        #expect(DownloadStatus(aria2Status: "invalid") == nil)
    }
}
