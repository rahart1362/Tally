import AppIntents

/// "Refresh Tally" (architecture.md §3.1 App Intents list). Intents run in
/// the app process — never the widget — because public-client refresh
/// tokens rotate on every use (ARC-03), so only the app may hold and rotate
/// them.
///
/// The body is intentionally a no-op: `TallySync.RefreshCoordinator` (the
/// actor that would actually run a refresh) does not exist yet — it is a
/// later milestone's work package. Wiring this intent to a coordinator that
/// isn't implemented would mean fabricating a result, which the
/// implementation brief forbids ("Never write mock data into shipping code
/// paths"). This intent exists so the shortcut and Siri phrase are in place
/// and testable now; `perform()` gets a real body in the sync work package.
public struct RefreshTallyIntent: AppIntent {
    // `let`, not `var`: the compiler flags a nonisolated `static var` as
    // unsafe shared mutable state under strict concurrency checking, even
    // though `AppIntent`'s requirements are get-only.
    public static let title: LocalizedStringResource = "Refresh Tally"
    public static let description = IntentDescription(
        "Refreshes Tally's saved Canvas data. Not yet wired to a live refresh."
    )

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

public struct TallyShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshTallyIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh",
            systemImageName: "arrow.clockwise"
        )
    }
}
