import TallySync

/// How "Refresh Tally" reaches the signed-in account's `RefreshCoordinator` (E04). An app intent's
/// `perform()` has no access to the app's composition root, so `AppModel.attach(_:)` sets
/// `coordinator` and `detach()` (and so `signOut()`) clears it; the intent
/// (`apps/TallyiOS/Tally/Intents/RefreshTallyIntent+App.swift`, M3-D) reads it in the app's
/// process. Sample data never attaches, so it never reaches the intent (ASC-14).
///
/// Limit, recorded for the composition root's owner: when the system launches the app only to run
/// an intent (Siri, Shortcuts or the Control Center control while Tally is not running), no UI
/// starts, `AppModel.attach` does not run, and `coordinator` stays `nil`: the intent answers "Open
/// Tally to refresh" instead of refreshing. Resolving the account lazily there, the way
/// `.backgroundTask` does through `AccountRuntime`, needs a registration at launch in
/// `TallyApp.swift` (see the M3-D report).
@MainActor
public enum RefreshIntentBridge {
    public static var coordinator: RefreshCoordinator?
}
