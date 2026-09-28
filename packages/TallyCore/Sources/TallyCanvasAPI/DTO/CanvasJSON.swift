import Foundation

/// Parses every timestamp form Canvas and its docs use (fixtures/canvas/scenarios/dates):
/// `...Z`, `±HH:MM`, `±HHMM`, 1–9 fractional digits, date-only, and `YYYY-MM-DD HH:MM:SS +0000`.
/// Foundation's `.iso8601` strategy rejects fractions, hence this parser.
///
/// PERF-05 PA-6 (docs/pmo/reviews/perf-algorithms.md): a single pass over the string's UTF-8
/// bytes with no allocation, replacing a Swift `Regex` match plus a `Calendar`, `TimeZone` and
/// `DateComponents` per call, which was 62-63% of the stress-scale mapper decode (~10 µs per
/// date). It accepts exactly what that regex accepted, for ASCII input:
///
///     YYYY-MM-DD [ (T|space) HH:MM:SS [ .F{1,9} ] WS* [ Z | (+|-)HH[:]MM ] ]
///
/// where `WS` is ASCII whitespace (tab, LF, VT, FF, CR, space) and the offset's hours and minutes
/// are two digits each with no range check. It returns the same `Date`, bit for bit:
/// - The calendar is Foundation's `.gregorian` exactly as `DateComponents.isValidDate` and `.date`
///   applied it: proleptic Gregorian from 1582-10-15 on, the Julian calendar before that (the
///   Gregorian reform's cutover, as in ICU), 1582-10-05...14 and year 0000 invalid, hours 0-23,
///   minutes and seconds 0-59. Verified against the old code over all 4,620,000 date-only strings
///   0000-00-00...9999-13-32 and 8,000,000 date-times, with no difference.
/// - The fraction is `Double(digits) / 10^count`: both operands are exact, so the one rounding
///   gives the same correctly rounded value `Double("0." + digits)` did.
/// - Fraction then offset are applied in the old order, with the same operations.
/// The one difference is non-ASCII input: Swift `Regex`'s `\d` and `\s` also matched non-ASCII
/// digits and Unicode whitespace, which this parser rejects. `CanvasDateDifferentialTests` holds
/// the rest to exact equality against the old parser, kept there as a test-only reference.
public enum CanvasDate {
    public static func parse(_ text: String) -> Date? {
        var input = ASCIIInput(text)
        guard let year = input.number(digits: 4), input.consume(ASCII.hyphen),
              let month = input.number(digits: 2), input.consume(ASCII.hyphen),
              let day = input.number(digits: 2) else { return nil }

        var secondOfDay = 0
        var fraction: Double?
        var zone: (seconds: Int, isNegative: Bool)?
        if !input.isAtEnd {
            guard input.consume(ASCII.letterT) || input.consume(ASCII.space),
                  let hour = input.number(digits: 2), input.consume(ASCII.colon),
                  let minute = input.number(digits: 2), input.consume(ASCII.colon),
                  let second = input.number(digits: 2) else { return nil }
            guard hour <= 23, minute <= 59, second <= 59 else { return nil }
            secondOfDay = hour * 3_600 + minute * 60 + second

            if input.consume(ASCII.period) {
                var digits = 0, scale = 1.0, count = 0
                while let digit = input.digit() {
                    guard count < maxFractionDigits else { return nil }
                    digits = digits * 10 + digit
                    scale *= 10
                    count += 1
                }
                guard count > 0 else { return nil }
                fraction = Double(digits) / scale
            }
            input.skipWhitespace()
            if input.consume(ASCII.letterZ) {
                // UTC: nothing to subtract, as before.
            } else if let sign = input.current, sign == ASCII.plus || sign == ASCII.minus {
                input.advance()
                guard let offsetHours = input.number(digits: 2) else { return nil }
                _ = input.consume(ASCII.colon)
                guard let offsetMinutes = input.number(digits: 2) else { return nil }
                zone = (offsetHours * 3_600 + offsetMinutes * 60, sign == ASCII.minus)
            }
            guard input.isAtEnd else { return nil }
        }

        guard let days = daysSince1970(year: year, month: month, day: day) else { return nil }
        var seconds = Double(days * 86_400 + secondOfDay)
        if let fraction { seconds += fraction }
        if let zone { seconds -= zone.isNegative ? -Double(zone.seconds) : Double(zone.seconds) }
        return Date(timeIntervalSince1970: seconds)
    }

