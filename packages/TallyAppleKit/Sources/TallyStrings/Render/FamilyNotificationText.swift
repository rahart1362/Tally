import Foundation
import TallyDomain

/// Phrases a `FamilyNotificationMessage` (family-linking.md §6.5, FAM-08; plan 08 L10N-02
/// pattern). TallyCore's `FamilyNotificationMessage`/`FamilyNotificationContentBuilder` build no
/// words and carry no score, percentage or letter grade (R10a, structurally — see that type's
/// own doc comment and `FamilyNotificationMessageTests`); this is only where the words become
/// English, in the parent's locale and time zone. Reuses `NotificationText`'s own date/weekday
/// formatting so a parent's notifications read in the same voice as the student's.
public enum FamilyNotificationText {
    public static func render(_ message: FamilyNotificationMessage, seenAt: Date, timeZone: TimeZone,
                              weekdayNamingDays: Int, locale: Locale = TallyLocale.effective) -> NotificationContent.Rendered {
        func when(_ date: Date) -> String {
            NotificationText.dayTime(date, relativeTo: seenAt, timeZone: timeZone, weekdayNamingDays: weekdayNamingDays, locale: locale)
        }
        switch message {
        case .weekAhead(let student, let count, let busiest):
            let title = resolve(Key.weekAheadTitle(studentLabel(student, locale: locale)), locale)
            let body = busiest.map { Key.weekAheadBodyWithBusiest(count, NotificationText.weekdayName($0, timeZone: timeZone, locale: locale)) }
                ?? Key.weekAheadBody(count)
            return .init(title: title, body: resolve(body, locale))

        case .missingStillOpen(let student, let assignmentTitle, let until):
            let title = resolve(Key.subjectTitle(studentLabel(student, locale: locale), assignmentTitle), locale)
            let body = until.map { Key.stillAcceptedUntil(when($0)) } ?? Key.noClosingDate()
            return .init(title: title, body: resolve(body, locale))

        case .dueReminder(let student, let assignmentTitle, let dueAt, let isFinal):
            let title = resolve(Key.subjectTitle(studentLabel(student, locale: locale), assignmentTitle), locale)
            let body = isFinal ? Key.dueFinalBody(when(dueAt)) : Key.dueBody(when(dueAt))
            return .init(title: title, body: resolve(body, locale))

        case .gradePosted(let student, let courseCode):
            // The course code is Canvas's own text, never translated — same as the student
            // renderer's `courseLabel` (`NotificationText.swift`). Never the grade itself.
            return .init(title: resolve(Key.gradePostedTitle(studentLabel(student, locale: locale)), locale), body: courseCode)

        case .belowGoal(let student, let courseCode):
            return .init(title: resolve(Key.belowGoalTitle(studentLabel(student, locale: locale), courseCode), locale),
                        body: resolve(Key.belowGoalBody(), locale))
        }
    }

    private static func studentLabel(_ student: FamilyNotificationMessage.StudentNameRef, locale: Locale) -> String {
        switch student {
        case .named(let name): name
        case .hidden: resolve(Key.hiddenStudent(), locale)
        }
    }

    /// The catalog keys (`Resources/Localizable.xcstrings`), via `L10n.Family` — matching
    /// `NotificationText`'s own `Key` indirection so every lookup stays one call site.
    private enum Key {
        static func weekAheadTitle(_ student: String) -> LocalizedStringResource { L10n.Family.weekAheadTitle(student: student) }
        static func weekAheadBody(_ count: Int) -> LocalizedStringResource { L10n.Family.weekAheadBody(count) }
        static func weekAheadBodyWithBusiest(_ count: Int, _ day: String) -> LocalizedStringResource {
            L10n.Family.weekAheadBodyWithBusiest(count, day)
        }
        static func subjectTitle(_ student: String, _ assignmentTitle: String) -> LocalizedStringResource {
            L10n.Family.subjectTitle(student: student, assignmentTitle: assignmentTitle)
        }
        static func stillAcceptedUntil(_ when: String) -> LocalizedStringResource { L10n.Family.stillAcceptedUntil(when) }
        static func noClosingDate() -> LocalizedStringResource { L10n.Family.noClosingDate() }
        static func dueBody(_ when: String) -> LocalizedStringResource { L10n.Family.dueBody(when) }
        static func dueFinalBody(_ when: String) -> LocalizedStringResource { L10n.Family.dueFinalBody(when) }
        static func gradePostedTitle(_ student: String) -> LocalizedStringResource { L10n.Family.gradePostedTitle(student: student) }
        static func belowGoalTitle(_ student: String, _ courseCode: String) -> LocalizedStringResource {
            L10n.Family.belowGoalTitle(student: student, courseCode: courseCode)
        }
        static func belowGoalBody() -> LocalizedStringResource { L10n.Family.belowGoalBody() }
        static func hiddenStudent() -> LocalizedStringResource { L10n.Family.hiddenStudent() }
    }
}
