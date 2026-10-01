import Foundation
import TallyDomain

/// Phrases a `NotificationMessage` (plan 08 §3.2, L10N-02). TallyCore builds the message as values
/// (no score or grade in any case, R10; no Canvas name at all when "Hide course names" is on); this
/// is where it becomes words, in the student's language, with its dates in the student's locale and
/// time zone. Every sentence is one catalog key with positional placeholders, so a translation can
/// reorder it. Canvas titles and course codes are passed through untouched.
///
/// English is byte-identical to what TallyCore's `NotificationContent` builders and the reminders'
/// `ReminderTimeFormat` produced before L10N-02 (`RendererGoldenTests` in TallyAppTests).
public enum NotificationText {
    /// `message`'s title and body, with its dates relative to `seenAt` (the fire date: when the
    /// student sees it, not when it was planned). `weekdayNamingDays`: see `dayTime`.
    public static func render(
        _ message: NotificationMessage, seenAt: Date, timeZone: TimeZone, weekdayNamingDays: Int,
        locale: Locale = TallyLocale.effective
    ) -> NotificationContent.Rendered {
        func when(_ date: Date) -> String {
            dayTime(date, relativeTo: seenAt, timeZone: timeZone, weekdayNamingDays: weekdayNamingDays, locale: locale)
        }
        let title: LocalizedStringResource, body: LocalizedStringResource
        switch message {
        case .due(let subject, let dueAt, let isFinal):
            return .init(title: subjectTitle(subject, locale: locale),
                         body: resolve(isFinal ? Key.dueFinalBody(when(dueAt)) : Key.dueBody(when(dueAt)), locale))
        case .missingFollowup(let subject, let until):
            return .init(title: subjectTitle(subject, locale: locale),
                         body: resolve(until.map { Key.stillAcceptedUntil(when($0)) } ?? Key.noClosingDate(), locale))
        case .examReminder(let subject, let dueAt):
            return .init(title: subjectTitle(subject, locale: locale), body: resolve(Key.examBody(when(dueAt)), locale))
        case .gradePosted(let course):
            return .init(title: resolve(Key.gradePostedTitle(), locale), body: courseLabel(course, locale: locale))
        case .belowGoal(let course):
            title = Key.belowGoalTitle(courseLabel(course, locale: locale))
            body = Key.belowGoalBody()
        case .eveningDigest(let count, let first):
            title = Key.digestTitle()
            switch first {
            case .title(let name)?: body = Key.digestCountWithFirst(count, name)
            case .hidden?: body = Key.digestCountWithFirst(count, resolve(Key.hiddenItem(), locale))
            case nil: body = Key.digestCount(count)
            }
        case .weekAhead(let count, let busiest):
            title = Key.weekAheadTitle()
            body = busiest.map { Key.weekAheadCountWithBusiest(count, weekdayName($0, timeZone: timeZone, locale: locale)) }
                ?? Key.weekAheadCount(count)
        case .sentinel(let lastSuccess):
            title = Key.sentinelTitle(when(lastSuccess))
            body = Key.sentinelBody()
        }
        return .init(title: resolve(title, locale), body: resolve(body, locale))
    }

