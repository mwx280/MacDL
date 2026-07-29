import SwiftUI

@main
struct Aria2DeskApp: App {
    init() {
        Aria2RPCClient.shared.startEngine()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(LanguageManager.shared)
                .environment(Aria2RPCClient.shared)
        }
    }
}
