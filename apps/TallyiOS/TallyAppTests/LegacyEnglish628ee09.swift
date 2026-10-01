import Foundation
import TallyDomain
#if canImport(TallyFeatures)
import TallyStrings
@testable import TallyFeatures
#endif

/// Plan 08 L10N-02: the English Tally produced before TallyCore became string-free, frozen as the
/// oracle for `RendererGoldenTests`. Every string-building line below is copied verbatim from
/// `origin/main` @ 628ee09 (PR #12):
/// - `Notification`: `packages/TallyCore/Sources/TallyDomain/Reminders/NotificationContent.swift:23-97`;
/// - `TimeFormat`, `pastDueNoClosingDate`: `packages/TallyAppleKit/Sources/TallyFeatures/Reminders/ReminderSubjects.swift:135-189`;
/// - `text(for:seenAt:format:)`: that file's `content(for:…)`, `:73-118`, the `NotificationContent` calls in the same order;
/// - `describe`, `safeInt`: `packages/TallyCore/Sources/TallyDomain/Insights/PriorityScore.swift:205-233`;
/// - `attention`: `packages/TallyCore/Sources/TallyDomain/Dashboard/DashboardProjection.swift:256-258, 287-299`, with
///   the due-soon time and the overload date as `HomeProjector.localized` re-rendered them
///   (`packages/TallyAppleKit/Sources/TallyFeatures/Home/HomeProjector.swift:74-91`), which is what the app showed;
/// - `changeSummary`: `HomeProjector.swift:93-96`.
/// Nothing here may change: it is the definition of "today's text".
enum LegacyEnglish {
    // MARK: - NotificationContent (628ee09)

    enum Notification {
        typealias Rendered = NotificationContent.Rendered

        private static func subjectTitle(_ assignmentTitle: String, courseCode: String, hideCourseNames: Bool) -> String {
            hideCourseNames ? "An assignment" : "\(assignmentTitle) · \(courseCode)"
        }

        private static func courseLabel(_ courseCode: String, hideCourseNames: Bool) -> String {
            hideCourseNames ? "a course" : courseCode
        }

        private static func itemLabel(_ title: String, hideCourseNames: Bool) -> String {
            hideCourseNames ? "An assignment" : title
        }

        static func due(
            assignmentTitle: String, courseCode: String, dueTimeText: String, isFinalReminder: Bool, hideCourseNames: Bool
        ) -> Rendered {
            let title = subjectTitle(assignmentTitle, courseCode: courseCode, hideCourseNames: hideCourseNames)
            let body = isFinalReminder ? "Due \(dueTimeText), if you haven't submitted yet." : "Due \(dueTimeText)."
            return Rendered(title: title, body: body)
        }

        static func missingFollowup(
            assignmentTitle: String, courseCode: String, stillAcceptedUntilText: String, hideCourseNames: Bool
        ) -> Rendered {
            Rendered(
                title: subjectTitle(assignmentTitle, courseCode: courseCode, hideCourseNames: hideCourseNames),
                body: "Still accepted until \(stillAcceptedUntilText).")
        }

        static func examReminder(
            assignmentTitle: String, courseCode: String, dueTimeText: String, hideCourseNames: Bool
        ) -> Rendered {
            Rendered(
                title: subjectTitle(assignmentTitle, courseCode: courseCode, hideCourseNames: hideCourseNames),
                body: "Due \(dueTimeText).")
        }

        static func gradePosted(courseCode: String, hideCourseNames: Bool) -> Rendered {
            Rendered(title: "New grade posted", body: courseLabel(courseCode, hideCourseNames: hideCourseNames))
        }

        static func belowGoal(courseCode: String, hideCourseNames: Bool) -> Rendered {
            Rendered(
                title: "\(courseLabel(courseCode, hideCourseNames: hideCourseNames)) needs attention",
                body: "Open Tally to see your standing.")
        }

        static func eveningDigest(dueCount: Int, firstItemTitle: String?, hideCourseNames: Bool) -> Rendered {
            var body = "\(dueCount) due"
            if let firstItemTitle {
                body += " · \(itemLabel(firstItemTitle, hideCourseNames: hideCourseNames)) first"
            }
            return Rendered(title: "Tomorrow", body: body)
        }

        static func weekAhead(dueCount: Int, busiestDayText: String?) -> Rendered {
            var body = "\(dueCount) due"
            if let busiestDayText { body += " · busiest \(busiestDayText)" }
            return Rendered(title: "This week", body: body)
        }

