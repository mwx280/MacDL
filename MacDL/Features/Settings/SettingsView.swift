import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "General") }, icon: { Image(systemName: "gear") })
                }

            DownloadPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Download") }, icon: { Image(systemName: "arrow.down.circle") })
                }
        }
        .frame(width: 420, height: 260)
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
                    .frame(width: 140)
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
                    .frame(width: 140)
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
            .alert("Launch at Login", isPresented: $launchAtLoginFailed) {
                Button("OK", role: .cancel) { }
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
                    .frame(width: 72)
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
                    .frame(width: 72)
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
                    .frame(width: 100)
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
