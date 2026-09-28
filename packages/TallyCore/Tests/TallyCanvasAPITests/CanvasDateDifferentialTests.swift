import Foundation
import Testing
import TallyCanvasAPI
import TallyTestSupport

/// PERF-05 PA-6 (docs/pmo/reviews/perf-algorithms.md): the allocation-free `CanvasDate.parse`
/// against the `Regex` + `DateComponents` parser it replaced. Every result must be exactly equal:
/// the same `Date` bit pattern, or both nil. The one allowed difference is non-ASCII input
/// (non-ASCII digits and Unicode whitespace, which `Regex`'s `\d`/`\s` matched), pinned down by
/// `nonASCIIDigitsAndUnicodeWhitespaceAreTheOnlyDifference`.
@Suite("CanvasDate.parse: byte parser vs the original Regex parser (PERF-05)")
struct CanvasDateDifferentialTests {
    /// The parser as it stood on `pmo/assessment` @ 1ec17ff (`DTO/CanvasJSON.swift:6-29`), verbatim
    /// except that the pattern is an instance property rather than a `nonisolated(unsafe)
    /// static`: a value that is freed with the test needs no LeakSanitizer suppression.
    struct Legacy {
        let pattern = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?\s*(Z|[+-]\d{2}:?\d{2})?)?$/

        func parse(_ text: String) -> Date? {
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

    struct Tally {
        var compared = 0
        var parsed = 0
        var mismatches: [String] = []

        mutating func check(_ text: String, legacy: Legacy) {
            let old = legacy.parse(text)
            let new = CanvasDate.parse(text)
            compared += 1
            if old != nil { parsed += 1 }
            if old?.timeIntervalSinceReferenceDate.bitPattern != new?.timeIntervalSinceReferenceDate.bitPattern {
                mismatches.append("\(text.debugDescription): legacy \(String(describing: old?.timeIntervalSince1970)) "
                    + "new \(String(describing: new?.timeIntervalSince1970))")
            }
        }

        func expectIdentical(_ label: String) {
            print("PERF-05-DIFF | canvasDate/\(label) | compared=\(compared) parsed=\(parsed) mismatches=\(mismatches.count)")
            #expect(mismatches.isEmpty, "\(label): \(mismatches.count) of \(compared) differ; first: \(mismatches.prefix(8))")
        }
    }

    // MARK: - Every string in fixtures/canvas

    private static func strings(in json: Any, into out: inout [String]) {
        if let text = json as? String {
            out.append(text)
        } else if let object = json as? [String: Any] {
            for value in object.values { strings(in: value, into: &out) }
        } else if let array = json as? [Any] {
            for element in array { strings(in: element, into: &out) }
        }
    }

    /// Every string value in every JSON file under `fixtures/canvas` (all personas, scenarios,
    /// expected results and errors), whether or not it is a date: a string that is not a date
    /// must be rejected by both parsers.
    @Test func everyFixtureStringParsesTheSame() throws {
        let root = Fixtures.root()
        var files: [URL] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "json" { files.append(url) }
        }
        #expect(files.count > 300, "only \(files.count) fixture files found under \(root.path)")
        var strings: [String] = []
        for file in files {
            Self.strings(in: try JSONSerialization.jsonObject(with: Data(contentsOf: file), options: .fragmentsAllowed), into: &strings)
        }
        let legacy = Legacy()
        var tally = Tally()
        for text in strings { tally.check(text, legacy: legacy) }
        tally.expectIdentical("fixtures (\(files.count) files)")
        #expect(tally.parsed > 1_000, "only \(tally.parsed) fixture strings are dates")
    }

    // MARK: - Calendar edges, swept

    /// Every month 00...13 and day 00...32 in the years where the calendar's rules change:
    /// year 0000 (rejected), the first Julian years, Julian-only leap years (1500), the 1582
    /// reform and its ten skipped days, the Gregorian century rules (1600, 1700, 1900, 2000,
    /// 2100, 2400) and the last year; each date-only and with a time.
    @Test func calendarEdgesSweepParsesTheSame() {
        let years = [0, 1, 2, 3, 4, 5, 100, 200, 400, 1000, 1500, 1580, 1581, 1582, 1583, 1584, 1600, 1700, 1800, 1900,
                     1970, 2000, 2024, 2025, 2100, 2400, 9998, 9999]
        let legacy = Legacy()
        var tally = Tally()
        for year in years {
            for month in 0...13 {
                for day in 0...32 {
                    let date = String(format: "%04d-%02d-%02d", year, month, day)
                    tally.check(date, legacy: legacy)
                    tally.check(date + "T23:59:59.999999999Z", legacy: legacy)
                    tally.check(date + " 00:00:00 -1159", legacy: legacy)
                }
            }
        }
        tally.expectIdentical("calendar edges")
    }

    // MARK: - Seeded fuzz corpus

    static let fuzzCount = 150_000