        static func sentinel(lastSuccessText: String) -> Rendered {
            Rendered(title: "Tally hasn't refreshed since \(lastSuccessText)", body: "Open Tally to update your reminders.")
        }
    }

    // MARK: - RemindersCopy and ReminderTimeFormat (628ee09)

    static let pastDueNoClosingDate = "Past due. Canvas lists no closing date."
    /// `RemindersConfig.weekdayNamingDays` at 628ee09.
    static let weekdayNamingDays = 6

    struct TimeFormat {
        let timeZone: TimeZone
        let locale: Locale

        private var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            calendar.locale = locale
            return calendar
        }

        func time(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
        }

        func weekday(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
        }

        func dayTime(_ date: Date, relativeTo reference: Date) -> String {
            let calendar = calendar
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                               to: calendar.startOfDay(for: date)).day ?? Int.max
            let day: String
            switch days {
            case 0: day = "today"
            case 1: day = "tomorrow"
            case -1: day = "yesterday"
            case -LegacyEnglish.weekdayNamingDays...LegacyEnglish.weekdayNamingDays: day = weekday(date)
            default: day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day())
            }
            return "\(day) at \(time(date))"
        }

        /// The busiest day's name, as 628ee09's `busiestDay(of:)` formatted the day it picked.
        func busiestDayName(_ day: Date) -> String {
            day.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.wide))
        }
    }

    /// What 628ee09's `ReminderSubjects.content(for:…)` returned for the reminder `message` now
    /// describes: the same `NotificationContent` call with the same arguments.
    static func text(for message: NotificationMessage, seenAt: Date, format: TimeFormat) -> NotificationContent.Rendered {
        func parts(_ subject: NotificationMessage.Subject) -> (title: String, code: String, hide: Bool) {
            switch subject {
            case .assignment(let title, let code): (title: title, code: code, hide: false)
            case .hidden: (title: "<hidden title>", code: "<hidden code>", hide: true)
            }
        }
        func course(_ name: NotificationMessage.CourseName) -> (code: String, hide: Bool) {
            switch name {
            case .code(let code): (code: code, hide: false)
            case .hidden: (code: "<hidden code>", hide: true)
            }
        }
        switch message {
        case .due(let subject, let dueAt, let isFinal):
            let s = parts(subject)
            return Notification.due(assignmentTitle: s.title, courseCode: s.code,
                                    dueTimeText: format.dayTime(dueAt, relativeTo: seenAt), isFinalReminder: isFinal,
                                    hideCourseNames: s.hide)
        case .missingFollowup(let subject, nil):
            let s = parts(subject)
            let titled = Notification.missingFollowup(assignmentTitle: s.title, courseCode: s.code,
                                                      stillAcceptedUntilText: "", hideCourseNames: s.hide)
            return NotificationContent.Rendered(title: titled.title, body: pastDueNoClosingDate)
        case .missingFollowup(let subject, let lockAt?):
            let s = parts(subject)
            return Notification.missingFollowup(assignmentTitle: s.title, courseCode: s.code,
                                                stillAcceptedUntilText: format.dayTime(lockAt, relativeTo: seenAt),
                                                hideCourseNames: s.hide)
        case .examReminder(let subject, let dueAt):
            let s = parts(subject)
            return Notification.examReminder(assignmentTitle: s.title, courseCode: s.code,
                                             dueTimeText: format.dayTime(dueAt, relativeTo: seenAt), hideCourseNames: s.hide)
        case .eveningDigest(let count, let first):
            switch first {
            case .title(let title)?: return Notification.eveningDigest(dueCount: count, firstItemTitle: title, hideCourseNames: false)
            case .hidden?: return Notification.eveningDigest(dueCount: count, firstItemTitle: "<hidden title>", hideCourseNames: true)
            case nil: return Notification.eveningDigest(dueCount: count, firstItemTitle: nil, hideCourseNames: false)
            }
        case .weekAhead(let count, let busiest):
            return Notification.weekAhead(dueCount: count, busiestDayText: busiest.map(format.busiestDayName))
        case .sentinel(let lastSuccess):
            return Notification.sentinel(lastSuccessText: format.dayTime(lastSuccess, relativeTo: seenAt))
        case .gradePosted(let name):
            let c = course(name)
            return Notification.gradePosted(courseCode: c.code, hideCourseNames: c.hide)
        case .belowGoal(let name):
            let c = course(name)
            return Notification.belowGoal(courseCode: c.code, hideCourseNames: c.hide)
        }
    }

    // MARK: - PriorityScore reason text (628ee09)

    static func reasonText(hoursUntilDue: Double?, weight: Double, modifiers: PriorityScore.Modifiers, courseCode: String) -> String {
        PriorityScore.reasonFactors(hoursUntilDue: hoursUntilDue, weight: weight, modifiers: modifiers)
            .map { describe($0, courseCode: courseCode) }
            .joined(separator: " · ")
    }

    static func reasonText(_ factors: [PriorityScore.Factor], courseCode: String) -> String {
        factors.map { describe($0, courseCode: courseCode) }.joined(separator: " · ")
    }

    private static func safeInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(1e9, max(-1e9, value)).rounded())
    }

    private static func describe(_ factor: PriorityScore.Factor, courseCode: String) -> String {
        switch factor {
        case .dueIn(let h):
            if h < 1 { return "Due in \(max(1, safeInt(h * 60)))m" }
            return "Due in \(safeInt(h))h"
        case .overdue: return "Overdue"
        case .stillAccepted: return "Still accepted"
        case .courseWeight(let w): return "~\(safeInt(w * 100))% of \(courseCode)"
        case .courseBelowGoal: return "course below your goal"
        case .nearBoundary: return "near a grade boundary"
        case .noDueDate: return "No due date"
        }
    }

    // MARK: - Needs attention and the change chip, as the app showed them (628ee09)

    static func attention(
        _ content: DashboardProjection.AttentionItem.Content, calendar: Calendar, locale: Locale
    ) -> (title: String, subtitle: String) {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                    timeZone: calendar.timeZone)
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar,
                                   timeZone: calendar.timeZone)
        switch content {
        case .missingOpen(let name, let courseCode):
            return ("\(name) is missing", "\(courseCode) · still accepted")
        case .missingClosed(let courseCode):
            return ("\(courseCode): missing work is closed", "Talk to your instructor")
        case .dueSoon(let name, let due, let courseCode):
            return ("\(name) due \(due.formatted(time))", courseCode)
        case .overload(let start):
            return ("Busy stretch starting \(start.formatted(day))", "Several items are due close together")
        case .other(let name, let courseCode):
            return (name, courseCode)
        }
    }

    static func changeSummary(count: Int, asOf: Date, calendar: Calendar, locale: Locale) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                    timeZone: calendar.timeZone)
        return "\(count) change\(count == 1 ? "" : "s") since \(asOf.formatted(time))"
    }
}

