import SwiftUI

@main
struct Aria2DeskApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(LanguageManager.shared)
        }
    }
}
