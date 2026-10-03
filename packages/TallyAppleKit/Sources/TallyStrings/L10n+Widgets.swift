import Foundation

/// M3-D: the run-time text of the widgets and of the intents' spoken answers (plan 08 §3.1:
/// "Widget and Control strings go in TallyStrings"). Keys start with `widget.` so they sort after
/// every other area of the catalog.
///
/// Not here: the widget and control galleries' names and descriptions, which are also the
/// controls' labels (the widget's own catalog, read from the extension bundle), and the App
/// Intents metadata (titles, descriptions, parameter names), which must be build-time constants in
/// the declaring target's `AppIntents` table (WWDC25 session 244).
///
/// Placeholders are already-formatted, locale-aware values (`TallyFormat`); titles and course codes
/// come from Canvas and are passed through untouched.
extension L10n {
    public enum Widgets {
        // MARK: Headers (shown upper-cased)

        public static func headerNextUp() -> LocalizedStringResource {
            LocalizedStringResource("widget.header.nextUp", defaultValue: "Next up", bundle: #bundle,
                                    comment: "Widget header above the next assignment due. Shown in capital letters.")
        }

        public static func headerDueSoon() -> LocalizedStringResource {
            LocalizedStringResource("widget.header.dueSoon", defaultValue: "Due soon", bundle: #bundle,
                                    comment: "Widget header above the next three assignments due. Shown in capital letters.")
        }

        public static func headerWeekAhead() -> LocalizedStringResource {
            LocalizedStringResource("widget.header.weekAhead", defaultValue: "Week ahead", bundle: #bundle,
                                    comment: "Widget header above the next seven days and what is due on each. Shown in capital letters.")
        }

        public static func headerStanding() -> LocalizedStringResource {
            LocalizedStringResource("widget.header.standing", defaultValue: "Standing", bundle: #bundle,
                                    comment: "Widget header above the student's average grade band. Shown in capital letters.")
        }

        // MARK: Messages when there is nothing to show

