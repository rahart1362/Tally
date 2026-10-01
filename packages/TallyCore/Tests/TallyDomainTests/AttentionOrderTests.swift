import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// "Needs attention" shows the top three alerts. Equal-rank alerts used to keep their input order,
/// part of which comes from dictionary iteration, so the rows shown could change between launches
/// with the same data (XG-02 report open item). `DashboardBuilder.attentionOrder` breaks ties by
/// the alert's stable key.
@Suite("Needs attention: the rows never depend on input order")
struct AttentionOrderTests {
    private static let tied: [Alert] = (1...6).map { Alert(kind: .missingOpen(assignmentID: CanvasID("a\($0)")), severity: .high, priority: 40) }
        + [Alert(kind: .missingClosed(courseID: CanvasID("c1")), severity: .high, priority: 40)]

    @Test func equalRankAlertsSortTheSameWhateverTheirInputOrder() {
        let expected = Self.tied.sorted(by: DashboardBuilder.attentionOrder).map(\.dedupeKey)
        for seed in 0..<25 {
            var rng = SeededRandom(seed: UInt64(seed))
            let shuffled = Self.tied.shuffled(using: &rng)
            #expect(shuffled.sorted(by: DashboardBuilder.attentionOrder).map(\.dedupeKey) == expected, "seed \(seed)")
        }
        #expect(expected == expected.sorted(), "ties fall back to the stable key")
    }

    @Test func rankStillComesFirst() {
        let urgent = Alert(kind: .missingOpen(assignmentID: CanvasID("z9")), severity: .critical, priority: 0)
        let higherPriority = Alert(kind: .missingOpen(assignmentID: CanvasID("z8")), severity: .high, priority: 90)
        let ordered = ([higherPriority] + Self.tied + [urgent]).sorted(by: DashboardBuilder.attentionOrder)
        #expect(ordered.first?.dedupeKey == urgent.dedupeKey, "critical outranks any high")
        #expect(ordered.dropFirst().first?.dedupeKey == higherPriority.dedupeKey, "within a severity, priority decides")
    }
}
