import Foundation

// What to do when a URL or filename already exists in the download list.
enum DuplicateDecision {
    case proceed
    case skip
    case resume
}

// Decides how a duplicate-add should proceed based on the existing download's
// status. The dialog prompts are injectable so the branching is unit-testable
// without presenting NSAlerts.
@MainActor
enum DuplicatePolicy {
    static func decide(
        for existing: Download,
        showDuplicateActive: () -> Void = { _ = DialogPresenter.duplicateActive() },
        showDuplicatePaused: () -> DownloadDialogResult = { DialogPresenter.duplicatePaused() },
        showDuplicateCompleted: () -> Bool = { DialogPresenter.duplicateCompleted() },
        showDuplicateFailed: (String) -> Bool = { DialogPresenter.duplicateFailed(reason: $0) }
    ) -> DuplicateDecision {
        switch existing.status {
        case .active, .waiting:
            showDuplicateActive()
            return .skip
        case .paused:
            switch showDuplicatePaused() {
            case .resume: return .resume
            case .newDownload: return .proceed
            default: return .skip
            }
        case .completed:
            return showDuplicateCompleted() ? .proceed : .skip
        case .error, .stopped:
            let reason = DownloadErrorText.text(for: existing) ?? LanguageManager.shared.localized("Unknown error")
            return showDuplicateFailed(reason) ? .proceed : .skip
        }
    }
}
