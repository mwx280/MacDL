import Foundation
import os
import UserNotifications
import MacDLCore

extension Notification.Name {
    static let requestDownloadAction = Notification.Name("com.xiaowu.requestDownloadAction")
}

/// What to do when a duplicate-add notification's button is tapped. The action
/// reuses the existing download (by id) instead of creating a new one, so two
/// same-name tasks never write the same `.macdl` file.
enum DuplicateNotificationAction: Sendable {
    case resume(UUID)
    case retry(UUID)
    case reveal(UUID)
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

    private let resumeCategory = "resume"
    private let resumeAction = "resume-action"
    private let retryCategory = "retry"
    private let retryAction = "retry-action"
    private let revealCategory = "reveal"
    private let revealAction = "reveal-action"

    override private init() {
        post = { UNUserNotificationCenter.current().add($0) }
        removePending = { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: $0) }
        settings = SettingsStore.shared
        super.init()
        UNUserNotificationCenter.current().delegate = self
        EngineLog.app.debug("DownloadNotifier delegate set")
        let resume = UNNotificationAction(identifier: resumeAction,
                                          title: LanguageManager.shared.localized("Continue Download"),
                                          options: [])
        let retry = UNNotificationAction(identifier: retryAction,
                                         title: LanguageManager.shared.localized("Retry"),
                                         options: [])
        let reveal = UNNotificationAction(identifier: revealAction,
                                          title: LanguageManager.shared.localized("Show in Finder"),
                                          options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: resumeCategory, actions: [resume], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: retryCategory, actions: [retry], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: revealCategory, actions: [reveal], intentIdentifiers: [], options: [])
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

    /// Posts the "running in the background" notice when the app starts with
    /// the main window suppressed, so the user knows the app is alive. Gated by
    /// the Launch Notification setting.
    func notifyLaunched() {
        guard settings.notifyLaunch else { return }
        notify(title: LanguageManager.shared.localized("MacDL is Running"),
               body: LanguageManager.shared.localized("MacDL is running in the background"))
    }

    func notifyCompleted(_ download: Download) {
        guard settings.notifyCompleted else { return }
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        EngineLog.app.debug("DownloadNotifier notifyCompleted \(download.filename) authorized=\(self.authorized ? 1 : 0)")
        suppressPendingStarted(for: download.id)
        let content = UNMutableNotificationContent()
        content.title = LanguageManager.shared.localized("Download Completed")
        content.body = dir + "/" + download.filename
        content.sound = .default
        // Offer "Open File Location" so the user can reveal the finished file.
        content.categoryIdentifier = revealCategory
        content.userInfo = ["id": download.id.uuidString]
        let request = UNNotificationRequest(identifier: download.id.uuidString + "-completed",
                                            content: content,
                                            trigger: nil)
        guard authorized else {
            pending.append(request)
            return
        }
        EngineLog.app.debug("DownloadNotifier posting completed")
        post(request)
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

    func notifyDuplicate(_ download: Download) {
        guard settings.notifyRedownload else { return }
        EngineLog.app.debug("DownloadNotifier notifyDuplicate \(download.filename)")
        let content = UNMutableNotificationContent()
        content.title = LanguageManager.shared.localized("Already in Download List")
        content.body = download.filename
        content.userInfo = ["id": download.id.uuidString]
        // The action matches the existing task's state: resume a paused task,
        // retry a failed one, reveal a finished file. Active/waiting tasks get
        // no action — they're already downloading.
        switch download.status {
        case .paused:
            content.categoryIdentifier = resumeCategory
        case .error, .stopped:
            content.categoryIdentifier = retryCategory
        case .completed:
            content.categoryIdentifier = revealCategory
        default:
            break
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString + "-duplicate",
                                            content: content,
                                            trigger: nil)
        guard authorized else {
            pending.append(request)
            return
        }
        EngineLog.app.debug("DownloadNotifier posting duplicate prompt")
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
        let userInfo = response.notification.request.content.userInfo
        if let idString = userInfo["id"] as? String, let id = UUID(uuidString: idString) {
            let action: DuplicateNotificationAction?
            switch response.actionIdentifier {
            case resumeAction: action = .resume(id)
            case retryAction: action = .retry(id)
            case revealAction: action = .reveal(id)
            default: action = nil
            }
            if let action {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .requestDownloadAction, object: action)
                }
            }
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // Tapping the notification body opens the main window so the user can
            // see the download — a background launch may have no window open yet.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MacDLApp.showWindow()
                }
            }
        }
        completionHandler()
    }
}
