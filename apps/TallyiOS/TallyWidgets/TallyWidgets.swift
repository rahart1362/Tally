import SwiftUI
import TallyDesignSystem
import WidgetKit

/// The WidgetKit extension entry point (architecture.md §3.1). Reads
/// **only** its own placeholder entry today — no App Group access, no
/// network, no Keychain — because `glance.v1` (the projection this widget
/// will eventually read) is written by `TallyStore`, which does not exist
/// yet (a later work package). WP-E01 scope is proving the extension
/// target, its entitlement and its Info.plist wiring build and install
/// correctly.
///
/// Deliberately one file, not two: CI run 36329218945 showed that splitting
/// the bundle entry point (`@main ...: WidgetBundle`) into its own file
/// from the `Widget` conformance it references made `Widget`/`WidgetBundle`
/// unresolvable in that file specifically ("cannot find type 'Widget' in
/// scope"), even though the sibling file's identical `import WidgetKit`
/// resolved the same types fine in the same target/compile. That symptom
/// didn't change after adding `-parse-as-library` (ruled out as the cause)
/// and points at Swift's explicit-module-build dependency scan rather than
/// anything in this source; consolidating into one file removes the
/// multi-file scan path entirely.
@main
struct TallyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TallyGlanceWidget()
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

/// A timeline provider that reads nothing (WP-E01: "a placeholder timeline
/// that reads nothing"). It never touches the App Group container, so it
/// cannot race with, or depend on, the store work that lands separately.
/// MUTATION MA2: an isolated deinit.
actor MutationA2Probe { isolated deinit {} }

struct PlaceholderTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        _ = MutationA2Probe() // MUTATION MA2: keeps the probe live
        return PlaceholderEntry(date: .now)
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
