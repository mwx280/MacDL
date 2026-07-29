import SwiftUI

struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String) -> Void
    @State private var refresh = UUID()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text(LanguageManager.shared.localized("New Download"))
                .font(.headline)

            PlaceholderTextEditor(
                text: $text,
                placeholder: LanguageManager.shared.localized("One URL per line, multiple URLs supported")
            )
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 1)
            }

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(LanguageManager.shared.localized("Download")) {
                    onDownload(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 260)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
        .onAppear {
            guard text.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            guard let str = pasteboard.string(forType: .string) else { return }
            let hasURL = str.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
            if hasURL { text = str }
        }
    }
}
