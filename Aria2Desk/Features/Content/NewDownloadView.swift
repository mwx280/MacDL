import SwiftUI
import AppKit

struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String, String, Int) -> Void
    @State private var downloadPath: String
    @State private var connections: Int
    @State private var refresh = UUID()
    @Environment(\.dismiss) var dismiss

    private let connectionOptions = [1, 2, 4, 8, 16]

    init(text: Binding<String>, onDownload: @escaping (String, String, Int) -> Void) {
        _text = text
        self.onDownload = onDownload
        _downloadPath = State(initialValue: SettingsStore.shared.downloadPath)
        _connections = State(initialValue: SettingsStore.shared.maxConnections)
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
                    .help("Browse...")
                }
            }

            HStack {
                LocalizedText(key: "Connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(selection: $connections) {
                    ForEach(connectionOptions, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                } label: { }
                .labelsHidden()
                .frame(width: 72)
            }

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(LanguageManager.shared.localized("Download")) {
                    onDownload(text, downloadPath, connections)
                    SettingsStore.shared.downloadPath = downloadPath
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 380)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
        .onAppear {
            guard text.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            guard let str = pasteboard.string(forType: .string) else { return }
            let hasURL = str.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
            if hasURL { text = str }
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
}
