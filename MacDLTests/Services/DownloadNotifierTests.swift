import Testing
import Foundation
import UserNotifications
import MacDLCore
@testable import MacDL

@MainActor @Suite(.serialized) struct DownloadNotifierTests {
    @Test func startedSendsRequest() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin")
        notifier.notifyStarted(d)
        #expect(requests.count == 1)
        #expect(requests[0].identifier == d.id.uuidString + "-started")
        #expect(requests[0].content.body == "a.bin")
        #expect(requests[0].content.sound != nil)
    }

    @Test func completedSendsRequestWithPath() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", savePath: "/tmp/dir")
        notifier.notifyCompleted(d)
        #expect(requests.count == 1)
        #expect(requests[0].content.body == "/tmp/dir/a.bin")
        #expect(requests[0].content.sound != nil)
    }

    @Test func completedDefaultPathUsesDownloads() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin")
        notifier.notifyCompleted(d)
        #expect(requests[0].content.body == AppConfig.defaultDownloadDir + "/a.bin")
    }

    @Test func failedSendsRequestWithReason() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", errorMessage: "network")
        notifier.notifyFailed(d)
        #expect(requests.count == 1)
        #expect(requests[0].content.body == "a.bin — network")
        #expect(requests[0].content.sound != nil)
    }

    @Test func notAuthorizedQueuesInsteadOfPosting() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = false
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin")
        notifier.notifyStarted(d)
        #expect(requests.isEmpty)
    }

    @Test func pendingFlushedWhenAuthorized() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = false
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin")
        notifier.notifyStarted(d)
        #expect(requests.isEmpty)
        notifier.authorized = true
        notifier.flushPending()
        #expect(requests.count == 1)
        #expect(requests[0].identifier == d.id.uuidString + "-started")
        #expect(requests[0].content.body == "a.bin")
    }

    @Test func pendingFlushedWhenSettingsReportAuthorized() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = false
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin")
        notifier.notifyStarted(d)
        #expect(requests.isEmpty)
        // Simulates getNotificationSettings reporting .authorized without a new prompt.
        notifier.setAuthorized(true)
        #expect(requests.count == 1)
        #expect(requests[0].identifier == d.id.uuidString + "-started")
    }

    @Test func fastCompletionCancelsPendingStarted() {
        var removed: [String] = []
        let notifier = DownloadNotifier(post: { _ in }, removePending: { removed.append(contentsOf: $0) })
        notifier.authorized = true
        let d = Download(filename: "fast.bin", url: "https://e.com/fast.bin")
        notifier.notifyStarted(d)
        notifier.notifyCompleted(d)
        // The still-pending "started" must be cancelled so "completed" isn't beaten by it.
        #expect(removed == [d.id.uuidString + "-started"])
    }

    @Test func slowDownloadKeepsStarted() {
        var removed: [String] = []
        let notifier = DownloadNotifier(post: { _ in }, removePending: { removed.append(contentsOf: $0) })
        notifier.authorized = true
        notifier.startedDelay = 0
        let d = Download(filename: "slow.bin", url: "https://e.com/slow.bin")
        notifier.notifyStarted(d)
        notifier.notifyCompleted(d)
        #expect(removed.isEmpty)
    }

    @Test func redownloadPromptCarriesUrl() {
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        notifier.notifyRedownload("https://e.com/a.zip")
        #expect(requests.count == 1)
        #expect(requests[0].content.categoryIdentifier == "redownload")
        #expect(requests[0].content.userInfo["url"] as? String == "https://e.com/a.zip")
    }
}