    /// Near-valid strings: every field, separator, fraction length, whitespace run and zone
    /// form, in and out of range, then (half the time) one random edit — a truncation at any
    /// length, a deleted, replaced or inserted byte, or trailing junk. Bytes come from all of
    /// ASCII, including every control character.
    static func fuzzString(_ rng: inout SeededRandom) -> String {
        func pick<T>(_ options: [T]) -> T { options[Int(rng.next() % UInt64(options.count))] }
        func number(_ range: ClosedRange<Int>, width: Int) -> String {
            let n = Int.random(in: range, using: &rng)
            let digits = String(n)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        let year = Int.random(in: 0..<10, using: &rng) < 3
            ? number(0...9999, width: 4)
            : String(format: "%04d", pick([0, 1, 4, 1500, 1582, 1583, 1600, 1700, 1900, 1970, 2000, 2024, 2025, 2026, 2100, 9999]))
        var s = year + "-" + number(0...14, width: 2) + "-" + pick([number(0...33, width: 2), "29", "28", "30", "31", "05", "14", "15"])
        if Int.random(in: 0..<10, using: &rng) != 0 {
            s += pick(["T", "T", " ", "t", "_"])
            s += number(0...25, width: 2) + ":" + number(0...61, width: 2) + ":" + number(0...61, width: 2)
            if Bool.random(using: &rng) {
                s += "." + (0..<Int.random(in: 0...11, using: &rng)).map { _ in String(Int.random(in: 0...9, using: &rng)) }.joined()
            }
            s += (0..<pick([0, 0, 0, 1, 2, 5])).map { _ in pick([" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{1C}", "\u{1F}", "\u{00}"]) }.joined()
            s += pick(["", "Z", "Z", "z", "+00:00", "-00:00", "+0000", "-05:00", "+05:30", "-0930", "+14:00", "-12:00",
                       "+99:99", "+9999", "+5:30", "+05:3", "+05:300", "+05::30", "-", "+", "UTC", "GMT"])
        }
        if Bool.random(using: &rng) {
            var bytes = Array(s.utf8)
            let at = Int.random(in: 0...bytes.count, using: &rng)
            let byte = UInt8.random(in: 0...0x7F, using: &rng)
            switch Int.random(in: 0..<5, using: &rng) {
            case 0: bytes = Array(bytes.prefix(at)) // truncate: every length
            case 1: if at < bytes.count { bytes.remove(at: at) }
            case 2: if at < bytes.count { bytes[at] = byte }
            case 3: bytes.insert(byte, at: at)
            default: bytes += pick([" ", "Z", "0", "x", "\u{00}"]).utf8
            }
            s = String(decoding: bytes, as: UTF8.self)
        }
        return s
    }

    @Test func seededFuzzCorpusParsesTheSame() {
        var rng = SeededRandom(seed: 0xDA7E_0006)
        let legacy = Legacy()
        var tally = Tally()
        for _ in 0..<Self.fuzzCount { tally.check(Self.fuzzString(&rng), legacy: legacy) }
        tally.expectIdentical("fuzz")
        // The corpus must keep a real share of valid dates, or equality would mostly be both
        // parsers saying nil. This seed parses 16,264 of 150,000; the floor is about half that.
        #expect(tally.compared == Self.fuzzCount && tally.parsed > 8_000, "only \(tally.parsed) of \(tally.compared) parsed")
    }

    // MARK: - The allowed difference

    /// `Regex`'s `\d` and `\s` match non-ASCII digits and Unicode whitespace; the byte parser
    /// does not. Every input below differs only in that way from a valid ASCII date, and the new
    /// parser rejects each one. What the old parser did with them is printed for the record.
    @Test func nonASCIIDigitsAndUnicodeWhitespaceAreTheOnlyDifference() {
        let legacy = Legacy()
        let inputs = [
            "٢٠٢٦-٠٩-٢٨", "2026-09-2٨", "2026-09-28T1٣:00:00Z", "２０２６-０９-２８", "2026-09-28T13:00:00.１２３Z",
            "2026-09-28T13:00:00\u{00A0}Z", "2026-09-28T13:00:00\u{2003}Z", "2026-09-28T13:00:00\u{3000}", "2026-09-28T13:00:00\u{85}+05:00",
        ]
        for text in inputs {
            let old = legacy.parse(text)
            print("PERF-05-DIFF | canvasDate/non-ASCII | \(text.debugDescription): legacy \(String(describing: old?.timeIntervalSince1970)) new nil")
            #expect(CanvasDate.parse(text) == nil, "\(text.debugDescription) must be rejected")
        }
        // And the ASCII twins of the same inputs agree exactly.
        var tally = Tally()
        for text in ["2026-09-28", "2026-09-28T13:00:00Z", "2026-09-28T13:00:00.123Z", "2026-09-28T13:00:00 Z",
                     "2026-09-28T13:00:00\t+05:00", "2026-09-28T13:00:00\r\n"] {
            tally.check(text, legacy: legacy)
        }
        tally.expectIdentical("ASCII twins")
    }
}
