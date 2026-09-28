import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// perf-app-runtime.md §7 step 6 / plan 06 row 6: the **real** parity test, run before the old
/// builder is deleted. perf-core could only compare `DashboardProjection` against hand-derived
/// expectations, because app-core's builder cannot build on Linux. Here the pre-port
/// `TallyFeatures.DashboardBuilder` and the port (`TallyDomain.DashboardBuilder`, then
/// `HomeProjector.localized`, which re-renders the port's three fixed-format time strings in the
/// user's locale) are compared field by field over the flagship persona, the large persona and
/// the in-test stress snapshot.
///
/// The comparison runs at several "now"s per snapshot, so every section has items: at the
/// fixture's own anchor, and 1 and 3 days before it.
@Suite("Dashboard parity: pre-port builder vs DashboardProjection + localization")
struct DashboardParityTests {
    private static func personaSnapshot(_ persona: String, now: Date) async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: now)
    }

    /// The fixtures' capture instant (`fixtures/canvas/README.md`: 2026-09-28).
    private static let anchor = Date(timeIntervalSince1970: 1_790_600_400)
    private static let offsets: [TimeInterval] = [0, -86_400, -3 * 86_400]

    @Test("flagship and large personas: every field matches", arguments: ["flagship", "large"])
    func personaParity(_ persona: String) async throws {
        for offset in Self.offsets {
            let now = Self.anchor.addingTimeInterval(offset)
            let snapshot = try await Self.personaSnapshot(persona, now: now)
            try Self.assertParity(snapshot: snapshot, digest: nil, digestAsOf: nil, now: now, label: "\(persona) \(offset)")
        }
    }

    @Test("flagship with a digest: the change chip matches too")
    func digestParity() async throws {
        let now = Self.anchor
        let previous = try await Self.personaSnapshot("flagship-previous", now: now)
        let current = try await Self.personaSnapshot("flagship", now: now)
        let digest = ChangeDigest.diff(old: previous, new: current)
        #expect(!digest.isEmpty)
        try Self.assertParity(snapshot: current, digest: digest, digestAsOf: current.fetchedAt, now: now, label: "digest")
    }

    @Test("stress snapshot (20 courses × 250 assignments): every field matches")
    func stressParity() throws {
        let now = StressSnapshotFixture.referenceDate
        let snapshot = StressSnapshotFixture.make(scale: .stress, now: now)
        try Self.assertParity(snapshot: snapshot, digest: nil, digestAsOf: nil, now: now, label: "stress")
    }

    /// Plan 06 A8 (crash-safety-2.md §8 A1-A3): until step 6b deletes it, the old builder carries
    /// a copy of CS-07's `uniquingKeysWith` fix. Without it, each of these kinds traps
    /// (`Dictionary(uniqueKeysWithValues:)`: "Duplicate values for key"). Parity is not asserted
    /// here: the old per-item weight path and TallyDomain's `WeightContext` may resolve a repeated
    /// group differently, and the old builder is deleted in step 6b.
    @Test("the old builder no longer traps on a repeated ID", arguments: DuplicateIDFixture.Kind.allCases)
    func oldBuilderSurvivesRepeatedIDs(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        let state = TallyFeatures.DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil,
                                                          now: DuplicateIDFixture.now)
        #expect(state.nextUp.count <= 3)
        #expect(state.hero.courseCount == snapshot.courses.count)
    }

    private static func assertParity(
        snapshot: CanvasSnapshot, digest: ChangeDigest?, digestAsOf: Date?, now: Date, label: String
    ) throws {
        let old = TallyFeatures.DashboardBuilder.build(from: snapshot, digest: digest, digestAsOf: digestAsOf, now: now)
        let raw = TallyDomain.DashboardBuilder.build(from: snapshot, digest: digest, digestAsOf: digestAsOf, now: now)
        let new = HomeProjector.localized(raw, snapshot: snapshot, digest: digest, digestAsOf: digestAsOf,
                                          locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent)

        #expect(old.hero.courseCount == new.hero.courseCount, "\(label): hero.courseCount")
        #expect(old.hero.overallPercent == new.hero.overallPercent, "\(label): hero.overallPercent")
        #expect(old.hero.overallBand == new.hero.overallBand, "\(label): hero.overallBand")

        #expect(old.nextUp.count == new.nextUp.count, "\(label): nextUp.count")
        for (o, n) in zip(old.nextUp, new.nextUp) {
            #expect(o.id == n.id && o.title == n.title && o.courseCode == n.courseCode && o.dueAt == n.dueAt
                        && o.band == n.band && o.reason == n.reason, "\(label): nextUp \(o.id)")
        }

        #expect(old.needsAttention.count == new.needsAttention.count, "\(label): needsAttention.count")
        for (o, n) in zip(old.needsAttention, new.needsAttention) {
            #expect(o.id == n.id && o.severity == n.severity && o.title == n.title && o.subtitle == n.subtitle,
                    "\(label): needsAttention \(o.id): \(o.title) | \(n.title)")
        }

        #expect(old.dueSoon.count == new.dueSoon.count, "\(label): dueSoon.count")
        for (o, n) in zip(old.dueSoon, new.dueSoon) {
            #expect(o.id == n.id && o.title == n.title && o.courseCode == n.courseCode && o.dueAt == n.dueAt,
                    "\(label): dueSoon \(o.id)")
        }

        #expect(old.weekAhead.count == new.weekAhead.count, "\(label): weekAhead.count")
        for (o, n) in zip(old.weekAhead, new.weekAhead) {
            #expect(o.id == n.id && o.date == n.date && o.dueCount == n.dueCount && o.isBusy == n.isBusy,
                    "\(label): weekAhead \(o.date)")
        }

        #expect(old.changeDigestSummary == new.changeDigestSummary, "\(label): changeDigestSummary")
    }
}
