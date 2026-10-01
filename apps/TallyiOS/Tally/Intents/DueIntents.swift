import AppIntents
import Foundation
import TallyGlance

// The Siri and Shortcuts questions (integrations.md §2.4), declared in the app target because App
// Shortcuts must live there (Apple DTS, developer forums thread 770279). They read the glance the
// widgets read (`GlanceReader.appProcess`), with no network call, and answer through
// `GlanceIntentAnswers`, so a spoken answer and a widget always agree. No answer contains a grade.
//
// The "top 3 by priority" question of insights-at-a-glance.md §1.5 needs the snapshot's grade
// weights, which only the app's screens read; these answer by due date, and say so in their names.

/// "What's due next?": the next three open items, then how many more, how many are overdue, and how
/// old the data is when it is more than 3 hours old.
struct WhatsDueNextIntent: AppIntent {
    static let title = LocalizedStringResource("intent.dueNext.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.dueNext.description", table: "AppIntents"))

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await GlanceReader.appProcess().read()
        let answer = GlanceIntentAnswers.dueNext(result, now: Date(), calendar: .autoupdatingCurrent)
        return .result(dialog: IntentDialog(GlanceIntentAnswers.dialog(answer, calendar: .autoupdatingCurrent)))
    }
}

/// "What's due today?": the open items still due today, then the same follow-ups.
struct WhatsDueTodayIntent: AppIntent {
    static let title = LocalizedStringResource("intent.dueToday.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.dueToday.description", table: "AppIntents"))

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await GlanceReader.appProcess().read()
        let answer = GlanceIntentAnswers.dueToday(result, now: Date(), calendar: .autoupdatingCurrent)
        return .result(dialog: IntentDialog(GlanceIntentAnswers.dialog(answer, calendar: .autoupdatingCurrent)))
    }
}
