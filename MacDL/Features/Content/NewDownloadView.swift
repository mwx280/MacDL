import SwiftUI
import AppKit
import MacDLCore

// 新建下载时提交的数据：保存路径 + 全局连接数 + 每任务限速/续传状态
struct NewDownloadPayload {
    let path: String
    let bookmark: Data?
    let connections: Int
    let limits: [String: Int]
    let resumeStatus: [String: Bool]
}

struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String, NewDownloadPayload) -> Void
    @State private var downloadPath: String
    @State private var downloadBookmark: Data?
    @State private var downloadConnections: Int
    @State private var resumeStatus: [String: Bool] = [:]
    @State private var limits: [String: Int] = [:]
    @State private var probedURLs: Set<String> = []
    @State private var refresh = UUID()
    @Environment(\.dismiss) var dismiss

    init(text: Binding<String>, onDownload: @escaping (String, NewDownloadPayload) -> Void) {
        _text = text
        self.onDownload = onDownload
        _downloadPath = State(initialValue: SettingsStore.shared.downloadPath)
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

            // 卡片：URL 输入
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

                if !queueLines.isEmpty && !inputIsValid {
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

            // 卡片：任务队列（始终显示，无任务时占位）
            fieldCard {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LocalizedText(key: "Queue")
                        .font(.headline)
                    Text(String(format: LanguageManager.shared.localized("%lld downloads"), Int64(validTasks.count)))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([1, 2, 4, 8], id: \.self) { n in
                            connectionChip(n)
                        }
                    }
                }

                Divider()

                if validTasks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        LocalizedText(key: "Paste download links to see them here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(validTasks, id: \.url) { task in
                                HStack(spacing: 8) {
                                    Image(systemName: task.icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(.tint)
                                        .frame(width: 20)
                                    Text(task.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    resumeBadge(for: task.url)
                                    speedChip(for: task.url)
                                }
                                .padding(8)
                                .background(.quaternary.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 150)
                }
            }

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(LanguageManager.shared.localized("Download")) {
                    onDownload(text, NewDownloadPayload(
                        path: downloadPath,
                        bookmark: downloadBookmark,
                        connections: downloadConnections,
                        limits: limits,
                        resumeStatus: resumeStatus))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!inputIsValid)
            }
        }
        .padding(18)
        .frame(width: 420, height: 540)
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

    // MARK: - 数据

    private var queueLines: [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // 每个非空行必须是合法 http/https 链接（含主机）
    private var inputIsValid: Bool {
        let lines = queueLines
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

    private var validTasks: [(url: String, name: String, icon: String)] {
        queueLines.compactMap { line -> (url: String, name: String, icon: String)? in
            guard let url = URL(string: line),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil
            else { return nil }
            let name = url.lastPathComponent
            let filename = name.isEmpty ? (url.host ?? line) : name
            let icon = Download(filename: filename, url: line).fileTypeIcon
            return (line, filename, icon)
        }
    }

    // 逐 URL 探测续传能力
    private func detectResumeSupport() {
        for line in validTasks.map(\.url) where !probedURLs.contains(line) {
            probedURLs.insert(line)
            resumeStatus[line] = nil
            guard let url = URL(string: line) else { continue }
            var req = URLRequest(url: url)
            req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            req.timeoutInterval = 5
            URLSession.shared.dataTask(with: req) { _, response, error in
                let result: Bool?
                if error == nil, let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 206: result = true
                    case 200..<300: result = false
                    case 429: result = nil // rate-limited: transient, not 'not resumable'
                    case 500..<600: result = nil // server error: transient
                    default: result = false // other 4xx: truly not resumable
                    }
                } else {
                    result = nil
                }
                DispatchQueue.main.async { self.resumeStatus[line] = result }
            }.resume()
        }
    }

    // MARK: - 组件

    @ViewBuilder
    private func resumeBadge(for url: String) -> some View {
        switch resumeStatus[url] {
        case true:
            badge("arrow.clockwise", "Resumable", .green)
        case false:
            badge("exclamationmark.triangle", "Not Resumable", .orange)
        default:
            badge(nil, "Checking...", .gray)
        }
    }

    private func badge(_ icon: String?, _ key: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9))
            }
            LocalizedText(key: key).font(.system(size: 10))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .foregroundStyle(color)
    }

    private func speedChip(for url: String) -> some View {
        Picker(selection: Binding(
            get: { limits[url] ?? SettingsStore.shared.maxDownloadSpeed },
            set: { limits[url] = $0 }
        )) {
            ForEach(speedOptions, id: \.self) { speed in
                Text(speedLabel(speed)).tag(speed)
            }
        } label: { }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 96)
        .controlSize(.small)
    }

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
}
