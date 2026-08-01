import Testing
import Foundation
import UserNotifications
import MacDLCore
@testable import MacDL

@Suite(.serialized) struct DownloadNotifierTests {
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
}