    /// `\.(\d{1,9})`: a tenth digit meant the old pattern could not match.
    private static let maxFractionDigits = 9

    // MARK: - Foundation's `.gregorian` calendar, as `DateComponents.isValidDate` sees it

    /// The first day of the Gregorian calendar; the day before it is Julian 1582-10-04.
    private static let gregorianStart = (year: 1582, month: 10, day: 15)
    /// The first of the ten dates the 1582 reform skipped (1582-10-05...14), which Foundation's
    /// hybrid calendar rejects.
    private static let reformGapStartDay = 5

    /// Days from 1970-01-01 to the date, or nil when Foundation's `.gregorian` calendar rejects it.
    static func daysSince1970(year: Int, month: Int, day: Int) -> Int? {
        guard (1...12).contains(month), day >= 1 else { return nil }
        let start = gregorianStart
        if (year, month, day) >= (start.year, start.month, start.day) {
            let isLeap = (year.isMultiple(of: 4) && !year.isMultiple(of: 100)) || year.isMultiple(of: 400)
            guard day <= daysIn(month: month, isLeap: isLeap) else { return nil }
            return gregorianDaysSince1970(year: year, month: month, day: day)
        }
        guard (year, month, day) < (start.year, start.month, reformGapStartDay), year >= 1,
              day <= daysIn(month: month, isLeap: year.isMultiple(of: 4)) else { return nil }
        return julianDaysSince1970(year: year, month: month, day: day)
    }

    private static func daysIn(month: Int, isLeap: Bool) -> Int {
        switch month {
        case 2: isLeap ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Howard Hinnant's `days_from_civil` for the (proleptic) Gregorian calendar
    /// (https://howardhinnant.github.io/date_algorithms.html). Only called for years >= 1582,
    /// so every division below is of a non-negative number.
    private static func gregorianDaysSince1970(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = y / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The Julian calendar's Julian Day Number (Richards' algorithm, as in the Explanatory
    /// Supplement to the Astronomical Almanac), shifted so 1970-01-01 (JDN 2440588) is day 0.
    private static func julianDaysSince1970(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4_800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32_083 - 2_440_588
    }

    // MARK: - Input

    private enum ASCII {
        static let hyphen = UInt8(ascii: "-"), colon = UInt8(ascii: ":"), period = UInt8(ascii: ".")
        static let plus = UInt8(ascii: "+"), minus = UInt8(ascii: "-"), space = UInt8(ascii: " ")
        static let letterT = UInt8(ascii: "T"), letterZ = UInt8(ascii: "Z")
        static let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
    }

    /// A cursor over the string's UTF-8 bytes, one byte of lookahead, no allocation.
    private struct ASCIIInput {
        private var iterator: String.UTF8View.Iterator
        private(set) var current: UInt8?

        init(_ text: String) {
            iterator = text.utf8.makeIterator()
            current = iterator.next()
        }

        var isAtEnd: Bool { current == nil }

        mutating func advance() { current = iterator.next() }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard current == byte else { return false }
            advance()
            return true
        }

        /// The next byte's value if it is an ASCII digit (consumed), else nil (nothing consumed).
        mutating func digit() -> Int? {
            guard let byte = current, byte >= ASCII.zero, byte <= ASCII.nine else { return nil }
            advance()
            return Int(byte - ASCII.zero)
        }

        mutating func number(digits count: Int) -> Int? {
            var value = 0
            for _ in 0..<count {
                guard let digit = digit() else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        /// `\s*` over ASCII: tab, LF, VT, FF, CR (0x09...0x0D) and space.
        mutating func skipWhitespace() {
            while let byte = current, byte == ASCII.space || (0x09...0x0D).contains(byte) { advance() }
        }
    }
}

public enum CanvasJSON {
    /// The decoder every Canvas DTO goes through.
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = CanvasDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised Canvas date")
            }
            return date
        }
        return decoder
    }
}
