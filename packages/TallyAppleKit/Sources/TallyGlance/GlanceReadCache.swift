import Foundation
import TallyStore

/// SEC2-10: a cheap (no Keychain, no decryption) fingerprint of whatever `GlanceReadCache` must
/// re-check before reusing a cached read within `maxAge` — the account directory listing, and
/// which of those directories currently have a glance file. Two captures that are `==` are safe
/// to treat as "nothing changed since the cached read began"; one that differs means a purge, a
/// sign-out or a fresh sign-in landed in between, so the cache must not serve the old result even
/// though it is still within its time window.
///
/// `.unchecked` is the default every existing caller (and both pre-SEC2-10 tests) gets: always
/// equal to itself, so `read(_:using:)` keeps its original `maxAge`-only behaviour unless a caller
/// opts into the real check (`GlanceWidgetSource.readFromAppGroup` does).
struct GlanceCacheSignature: Equatable, Sendable {
    private let accountDirectories: [String]
    private let directoriesWithGlance: [String]

    static let unchecked = GlanceCacheSignature(accountDirectories: [], directoriesWithGlance: [])

    /// `storeRoot` is the same App Group root `GlanceReader` would read; `nil` (no App Group
    /// entitlement) always signatures the same way, so it never falsely looks "changed."
    static func capture(storeRoot: URL?) -> GlanceCacheSignature {
        guard let storeRoot else { return GlanceCacheSignature(accountDirectories: [], directoriesWithGlance: []) }
        let names = GlanceReader.accountKeys(in: storeRoot).map(\.rawValue).sorted()
        let accountsDirectory = storeRoot.appendingPathComponent("accounts", isDirectory: true)
        let withGlance = names.filter {
            FileManager.default.fileExists(atPath: accountsDirectory.appendingPathComponent($0)
                .appendingPathComponent(StoreLayout.fileName(.glance)).path)
        }
        return GlanceCacheSignature(accountDirectories: names, directoriesWithGlance: withGlance)
    }
}

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
    private var reads: [GlanceScope: (task: Task<GlanceReadResult, Never>, startedAt: ContinuousClock.Instant,
                                       signature: GlanceCacheSignature)] = [:]

    init(maxAge: Duration = GlanceReadCache.defaultMaxAge) {
        self.maxAge = maxAge
    }
    /// How many times `using` actually ran a Keychain-backed read, not how many callers asked --
    /// the call-count probe `WidgetGlanceTests` uses to prove the shared read, the same way
    /// `HomeProjector.projectionCount` proves "recomputes exactly once" elsewhere.
    private(set) var realReadCount = 0

    /// `scope`'s glance, read at most once per `maxAge` window. Every caller within the window for
    /// that scope, whatever widget kind, gets the first call's own result (awaiting it if it is
    /// still in flight) instead of triggering another read -- UNLESS `signature`'s freshly
    /// captured value no longer matches the one the cached read started with (SEC2-10: the glance
    /// file is gone, or the account directory listing changed), in which case this starts a new
    /// read even though the window has not passed. `signature` defaults to `.unchecked` (always
    /// equal to itself), so a caller that never supplies one keeps the original, window-only
    /// behaviour.
    func read(_ scope: GlanceScope, signature: @Sendable () -> GlanceCacheSignature = { .unchecked },
             using read: @escaping @Sendable (GlanceScope) async -> GlanceReadResult) async -> GlanceReadResult {
        let now = clock.now
        let currentSignature = signature()
        if let existing = reads[scope], now - existing.startedAt < maxAge, existing.signature == currentSignature {
            return await existing.task.value
        }
        realReadCount += 1
        let task = Task { await read(scope) }
        reads[scope] = (task: task, startedAt: now, signature: currentSignature)
        return await task.value
    }
}
