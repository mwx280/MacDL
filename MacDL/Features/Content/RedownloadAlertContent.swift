import SwiftUI

// Centered content for the re-download confirmation alert. NSAlert's default
// message/icon are left-aligned; hosting a SwiftUI layout in the accessory view
// lets us center the icon, title and body text.
struct RedownloadAlertContent: View {
    let filename: String
    let fileExists: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: fileExists ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(fileExists ? Color.yellow : Color.accentColor)
            Text(LanguageManager.shared.localized("Redownload"))
                .font(.title3.weight(.semibold))
            Text(fileExists
                 ? String(format: LanguageManager.shared.localized("%@ already exists and will be overwritten. Download it again?"), filename)
                 : String(format: LanguageManager.shared.localized("Download %@ again?"), filename))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 280)
        .padding(.top, 4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}
