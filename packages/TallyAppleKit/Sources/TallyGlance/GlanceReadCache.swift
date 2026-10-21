import Foundation

/// One Keychain-backed glance read shared by every widget kind the extension process is asked
/// for, instead of one independent Keychain open per kind (PERF-FIX-2 item 1; perf1/report.md §4
/// opportunity 3; perf-app-runtime.md §8's open cross-lane Keychain-caching request). Every
/// `AppIntentConfiguration` kind `TallyWidgetsBundle` declares (`TallyWidgets.swift`: 5 widgets)
/// can be asked for a timeline or snapshot in the same extension process wake-up, and before this
/// fix each kind's own `GlanceProvider` called `GlanceWidgetSource.readFromAppGroup`
/// independently -- N kinds placed multiplied the per-refresh Keychain IPC count by N for what
/// is, in every practical case, the same moment's data (the architecture review's own framing:
/// `VaultKeyring.swift:30-45`'s Keychain round trip is "the dominant per-access cost").
///
/// This actor's cache lives exactly as long as the process -- "a per-process cache keyed by
/// scope, with the same lifetime as the extension process," the report's own proposed fix -- so
/// it needs no explicit invalidation or TTL: the system relaunches the extension process per
/// refresh in the ordinary case, and a fresh process starts with an empty cache. This changes
/// Keychain IPC count, not freshness: every kind still sees the data as of this invocation's one
/// real read, the same moment each kind's own independent read would otherwise have landed on.
///
/// A plain `actor` serialises both the single-flight de-dup (a second caller for a scope already
/// in flight awaits the same in-progress `Task` rather than starting another) and the cache
/// lookup, with no separate lock -- the same reasoning `VaultKeyring` itself gives for
/// serialising its own Keychain access.
actor GlanceReadCache {
    /// One instance per process: the widget extension's `GlanceIntentTimelineProvider` default
    /// uses this. Tests construct their own `GlanceReadCache()` so runs never share state.
    static let shared = GlanceReadCache()

    private var reads: [GlanceScope: Task<GlanceReadResult, Never>] = [:]
    /// How many times `using` actually ran a Keychain-backed read, not how many callers asked --
    /// the call-count probe `WidgetGlanceTests` uses to prove the shared read, the same way
    /// `HomeProjector.projectionCount` proves "recomputes exactly once" elsewhere.
    private(set) var realReadCount = 0

    /// `scope`'s glance, read at most once per process invocation. Every caller after the first
    /// for that scope -- concurrent or later, whatever widget kind -- gets the first call's own
    /// result (awaiting it if it is still in flight) instead of triggering another read.
    func read(_ scope: GlanceScope, using read: @Sendable (GlanceScope) async -> GlanceReadResult) async -> GlanceReadResult {
        if let existing = reads[scope] { return await existing.value }
        realReadCount += 1
        let task = Task { await read(scope) }
        reads[scope] = task
        return await task.value
    }
}
