import Foundation
import Synchronization

/// Locale-aware formatting helpers (plan 08 §3.3). Each takes the locale explicitly, defaulting
/// to `TallyLocale.effective`, so tests pin it and callers never format with a different locale
/// from the words around the value. Nothing here concatenates a symbol or a word onto a number:
/// the sign's position and spacing vary by locale ("90.1%", "90,1 %", "%90,1").
///
/// The screens adopt these in L10N-03a/03b (`ScreenFormatter`, `FreshnessPresenter`); until
/// then their English output is unchanged.
public enum TallyFormat {
    /// Decimal places for a grade percentage ("90.1%"), as the screens show it today.
    public static let percentFractionDigits = 1
    /// The day offsets that have a name ("yesterday", "today", "tomorrow"); others use a date.
    public static let namedDayOffsets = -1...1

    /// "90.1%" (en_US), "90,1 %" (fr_FR), "%90,1" (tr_TR): a percentage on a 0-100 scale.
    ///
    /// `.scale(1)`: the value is already a percentage, so it is rounded as given. Dividing by 100
    /// first moves ties in binary (9.95 / 100 rounds to "9.9%"), which would change the English
    /// the screens show today ("10.0%", `ScreenFormatter.percentText`); a hosted test checks the
    /// two agree for en_US.
    public static func percent(
        _ percent: Double, fractionDigits: Int = percentFractionDigits, locale: Locale = TallyLocale.effective
    ) -> String {
        percent.formatted(.percent.scale(1).precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// "50%": a share on a 0-1 scale, as a whole percentage (rounded as `ScreenFormatter.shareText`
    /// rounds it, for the same reason as `percent`).
    public static func share(_ share: Double, locale: Locale = TallyLocale.effective) -> String {
        percent(share * 100, fractionDigits: 0, locale: locale)
    }

    /// "2:05 PM" (en_US), "14:05" (en_GB, de_DE): a time of day in `calendar`'s time zone, with
    /// the locale's 12- or 24-hour clock (or the user's override, which `TallyLocale.effective`
    /// keeps).
    public static func time(_ date: Date, calendar: Calendar, locale: Locale = TallyLocale.effective) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                        calendar: calendar, timeZone: calendar.timeZone))
    }

    /// "today", "tomorrow", "yesterday" ("hoy", "mañana", "ayer") for a whole-day offset in
    /// `namedDayOffsets`, capitalized for `context`; `nil` for any other offset. The caller works
    /// out the offset in its own calendar (`ScreenFormatter.dayOffset(to:)`), so a time late
    /// tonight never reads "tomorrow".
    public static func namedDay(
        offset: Int, context: Formatter.Context = .middleOfSentence, locale: Locale = TallyLocale.effective
    ) -> String? {
        guard namedDayOffsets.contains(offset) else { return nil }
        // Cached per locale, context and offset. A new `RelativeDateTimeFormatter` for every due
        // date in Course Detail, the course cards and To-Do kept PR #27's sample-entry projection
        // over its 0.15 s budget (runs 36956322638, 36962237376: 0.1795-0.2760 s).
        let key = NamedDayKey(locale: locale.identifier, context: context.rawValue, offset: offset)
        if let cached = namedDayCache.strings.withLock({ $0[key] }) { return cached }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.formattingContext = context
        let text = formatter.localizedString(from: DateComponents(day: offset))
        namedDayCache.strings.withLock { $0[key] = text }
        return text
    }

    private struct NamedDayKey: Hashable, Sendable {
        let locale: String
        let context: Int
        let offset: Int
    }

    /// At most a few entries per locale: 3 offsets × the contexts in use.
    private final class NamedDayCache: Sendable {
        let strings = Mutex<[NamedDayKey: String]>([:])
    }

    private static let namedDayCache = NamedDayCache()

    /// "A, B, and C" (en_US), "A, B y C" (es): items joined the way the locale joins a list.
    public static func list(_ items: [String], locale: Locale = TallyLocale.effective) -> String {
        items.formatted(.list(type: .and).locale(locale))
    }
}
