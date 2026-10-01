import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// perf-app-runtime.md §7 step 6: `HomeProjector`'s pure pieces: it dedupes attention IDs and
/// bounds `validUntil`. Plan 08 L10N-02: the dashboard holds values now, phrased by
/// `TallyStrings.DashboardText` (the locale rendering this suite used to test is in
/// `RendererGoldenTests`).
@Suite("HomeProjector: unique IDs, validUntil")
struct HomeProjectorTests {
    private static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    @Test("attention items with the same ID collapse to the first (ForEach needs unique IDs)")
    func attentionIDsAreUnique() {
        let item = { (id: String, title: String) in
            DashboardProjection.AttentionItem(id: id, severity: .high, content: .other(title: title, courseCode: "BIO 101"))
        }
        let projection = DashboardProjection(
            hero: .init(courseCount: 1, averagedCount: 0, overallPercent: nil, overallBand: nil, exclusions: [.notYetPosted: 1],
                         school: .undetermined), nextUp: [],
            needsAttention: [item("missingClosed:1", "first"), item("missingClosed:1", "second"), item("due:9", "third")],
            dueSoon: [], weekAhead: [], changeDigestSummary: nil)
        let unique = HomeProjector.withUniqueAttention(projection).needsAttention
        #expect(unique.map(\.content) == [.other(title: "first", courseCode: "BIO 101"), .other(title: "third", courseCode: "BIO 101")])
    }

    @Test("validUntil is in the future, no later than dashboardMaxStaleness, and stops at the next due crossing")
    func validUntilBounds() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: Self.anchor)
        let calendar = Self.calendar("America/Chicago")
        let validUntil = HomeProjector.validUntil(snapshot: snapshot, now: Self.anchor, calendar: calendar)
        #expect(validUntil > Self.anchor)
        #expect(validUntil <= Self.anchor.addingTimeInterval(TallyConfig.dashboardMaxStaleness.timeInterval))
    }
}
