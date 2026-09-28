import AppIntents
import TallyDomain

/// "Refresh Tally" (architecture.md §3.1 App Intents list). Intents run in
/// the app process — never the widget — because public-client refresh
/// tokens rotate on every use (ARC-03), so only the app may hold and rotate
/// them.
///
/// E04: wired to `RefreshIntentBridge.coordinator` (see that type's doc
/// comment for why a bridge rather than `AppDependencyManager`/`@Dependency`
/// — full `AppIntentsPackage` wiring is deferred to E06). There is still no
/// signed-in account in this branch, so the bridge holds `nil` today and
/// this is a genuine no-op — real wiring around a currently-empty value, not
/// a fabricated result (implementation brief: "Never write mock data into
/// shipping code paths").
public struct RefreshTallyIntent: AppIntent {
    // `let`, not `var`: the compiler flags a nonisolated `static var` as
    // unsafe shared mutable state under strict concurrency checking, even
    // though `AppIntent`'s requirements are get-only.
    public static let title: LocalizedStringResource = "Refresh Tally"
    public static let description = IntentDescription(
        "Refreshes Tally's saved Canvas data."
    )

    public init() {}

    public func perform() async throws -> some IntentResult {
        await RefreshIntentBridge.coordinator?.run(trigger: .intent)
        return .result()
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
