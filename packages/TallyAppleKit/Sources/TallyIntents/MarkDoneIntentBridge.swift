import TallyDomain

/// How `MarkDoneIntent` (M3-D2, m3d-report.md §6 option A) reaches the signed-in account's write
/// path. `RefreshIntentBridge`'s own doc records the limit this fixes: an app intent's `perform()`
/// has no access to the composition root, and `AppModel.attach(_:)`/`detach()` (which set
/// `RefreshIntentBridge.coordinator`) never run when the system launches Tally only to perform an
/// intent — no UI starts, so `RefreshIntentBridge.coordinator` stays `nil`.
///
/// This bridge avoids that limit a different way: `handler` is registered exactly once, in
/// `TallyApp.swift`'s `init`, never by `attach`/`detach`, and the closure itself resolves the
/// account lazily on every call — the way `.backgroundTask` reaches `AccountRuntime` — so marking
/// an item done works whether or not any UI has ever attached this process's coordinator.
///
/// `nil` only in a process that never set it (a preview or a test host that does not install one):
/// the intent then does nothing, which is safe (PMO R16: the mark is local-only, never written to
/// Canvas either way, so silently doing nothing is the safe default, never a crash).
public enum MarkDoneIntentBridge {
    /// Marks (`done: true`) or unmarks one assignment for whichever account is active right now.
    /// `true` when a signed-in account's `UserState` was written; `false` with no signed-in
    /// account, an unreadable store, or a store this build must not overwrite.
    public typealias Handler = @Sendable (_ assignmentID: CanvasID<Assignment>, _ done: Bool) async -> Bool

    @MainActor public static var handler: Handler?
}
