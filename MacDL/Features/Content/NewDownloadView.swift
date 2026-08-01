import SwiftUI
import AppKit

struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String, String, Int, Int) -> Void
    @State private var downloadPath: String
    @State private var downloadLimit: Int
    @State private var downloadConnections: Int
    @State private var resumeSupported: Bool?
    @State private var refresh = UUID()
    @Environment(\.dismiss) var dismiss

    init(text: Binding<String>, onDownload: @escaping (String, String, Int, Int) -> Void) {
        _text = text
        self.onDownload = onDownload
        _downloadPath = State(initialValue: SettingsStore.shared.downloadPath)
        _downloadLimit = State(initialValue: SettingsStore.shared.maxDownloadSpeed)
        _downloadConnections = State(initialValue: SettingsStore.shared.maxConnections)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(.tint)

            Text(LanguageManager.shared.localized("New Download"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(key: "Download URLs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                PlaceholderTextEditor(
                    text: $text,
                    placeholder: LanguageManager.shared.localized("One URL per line, multiple URLs supported")
                )
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                LocalizedText(key: "Save to")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("", text: $downloadPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    Button { browseFolder() } label: {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(LanguageManager.shared.localized("Browse..."))
                }
            }

            Group {
                prefRow("arrow.down", "Download Limit") {
                    Picker(selection: $downloadLimit) {
                        ForEach(speedOptions, id: \.self) { speed in
                            Text(speedLabel(speed))
                                .tag(speed)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(width: 100)
                }

                if resumeSupported == false {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.body)
                            .frame(width: 18)
                            .foregroundStyle(.orange)
                        LocalizedText(key: "Server does not support resume, will download with a single connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    prefRow("square.grid.3x2", "Connections") {
                        Picker(selection: $downloadConnections) {
                            ForEach([1, 2, 4, 8], id: \.self) { count in
                                Text("\(count)")
                                    .tag(count)
                            }
                        } label: { }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(LanguageManager.shared.localized("Download")) {
                    onDownload(text, downloadPath, downloadLimit, resumeSupported == false ? 1 : downloadConnections)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 440)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
        .onChange(of: text) { _, _ in
            detectResumeSupport()
        }
        .onAppear {
            guard text.isEmpty else {
                detectResumeSupport()
                return
            }
            let pasteboard = NSPasteboard.general
            guard let str = pasteboard.string(forType: .string) else { return }
            let hasURL = str.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
            if hasURL { text = str }
            detectResumeSupport()
        }
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
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = LanguageManager.shared.localized("Select download folder")
        panel.directoryURL = URL(fileURLWithPath: downloadPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadPath = url.path
    }

    private func detectResumeSupport() {
        guard let first = text.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && ($0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://")) }),
            let url = URL(string: first)
        else {
            resumeSupported = nil
            return
        }
        resumeSupported = nil
        var req = URLRequest(url: url)
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let task = URLSession.shared.dataTask(with: req) { _, response, error in
            let result: Bool?
            if error == nil, let http = response as? HTTPURLResponse {
                result = http.statusCode == 206
            } else {
                result = nil
            }
            DispatchQueue.main.async { self.resumeSupported = result }
        }
        task.resume()
    }
}
