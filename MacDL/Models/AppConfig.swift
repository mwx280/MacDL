import Foundation

import Foundation
import Darwin

struct AppConfig {
    // Real user Downloads folder. Under the sandbox NSHomeDirectory() and
    // FileManager.urls(for:.downloadsDirectory) both resolve into the container,
    // so we look up the real home from the password database and let the
    // downloads entitlement grant access to it.
    static let defaultDownloadDir: String = {
        if let pw = getpwuid(getuid()) {
            return String(cString: pw.pointee.pw_dir) + "/Downloads"
        }
        return NSHomeDirectory() + "/Downloads"
    }()
}
