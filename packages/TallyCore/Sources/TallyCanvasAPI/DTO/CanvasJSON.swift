import Foundation

/// Parses every timestamp form Canvas and its docs use (fixtures/canvas/scenarios/dates):
/// `...Z`, `±HH:MM`, `±HHMM`, 1–9 fractional digits, date-only, and `YYYY-MM-DD HH:MM:SS +0000`.
/// Foundation's `.iso8601` strategy rejects fractions, hence this parser.
public enum CanvasDate {
    nonisolated(unsafe) private static let pattern =
        /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?\s*(Z|[+-]\d{2}:?\d{2})?)?$/

    public static func parse(_ text: String) -> Date? {
        guard let m = text.wholeMatch(of: pattern) else { return nil }
        var parts = DateComponents()
        parts.calendar = Calendar(identifier: .gregorian)
        parts.timeZone = TimeZone(secondsFromGMT: 0)
        parts.year = Int(m.1); parts.month = Int(m.2); parts.day = Int(m.3)
        parts.hour = m.4.flatMap { Int($0) } ?? 0
        parts.minute = m.5.flatMap { Int($0) } ?? 0
        parts.second = m.6.flatMap { Int($0) } ?? 0
        guard parts.isValidDate, let base = parts.date else { return nil }
        var seconds = base.timeIntervalSince1970
        if let fraction = m.7 { seconds += Double("0." + fraction) ?? 0 }
        if let zone = m.8, zone != "Z" {
            let digits = zone.dropFirst().filter(\.isNumber)
            let offset = (Int(digits.prefix(2)) ?? 0) * 3600 + (Int(digits.suffix(2)) ?? 0) * 60
            seconds -= zone.first == "-" ? -Double(offset) : Double(offset)
        }
        return Date(timeIntervalSince1970: seconds)
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
