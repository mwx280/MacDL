import Testing
import Foundation
@testable import MacDL

@MainActor
@Suite struct DuplicatePolicyTests {
    private func download(status: DownloadStatus) -> Download {
        Download(filename: "a.zip", url: "https://e.com/a.zip", status: status)
    }

    @Test func activeOrWaitingSkips() {
        #expect(DuplicatePolicy.decide(for: download(status: .active), showDuplicateActive: {}) == .skip)
        #expect(DuplicatePolicy.decide(for: download(status: .waiting), showDuplicateActive: {}) == .skip)
    }

    @Test func pausedResumeChoosesResume() {
        #expect(DuplicatePolicy.decide(for: download(status: .paused), showDuplicateActive: {}, showDuplicatePaused: { .resume }) == .resume)
    }

    @Test func pausedCancelSkips() {
        #expect(DuplicatePolicy.decide(for: download(status: .paused), showDuplicateActive: {}, showDuplicatePaused: { .cancel }) == .skip)
    }

    @Test func completedRedownloadsOnlyWhenConfirmed() {
        #expect(DuplicatePolicy.decide(for: download(status: .completed), showDuplicateActive: {}, showDuplicateCompleted: { true }) == .redownload)
        #expect(DuplicatePolicy.decide(for: download(status: .completed), showDuplicateActive: {}, showDuplicateCompleted: { false }) == .skip)
    }

    @Test func failedOrStoppedProceedsOnlyWhenConfirmed() {
        #expect(DuplicatePolicy.decide(for: download(status: .error), showDuplicateActive: {}, showDuplicateFailed: { _ in true }) == .proceed)
        #expect(DuplicatePolicy.decide(for: download(status: .stopped), showDuplicateActive: {}, showDuplicateFailed: { _ in false }) == .skip)
    }
}
