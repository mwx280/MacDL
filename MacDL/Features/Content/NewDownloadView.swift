import SwiftUI
import AppKit
import MacDLCore

// Data submitted when creating a new download: save path + default connection count + per-task thread/speed/resume state
struct NewDownloadPayload {
    let path: String
    let bookmark: Data?
    let connections: Int
    let connectionsByURL: [String: Int]
    let limits: [String: Int]
    let resumeStatus: [String: Bool]
}

struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String, NewDownloadPayload) -> Void
    @State private var model: NewDownloadModel
    @State private var downloadPath: String
    @State private var downloadBookmark: Data?
    @State private var hoveredURL: String?
    @State private var isDropTarget = false
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) var dismiss

    init(text: Binding<String>, onDownload: @escaping (String, NewDownloadPayload) -> Void) {
        _text = text
        self.onDownload = onDownload
        _downloadPath = State(initialValue: SettingsStore.shared.downloadPath)
        _downloadBookmark = State(initialValue: SettingsStore.shared.downloadPathBookmark)
        _model = State(initialValue: NewDownloadModel(
            defaultConnections: SettingsStore.shared.maxConnections,
            defaultSpeedLimit: 0))
    }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                Text(lang.localized("New Download"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(lang.localized("Paste links and they download"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            ZStack(alignment: .bottomTrailing) {
                dropZone
                if model.text.isEmpty && !model.clipboardHasURL {
                    Button { model.pasteFromClipboard() } label: {
                        Label(lang.localized("Paste from clipboard"), systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(10)
                }
            }

            if model.text.isEmpty && model.clipboardHasURL {
                clipboardBanner
            } else if model.hasInvalidLinks {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text(String(format: lang.localized("Recognized %lld links, %lld invalid"), model.validCount, model.invalidCount))
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Text(lang.localized("Task Queue"))
                    .font(.headline)
                Text("\(model.validTasks.count)")
                    .font(.caption2)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lang.localized("Each task configured independently"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if model.validTasks.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(model.validTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 210)
            }

            folderRow

            HStack(spacing: 10) {
                Button(lang.localized("Cancel")) { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onDownload(model.text, NewDownloadPayload(
                        path: downloadPath,
                        bookmark: downloadBookmark,
                        connections: model.defaultConnections,
                        connectionsByURL: model.connectionsByURL,
                        limits: model.limits,
                        resumeStatus: model.resumeStatus))
                    dismiss()
                } label: {
                    Text(lang.localized("Download"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .tint(.accentColor)
                .disabled(model.validTasks.isEmpty || model.hasInvalidLinks || downloadPath.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 420)
        .onChange(of: model.text) { _, newText in
            text = newText
            model.detectResumeSupport()
            model.detectClipboard()
        }
        .onAppear {
            if text.isEmpty {
                if let str = NSPasteboard.general.string(forType: .string),
                   NewDownloadModel.containsValidURL(in: str) {
                    model.text = str
                }
            } else {
                model.text = text
            }
            model.detectResumeSupport()
            model.detectClipboard()
        }
    }

    // MARK: - Components

    private var dropZone: some View {
        PlaceholderTextEditor(
            text: $model.text,
            placeholder: lang.localized("Paste download links here, one per line")
        )
        .frame(height: 64)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(isDropTarget ? 1 : 0.55), style: StrokeStyle(lineWidth: isDropTarget ? 1.5 : 1, dash: [6, 4]))
        }
        .dropDestination(for: String.self) { items, _ in
            model.appendURLs(items)
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private var clipboardBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.caption2).foregroundStyle(.tint)
            Text(lang.localized("Detected clipboard links")).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.pasteFromClipboard() } label: {
                Label(lang.localized("Fill"), systemImage: "doc.on.clipboard").font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.accentColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            Text(lang.localized("Paste download links to see them here"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var folderRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(downloadPath)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(downloadPath)
            Spacer(minLength: 8)
            Button(lang.localized("Change")) { browseFolder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func taskRow(_ task: NewDownloadModel.TaskInfo) -> some View {
        let isHovered = hoveredURL == task.url
        return HStack(spacing: 10) {
            Image(systemName: task.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(task.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if ContentViewModel.shared.downloads.contains(where: { $0.url == task.url }) {
                        Text(lang.localized("Already in Download List"))
                            .font(.system(size: 9))
                            .foregroundStyle(.purple)
                            .lineLimit(1)
                    }
                    if model.duplicatedNames.contains(task.name) {
                        Text(lang.localized("Will be renamed automatically"))
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Text(task.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                resumeLabel(for: task.url)
                HStack(spacing: 5) {
                    threadPicker(for: task.url)
                    speedPicker(for: task.url)
                }
            }
            if isHovered {
                Button { model.removeTask(task.url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(lang.localized("Remove this task"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.35))
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered in hoveredURL = isHovered ? task.url : nil }
    }

    @ViewBuilder
    private func resumeLabel(for url: String) -> some View {
        switch model.resumeStatus[url] {
        case true:
            Label(lang.localized("Resumable"), systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.green)
        case false:
            Label(lang.localized("Not Resumable · Single Thread"), systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.orange)
        default:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(lang.localized("Checking..."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func threadPicker(for url: String) -> some View {
        let locked = model.resumeStatus[url] == false
        return Picker(selection: Binding(
            get: { model.connections(for: url) },
            set: { model.connectionsByURL[url] = $0 }
        )) {
            ForEach([0, 1, 2, 4, 8, 16], id: \.self) { n in
                if n == 0 {
                    Text(lang.localized("Adaptive")).tag(n)
                } else {
                    Text(String(format: lang.localized("%lld Threads"), n)).tag(n)
                }
            }
        } label: { }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 74)
        .disabled(locked)
        .opacity(locked ? 0.55 : 1)
        .help(locked
            ? lang.localized("Non-resumable tasks use a single thread")
            : lang.localized("Parallel threads"))
    }

    private func speedPicker(for url: String) -> some View {
        Picker(selection: Binding(
            get: { model.speedLimit(for: url) },
            set: { model.limits[url] = $0 }
        )) {
            ForEach(speedOptions, id: \.self) { speed in
                Text(speedLabel(speed)).tag(speed)
            }
        } label: { }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 74)
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = lang.localized("Select download folder")
        panel.directoryURL = URL(fileURLWithPath: downloadPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadPath = url.path
        downloadBookmark = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
