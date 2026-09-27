import WidgetKit

/// The WidgetKit extension entry point (architecture.md §3.1). Reads
/// **only** its own placeholder entry today — no App Group access, no
/// network, no Keychain — because `glance.v1` (the projection this widget
/// will eventually read) is written by `TallyStore`, which does not exist
/// yet (a later work package). WP-E01 scope is proving the extension target,
/// its entitlement and its Info.plist wiring build and install correctly.
@main
struct TallyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TallyGlanceWidget()
    }
}
