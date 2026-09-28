import Foundation

/// R-1 (resilience.md): the `Retry-After` response header (RFC 9110 §10.2.3), read as a wait.
/// Canvas's throttling policy expects clients to back off. When a rate-limited response says how
/// long, `CanvasClient` waits at least that long, or stops if the wait would not fit in the
/// request's budget.
enum RetryAfter {
    /// The longest `delay-seconds` value read as written, about 31.7 years. A longer one, such as a
    /// 30-digit number, reads as this; it is past every budget either way, and the cap keeps the
    /// arithmetic from overflowing.
    static let longestDelaySeconds: Int64 = 999_999_999

    /// The wait `response` asks for, or nil when it has no `Retry-After` header in either form.
    /// - delay-seconds (`"120"`): that many seconds.
    /// - HTTP-date (`"Sun, 06 Nov 1994 08:49:37 GMT"`, or an obsolete form): the time from the
    ///   response's own `Date` header to it. Both come from the server's clock, so a wrong device
    ///   clock cannot stretch or shrink the wait. Without a usable `Date` header, from `now`.
    ///
    /// A date already past is a zero wait.
    static func delay(in response: HTTPResponse, now: Date) -> Duration? {
        guard let value = response.headers["Retry-After"] else { return nil }
        let reference = response.headers["Date"].flatMap { HTTPDate.parse($0, now: now) } ?? now
        return delay(value, reference: reference)
    }

    /// `value` as a wait from `reference`, or nil when it is in neither form.
    static func delay(_ value: String, reference: Date) -> Duration? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if let seconds = delaySeconds(text) { return .seconds(seconds) }
        guard let date = HTTPDate.parse(text, now: reference) else { return nil }
        // Capped like delay-seconds, so the milliseconds always fit in `Int64`, whatever `reference`
        // is. A NaN wait fails `> 0` and reads as zero.
        let wait = min(date.timeIntervalSince(reference), Double(longestDelaySeconds))
        return wait > 0 ? .milliseconds(Int64((wait * 1_000).rounded(.up))) : .zero
    }

    /// `1*DIGIT`, capped at `longestDelaySeconds`; nil for anything else (a sign, a fraction, a date).
    private static func delaySeconds(_ text: String) -> Int64? {
        guard !text.isEmpty else { return nil }
        var seconds: Int64 = 0
        for byte in text.utf8 {
            guard (0x30...0x39).contains(byte) else { return nil }
            seconds = min(seconds * 10 + Int64(byte - 0x30), longestDelaySeconds)
        }
        return seconds
    }
}

/// HTTP-date (RFC 9110 §5.6.7), always GMT. A recipient must accept all three forms:
/// - IMF-fixdate: `Sun, 06 Nov 1994 08:49:37 GMT`;
/// - obsolete RFC 850: `Sunday, 06-Nov-94 08:49:37 GMT`;
/// - obsolete asctime: `Sun Nov  6 08:49:37 1994`.
enum HTTPDate {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let shortDays: Set<String> = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private static let longDays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    /// `now` places an RFC 850 two-digit year: RFC 9110 reads one that would be more than 50 years
    /// ahead of `now` as the most recent past year with those two digits. The day name is only
    /// checked for being one; whether it matches the date is not checked.
    static func parse(_ text: String, now: Date) -> Date? {
        let fields = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        switch fields.count {
        case 6: // IMF-fixdate
            guard fields[0].hasSuffix(","), shortDays.contains(String(fields[0].dropLast()).lowercased()),
                  fields[5] == "GMT", let day = number(fields[1], digits: 2...2), let month = month(fields[2]),
                  let year = number(fields[3], digits: 4...4)
            else { return nil }
            return date(year: year, month: month, day: day, time: fields[4])
        case 4: // RFC 850
            let parts = fields[1].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard fields[0].hasSuffix(","), longDays.contains(String(fields[0].dropLast()).lowercased()),
                  fields[3] == "GMT", parts.count == 3, let day = number(parts[0], digits: 2...2),
                  let month = month(parts[1]), let twoDigitYear = number(parts[2], digits: 2...2)
            else { return nil }
            return date(year: fullYear(twoDigitYear, now: now), month: month, day: day, time: fields[2])
        case 5: // asctime
            guard shortDays.contains(fields[0].lowercased()), let month = month(fields[1]),
                  let day = number(fields[2], digits: 1...2), let year = number(fields[4], digits: 4...4)
            else { return nil }
            return date(year: year, month: month, day: day, time: fields[3])
        default:
            return nil
        }
    }

    private static func month(_ text: String) -> Int? {
        months.firstIndex(of: text.lowercased()).map { $0 + 1 }
    }

    /// ASCII digits only (`Int("+6")` would accept a sign), with a length in `digits`.
    private static func number(_ text: some StringProtocol, digits: ClosedRange<Int>) -> Int? {
        guard digits.contains(text.utf8.count), text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(text)
    }

    /// `HH:MM:SS`, with a leap second allowed.
    private static func date(year: Int, month: Int, day: Int, time: String) -> Date? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...9999).contains(year), parts.count == 3, let hour = number(parts[0], digits: 2...2),
              let minute = number(parts[1], digits: 2...2), let second = number(parts[2], digits: 2...2),
              (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second),
              let days = CanvasDate.daysSince1970(year: year, month: month, day: day)
        else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + hour * 3_600 + minute * 60 + second))
    }

    private static func fullYear(_ twoDigits: Int, now: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let thisYear = calendar.component(.year, from: now)
        var year = thisYear - thisYear % 100 + twoDigits
        if year > thisYear + 50 { year -= 100 }
        return year
    }
}
