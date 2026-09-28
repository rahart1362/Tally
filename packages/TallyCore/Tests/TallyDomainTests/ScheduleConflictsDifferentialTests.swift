import Foundation
import Testing
import TallyDomain
import TallyTestSupport

/// PERF-05 PA-3 (docs/pmo/reviews/perf-algorithms.md): `AlertEngine.scheduleConflicts`' sweep
/// against the all-pairs double loop it replaced, over a seeded corpus of schedules. The result
/// must be `==`: the same alerts, in the same order.
///
/// The corpus is built to sit on the sweep's pruning boundary: instants exactly `closeDueGap`
/// apart (and one second either side), instants exactly at an interval's start or end, items
/// sharing a start, inverted intervals (end before start), zero-length intervals, and
/// NaN/infinite dates, which the sweep has to handle without losing a pair.
@Suite("AlertEngine.scheduleConflicts: sweep vs the original all-pairs loop (PERF-05)")
struct ScheduleConflictsDifferentialTests {
    /// `scheduleConflicts` and `overlaps` exactly as they stood on `pmo/assessment` @ 1ec17ff
    /// (`Alerts/AlertEngine.swift:227-253`), kept as the reference implementation.
    enum Legacy {
        static func scheduleConflicts(_ items: [AlertEngine.ScheduleItem]) -> [Alert] {
            var alerts: [Alert] = []
            for i in items.indices {
                for j in (i + 1)..<items.count {
                    let a = items[i]
                    let b = items[j]
                    guard overlaps(a, b) else { continue }
                    let severity: AlertSeverity = (a.isExam || b.isExam) ? .high : .info
                    let ids = a.id < b.id ? (a.id, b.id) : (b.id, a.id)
                    alerts.append(Alert(kind: .scheduleConflict(idA: ids.0, idB: ids.1), severity: severity))
                }
            }
            return alerts
        }

        private static func overlaps(_ a: AlertEngine.ScheduleItem, _ b: AlertEngine.ScheduleItem) -> Bool {
            switch (a.end, b.end) {
            case let (ae?, be?):
                return a.start < be && b.start < ae
            case let (ae?, nil):
                return b.start >= a.start && b.start <= ae
            case let (nil, be?):
                return a.start >= b.start && a.start <= be
            case (nil, nil):
                return abs(a.start.timeIntervalSince(b.start)) <= InsightsConfig.closeDueGap.timeInterval
            }
        }
    }

    static let base = Date(timeIntervalSince1970: 1_790_600_400)
    static let gap = InsightsConfig.closeDueGap.timeInterval

    /// One schedule: `count` items whose starts cluster around a handful of anchors, so most
    /// items have neighbours right at the pruning distance.
    static func schedule(_ index: Int, rng: inout SeededRandom) -> [AlertEngine.ScheduleItem] {
        let count = Int.random(in: 0...40, using: &rng)
        var items: [AlertEngine.ScheduleItem] = []
        let anchors = (0..<Int.random(in: 1...4, using: &rng)).map { _ in
            base.addingTimeInterval(Double(Int.random(in: 0..<(3 * 86_400), using: &rng)))
        }
        for k in 0..<count {
            let anchor = anchors.randomElement(using: &rng) ?? base
            // Offsets on and around the boundaries the sweep prunes at.
            let offsets: [TimeInterval] = [0, gap, gap - 1, gap + 1, -gap, 3000, 3001, 2999, 600, -600, 7200, 0.5]
            var start = anchor.addingTimeInterval(offsets.randomElement(using: &rng) ?? 0)
            if Int.random(in: 0..<60, using: &rng) == 0 {
                start = [Date(timeIntervalSinceReferenceDate: .nan), .distantFuture, .distantPast,
                         Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: -.infinity)]
                    .randomElement(using: &rng) ?? start
            }
            let end: Date? = switch Int.random(in: 0..<10, using: &rng) {
            case 0...4: nil // an instant (a due time)
            case 5: start // zero-length
            case 6: start.addingTimeInterval(-1800) // inverted
            case 7: Int.random(in: 0..<10, using: &rng) == 0 ? Date(timeIntervalSinceReferenceDate: .nan) : start.addingTimeInterval(3000)
            default: start.addingTimeInterval([3000, gap, 5400, 1].randomElement(using: &rng) ?? 3000)
            }
            // Duplicate IDs now and then: the alert's ID pair is order-normalized either way.
            let id = Int.random(in: 0..<25, using: &rng) == 0 ? "dup" : "s\(index)-\(k)"
            items.append(AlertEngine.ScheduleItem(id: id, start: start, end: end, isExam: Int.random(in: 0..<5, using: &rng) == 0))
        }
        return items
    }

    static let scheduleCount = 4_000

    @Test func sweepFindsExactlyTheAllPairsConflictsInTheSameOrder() {
        var rng = SeededRandom(seed: 0x5EED_0A08)
        var compared = 0, conflicts = 0, high = 0
        var mismatches: [String] = []
        for index in 0..<Self.scheduleCount {
            let items = Self.schedule(index, rng: &rng)
            let old = Legacy.scheduleConflicts(items)
            let new = AlertEngine.scheduleConflicts(items)
            compared += 1
            conflicts += old.count
            high += old.filter { $0.severity == .high }.count
            if old != new { mismatches.append("schedule \(index): legacy \(old.count) alerts, sweep \(new.count)") }
        }
        print("PERF-05-DIFF | scheduleConflicts | schedules=\(compared) conflicts=\(conflicts) high=\(high) mismatches=\(mismatches.count)")
        #expect(mismatches.isEmpty, "\(mismatches.count) schedules differ; first: \(mismatches.prefix(5))")
        // Non-vacuity floors, about half of what this seed produces (see the printed line).
        #expect(conflicts > 20_000 && high > 5_000, "coverage: \(conflicts) conflicts, \(high) high")
    }

    @Test func edgeCasesMatchTheAllPairsLoop() {
        let s = Self.base
        let cases: [[AlertEngine.ScheduleItem]] = [
            [],
            [.init(id: "a", start: s)],
            // Two instants exactly closeDueGap apart (a conflict), and one second further (none).
            [.init(id: "a", start: s), .init(id: "b", start: s.addingTimeInterval(Self.gap))],
            [.init(id: "a", start: s), .init(id: "b", start: s.addingTimeInterval(Self.gap + 1))],
            // An instant at an interval's exact end, and at its exact start.
            [.init(id: "c", start: s, end: s.addingTimeInterval(3000)), .init(id: "d", start: s.addingTimeInterval(3000))],
            [.init(id: "d", start: s), .init(id: "c", start: s, end: s.addingTimeInterval(3000), isExam: true)],
            // A long interval that reaches past many instants beyond closeDueGap.
            [.init(id: "long", start: s, end: s.addingTimeInterval(86_400))]
                + (1...10).map { AlertEngine.ScheduleItem(id: "i\($0)", start: s.addingTimeInterval(Double($0) * 7200)) },
            // NaN and infinite starts next to ordinary items.
            [.init(id: "nan", start: Date(timeIntervalSinceReferenceDate: .nan)), .init(id: "a", start: s),
             .init(id: "b", start: s.addingTimeInterval(10)),
             .init(id: "ninf", start: Date(timeIntervalSinceReferenceDate: -.infinity), end: s.addingTimeInterval(20))],
        ]
        for items in cases {
            #expect(AlertEngine.scheduleConflicts(items) == Legacy.scheduleConflicts(items), "\(items.map(\.id))")
        }
    }
}