        public static func messageOpenTally() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.openTally", defaultValue: "Open Tally to see what's due.", bundle: #bundle,
                                    comment: "Widget text when Tally has no data to show yet (signed out, or the widget cannot read Tally's data).")
        }

        public static func messageUpdate() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.update", defaultValue: "Open Tally to update.", bundle: #bundle,
                                    comment: "Widget text when the student is signed in but Tally has not finished its first sync.")
        }

        public static func messageUnlock() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.unlock", defaultValue: "Unlock your iPhone to see what's next.", bundle: #bundle,
                                    comment: "Widget text before the iPhone has been unlocked once since it started: Tally's data cannot be read yet.")
        }

        public static func messageSubscribe() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.subscribe", defaultValue: "Open Tally to subscribe and see what's due.", bundle: #bundle,
                                    comment: "Widget text when the student's Tally subscription does not include widgets right now (no subscription, or it has ended).")
        }

        public static func shortOpenTally() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.short.openTally", defaultValue: "Open Tally", bundle: #bundle,
                                    comment: "Lock Screen widget text, very short: Tally has no data to show here yet.")
        }

        public static func shortUnlock() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.short.unlock", defaultValue: "Unlock your iPhone", bundle: #bundle,
                                    comment: "Lock Screen widget text, very short: the iPhone must be unlocked once before Tally's data can be read.")
        }

        public static func shortSubscribe() -> LocalizedStringResource {
            LocalizedStringResource("widget.message.short.subscribe", defaultValue: "Subscribe in Tally", bundle: #bundle,
                                    comment: "Lock Screen widget text, very short: the student's subscription does not include widgets right now.")
        }

        // MARK: Items

        public static func nothingNow() -> LocalizedStringResource {
            LocalizedStringResource("widget.nothingNow", defaultValue: "Nothing to do right now", bundle: #bundle,
                                    comment: "Next Up widget when no open assignment is due later.")
        }

        public static func nothingSoon() -> LocalizedStringResource {
            LocalizedStringResource("widget.nothingSoon", defaultValue: "Nothing due soon", bundle: #bundle,
                                    comment: "Widget text when no open assignment is coming up.")
        }

        /// A generic word in place of an assignment's title, with "Hide course names" on (PMO R10).
        public static func hiddenAssignment() -> LocalizedStringResource {
            LocalizedStringResource("widget.hiddenAssignment", defaultValue: "Assignment", bundle: #bundle,
                                    comment: "Shown instead of an assignment's title on widgets when the student turned on 'Hide course names'.")
        }

        /// M3-D2 (UX-WP-18): the "Due soon" row's trailing "Mark Done" button, as VoiceOver reads
        /// it. The placeholder is the item's own title (or "Assignment" with "Hide course names" on),
        /// so each button in the list is distinct.
        public static func markDoneButton(_ title: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.markDone.button", defaultValue: "Mark \(title) done", bundle: #bundle,
                                    comment: "Accessibility label for the Due Soon widget row's button that marks that one assignment done. "
                                        + "The placeholder is the assignment's title.")
        }

        public static func dueToday(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.due.today", defaultValue: "Due today, \(time)", bundle: #bundle,
                                    comment: "When an assignment is due. The placeholder is a time such as '6:00 PM'.")
        }

        public static func dueTomorrow(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.due.tomorrow", defaultValue: "Due tomorrow, \(time)", bundle: #bundle,
                                    comment: "When an assignment is due. The placeholder is a time such as '6:00 PM'.")
        }

        public static func dueWeekday(_ weekday: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.due.weekday", defaultValue: "Due \(weekday), \(time)", bundle: #bundle,
                                    comment: "When an assignment is due within the week. 1: a weekday such as 'Tuesday'. 2: a time such as '6:00 PM'.")
        }

        public static func dueDate(_ date: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.due.date", defaultValue: "Due \(date)", bundle: #bundle,
                                    comment: "When an assignment is due, more than a week away. The placeholder is a date such as 'Oct 14'.")
        }

        /// The short form on a Lock Screen line: "Tomorrow 6:00 PM".
        public static func shortTomorrow(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.when.short.tomorrow", defaultValue: "Tomorrow \(time)", bundle: #bundle,
                                    comment: "Short due time on a Lock Screen widget, for tomorrow. The placeholder is a time such as '6:00 PM'.")
        }

        /// The short form on a Lock Screen line: "Tue 6:00 PM".
        public static func shortWeekday(_ weekday: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.when.short.weekday", defaultValue: "\(weekday) \(time)", bundle: #bundle,
                                    comment: "Short due time on a Lock Screen widget, within the week. 1: an abbreviated weekday such as 'Tue'. 2: a time such as '6:00 PM'.")
        }

        /// "BIO 101 · 6:00 PM": a course code and a due time.
        public static func courseAndTime(_ courseCode: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.item.courseAndTime", defaultValue: "\(courseCode) · \(time)", bundle: #bundle,
                                    comment: "Lock Screen widget line. 1: the course code from Canvas, such as 'BIO 101'. 2: when it is due, such as '6:00 PM' or 'Tue 6:00 PM'.")
        }

        /// The one-line Lock Screen widget: "Next: Lab Report 4, 6:00 PM".
        public static func inlineNext(_ title: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.inline.next", defaultValue: "Next: \(title), \(time)", bundle: #bundle,
                                    comment: "One-line Lock Screen widget. 1: the assignment's title from Canvas (or 'Assignment'). 2: when it is due, such as '6:00 PM' or 'Tue 6:00 PM'.")
        }

        public static func laterCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.counts.later", defaultValue: "+\(count) more", bundle: #bundle,
                                    comment: "Widget footer: how many more open assignments are due after the ones shown.")
        }

        /// The count when Tally holds only the first few of them (its widget data is limited).
        public static func laterAtLeast(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.counts.laterAtLeast", defaultValue: "+\(count) or more", bundle: #bundle,
                                    comment: "Widget footer: at least this many more open assignments are due after the ones shown (there may be more).")
        }

        public static func overdueCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.counts.overdue", defaultValue: "\(count) overdue", bundle: #bundle,
                                    comment: "Widget footer: how many open assignments are past their due time.")
        }

        public static func countsJoin(_ first: String, _ second: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.counts.join", defaultValue: "\(first) · \(second)", bundle: #bundle,
                                    comment: "Joins two widget footer counts, such as '+2 more' and '1 overdue'.")
        }

        public static func asOf(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.asOf", defaultValue: "As of \(time)", bundle: #bundle,
                                    comment: "Widget footer when its data is more than 3 hours old. The placeholder is a time, with the weekday when it is from an earlier day, such as '2:14 PM' or 'Tue 2:14 PM'.")
        }

        // MARK: Week ahead

        public static func busy() -> LocalizedStringResource {
            LocalizedStringResource("widget.week.busy", defaultValue: "Busy", bundle: #bundle,
                                    comment: "Week Ahead widget: under a day with many assignments due. Keep it short.")
        }

        /// A day's count when Tally holds only some of that day's items: "3+".
        public static func atLeast(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.week.atLeast", defaultValue: "\(count)+", bundle: #bundle,
                                    comment: "Week Ahead widget: at least this many assignments are due that day (there may be more).")
        }

        // MARK: Due today (Lock Screen gauge)

        public static func dueTodayTitle() -> LocalizedStringResource {
            LocalizedStringResource("widget.today.title", defaultValue: "Due today", bundle: #bundle,
                                    comment: "Lock Screen gauge's label: how many assignments are still due today.")
        }

        public static func todayCaption() -> LocalizedStringResource {
            LocalizedStringResource("widget.today.caption", defaultValue: "today", bundle: #bundle,
                                    comment: "Lock Screen gauge, under the number of assignments still due today. Keep it very short.")
        }

        // MARK: Standing

        public static func hiddenWhileLocked() -> LocalizedStringResource {
            LocalizedStringResource("widget.standing.hiddenWhileLocked", defaultValue: "Hidden while locked", bundle: #bundle,
                                    comment: "Standing widget while the iPhone is locked: the grade is hidden.")
        }

        public static func hiddenByInstructor() -> LocalizedStringResource {
            LocalizedStringResource("widget.standing.hiddenByInstructor", defaultValue: "Hidden by instructor", bundle: #bundle,
                                    comment: "Standing widget, next to a course: the instructor hides the course total in Canvas.")
        }

        public static func bandA() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.aRange", defaultValue: "A range", bundle: #bundle,
                                    comment: "A grade band: the course average is in the A range.")
        }

        public static func bandB() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.bRange", defaultValue: "B range", bundle: #bundle,
                                    comment: "A grade band: the course average is in the B range.")
        }

        public static func bandC() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.cRange", defaultValue: "C range", bundle: #bundle,
                                    comment: "A grade band: the course average is in the C range.")
        }

        public static func bandD() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.dRange", defaultValue: "D range", bundle: #bundle,
                                    comment: "A grade band: the course average is in the D range.")
        }

        public static func bandF() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.fRange", defaultValue: "F range", bundle: #bundle,
                                    comment: "A grade band: the course average is in the F range.")
        }

        public static func bandPassing() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.passing", defaultValue: "Passing", bundle: #bundle,
                                    comment: "A grade band for a pass/fail course: passing.")
        }

        public static func bandNotPassing() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.notPassing", defaultValue: "Not passing", bundle: #bundle,
                                    comment: "A grade band for a pass/fail course: not passing.")
        }

        public static func bandNone() -> LocalizedStringResource {
            LocalizedStringResource("widget.band.none", defaultValue: "No grade", bundle: #bundle,
                                    comment: "A grade band when Canvas gave a grade Tally cannot place in a band.")
        }

        // MARK: Spoken answers (Siri and Shortcuts)

        /// "Lab Report 4 (BIO 101), due today at 6:00 PM".
        public static func answerItem(_ title: String, _ courseCode: String, _ when: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.item", defaultValue: "\(title) (\(courseCode)), due \(when)", bundle: #bundle,
                                    comment: "One assignment in a spoken answer. 1: its title from Canvas. 2: its course code from Canvas. 3: when it is due, such as 'today at 6:00 PM'.")
        }

        public static func answerItemNoCourse(_ title: String, _ when: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.itemNoCourse", defaultValue: "\(title), due \(when)", bundle: #bundle,
                                    comment: "One assignment with no course in a spoken answer. 1: its title from Canvas. 2: when it is due, such as 'today at 6:00 PM'.")
        }

        public static func answerItemHidden(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.itemHidden", defaultValue: "An assignment, due \(when)", bundle: #bundle,
                                    comment: "One assignment in a spoken answer when 'Hide course names' is on. The placeholder is when it is due, such as 'today at 6:00 PM'.")
        }

        public static func whenToday(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.when.today", defaultValue: "today at \(time)", bundle: #bundle,
                                    comment: "In a spoken answer, when an assignment is due. The placeholder is a time such as '6:00 PM'.")
        }

        public static func whenTomorrow(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.when.tomorrow", defaultValue: "tomorrow at \(time)", bundle: #bundle,
                                    comment: "In a spoken answer, when an assignment is due. The placeholder is a time such as '6:00 PM'.")
        }

        public static func whenWeekday(_ weekday: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.when.weekday", defaultValue: "\(weekday) at \(time)", bundle: #bundle,
                                    comment: "In a spoken answer, when an assignment is due. 1: a weekday such as 'Friday'. 2: a time such as '6:00 PM'.")
        }

        public static func answerDueNext(_ items: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.dueNext", defaultValue: "Next up: \(items).", bundle: #bundle,
                                    comment: "Spoken answer to 'What's due next?'. The placeholder is a list of assignments, such as 'Lab Report 4 (BIO 101), due today at 6:00 PM and Quiz 3 (CHEM 110), due Friday at 9:00 AM'.")
        }

        public static func answerDueToday(_ items: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.dueToday", defaultValue: "Due today: \(items).", bundle: #bundle,
                                    comment: "Spoken answer to 'What's due today?'. The placeholder is a list of assignments, such as 'Lab Report 4 (BIO 101), due today at 6:00 PM'.")
        }

        public static func answerNothingSoon() -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.nothingSoon", defaultValue: "Nothing is due soon.", bundle: #bundle,
                                    comment: "Spoken answer to 'What's due next?' when no open assignment is coming up.")
        }

        public static func answerNothingToday() -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.nothingToday", defaultValue: "Nothing else is due today.", bundle: #bundle,
                                    comment: "Spoken answer to 'What's due today?' when no open assignment is due later today.")
        }

        public static func answerMore(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.more", defaultValue: "Plus \(count) more.", bundle: #bundle,
                                    comment: "Spoken answer, after the list: how many more assignments are due after the ones read out.")
        }

        /// The count when Tally holds only the first few of them (its widget data is limited).
        public static func answerMoreAtLeast(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.moreAtLeast", defaultValue: "Plus \(count) or more.", bundle: #bundle,
                                    comment: "Spoken answer, after the list: at least this many more assignments are due after the ones read out (there may be more).")
        }

        public static func answerOverdue(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.overdue", defaultValue: "You also have \(count) overdue.", bundle: #bundle,
                                    comment: "Spoken answer, after the list: how many open assignments are past their due time.")
        }

        public static func answerAsOf(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.asOf", defaultValue: "As of \(time).", bundle: #bundle,
                                    comment: "Spoken answer, last: when Tally's data is from, because it is more than 3 hours old. The placeholder is a time, with the weekday when it is from an earlier day.")
        }

        /// Two sentences of a spoken answer, in order.
        public static func sentences(_ first: String, _ second: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.answer.join", defaultValue: "\(first) \(second)", bundle: #bundle,
                                    comment: "Joins two sentences of a spoken answer. Use the language's usual separator between sentences.")
        }

        // MARK: Refresh (Siri, Shortcuts and the Control Center button)

        public static func refreshUpdated() -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.updated", defaultValue: "Tally is up to date.", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': the refresh worked.")
        }

        public static func refreshStillRunning() -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.stillRunning", defaultValue: "Tally is still refreshing. Check back in a moment.", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': the refresh is taking longer than expected and goes on.")
        }

        public static func refreshOffline(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.offline", defaultValue: "You're offline. Tally is showing data from \(time).", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': no internet connection. The placeholder is when the saved data is from, such as '2:14 PM'.")
        }

        public static func refreshOfflineNoData() -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.offlineNoData", defaultValue: "You're offline, so Tally couldn't refresh.", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': no internet connection and nothing saved yet.")
        }

        public static func refreshSignInExpired() -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.signInExpired", defaultValue: "Your Canvas sign-in expired. Open Tally to sign in again.", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': the student must sign in to Canvas again in the app.")
        }

        public static func refreshFailed(_ time: String) -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.failed", defaultValue: "Tally couldn't refresh. It's showing data from \(time).", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': the refresh failed. The placeholder is when the saved data is from, such as '2:14 PM'.")
        }

        public static func refreshFailedNoData() -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.failedNoData", defaultValue: "Tally couldn't refresh yet.", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally': the refresh failed and nothing is saved yet.")
        }

        public static func refreshOpenTally() -> LocalizedStringResource {
            LocalizedStringResource("widget.refresh.openTally", defaultValue: "Open Tally to refresh.", bundle: #bundle,
                                    comment: "Answer after 'Refresh Tally' when Tally can't refresh from here: the student isn't signed in, is exploring sample data, or Tally isn't open.")
        }

        // MARK: Focus filter (the Focus settings' summary of this filter)

        public static func focusAllCourses() -> LocalizedStringResource {
            LocalizedStringResource("widget.focus.allCourses", defaultValue: "All courses", bundle: #bundle,
                                    comment: "Focus filter summary in iOS Settings: Tally shows every course during this Focus.")
        }

        public static func focusOnlyUrgent() -> LocalizedStringResource {
            LocalizedStringResource("widget.focus.onlyUrgent", defaultValue: "Only urgent alerts", bundle: #bundle,
                                    comment: "Focus filter summary in iOS Settings: only urgent Tally alerts come through during this Focus.")
        }

        public static func focusAllAlerts() -> LocalizedStringResource {
            LocalizedStringResource("widget.focus.allAlerts", defaultValue: "All alerts", bundle: #bundle,
                                    comment: "Focus filter summary in iOS Settings: every Tally alert comes through during this Focus.")
        }
    }
}
