import SwiftUI
import AppKit
import UserNotifications

struct SettingsView: View {
    private enum Pane: String {
        case general
        case download
        case update
        case notifications
    }

    @State private var pane: Pane = .general

    var body: some View {
        TabView(selection: $pane) {
            NotificationsPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Notifications") }, icon: { Image(systemName: "bell") })
                }
                .tag(Pane.notifications)

            GeneralPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "General") }, icon: { Image(systemName: "gear") })
                }
                .tag(Pane.general)

            DownloadPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Download") }, icon: { Image(systemName: "arrow.down.circle") })
                }
                .tag(Pane.download)

            UpdatePane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Update") }, icon: { Image(systemName: "arrow.triangle.2.circlepath") })
                }
                .tag(Pane.update)
        }
        .frame(width: 420, height: height(for: pane))
    }

    private func height(for pane: Pane) -> CGFloat {
        switch pane {
        case .general: 190
        case .download: 260
        case .update: 120
        case .notifications: 190
        }
    }
}

private struct GeneralPane: View {
    @Environment(LanguageManager.self) var lang
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("hideDockIconOnClose") private var hideDockIconOnClose = false
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginFailed = false

    var body: some View {
        VStack(spacing: 16) {
            card {
                prefRow("globe", "Language") {
                    Picker(selection: Bindable(lang).selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { l in
                            LocalizedText(key: l.displayKey).tag(l)
                        }
                    } label: { }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 140, alignment: .trailing)
                }
                .id(lang.selectedLanguage)

                divider

                prefRow("circle.lefthalf.filled", "Appearance") {
                    Picker(selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { a in
                            LocalizedText(key: a.displayKey).tag(a)
                        }
                    } label: { }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 140, alignment: .trailing)
                }

                divider

                prefRow("power", "Launch at Login") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            do {
                                try LaunchAtLoginService.setEnabled(newValue)
                                launchAtLogin = newValue
                            } catch {
                                launchAtLoginFailed = true
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                divider

                prefRow("rectangle.dashed", "Hide Dock Icon on Close") {
                    Toggle("", isOn: $hideDockIconOnClose)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .onChange(of: hideDockIconOnClose) { _, _ in
                            DockIconManager.shared.update()
                        }
                }
            }
            .alert(LanguageManager.shared.localized("Launch at Login"), isPresented: $launchAtLoginFailed) {
                Button(LanguageManager.shared.localized("OK"), role: .cancel) { }
            } message: {
                LocalizedText(key: "Launch at Login requires the app to run from the Applications folder.")
            }
        }
        .padding(20)
    }
}

private struct DownloadPane: View {
    @State private var maxConnections: Int
    @State private var maxConcurrent: Int
    @State private var downloadPath: String
    @State private var maxDownloadSpeed: Int

    private let connectionOptions = [1, 2, 4, 8]
    private let concurrentOptions = [1, 2, 3, 5, 10, 20]

    init() {
        _maxConnections = State(initialValue: SettingsStore.shared.maxConnections)
        _maxConcurrent = State(initialValue: SettingsStore.shared.maxConcurrentDownloads)
        _downloadPath = State(initialValue: SettingsStore.shared.downloadPath)
        _maxDownloadSpeed = State(initialValue: SettingsStore.shared.maxDownloadSpeed)
    }

    var body: some View {
        VStack(spacing: 16) {
            card {
                prefRow("number", "Default Max Connections") {
                    Picker(selection: $maxConnections) {
                        ForEach(connectionOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    } label: { }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 72, alignment: .trailing)
                    .onChange(of: maxConnections) { _, v in
                        SettingsStore.shared.maxConnections = v
                    }
                }

                divider

                prefRow("arrow.down.to.line", "Max Downloads") {
                    Picker(selection: $maxConcurrent) {
                        ForEach(concurrentOptions, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    } label: { }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 72, alignment: .trailing)
                    .onChange(of: maxConcurrent) { _, v in
                        SettingsStore.shared.maxConcurrentDownloads = v
                    }
                }
            }

            card {
                prefRow("arrow.down", "Download Limit") {
                    Picker(selection: $maxDownloadSpeed) {
                        ForEach(speedOptions, id: \.self) { speed in
                            Text(speedLabel(speed))
                                .tag(speed)
                        }
                    } label: { }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 100, alignment: .trailing)
                    .onChange(of: maxDownloadSpeed) { _, v in
                        SettingsStore.shared.maxDownloadSpeed = v
                    }
                }

                divider
            }

            card {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.body)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        LocalizedText(key: "Download Location")
                            .font(.body)
                        Spacer()
                        Button(LanguageManager.shared.localized("Select...")) { browsePath() }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)

                    Text(downloadPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(20)
    }

    private func browsePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = LanguageManager.shared.localized("Select download folder")
        panel.directoryURL = URL(fileURLWithPath: downloadPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadPath = url.path
        SettingsStore.shared.downloadPath = url.path
        // Save a security-scoped bookmark so the folder stays reachable on the
        // next launch (sandbox grants access only for the current session).
        SettingsStore.shared.downloadPathBookmark = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

private struct UpdatePane: View {
    @State private var model = UpdateModel.shared
    @AppStorage("autoUpdate") private var autoUpdate = true

    var body: some View {
        VStack(spacing: 16) {
            card {
                prefRow("info.circle", "Current Version") {
                    HStack(spacing: 10) {
                        Text(UpdateService.currentVersion)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        updateControl
                    }
                }

                divider

                prefRow("arrow.triangle.2.circlepath", "Auto check and download updates") {
                    Toggle("", isOn: $autoUpdate)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var updateControl: some View {
        switch model.status {
        case .idle:
            Button {
                Task { await model.checkForUpdates() }
            } label: {
                Text(LanguageManager.shared.localized("Detect Updates"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .checking:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                LocalizedText(key: "Checking for updates...")
                    .font(.caption)
            }

        case .upToDate:
            Label {
                LocalizedText(key: "You're up to date")
                    .font(.caption)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

        case .available(let release):
            Button {
                Task { await model.download(release) }
            } label: {
                Label(LanguageManager.shared.localized("Download Update"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(_, let progress):
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: progress)
                    .frame(width: 140)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .downloaded(_, let url):
            Button {
                Task { await model.install(url) }
            } label: {
                Label(LanguageManager.shared.localized("Install and Restart"), systemImage: "arrow.up.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
                if let dmg = model.downloadedDMG {
                    Button {
                        NSWorkspace.shared.open(dmg)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(LanguageManager.shared.localized("Open in Finder"))
                }
                Button {
                    Task { await model.checkForUpdates() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(LanguageManager.shared.localized("Retry"))
            }
        }
    }
}

private struct NotificationsPane: View {
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

                    prefRow("checkmark.circle.fill", "Download Completed") {
                        Toggle("", isOn: $notifyCompleted)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    divider

                    prefRow("xmark.circle.fill", "Download failed") {
                        Toggle("", isOn: $notifyFailed)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }

                    divider

                    prefRow("arrow.clockwise.circle", "Redownload Prompt") {
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
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?MacDL") {
            NSWorkspace.shared.open(url)
        }
    }
}

private func card(@ViewBuilder content: () -> some View) -> some View {
    VStack(spacing: 0) { content() }
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

private func prefRow<C: View>(_ icon: String, _ label: String, @ViewBuilder control: () -> C) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.body)
            .frame(width: 18)
            .foregroundStyle(.secondary)
        LocalizedText(key: label)
            .font(.body)
        Spacer()
        control()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
}

private var divider: some View { Divider().padding(.leading, 42) }
