import SwiftUI
import AppKit

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button { ContentViewModel.shared.downloadFromClipboard() } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Download from Clipboard")) }, icon: { Image(systemName: "arrow.down.doc") })
        }

        Divider()

        Button {
            MacDLWindowHider.shared.markUserWantsVisible()
            openWindow(id: "main")
            // openWindow creates the window asynchronously; once it exists, activate
            // the app and bring it to the front (accessory mode doesn't do this itself).
            // Target the main window only: a hidden settings window kept alive by
            // SwiftUI would otherwise be picked by the first key-capable window.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                NSApp.activate(ignoringOtherApps: true)
                MacDLWindowHider.findMainWindow()?.makeKeyAndOrderFront(nil)
            }
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

    private var mainWindow: NSWindow? {
        // The main window is tagged with identifier "main" when it appears.
        // Fall back to the app-title match (the settings window's title is
        // "MacDL Settings", never exactly "MacDL"), then to any non-settings
        // key-capable window as a last resort.
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.title == "MacDL" }
            ?? NSApp.windows.first { $0.canBecomeKey && !isSettingsWindow($0) }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        let t = window.title.lowercased()
        return t.contains("settings") || t.contains("preferences") || t.contains("设置")
    }
}
