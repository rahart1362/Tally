import Foundation
import os

/// The `Launch.GlancePaint` interval (perf-app-runtime.md §2.4 L1→L4, §5.2): from `TallyApp.init`
/// (L1) to the first frame that shows cached content, the glance or the full projection, whichever
/// comes first (L4). `TallyPerfUITests` measures it with `XCTOSSignpostMetric(subsystem:
/// category:name:)`; `perf/budgets.json` holds its budget (≤ 300 ms, `TallyConfig.warmStartBudget`).
///
/// Inside it, three back-to-back phase intervals say where the time goes (report only):
/// - `Launch.ToTask`: `TallyApp.init` to the launch task's start (the first frame, the launch colour);
/// - `Launch.Resolve`: the launch task (L3: the lock setting, `accounts.json`, the glance, off the
///   main actor);
/// - `Launch.HomeRender`: the route switch (L4) to the painted glance.
///
/// Main actor: it begins in `App.init` and ends in a view's `onAppear`, both on the main thread. A
/// signpost is a few hundred nanoseconds, in Release as in Debug. Only the first `glancePainted()`
/// of a process ends the interval; a launch that goes to Welcome ends its phases and never the
/// interval.
@MainActor
public enum LaunchSignpost {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "dev.tally-app.tally"
    public static let category = "perf"
    public static let glancePaint: StaticString = "Launch.GlancePaint"
    public static let toTask: StaticString = "Launch.ToTask"
    public static let resolve: StaticString = "Launch.Resolve"
    public static let homeRender: StaticString = "Launch.HomeRender"

    private static let signposter = OSSignposter(subsystem: subsystem, category: category)
    private static var interval: OSSignpostIntervalState?
    private static var phase: (name: StaticString, state: OSSignpostIntervalState)?

    /// L1: `TallyApp.init`, before anything else runs.
    public static func begin() {
        guard interval == nil else { return }
        interval = signposter.beginInterval(glancePaint, id: signposter.makeSignpostID())
        enterPhase(toTask)
    }

    /// Ends the current phase and, while the launch interval is open, begins `next`. A no-op in a
    /// process that never called `begin()` (tests and previews).
    public static func enterPhase(_ next: StaticString?) {
        if let current = phase {
            phase = nil
            signposter.endInterval(current.name, current.state)
        }
        guard interval != nil, let next else { return }
        phase = (next, signposter.beginInterval(next, id: signposter.makeSignpostID()))
    }

    /// L4: the first frame with cached content (the Dashboard's glance or full projection).
    public static func glancePainted() {
        #if true || TALLY_TEST_HOOKS
        LaunchProbe.shared.painted()
        #endif
        guard let state = interval else { return }
        enterPhase(nil)
        interval = nil
        signposter.endInterval(glancePaint, state)
    }
}