/// The differential sweeps `RendererGoldenTests` runs: today's renderers against `LegacyEnglish`
/// over real persona data. Each returns how many strings it compared and every mismatch.
enum RendererSweep {
    struct Outcome {
        var checked = 0
        var mismatches: [String] = []

        mutating func compare(_ new: String, _ old: String, _ label: @autoclosure () -> String) {
            checked += 1
            if new != old { mismatches.append("\(label()): new \(new.debugDescription) vs 628ee09 \(old.debugDescription)") }
        }
    }

    /// Every reminder `ReminderPlanner` plans for `snapshot` at `now` (the Balanced preset), with
    /// "Hide course names" off and on, plus a grade-posted and a below-goal message per course:
    /// `ReminderSubjects`' words against 628ee09's.
    static func notifications(snapshot: CanvasSnapshot, now: Date, timeZone: TimeZone, locale: Locale) -> Outcome {
        var outcome = Outcome()
        let subjects = ReminderSubjects(snapshot: snapshot, now: now)
        var refresh = RefreshRecord()
        refresh.succeeded(dataFetchedAt: now)
        let plan = ReminderPlanner.plan(accountKey: snapshot.accountKey, candidates: subjects.candidates,
                                        settings: ReminderSettings(), now: now, timeZone: timeZone, refresh: refresh)
        let format = ReminderTimeFormat(timeZone: timeZone, locale: locale)
        let legacy = LegacyEnglish.TimeFormat(timeZone: timeZone, locale: locale)
        let lastSuccess = now.addingTimeInterval(-30 * 3600)
        for hide in [false, true] {
            for reminder in plan {
                guard let message = subjects.message(for: reminder, accountKey: snapshot.accountKey, hideCourseNames: hide,
                                                     lastSuccess: lastSuccess, format: format) else { continue }
                let new = format.render(message, seenAt: reminder.fireDate)
                let old = LegacyEnglish.text(for: message, seenAt: reminder.fireDate, format: legacy)
                outcome.compare(new.title, old.title, "\(reminder.id) title")
                outcome.compare(new.body, old.body, "\(reminder.id) body")
                let content = subjects.content(for: reminder, accountKey: snapshot.accountKey, hideCourseNames: hide,
                                               lastSuccess: lastSuccess, format: format)
                outcome.compare(content?.body ?? "<nil>", new.body, "\(reminder.id) content(for:)")
            }
            for course in snapshot.courses {
                for message in [NotificationMessage.gradePosted(.init(courseCode: course.courseCode, hideCourseNames: hide)),
                                .belowGoal(.init(courseCode: course.courseCode, hideCourseNames: hide))] {
                    let new = format.render(message, seenAt: now)
                    let old = LegacyEnglish.text(for: message, seenAt: now, format: legacy)
                    outcome.compare(new.title, old.title, "\(course.courseCode) \(message) title")
                    outcome.compare(new.body, old.body, "\(course.courseCode) \(message) body")
                }
            }
        }
        return outcome
    }

