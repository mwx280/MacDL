import SwiftUI
import AppKit

struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String, String, Data?, Int, Int) -> Void
    @State private var downloadPath: String
    @State private var downloadBookmark: Data?
    @State private var downloadLimit: Int
    @State private var downloadConnections: Int
    @State private var resumeSupported: Bool?
    @State private var refresh = UUID()
    @Environment(\.dismiss) var dismiss

    init(text: Binding<String>, onDownload: @escaping (String, String, Data?, Int, Int) -> Void) {
        _text = text
        self.onDownload = onDownload
        _downloadPath = State(initialValue: SettingsStore.shared.downloadPath)
        _downloadLimit = State(initialValue: SettingsStore.shared.maxDownloadSpeed)
        _downloadConnections = State(initialValue: SettingsStore.shared.maxConnections)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text(LanguageManager.shared.localized("New Download"))
                    .font(.headline)
            }

            // 卡片 1：URL + 内嵌摘要/无效提示
            fieldCard {
                cardLabel("link", "Download URLs")
                PlaceholderTextEditor(
                    text: $text,
                    placeholder: LanguageManager.shared.localized("One URL per line, multiple URLs supported")
                )
                .frame(height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                }

                if !nonEmptyLines.isEmpty {
                    if inputIsValid {
                        let names = summaryFilenames
                        if let first = names.first {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(first)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if names.count > 1 {
                                    Text(String(format: LanguageManager.shared.localized("+%lld more"), Int64(names.count - 1)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                resumeBadge
                            }
                            .padding(8)
                            .background(.quaternary.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            LocalizedText(key: "Invalid download link")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }

            // 卡片 2：保存位置
            fieldCard {
                cardLabel("folder", "Save to")
                HStack(spacing: 6) {
                    TextField("", text: $downloadPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button { browseFolder() } label: {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(LanguageManager.shared.localized("Browse..."))
                }
            }

            // 卡片 3：选项
            fieldCard {
                HStack {
                    cardLabel("gauge", "Download Limit")
                    Spacer()
                    Picker(selection: $downloadLimit) {
                        ForEach(speedOptions, id: \.self) { speed in
                            Text(speedLabel(speed))
                                .tag(speed)
                        }
                    } label: { }
                    .labelsHidden()
                    .frame(width: 110)
                }

                Divider()

                if resumeSupported == false {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.body)
                            .foregroundStyle(.orange)
                        LocalizedText(key: "Server does not support resume, will download with a single connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    HStack {
                        cardLabel("square.grid.3x2", "Connections")
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach([1, 2, 4, 8], id: \.self) { n in
                                connectionChip(n)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(LanguageManager.shared.localized("Download")) {
                    onDownload(text, downloadPath, downloadBookmark, downloadLimit, resumeSupported == false ? 1 : downloadConnections)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!inputIsValid)
            }
        }
        .padding(18)
        .frame(width: 400, height: 470)
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

    // MARK: - 摘要条数据

    private var nonEmptyLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // 每个非空行都必须是合法的 http/https 链接（含主机），否则视为无效
    private var inputIsValid: Bool {
        let lines = nonEmptyLines
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { line in
            guard let url = URL(string: line),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil
            else { return false }
            return true
        }
    }

    private var firstURL: String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty && ($0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://")) })
    }

    // 摘要条显示所有已解析的文件名（每个合法链接一个）
    private var summaryFilenames: [String] {
        nonEmptyLines.compactMap { line in
            guard let url = URL(string: line) else { return nil }
            let name = url.lastPathComponent
            return name.isEmpty ? (url.host ?? line) : name
        }
    }

    @ViewBuilder
    private var resumeBadge: some View {
        switch resumeSupported {
        case true:
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise").font(.caption2)
                LocalizedText(key: "Resumable").font(.caption2)
            }
            .foregroundStyle(.green)
        case false:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle").font(.caption2)
                LocalizedText(key: "Not Resumable").font(.caption2)
            }
            .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    // MARK: - 组件

    private func connectionChip(_ n: Int) -> some View {
        Button {
            downloadConnections = n
        } label: {
            Text("\(n)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(downloadConnections == n ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(downloadConnections == n ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func fieldCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            }
    }

    private func cardLabel(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            LocalizedText(key: label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        downloadBookmark = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
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
