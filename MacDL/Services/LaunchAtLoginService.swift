import Foundation
import ServiceManagement

// Launch at login via SMAppService (sandbox-safe, macOS 13+).
// Registering only takes effect when the app runs from /Applications; from build
// products the call throws and the toggle reverts.
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
