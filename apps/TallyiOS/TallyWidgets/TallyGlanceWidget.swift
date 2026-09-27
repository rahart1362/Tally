import SwiftUI
import TallyDesignSystem
import WidgetKit

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

/// A timeline provider that reads nothing (WP-E01: "a placeholder timeline
/// that reads nothing"). It never touches the App Group container, so it
/// cannot race with, or depend on, the store work that lands separately.
struct PlaceholderTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

struct TallyGlanceWidgetView: View {
    let entry: PlaceholderEntry

    var body: some View {
        VStack(spacing: TallySpacing.sm) {
            TMark(size: 32)
            Text("Tally")
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textOnHero)
        }
        .containerBackground(TallyColor.bgBrand, for: .widget)
    }
}

struct TallyGlanceWidget: Widget {
    let kind = "TallyGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlaceholderTimelineProvider()) { entry in
            TallyGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Tally")
        .description("Placeholder. Live grades and due dates land in a later milestone.")
        .supportedFamilies([.systemSmall])
    }
}
