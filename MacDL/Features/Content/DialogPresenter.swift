import AppKit

// Result of a multi-button confirmation alert.
enum DownloadDialogResult {
    case ok
    case resume
    case cancel
}

// Central NSAlert construction so the app's confirmation dialogs share one
// implementation and can be re-tested through a single seam.
@MainActor
enum DialogPresenter {
    /// Duplicate URL already queued / downloading.
    static func duplicateActive() -> Bool {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Duplicate URL")
        alert.informativeText = LanguageManager.shared.localized("The URL is already in the download queue")
        alert.addButton(withTitle: LanguageManager.shared.localized("OK"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Duplicate is paused: offer Resume / Cancel.
    static func duplicatePaused() -> DownloadDialogResult {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Paused Download")
        alert.informativeText = LanguageManager.shared.localized("A paused download for this file already exists. Resume it?")
        alert.addButton(withTitle: LanguageManager.shared.localized("Resume"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? .resume : .cancel
    }

    /// Duplicate already completed: offer Download Again / Cancel.
    static func duplicateCompleted() -> Bool {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Completed Download")
        alert.informativeText = LanguageManager.shared.localized("This file has already been downloaded. Download again?")
        alert.addButton(withTitle: LanguageManager.shared.localized("Download Again"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Duplicate previously failed: offer Retry / Cancel.
    static func duplicateFailed(reason: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Failed Download")
        alert.informativeText = String(format: LanguageManager.shared.localized("Previous download failed: %@. Retry?"), reason)
        alert.addButton(withTitle: LanguageManager.shared.localized("Retry"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Pausing a download that cannot resume.
    static func confirmPauseNonResumable() -> Bool {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Pause non-resumable download?")
        alert.informativeText = LanguageManager.shared.localized("This download does not support resuming. Pausing it means it must restart from the beginning. Pause anyway?")
        alert.addButton(withTitle: LanguageManager.shared.localized("Pause"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Re-download confirmation. When the destination file already exists the
    /// dialog warns it will be overwritten.
    static func confirmRedownload(filename: String, fileExists: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Redownload")
        if fileExists {
            alert.informativeText = String(
                format: LanguageManager.shared.localized("%@ already exists and will be overwritten. Download it again?"),
                filename)
        } else {
            alert.informativeText = String(
                format: LanguageManager.shared.localized("Download %@ again?"),
                filename)
        }
        alert.addButton(withTitle: LanguageManager.shared.localized("Redownload"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Bulk delete with a "also remove files" checkbox.
    static func confirmBulkDelete(count: Int) -> (confirmed: Bool, deleteFiles: Bool) {
        let alert = NSAlert()
        alert.messageText = String(format: LanguageManager.shared.localized("Are you sure you want to delete %lld download(s)?"), Int64(count))
        alert.alertStyle = .warning
        alert.addButton(withTitle: LanguageManager.shared.localized("Delete"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        let cb = NSButton(checkboxWithTitle: LanguageManager.shared.localized("Also remove downloaded files"), target: nil, action: nil)
        cb.state = .on
        alert.accessoryView = cb
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        return (confirmed, cb.state == .on)
    }
}
