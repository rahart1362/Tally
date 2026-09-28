import Foundation
import os

/// The `Launch.GlancePaint` interval (perf-app-runtime.md §2.4 L1→L4, §5.2): from `TallyApp.init`
/// (L1) to the first frame that shows cached content, the glance or the full projection, whichever
/// comes first (L4). `TallyPerfUITests` measures it with `XCTOSSignpostMetric(subsystem:
/// category:name:)`; `perf/budgets.json` holds its budget (≤ 300 ms, `TallyConfig.warmStartBudget`).
///
/// Main actor: it begins in `App.init` and ends in a view's `onAppear`, both on the main thread. A
/// signpost is a few hundred nanoseconds, in Release as in Debug. Only the first `glancePainted()`
/// of a process ends the interval; a launch that goes to Welcome never ends it.
@MainActor
public enum LaunchSignpost {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "dev.tally-app.tally"
    public static let category = "perf"
    public static let glancePaint: StaticString = "Launch.GlancePaint"

    private static let signposter = OSSignposter(subsystem: subsystem, category: category)
    private static var interval: OSSignpostIntervalState?

    /// L1: `TallyApp.init`, before anything else runs.
    public static func begin() {
        guard interval == nil else { return }
        interval = signposter.beginInterval(glancePaint, id: signposter.makeSignpostID())
    }

    /// L4: the first frame with cached content (the Dashboard's glance or full projection).
    public static func glancePainted() {
        #if DEBUG || TALLY_TEST_HOOKS
        LaunchProbe.shared.painted()
        #endif
        guard let state = interval else { return }
        interval = nil
        signposter.endInterval(glancePaint, state)
    }
}
