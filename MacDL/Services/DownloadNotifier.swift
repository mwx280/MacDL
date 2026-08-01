import Foundation
import UserNotifications
import MacDLCore

// Sends local notifications for download start / completion / failure.
// Delivery is injectable so tests can capture the requests without touching the OS.
final class DownloadNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DownloadNotifier()

    var authorized = false
    var post: (UNNotificationRequest) -> Void

    override private init() {
        post = { UNUserNotificationCenter.current().add($0) }
        super.init()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }

    init(post: @escaping (UNNotificationRequest) -> Void) {
        self.post = post
        super.init()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func notifyStarted(_ download: Download) {
        send(title: LanguageManager.shared.localized("Download Started"),
             body: download.filename,
             id: download.id,
             sound: false)
    }

    func notifyCompleted(_ download: Download) {
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        send(title: LanguageManager.shared.localized("Download Completed"),
             body: dir + "/" + download.filename,
             id: download.id,
             sound: true)
    }

    func notifyFailed(_ download: Download) {
        let reason = download.errorMessage ?? LanguageManager.shared.localized("Unknown error")
        send(title: LanguageManager.shared.localized("Download failed"),
             body: download.filename + " — " + reason,
             id: download.id,
             sound: true)
    }

    private func send(title: String, body: String, id: UUID, sound: Bool) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        post(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
    }

    // Show the banner even while the app (or its menu bar UI) is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
