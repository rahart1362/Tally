import Foundation
import TallyDomain

/// The text every M3 screen shows for a date, a score or a letter grade, built once per projection
/// off the main actor (`HomeProjector`), in the student's locale and calendar. Views never format a
/// date relative to "now" themselves: they have no clock (perf-app-runtime.md §3 item 4).
///
/// `nonisolated`: `TallyFeatures` defaults to `MainActor`; this is a pure value used from the
/// projector actor and from tests.
public nonisolated struct ScreenFormatter: Sendable {
    public let now: Date
    public let calendar: Calendar
    public let locale: Locale

    public init(now: Date, calendar: Calendar, locale: Locale) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    // MARK: - Dates

    private var time: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var base: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// Whole calendar days from today to `date`'s day: 0 today, 1 tomorrow, -1 yesterday.
    public func dayOffset(to date: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "11:59 PM" (or "23:59"), in the student's locale.
    public func timeText(_ date: Date) -> String {
        date.formatted(time)
    }

    /// "Thu", "Oct 12"; `spoken` gives "Thursday", "October 12" for VoiceOver.
    public func dayText(_ date: Date, spoken: Bool = false) -> String {
        let offset = dayOffset(to: date)
        switch offset {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6, -6 ... -2:
            return date.formatted(base.weekday(spoken ? .wide : .abbreviated))
        default:
            return date.formatted(base.month(spoken ? .wide : .abbreviated).day())
        }
    }

    /// "Due today at 11:59 PM", "Due Thu at 9:00 AM", "Due Oct 12"; past dates read "Was due Fri".
    /// `spoken` spells weekdays and months out for VoiceOver.
    public func dueText(_ due: Date, spoken: Bool = false) -> String {
        let offset = dayOffset(to: due)
        let day = dayText(due, spoken: spoken)
        if due < now {
            return "Was due \(day)"
        }
        // The time matters within the coming week; further out, the day alone.
        return (0...6).contains(offset) ? "Due \(day) at \(timeText(due))" : "Due \(day)"
    }

    /// "Fri at 11:59 PM", for "still accepted until …".
    public func untilText(_ date: Date, spoken: Bool = false) -> String {
        "\(dayText(date, spoken: spoken)) at \(timeText(date))"
    }

    /// "Mon, Sep 28" (a day heading), "Monday, September 28" when `spoken`.
    public func dayHeading(_ day: Date, spoken: Bool = false) -> String {
        if spoken {
            return day.formatted(base.weekday(.wide).month(.wide).day())
        }
        return day.formatted(base.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "September" (the Calendar tab's title).
    public func monthTitle(_ date: Date) -> String {
        date.formatted(base.month(.wide))
    }

    /// "S", "M" … (the week strip).
    public func weekdayLetter(_ date: Date) -> String {
        date.formatted(base.weekday(.narrow))
    }

    /// "28" (the week strip).
    public func dayNumber(_ date: Date) -> String {
        date.formatted(base.day())
    }

    /// "Oct 12" (charts and ranges).
    public func shortDate(_ date: Date) -> String {
        date.formatted(base.month(.abbreviated).day())
    }

    // MARK: - Numbers

    /// "90.1%": one decimal, in the student's locale.
    public func percentText(_ percent: Double) -> String {
        percent.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%"
    }

    /// "90.1 percent", for VoiceOver.
    public func spokenPercent(_ percent: Double) -> String {
        percent.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " percent"
    }

    /// "92", "8.5": a score or point value with at most two decimals.
    public func pointsText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// "50%": a whole-number share of 0…1.
    public func shareText(_ share: Double) -> String {
        (share * 100).formatted(.number.precision(.fractionLength(0)).locale(locale)) + "%"
    }

    // MARK: - Letter grades

    /// VoiceOver reads "A-" as "A dash"; say "A minus" instead.
    public static func spokenLetter(_ letter: String) -> String {
        var spoken = letter
        if spoken.hasSuffix("-") { spoken = String(spoken.dropLast()) + " minus" }
        if spoken.hasSuffix("+") { spoken = String(spoken.dropLast()) + " plus" }
        return spoken
    }
}
