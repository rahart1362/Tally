import AppIntents
import Foundation
import TallyGlance
import TallyPlatform

// The Siri and Shortcuts questions (integrations.md §2.4), declared in the app target because App
// Shortcuts must live there (Apple DTS, developer forums thread 770279). They read the glance the
// widgets read (`GlanceReader.appProcess`), with no network call, and answer through
// `GlanceIntentAnswers`, so a spoken answer and a widget always agree. No answer contains a grade.
//
// The "top 3 by priority" question of insights-at-a-glance.md §1.5 needs the snapshot's grade
// weights, which only the app's screens read; these answer by due date, and say so in their names.
//
// SEC1-10 (hardening review): both intents below now require a device unlock before they speak
// an item's title. The other App Intents were checked too, and need no change: "Refresh Tally"
// (`TallyControlIntents.swift`) answers with a status word only, never a title or grade
// (`RefreshAnswer`); "Mark Done" (`TallyWidgets/Shared/MarkDoneIntent.swift`) takes only an
// opaque ID, discloses nothing, and is not Siri/Shortcuts-discoverable; the Focus filter
// (`TallyFocusFilter.swift`) only (de)activates a filter from courses the student already chose
// while configuring it (unlocked, in Settings) — its `perform()` reveals nothing new.
//
// SEC1-10 optional variant: `.requiresLocalDeviceAuthentication` above forces this iOS device to
// unlock before `perform()` runs at all, but that is a device-level gate, not Tally's own in-app
// App Lock — a student can turn App Lock on independently, and the rest of the app honours it
// regardless of whether the device itself is currently unlocked. `appLockIsEnabled()` reads only
// that one boolean setting from the Keychain (`KeychainAppLockPreferenceStore`, the same store and
// defaults the composition root uses) — never the glance, never any protected content — so it
// stays a read-only flag the intents can consult without needing to unlock anything themselves.
private func appLockIsEnabled() async -> Bool {
    await KeychainAppLockPreferenceStore().load().effective.isEnabled
}

/// "What's due next?": the next three open items, then how many more, how many are overdue, and how
/// old the data is when it is more than 3 hours old.
struct WhatsDueNextIntent: AppIntent {
    static let title = LocalizedStringResource("intent.dueNext.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.dueNext.description", table: "AppIntents"))
    // SEC1-10: reads and speaks assignment titles from CUFA-protected disk data, readable only
    // once this iPhone itself has been unlocked. Per Apple's App Intents docs, that is the
    // documented use case for `.requiresLocalDeviceAuthentication`, not the weaker
    // `.requiresAuthentication`: the latter is satisfied by any one unlocked device in the
    // request, so it would still let the intent's code run on a locked iPhone if the request
    // came in from an already-unlocked paired Apple Watch — the report's roommate-holding-the-
    // phone scenario, by another route. `.requiresLocalDeviceAuthentication` forces this specific
    // device to unlock regardless of what else in the request is already authenticated. Either
    // one closes App Intents' default (`.alwaysAllowed`, answering straight past App Lock); this
    // is the one that actually matches what the data needs. The system handles the unlock prompt
    // itself; no new string.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await GlanceReader.appProcess().read()
        let answer = GlanceIntentAnswers.dueNext(result, now: Date(), calendar: .autoupdatingCurrent,
                                                 appLockIsEnabled: await appLockIsEnabled())
        return .result(dialog: IntentDialog(GlanceIntentAnswers.dialog(answer, calendar: .autoupdatingCurrent)))
    }
}

/// "What's due today?": the open items still due today, then the same follow-ups.
struct WhatsDueTodayIntent: AppIntent {
    static let title = LocalizedStringResource("intent.dueToday.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.dueToday.description", table: "AppIntents"))
    // SEC1-10: see WhatsDueNextIntent.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await GlanceReader.appProcess().read()
        let answer = GlanceIntentAnswers.dueToday(result, now: Date(), calendar: .autoupdatingCurrent,
                                                  appLockIsEnabled: await appLockIsEnabled())
        return .result(dialog: IntentDialog(GlanceIntentAnswers.dialog(answer, calendar: .autoupdatingCurrent)))
    }
}