    /// The dashboard `DashboardBuilder` builds for `snapshot` at `now`: every "Next up" reason,
    /// "Needs attention" row and the change chip, against 628ee09's.
    static func dashboard(snapshot: CanvasSnapshot, digest: ChangeDigest?, now: Date, calendar: Calendar,
                          locale: Locale) -> Outcome {
        var outcome = Outcome()
        let projection = DashboardBuilder.build(from: snapshot, digest: digest, digestAsOf: digest == nil ? nil : now, now: now)
        for item in projection.nextUp {
            outcome.compare(DashboardText.reason(item.reasonFactors, courseCode: item.courseCode, locale: locale),
                            LegacyEnglish.reasonText(item.reasonFactors, courseCode: item.courseCode), "reason \(item.id.rawValue)")
        }
        for item in projection.needsAttention {
            let old = LegacyEnglish.attention(item.content, calendar: calendar, locale: locale)
            outcome.compare(DashboardText.attentionTitle(item.content, calendar: calendar, locale: locale), old.title,
                            "\(item.id) title")
            outcome.compare(DashboardText.attentionSubtitle(item.content, locale: locale), old.subtitle, "\(item.id) subtitle")
        }
        if let summary = projection.changeDigestSummary {
            outcome.compare(DashboardText.changeSummary(summary, calendar: calendar, locale: locale),
                            LegacyEnglish.changeSummary(count: summary.count, asOf: summary.asOf, calendar: calendar, locale: locale),
                            "change summary")
        }
        return outcome
    }

    /// The reason over a grid of due times, weights and modifiers (the grid the 628ee09 capture in
    /// the L10N-02 report used), non-finite values included: 628ee09's `reasonText` against the
    /// factors phrased today.
    static func reasonGrid(locale: Locale) -> Outcome {
        var outcome = Outcome()
        let hours: [Double?] = [nil, -5, 0, 0.001, 0.0083, 0.5, 0.99, 1, 1.5, 6, 23.6, 100, 581.4, .infinity, -.infinity, .nan]
        let weights: [Double] = [0, 0.019, 0.02, 0.05, 0.123, 0.125, 1, .nan, .infinity]
        let modifiers: [PriorityScore.Modifiers] = [
            .init(), .init(overdueStillOpen: true), .init(courseBelowGoal: true), .init(nearBoundary: true),
            .init(overdueStillOpen: true, courseBelowGoal: true), .init(overdueStillOpen: true, nearBoundary: true),
            .init(overdueStillOpen: true, courseBelowGoal: true, nearBoundary: true),
        ]
        for h in hours {
            for w in weights {
                for m in modifiers {
                    let factors = PriorityScore.reasonFactors(hoursUntilDue: h, weight: w, modifiers: m)
                    outcome.compare(DashboardText.reason(factors, courseCode: "BIO 101", locale: locale),
                                    LegacyEnglish.reasonText(hoursUntilDue: h, weight: w, modifiers: m, courseCode: "BIO 101"),
                                    "h=\(String(describing: h)) w=\(w) \(m)")
                }
            }
        }
        return outcome
    }

    /// The change chip for every count from 0 to 30 and three times of day.
    static func changeSummaries(calendar: Calendar, locale: Locale) -> Outcome {
        var outcome = Outcome()
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000))
        for asOf in [midnight, midnight.addingTimeInterval(9 * 3600 + 5 * 60), midnight.addingTimeInterval(14 * 3600 + 13 * 60)] {
            for count in 0...30 {
                let summary = DashboardProjection.ChangeSummary(count: count, asOf: asOf)
                outcome.compare(DashboardText.changeSummary(summary, calendar: calendar, locale: locale),
                                LegacyEnglish.changeSummary(count: count, asOf: asOf, calendar: calendar, locale: locale),
                                "\(count) at \(asOf)")
            }
        }
        return outcome
    }
}
