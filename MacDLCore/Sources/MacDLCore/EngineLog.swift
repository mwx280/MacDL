import os

// Unified logging. One subsystem (the app's bundle id) with per-area categories,
// so Console.app can filter to MacDL and hide the noisy Network.framework lines.
//
// Level policy:
//  - .debug: per-chunk start/response and periodic status (thousands of lines)
//  - .notice: chunk done, dispatch, probe decisions, retries
//  - .error: permanent failures and aborts
public enum EngineLog {
    public static let manager = Logger(subsystem: "com.xiaowu.MacDL", category: "engine.manager")
    public static let chunk = Logger(subsystem: "com.xiaowu.MacDL", category: "engine.chunk")
    public static let app = Logger(subsystem: "com.xiaowu.MacDL", category: "app")
}
