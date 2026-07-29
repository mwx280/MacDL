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
        .frame(width: 420, height: 180)
    }
}

private struct GeneralPane: View {
    @Environment(LanguageManager.self) var lang
    @AppStorage("appearance") private var appearance: Appearance = .system

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
            }
        }
        .padding(20)
    }
}

private struct DownloadPane: View {
    @State private var maxConnections: Int
    @State private var maxConcurrent: Int

    private let connectionOptions = [1, 2, 4, 8, 16, 32, 64]
    private let concurrentOptions = [1, 2, 3, 5, 10, 20]

    init() {
        _maxConnections = State(initialValue: SettingsStore.shared.maxConnections)
        _maxConcurrent = State(initialValue: SettingsStore.shared.maxConcurrentDownloads)
    }

    var body: some View {
        VStack(spacing: 16) {
            card {
                prefRow("number", "Max Connections") {
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
        }
        .padding(20)
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
