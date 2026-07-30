import Testing
@testable import MacDL

@Suite struct DownloadStatusDisplayTests {
    @Test(arguments: [
        (DownloadStatus.active, "arrow.down.circle.fill"),
        (.paused, "pause.circle.fill"),
        (.waiting, "clock.fill"),
        (.completed, "checkmark.circle.fill"),
        (.stopped, "stop.circle.fill"),
        (.error, "exclamationmark.circle.fill"),
    ]) func displayIcon(status: DownloadStatus, expected: String) {
        #expect(status.displayIcon == expected)
    }

    @Test(arguments: [
        DownloadStatus.active, .paused, .waiting, .completed, .stopped, .error,
    ]) func displayColorNotClear(status: DownloadStatus) {
        #expect(status.displayColor != .clear)
    }

    @Test(arguments: [
        (DownloadStatus.active, "Active"),
        (.paused, "Paused"),
        (.waiting, "Waiting"),
        (.completed, "Completed"),
        (.stopped, "Stopped"),
        (.error, "Error"),
    ]) func labelKey(status: DownloadStatus, expected: String) {
        #expect(status.labelKey == expected)
    }
}