    /// "today at 6:00 PM", "tomorrow at …", "yesterday at …", "Fri at …" within
    /// `weekdayNamingDays` either way (the reminders' `RemindersConfig.weekdayNamingDays`), else
    /// "Oct 9 at …": `date` relative to `reference`, by calendar day in `timeZone`.
    public static func dayTime(_ date: Date, relativeTo reference: Date, timeZone: TimeZone, weekdayNamingDays: Int,
                               locale: Locale = TallyLocale.effective) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                           to: calendar.startOfDay(for: date)).day ?? Int.max
        let window = max(0, weekdayNamingDays)
        let day: String
        switch days {
        case TallyFormat.namedDayOffsets:
            day = TallyFormat.namedDay(offset: days, locale: locale)
                ?? date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
        case -window...window:
            day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
        default:
            day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day())
        }
        return resolve(Key.dayAtTime(day, time(date, timeZone: timeZone, locale: locale)), locale)
    }

    /// "6:00 PM" (en_US), "18:00" (en_GB): a time of day in `timeZone`.
    public static func time(_ date: Date, timeZone: TimeZone, locale: Locale = TallyLocale.effective) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// "Thursday": the full weekday name of `day` in `timeZone`.
    static func weekdayName(_ day: Date, timeZone: TimeZone, locale: Locale) -> String {
        day.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.wide))
    }

    private static func subjectTitle(_ subject: NotificationMessage.Subject, locale: Locale) -> String {
        switch subject {
        case .assignment(let title, let courseCode): resolve(Key.subject(title, courseCode), locale)
        case .hidden: resolve(Key.hiddenSubject(), locale)
        }
    }

    private static func courseLabel(_ course: NotificationMessage.CourseName, locale: Locale) -> String {
        switch course {
        case .code(let code): code
        case .hidden: resolve(Key.hiddenCourse(), locale)
        }
    }

    /// The catalog keys (`Resources/Localizable.xcstrings`). The `defaultValue` is only the
    /// fallback when a lookup finds nothing; the catalog holds the text.
    private enum Key {
        static func subject(_ title: String, _ courseCode: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.subject.assignment", defaultValue: "\(title) · \(courseCode)", bundle: #bundle,
                                    comment: "Notification title naming an assignment. 1: the assignment's title from Canvas. 2: its course code from Canvas.")
        }
        static func hiddenSubject() -> LocalizedStringResource {
            LocalizedStringResource("notification.subject.hidden", defaultValue: "An assignment", bundle: #bundle,
                                    comment: "Notification title when the student turned on Hide Course Names: it stands for the assignment's title and course.")
        }
        static func hiddenCourse() -> LocalizedStringResource {
            LocalizedStringResource("notification.course.hidden", defaultValue: "a course", bundle: #bundle,
                                    comment: "Stands for a course name when the student turned on Hide Course Names. Shown alone as a notification body, and at the start of 'needs attention' titles.")
        }
        static func hiddenItem() -> LocalizedStringResource {
            LocalizedStringResource("notification.digest.hiddenItem", defaultValue: "An assignment", bundle: #bundle,
                                    comment: "Stands for an assignment's title in the evening digest when the student turned on Hide Course Names.")
        }
        static func dueBody(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.due.body", defaultValue: "Due \(when).", bundle: #bundle,
                                    comment: "Due-date reminder body. The argument is a day and time, such as 'today at 6:00 PM' or 'Fri at 11:59 PM'.")
        }
        static func dueFinalBody(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.due.finalBody", defaultValue: "Due \(when), if you haven't submitted yet.", bundle: #bundle,
                                    comment: "The last due-date reminder's body: Tally cannot know whether the work was submitted since. The argument is a day and time, such as 'today at 6:00 PM'.")
        }
        static func stillAcceptedUntil(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.missing.stillAcceptedUntil", defaultValue: "Still accepted until \(when).", bundle: #bundle,
                                    comment: "Missing-work reminder body: Canvas still accepts the work until the given day and time, such as 'Fri at 11:59 PM'.")
        }
        static func noClosingDate() -> LocalizedStringResource {
            LocalizedStringResource("notification.missing.noClosingDate", defaultValue: "Past due. Canvas lists no closing date.", bundle: #bundle,
                                    comment: "Missing-work reminder body when Canvas gives no date after which the work is no longer accepted. 'Canvas' is a product name.")
        }
        static func examBody(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.exam.body", defaultValue: "Due \(when).", bundle: #bundle,
                                    comment: "Exam reminder body. The argument is a day and time, such as 'tomorrow at 9:00 AM'.")
        }
        static func gradePostedTitle() -> LocalizedStringResource {
            LocalizedStringResource("notification.gradePosted.title", defaultValue: "New grade posted", bundle: #bundle,
                                    comment: "Notification title when a teacher posts a grade. The body names the course; the grade itself is never shown.")
        }
        static func belowGoalTitle(_ course: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.belowGoal.title", defaultValue: "\(course) needs attention", bundle: #bundle,
                                    comment: "Notification title when a course falls below the student's goal. The argument is the course code from Canvas, or 'a course' when course names are hidden.")
        }
        static func belowGoalBody() -> LocalizedStringResource {
            LocalizedStringResource("notification.belowGoal.body", defaultValue: "Open Tally to see your standing.", bundle: #bundle,
                                    comment: "Body of the 'needs attention' notification. 'Tally' is the app's name. The score is never shown in a notification.")
        }
        static func digestTitle() -> LocalizedStringResource {
            LocalizedStringResource("notification.digest.title", defaultValue: "Tomorrow", bundle: #bundle,
                                    comment: "Title of the evening digest notification, which lists what is due tomorrow.")
        }
        static func digestCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("notification.digest.count", defaultValue: "\(count) due", bundle: #bundle,
                                    comment: "Evening digest body: how many items are due.")
        }
        static func digestCountWithFirst(_ count: Int, _ first: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.digest.countWithFirst", defaultValue: "\(count) due · \(first) first", bundle: #bundle,
                                    comment: "Evening digest body. 1: how many items are due. 2: the title of the first one due, from Canvas (or 'An assignment' when hidden).")
        }
        static func weekAheadTitle() -> LocalizedStringResource {
            LocalizedStringResource("notification.weekAhead.title", defaultValue: "This week", bundle: #bundle,
                                    comment: "Title of the Sunday notification that summarizes the week ahead.")
        }
        static func weekAheadCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("notification.weekAhead.count", defaultValue: "\(count) due", bundle: #bundle,
                                    comment: "Week-ahead body: how many items are due in the next 7 days.")
        }
        static func weekAheadCountWithBusiest(_ count: Int, _ day: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.weekAhead.countWithBusiest", defaultValue: "\(count) due · busiest \(day)", bundle: #bundle,
                                    comment: "Week-ahead body. 1: how many items are due in the next 7 days. 2: the weekday with the most, such as 'Thursday'.")
        }
        static func sentinelTitle(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.sentinel.title", defaultValue: "Tally hasn't refreshed since \(when)", bundle: #bundle,
                                    comment: "Notification title when Tally's data is stale. The argument is a day and time, such as 'yesterday at 2:14 PM'. 'Tally' is the app's name.")
        }
        static func sentinelBody() -> LocalizedStringResource {
            LocalizedStringResource("notification.sentinel.body", defaultValue: "Open Tally to update your reminders.", bundle: #bundle,
                                    comment: "Body of the stale-data notification. 'Tally' is the app's name.")
        }
        static func dayAtTime(_ day: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.dayAtTime", defaultValue: "\(day) at \(time)", bundle: #bundle,
                                    comment: "A day and a time in a reminder. 1: 'today', 'tomorrow', 'yesterday', a short weekday ('Fri') or a short date ('Oct 9'). 2: a time ('6:00 PM').")
        }
    }
}
