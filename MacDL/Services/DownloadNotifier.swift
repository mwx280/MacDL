import Foundation
import os
import UserNotifications
import MacDLCore

extension Notification.Name {
    static let requestRedownload = Notification.Name("com.xiaowu.requestRedownload")
}

// Sends local notifications for download start / completion / failure.
// Delivery is injectable so tests can capture the requests without touching the OS.
// Main-actor isolated: all notification calls come from the main thread and the
// UNUserNotificationCenter callbacks hop back to main, so no lock is needed.
@MainActor
final class DownloadNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DownloadNotifier()

    var authorized = false
    var post: (UNNotificationRequest) -> Void
    var removePending: ([String]) -> Void
    private var pending: [UNNotificationRequest] = []
    private let settings: SettingsStore

    var startedDelay: TimeInterval = 0.5
    private var startedAt: [UUID: Date] = [:]

    private let redownloadCategory = "redownload"
    private let redownloadAction = "redownload-action"

    override private init() {
        post = { UNUserNotificationCenter.current().add($0) }
        removePending = { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0) }
        settings = SettingsStore.shared
        super.init()
        UNUserNotificationCenter.current().delegate = self
        EngineLog.app.debug("DownloadNotifier delegate set")
        let action = UNNotificationAction(identifier: redownloadAction,
                                          title: LanguageManager.shared.localized("Redownload"),
                                          options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: redownloadCategory,
                                   actions: [action],
                                   intentIdentifiers: [],
                                   options: [])
        ])
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            // Extract Sendable values here; the settings object itself must not
            // cross into the main-actor closure.
            let auth = settings.authorizationStatus
            let alert = settings.alertSetting
            let authorized = auth == .authorized || auth == .provisional
            DispatchQueue.main.async {
                EngineLog.app.debug("DownloadNotifier settings auth=\(String(describing: auth)) alert=\(String(describing: alert))")
                self?.setAuthorized(authorized)
            }
        }
    }

    init(post: @escaping (UNNotificationRequest) -> Void,
         removePending: @escaping ([String]) -> Void = { _ in },
         settings: SettingsStore = .shared) {
        self.post = post
        self.removePending = removePending
        self.settings = settings
        super.init()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    EngineLog.app.error("DownloadNotifier authorization error: \(String(describing: error))")
                }
                EngineLog.app.debug("DownloadNotifier authorization granted=\(granted ? 1 : 0)")
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
        guard settings.notifyStart else { return }
        EngineLog.app.debug("DownloadNotifier notifyStarted \(download.filename) authorized=\(self.authorized ? 1 : 0)")
        startedAt[download.id] = Date()
        // Small delay so the banner lands after the new-download sheet has fully
        // dismissed - a notification posted mid-transition gets parked in the
        // notification center instead of presenting.
        send(title: LanguageManager.shared.localized("Download Started"),
             body: download.filename,
             id: download.id,
             kind: "started",
             sound: true,
             delay: startedDelay)
    }

    func notify(title: String, body: String) {
        EngineLog.app.debug("DownloadNotifier notify \(title)")
        send(title: title, body: body, id: UUID(), kind: "message", sound: false)
    }

    // Shown when the app launches in the background so the user knows it is
    // still running (and downloads keep going) even though no window appears.
    func notifyLaunch() {
        guard settings.notifyLaunch else { return }
        EngineLog.app.debug("DownloadNotifier notifyLaunch authorized=\(self.authorized ? 1 : 0)")
        send(title: LanguageManager.shared.localized("MacDL is Running"),
             body: LanguageManager.shared.localized("MacDL is running in the background"),
             id: UUID(), kind: "launch", sound: false)
    }

    func notifyCompleted(_ download: Download) {
        guard settings.notifyCompleted else { return }
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        EngineLog.app.debug("DownloadNotifier notifyCompleted \(download.filename) authorized=\(self.authorized ? 1 : 0)")
        suppressPendingStarted(for: download.id)
        send(title: LanguageManager.shared.localized("Download Completed"),
             body: dir + "/" + download.filename,
             id: download.id,
             kind: "completed",
             sound: true)
    }

    func notifyFailed(_ download: Download) {
        guard settings.notifyFailed else { return }
        let reason = DownloadErrorText.text(for: download) ?? LanguageManager.shared.localized("Unknown error")
        EngineLog.app.debug("DownloadNotifier notifyFailed \(download.filename) authorized=\(self.authorized ? 1 : 0)")
        suppressPendingStarted(for: download.id)
        send(title: LanguageManager.shared.localized("Download failed"),
             body: download.filename + " — " + reason,
             id: download.id,
             kind: "failed",
             sound: true)
    }

    func notifyRedownload(_ url: String) {
        guard settings.notifyRedownload else { return }
        EngineLog.app.debug("DownloadNotifier notifyRedownload \(url)")
        let content = UNMutableNotificationContent()
        content.title = LanguageManager.shared.localized("Already in Download List")
        content.body = url
        content.categoryIdentifier = redownloadCategory
        content.userInfo = ["url": url]
        let request = UNNotificationRequest(identifier: UUID().uuidString + "-redownload",
                                            content: content,
                                            trigger: nil)
        guard authorized else {
            pending.append(request)
            return
        }
        EngineLog.app.debug("DownloadNotifier posting redownload prompt")
        post(request)
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
        EngineLog.app.debug("DownloadNotifier posting \(title)")
        post(request)
    }

    // If a download finishes inside the started banner's delay window, drop the
    // pending "started" so a fast download can't show "completed" first.
    private func suppressPendingStarted(for id: UUID) {
        guard let at = startedAt.removeValue(forKey: id),
              Date().timeIntervalSince(at) < startedDelay else { return }
        let identifier = id.uuidString + "-started"
        pending.removeAll { $0.identifier == identifier }
        removePending([identifier])
    }

    func flushPending() {
        let toPost = pending
        pending.removeAll()
        for request in toPost { post(request) }
    }

    // Show the banner even while the app (or its menu bar UI) is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        EngineLog.app.debug("DownloadNotifier willPresent called id=\(notification.request.identifier)")
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == redownloadAction,
           let url = response.notification.request.content.userInfo["url"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .requestRedownload, object: url)
            }
        }
        completionHandler()
    }
}
