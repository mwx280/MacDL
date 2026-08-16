import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            if ContentViewModel.shared.downloadFromClipboard() {
                MacDLApp.showWindow()
            }
        } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Download from Clipboard")) }, icon: { Image(systemName: "arrow.down.doc") })
        }

        Divider()

        Button {
            MacDLApp.showWindow()
        } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Show Window")) }, icon: { Image(systemName: "macwindow") })
        }

        Button { MacDLApp.hideWindow() } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Hide Window")) }, icon: { Image(systemName: "rectangle.dashed") })
        }

        Button { MacDLApp.showAbout() } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("About")) }, icon: { Image(systemName: "info.circle") })
        }

        Divider()

        Button {
            openSettings()
            presentSettings()
        } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Preferences")) }, icon: { Image(systemName: "gearshape") })
        }

        Divider()

        Button {
            if MacDLApp.quitWithCheck() {
                NSApp.terminate(nil)
            }
        } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Quit")) }, icon: { Image(systemName: "xmark.rectangle") })
        }
    }

    // Opens the Settings window via openSettings() first; once it exists,
    // activate the app and bring the settings window to the front (accessory
    // mode doesn't raise windows by itself).
    private func presentSettings() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { isSettingsWindow($0) }?.makeKeyAndOrderFront(nil)
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        let t = window.title.lowercased()
        return t.contains("settings") || t.contains("preferences") || t.contains("设置")
    }
}
