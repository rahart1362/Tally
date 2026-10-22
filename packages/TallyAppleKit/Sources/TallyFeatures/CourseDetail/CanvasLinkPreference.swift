import Foundation
import Synchronization

/// FEAT-8 (Idea 7, "Open Canvas links in: App / Browser",
/// `pmo-audit/.build-audit/ideas1/report.md`): which destination `CanvasLinkOpener` tries first.
/// `.app` is today's default (the Canvas Student app, falling back to the browser); `.browser`
/// never tries the app. `CanvasLinkOpener.isSafe` runs first in both modes (SEC1-15) -- this
/// preference only ever picks among destinations that already passed it.
public nonisolated enum CanvasLinkPreference: String, Sendable, Equatable, CaseIterable {
    case app, browser
}

/// The local, non-account preference for `CanvasLinkPreference`. Device-only and never
/// transmitted. Not sensitive, so no Keychain (mirrors `NotEnabledSchoolPreferenceStoring`'s own
/// reasoning): the composition root's concrete store (`TallyPlatform`) persists it the way
/// `UserStateStore` persists its own file -- `ProtectedFile`'s directory-prepare, atomic-write and
/// excluded-from-backup pattern (WP-ENC-02) -- never `UserDefaults`, and never `UserState` (FEAT-3
/// and FEAT-4 own the next schema bumps). Cleared on Sign Out & Erase.
public nonisolated protocol CanvasLinkPreferenceStoring: Sendable {
    func load() async -> CanvasLinkPreference?
    /// Overwrites any previous value.
    func save(_ preference: CanvasLinkPreference) async
    /// Sign Out & Erase.
    func clear() async
}

/// The default when no store is injected (tests, previews). Nothing is persisted. Mirrors
/// `InMemoryNotEnabledSchoolPreferenceStore`'s shape.
public nonisolated final class InMemoryCanvasLinkPreferenceStore: CanvasLinkPreferenceStoring {
    private let stored: Mutex<CanvasLinkPreference?>

    public init(_ preference: CanvasLinkPreference? = nil) {
        stored = Mutex(preference)
    }

    public func load() async -> CanvasLinkPreference? { stored.withLock { $0 } }
    public func save(_ preference: CanvasLinkPreference) async { stored.withLock { $0 = preference } }
    public func clear() async { stored.withLock { $0 = nil } }
}
