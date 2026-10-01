import AppIntents

/// Tally's App Shortcuts (insights-at-a-glance.md §1.5; integrations.md §2.4): Siri phrases that
/// work on every device the app supports, with no Apple Intelligence requirement. In the app target
/// because App Shortcuts must be declared there (Apple DTS, developer forums thread 770279; plan 08
/// asked M3-D to check the package case, and `TallyIntents` declared them in a package before).
///
/// Each phrase is a build-time constant and the key of its translations in `AppShortcuts.xcstrings`
/// beside this directory, which is how the system matches phrases in each language; that is why
/// they are literals here (each line carries the l10n gate's exemption with that reason). Every
/// phrase names the app (`.applicationName`), as App Shortcuts require.
struct TallyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsDueNextIntent(),
            phrases: [
                "What's due next in \(.applicationName)", // l10n-exempt: App Shortcuts phrase, keyed in AppShortcuts.xcstrings
                "What's next in \(.applicationName)", // l10n-exempt: App Shortcuts phrase, keyed in AppShortcuts.xcstrings
            ],
            shortTitle: LocalizedStringResource("intent.dueNext.shortTitle", table: "AppIntents"),
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: WhatsDueTodayIntent(),
            phrases: [
                "What's due today in \(.applicationName)", // l10n-exempt: App Shortcuts phrase, keyed in AppShortcuts.xcstrings
                "What's due in \(.applicationName)", // l10n-exempt: App Shortcuts phrase, keyed in AppShortcuts.xcstrings
            ],
            shortTitle: LocalizedStringResource("intent.dueToday.shortTitle", table: "AppIntents"),
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: RefreshTallyIntent(),
            phrases: [
                "Refresh \(.applicationName)", // l10n-exempt: App Shortcuts phrase, keyed in AppShortcuts.xcstrings
                "Update \(.applicationName)", // l10n-exempt: App Shortcuts phrase, keyed in AppShortcuts.xcstrings
            ],
            shortTitle: LocalizedStringResource("intent.refresh.shortTitle", table: "AppIntents"),
            systemImageName: "arrow.clockwise"
        )
    }
}
