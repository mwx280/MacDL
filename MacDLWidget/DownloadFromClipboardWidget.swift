import SwiftUI
import WidgetKit

// Tapping the widget hands whatever download link the user copied to MacDL
// through the macdl://clipboard deep link. No App Group needed: the clipboard
// is the shared channel, and MacDL reads it on arrival.
struct DownloadFromClipboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClipboardDownload", provider: ClipboardDownloadProvider()) { _ in
            DownloadFromClipboardWidgetView()
        }
        .configurationDisplayName("Download from Clipboard")
        .description("Copy a download link, then tap the widget to add it to MacDL.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClipboardDownloadEntry: TimelineEntry {
    let date: Date
}

struct ClipboardDownloadProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipboardDownloadEntry {
        ClipboardDownloadEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ClipboardDownloadEntry) -> Void) {
        completion(ClipboardDownloadEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipboardDownloadEntry>) -> Void) {
        completion(Timeline(entries: [ClipboardDownloadEntry(date: Date())], policy: .never))
    }
}

struct DownloadFromClipboardWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.tint.opacity(0.18))
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.title3)
                }
                .frame(width: 36, height: 36)
                Spacer()
            }
            Text(verbatim: "MacDL")
                .font(.headline)
            Text("Download from Clipboard")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Copy a link, then tap")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "macdl://clipboard"))
    }
}
