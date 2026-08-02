import SwiftUI

struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { ContentViewModel.shared.downloadFromClipboard() } label: {
            Label(title: { Text(verbatim: LanguageManager.shared.localized("Download from Clipboard")) }, icon: { Image(systemName: "arrow.down.doc") })
        }


        Button {
            openWindow(id: "main")
            // openWindow creates the window asynchronously; once it exists, activate
            // the app and bring it to the front (accessory mode doesn't do this itself).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
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

        SettingsLink {
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
}
