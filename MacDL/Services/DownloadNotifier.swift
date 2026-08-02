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
        os_log("[DownloadNotifier] delegate set")
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                os_log("[DownloadNotifier] settings auth=%@ alert=%@",
                       String(describing: settings.authorizationStatus),
                       String(describing: settings.alertSetting))
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
                os_log("[DownloadNotifier] authorization granted=%d", granted ? 1 : 0)
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
        // Small delay so the banner lands after the new-download sheet has fully
        // dismissed - a notification posted mid-transition gets parked in the
        // notification center instead of presenting.
        send(title: LanguageManager.shared.localized("Download Started"),
             body: download.filename,
             id: download.id,
             kind: "started",
             sound: true,
             delay: 0.5)
    }

    func notify(title: String, body: String) {
        os_log("[DownloadNotifier] notify %{public}@", title)
        send(title: title, body: body, id: UUID(), kind: "message", sound: false)
    }

    func notifyCompleted(_ download: Download) {
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        os_log("[DownloadNotifier] notifyCompleted %{public}@ authorized=%d", download.filename, authorized ? 1 : 0)
        send(title: LanguageManager.shared.localized("Download Completed"),
             body: dir + "/" + download.filename,
             id: download.id,
             kind: "completed",
             sound: true)
    }

    func notifyFailed(_ download: Download) {
        let reason = download.errorMessage ?? LanguageManager.shared.localized("Unknown error")
        os_log("[DownloadNotifier] notifyFailed %{public}@ authorized=%d", download.filename, authorized ? 1 : 0)
        send(title: LanguageManager.shared.localized("Download failed"),
             body: download.filename + " — " + reason,
             id: download.id,
             kind: "failed",
             sound: true)
    }

    private func send(title: String, body: String, id: UUID, kind: String, sound: Bool, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        // Distinct identifier per event type so "started" isn't replaced by
        // "completed" for fast downloads.
        let trigger: UNNotificationTrigger? = delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil
        let request = UNNotificationRequest(identifier: id.uuidString + "-" + kind, content: content, trigger: trigger)
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
        os_log("[DownloadNotifier] willPresent called id=%{public}@", notification.request.identifier)
        completionHandler([.banner, .list, .sound])
    }
}
