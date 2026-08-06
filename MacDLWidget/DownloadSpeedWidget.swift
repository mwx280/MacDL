import SwiftUI
import WidgetKit

// Placeholder widget: establishes the WidgetKit extension so the widget can be
// added to the desktop / notification center. The real download-speed content
// lands here later.
struct DownloadSpeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DownloadSpeed", provider: DownloadSpeedProvider()) { _ in
            DownloadSpeedPlaceholderView()
        }
        .configurationDisplayName("Download Speed")
        .description("Shows the overall download speed.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DownloadSpeedEntry: TimelineEntry {
    let date: Date
}

struct DownloadSpeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> DownloadSpeedEntry {
        DownloadSpeedEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (DownloadSpeedEntry) -> Void) {
        completion(DownloadSpeedEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DownloadSpeedEntry>) -> Void) {
        completion(Timeline(entries: [DownloadSpeedEntry(date: Date())], policy: .never))
    }
}

struct DownloadSpeedPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.title2)
            Text("MacDL")
                .font(.headline)
            Text("—")
                .font(.title)
            Text("Total speed coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}
