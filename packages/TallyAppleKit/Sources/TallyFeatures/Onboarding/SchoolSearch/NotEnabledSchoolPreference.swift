import Foundation
import Synchronization

/// FEAT-2 (school-check hardening of the subscription path): the one local, non-account preference
/// holding the school name `SchoolSearchView` most recently resolved to "not enabled"
/// (ux-ui.md §3.2.1). Device-only and never transmitted (it is the free-text name the student typed,
/// not a Canvas identifier). Cleared on Sign Out & Erase and once a real signed-in account exists
/// (`AppModel.signOut()`/`completeSignIn(_:storeRoot:)`), so a stale name never survives past the
/// moment it stops being relevant.
///
/// Unlike the app lock's setting (`AppLockPreferenceStoring`), this value is not sensitive, so it
/// needs no Keychain: the composition root's concrete store (`TallyPlatform`) persists it the way
/// `UserStateStore` persists its own file — `ProtectedFile`'s directory-prepare, atomic-write and
/// excluded-from-backup pattern (WP-ENC-02) — never `UserDefaults`, and never a sealed/encrypted
/// payload (there is nothing here worth encrypting, and no `AccountKey` exists yet when it is first
/// written: the "not enabled" page happens in `.welcome`/`.sample`, before any account).
public nonisolated protocol NotEnabledSchoolPreferenceStoring: Sendable {
    func load() async -> String?
    /// Overwrites any previous value.
    func save(_ schoolName: String) async
    /// Sign-out/erase, and once sample mode (or a direct sign-in) reaches a real account.
    func clear() async
}

/// The default when no store is injected (tests, previews). Nothing is persisted. Mirrors
/// `InMemoryAppLockPreferenceStore`'s shape.
public nonisolated final class InMemoryNotEnabledSchoolPreferenceStore: NotEnabledSchoolPreferenceStoring {
    private let stored: Mutex<String?>

    public init(_ schoolName: String? = nil) {
        stored = Mutex(schoolName)
    }

    public func load() async -> String? { stored.withLock { $0 } }
    public func save(_ schoolName: String) async { stored.withLock { $0 = schoolName } }
    public func clear() async { stored.withLock { $0 = nil } }
}
