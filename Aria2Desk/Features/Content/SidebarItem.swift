enum SidebarItem: String, CaseIterable {
    case all
    case active
    case waiting
    case completed
    case stopped
    case settings

    var icon: String {
        switch self {
        case .all: "tray.full"
        case .active: "arrow.down.circle"
        case .waiting: "clock"
        case .completed: "checkmark.circle"
        case .stopped: "stop.circle"
        case .settings: "gearshape"
        }
    }

    var titleKey: String {
        switch self {
        case .all: "All Downloads"
        case .active: "Active"
        case .waiting: "Waiting"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .settings: "Settings"
        }
    }
}
