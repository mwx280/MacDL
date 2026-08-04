import Foundation

// What to do when a URL or filename already exists in the download list.
enum DuplicateDecision {
    case proceed
    case skip
    case resume
}

// Decides how a duplicate-add should proceed based on the existing download's
// status, showing the matching confirmation dialog. Isolated so the branching
// can be reasoned about (and later tested) without the add flow.
enum DuplicatePolicy {
    static func decide(for existing: Download) -> DuplicateDecision {
        switch existing.status {
        case .active, .waiting:
            _ = DialogPresenter.duplicateActive()
            return .skip
        case .paused:
            switch DialogPresenter.duplicatePaused() {
            case .resume: return .resume
            case .newDownload: return .proceed
            default: return .skip
            }
        case .completed:
            return DialogPresenter.duplicateCompleted() ? .proceed : .skip
        case .error, .stopped:
            let reason = DownloadErrorText.text(for: existing) ?? LanguageManager.shared.localized("Unknown error")
            return DialogPresenter.duplicateFailed(reason: reason) ? .proceed : .skip
        }
    }
}
