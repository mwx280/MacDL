import SwiftUI
import AppKit

struct UpdatePane: View {
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

                prefRow("arrow.triangle.2.circlepath", "Auto check and download updates", description: "Auto check and download updates description") {
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
