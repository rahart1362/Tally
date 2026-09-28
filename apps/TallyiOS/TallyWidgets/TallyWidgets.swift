import SwiftUI
import TallyGlance
import WidgetKit

/// The WidgetKit extension (plan 06 step 11; perf-app-runtime.md §2.4 W1-W3). Both widgets read the
/// glance only, through `TallyGlance`: `SnapshotStore(root: <App Group>, sealer: VaultSealer(…,
/// mayCreateKeys: false), isOwner: false).loadGlance()`, with the widget-audience key alone. They
/// never decode the snapshot, use the network, build a `RefreshCoordinator` or read a credential,
/// and this target links no `TallyFeatures` (CI: scripts/ci/check_widget_isolation.py). Without a
/// Team ID (GO-LIVE GL-02) the App Group Keychain group is unavailable (-34018 on the CI
/// simulator) and both widgets show their placeholder text.
///
/// Deliberately one file: CI runs 36328840843 and 36329218945 failed to resolve `Widget` in a
/// second file of this target ("cannot find type 'Widget' in scope"). Everything else lives in the
/// `TallyGlance` package target.
@main
struct TallyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TallyNextUpWidget()
        TallyStandingWidget()
    }
}

/// "Next up" (insights-at-a-glance.md §1.5): no grades.
struct TallyNextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceWidgetKind.nextUp, provider: GlanceTimelineProvider()) { entry in
            NextUpWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Up")
        .description("The next thing due in your courses.")
        .supportedFamilies([.systemSmall])
    }
}

/// "Standing": the overall grade band, only if the user chose to show grades in widgets, and
/// hidden while the iPhone is locked (PMO R10).
struct TallyStandingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceWidgetKind.standing, provider: GlanceTimelineProvider()) { entry in
            StandingWidgetView(entry: entry)
        }
        .configurationDisplayName("Standing")
        .description("Your average grade band, if you choose to show grades in widgets. Hidden while your iPhone is locked.")
        .supportedFamilies([.systemSmall])
    }
}
