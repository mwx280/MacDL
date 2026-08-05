import SwiftUI
import AppKit
import UserNotifications

struct NotificationsPane: View {
    @AppStorage("notifyStart") private var notifyStart = true
    @AppStorage("notifyCompleted") private var notifyCompleted = true
    @AppStorage("notifyFailed") private var notifyFailed = true
    @AppStorage("notifyRedownload") private var notifyRedownload = true
    @State private var notificationsEnabled = true

    var body: some View {
        VStack(spacing: 16) {
            if notificationsEnabled {
                card {
                    prefRow("play.circle", "Download Started") {
                        Toggle("", isOn: $notifyStart)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    divider

                    prefRow("checkmark.circle.fill", "Download Completed", suffix: "Recommended") {
                        Toggle("", isOn: $notifyCompleted)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    divider

                    prefRow("xmark.circle.fill", "Download failed", suffix: "Recommended") {
                        Toggle("", isOn: $notifyFailed)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    divider

                    prefRow("arrow.clockwise.circle", "Redownload Prompt", suffix: "Recommended") {
                        Toggle("", isOn: $notifyRedownload)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }
            } else {
                card {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        LocalizedText(key: "Notifications are disabled")
                            .font(.body)
                        LocalizedText(key: "Enable notifications in System Settings to customize which alerts MacDL shows")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            openNotificationSettings()
                        } label: {
                            LocalizedText(key: "Enable Notifications")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(20)
        .onAppear { refreshAuthorization() }
    }

    private func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // Extract the Sendable flag so the settings object stays on this queue.
            let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                notificationsEnabled = enabled
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?MacDL") {
            NSWorkspace.shared.open(url)
        }
    }
}
