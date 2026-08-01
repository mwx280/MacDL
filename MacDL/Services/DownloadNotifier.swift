import Foundation
import os
import UserNotifications
import MacDLCore

// Sends local notifications for download start / completion / failure.
// Delivery is injectable so tests can capture the requests without touching the OS.
final class DownloadNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DownloadNotifier()

    var authorized = false
    var post: (UNNotificationRequest) -> Void
    private var pending: [UNNotificationRequest] = []

    override private init() {
        post = { UNUserNotificationCenter.current().add($0) }
        super.init()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.setAuthorized(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }

    init(post: @escaping (UNNotificationRequest) -> Void) {
        self.post = post
        super.init()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    os_log("[DownloadNotifier] authorization error: %{public}@", String(describing: error))
                }
                self.setAuthorized(granted)
            }
        }
    }

    func setAuthorized(_ value: Bool) {
        let was = authorized
        authorized = value
        if value && !was { flushPending() }
    }

    func notifyStarted(_ download: Download) {
        os_log("[DownloadNotifier] notifyStarted %{public}@ authorized=%d", download.filename, authorized ? 1 : 0)
        send(title: LanguageManager.shared.localized("Download Started"),
             body: download.filename,
             id: download.id,
             sound: false)
    }

    func notifyCompleted(_ download: Download) {
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        os_log("[DownloadNotifier] notifyCompleted %{public}@ authorized=%d", download.filename, authorized ? 1 : 0)
        send(title: LanguageManager.shared.localized("Download Completed"),
             body: dir + "/" + download.filename,
             id: download.id,
             sound: true)
    }

    func notifyFailed(_ download: Download) {
        let reason = download.errorMessage ?? LanguageManager.shared.localized("Unknown error")
        os_log("[DownloadNotifier] notifyFailed %{public}@ authorized=%d", download.filename, authorized ? 1 : 0)
        send(title: LanguageManager.shared.localized("Download failed"),
             body: download.filename + " — " + reason,
             id: download.id,
             sound: true)
    }

    private func send(title: String, body: String, id: UUID, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil)
        // If the permission prompt is still pending, hold the banner and deliver
        // it once access is granted (otherwise the first download's "started"
        // notification would be silently dropped).
        guard authorized else {
            pending.append(request)
            return
        }
        os_log("[DownloadNotifier] posting %{public}@", title)
        post(request)
    }

    func flushPending() {
        for request in pending { post(request) }
        pending.removeAll()
    }

    // Show the banner even while the app (or its menu bar UI) is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
