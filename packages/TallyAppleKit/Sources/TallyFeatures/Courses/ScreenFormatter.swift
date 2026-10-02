import Foundation
import TallyDomain
import TallyStrings

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

    /// "Thu", "Oct 12"; `spoken` gives "Thursday", "October 12" for VoiceOver. §3.3 "Relative days":
    /// `Date.RelativeFormatStyle` names today/tomorrow/yesterday in the student's language, instead
    /// of the three hard-coded English words. `TallyFormat.namedDay` works out the offset in whole
    /// days the same way this function already did (`dayOffset`), so a time late tonight never
    /// reads "tomorrow", unchanged from before.
    public func dayText(_ date: Date, spoken: Bool = false) -> String {
        let offset = dayOffset(to: date)
        // Byte-identical to before for every offset `namedDayOffsets` covers: the original always
        // returned the same lowercase word regardless of `spoken` (only the weekday/month branches
        // below varied by it), so the context stays fixed here too.
        if let named = TallyFormat.namedDay(offset: offset, locale: locale) {
            return named
        }
        switch offset {
        case 2...6, -6 ... -2:
            return date.formatted(base.weekday(spoken ? .wide : .abbreviated))
        default:
            return date.formatted(base.month(spoken ? .wide : .abbreviated).day())
        }
    }

    /// "Due today at 11:59 PM", "Due Thu at 9:00 AM", "Due Oct 12"; past dates read "Was due Fri".
    /// `spoken` spells weekdays and months out for VoiceOver. Whole-sentence keys (§3.3 "Sentence
    /// assembly"): word order varies by language, so the already-formatted day/time are placeholders
    /// in a template, never pieced together from independently translated fragments.
    public func dueText(_ due: Date, spoken: Bool = false) -> String {
        let offset = dayOffset(to: due)
        let day = dayText(due, spoken: spoken)
        if due < now {
            return L10n.string(L10n.Courses.wasDue, day)
        }
        // The time matters within the coming week; further out, the day alone.
        return (0...6).contains(offset)
            ? L10n.string(L10n.Courses.dueAtTime, day, timeText(due))
            : L10n.string(L10n.Courses.dueDay, day)
    }

    /// "Fri at 11:59 PM", for "still accepted until …".
    public func untilText(_ date: Date, spoken: Bool = false) -> String {
        L10n.string(L10n.Courses.atTime, dayText(date, spoken: spoken), timeText(date))
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

    /// "90.1%" (en_US), "90,1 %" (fr_FR), "%90,1" (tr_TR): §3.3 "Percent". `TallyFormat.percent`'s
    /// `.scale(1)` rounds the value as given (it is already 0-100), matching this function's old
    /// `.number.precision(.fractionLength(1))` tie-for-tie, so en_US output is unchanged.
    public func percentText(_ percent: Double) -> String {
        TallyFormat.percent(percent, locale: locale)
    }

    /// "90.1 percent", for VoiceOver. The number is locale-aware (§3.3 "Percent"); " percent" is a
    /// whole-sentence key, never a hand-appended English word.
    public func spokenPercent(_ percent: Double) -> String {
        L10n.string(L10n.Insights.spokenPercent, percent.formatted(.number.precision(.fractionLength(1)).locale(locale)))
    }

    /// "92", "8.5": a score or point value with at most two decimals. Not a percentage (§3.3 "Points
    /// and '9/10'": keep the visual form), so `TallyFormat.percent`'s sign placement does not apply.
    public func pointsText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// "50%": a whole-number share of 0…1 (§3.3 "Percent").
    public func shareText(_ share: Double) -> String {
        TallyFormat.share(share, locale: locale)
    }

    /// "40%", "90%", "16.67%" (§3.3 "Percent"): `.percent` FormatStyle, with the same 0...2
    /// fraction-digit trimming as `pointsText` (unlike `percentText`'s fixed 1 digit), for
    /// percent-like values that are not a grade percentage: category/what-if weights, goals and
    /// letter-grade cutoffs.
    public func trimmedPercentText(_ value: Double) -> String {
        value.formatted(.percent.scale(1).precision(.fractionLength(0...2)).locale(locale))
    }

    // MARK: - Letter grades

    /// VoiceOver reads "A-" as "A dash"; say "A minus" instead. §3.3 "Letter grades": the letter
    /// itself is never translated (Canvas's own grading scheme, passed through as data); the spoken
    /// "minus"/"plus" words are catalog keys.
    public static func spokenLetter(_ letter: String) -> String {
        if letter.hasSuffix("-") {
            return L10n.string(L10n.Courses.letterMinus, String(letter.dropLast()))
        }
        if letter.hasSuffix("+") {
            return L10n.string(L10n.Courses.letterPlus, String(letter.dropLast()))
        }
        return letter
    }
}
