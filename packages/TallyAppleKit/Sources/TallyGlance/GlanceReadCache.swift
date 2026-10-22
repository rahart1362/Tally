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
/// PMO review (2026-10-21): an entry is reused only within `maxAge` (2 s by default), long enough
/// to coalesce the kinds WidgetKit asks for in one wake-up (milliseconds apart), never long
/// enough to outlive the app's next refresh or a Sign Out & Erase. A widget extension process can
/// stay alive across timeline reloads, so a process-lifetime cache could keep serving a glance
/// after the app replaced it, or after sign-out removed it (grades on a signed-out Home Screen).
/// This changes Keychain IPC count, not freshness: every kind in one burst sees the data as of
/// that burst's one real read.
///
/// A plain `actor` serialises both the single-flight de-dup (a second caller for a scope already
/// in flight awaits the same in-progress `Task` rather than starting another) and the cache
/// lookup, with no separate lock -- the same reasoning `VaultKeyring` itself gives for
/// serialising its own Keychain access.
actor GlanceReadCache {
    /// One instance per process: the widget extension's `GlanceIntentTimelineProvider` default
    /// uses this. Tests construct their own `GlanceReadCache()` so runs never share state.
    static let shared = GlanceReadCache()
    /// How long one read answers later callers for the same scope (see the type's doc comment).
    static let defaultMaxAge: Duration = .seconds(2)
    private let maxAge: Duration
    private let clock = ContinuousClock()
    private var reads: [GlanceScope: (task: Task<GlanceReadResult, Never>, startedAt: ContinuousClock.Instant)] = [:]

    init(maxAge: Duration = GlanceReadCache.defaultMaxAge) {
        self.maxAge = maxAge
    }
    /// How many times `using` actually ran a Keychain-backed read, not how many callers asked --
    /// the call-count probe `WidgetGlanceTests` uses to prove the shared read, the same way
    /// `HomeProjector.projectionCount` proves "recomputes exactly once" elsewhere.
    private(set) var realReadCount = 0

    /// `scope`'s glance, read at most once per `maxAge` window. Every caller within the window for
    /// that scope, whatever widget kind, gets the first call's own result (awaiting it if it is
    /// still in flight) instead of triggering another read; after the window, a fresh read.
    func read(_ scope: GlanceScope, using read: @escaping @Sendable (GlanceScope) async -> GlanceReadResult) async -> GlanceReadResult {
        let now = clock.now
        if let existing = reads[scope], now - existing.startedAt < maxAge { return await existing.task.value }
        realReadCount += 1
        let task = Task { await read(scope) }
        reads[scope] = (task: task, startedAt: now)
        return await task.value
    }
}
