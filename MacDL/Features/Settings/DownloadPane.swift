import SwiftUI
import AppKit

struct DownloadPane: View {
    @State private var maxConnections: Int
    @State private var maxConcurrent: Int
    @State private var downloadPath: String
    @State private var maxDownloadSpeed: Int
    @AppStorage("autoResumeOnLaunch") private var autoResumeOnLaunch = false

    private let connectionOptions = [0, 1, 2, 4, 8] // 0 = Auto
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
                prefRow("number", "Default Max Connections", description: "Default Max Connections description", color: .teal) {
                    Picker(selection: $maxConnections) {
                        ForEach(connectionOptions, id: \.self) { n in
                            if n == 0 {
                                LocalizedText(key: "Auto").tag(n)
                            } else {
                                Text("\(n)").tag(n)
                            }
                        }
                    } label: { }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .frame(minWidth: 88, alignment: .trailing)
                    .onChange(of: maxConnections) { _, v in
                        SettingsStore.shared.maxConnections = v
                    }
                }

                divider

                prefRow("arrow.down.to.line", "Max Downloads", description: "Max Downloads description", color: .green) {
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

                divider

                prefRow("play.circle", "Resume Downloads on Launch", description: "Resume Downloads on Launch description", color: .blue) {
                    Toggle("", isOn: $autoResumeOnLaunch)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }

            card {
                prefRow("arrow.down", "Download Limit", description: "Download Limit description", color: .red) {
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
                            .foregroundStyle(.yellow)
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
