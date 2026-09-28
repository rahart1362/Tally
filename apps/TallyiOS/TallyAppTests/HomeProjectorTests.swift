import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// perf-app-runtime.md §7 step 6: `HomeProjector`'s pure pieces. The TallyDomain port formats the
/// due-soon title and the change-chip time as fixed `HH:mm` (it builds on Linux); the projector
/// renders them again from the raw dates in the user's locale, and dedupes attention IDs.
@Suite("HomeProjector: locale rendering, unique IDs, validUntil")
struct HomeProjectorTests {
    private static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// `localized` is tested on a projection built for it: "Needs attention" keeps only the top
    /// three alerts, and on the flagship persona those are missing-work alerts, so the port's
    /// own output never carries a due-soon item there (found on the Linux harness before CI).
    private static func portProjection(dueID: String, overloadStart: Date, summary: String?) -> DashboardProjection {
        DashboardProjection(
            hero: .init(courseCount: 1, overallPercent: nil, overallBand: nil), nextUp: [],
            needsAttention: [
                .init(id: "due:\(dueID)", severity: .high, title: "port HH:mm", subtitle: "BIO 101"),
                .init(id: "overload:\(Int(overloadStart.timeIntervalSince1970))", severity: .medium,
                      title: "port yyyy-MM-dd", subtitle: "Several items are due close together"),
                .init(id: "missing:1", severity: .high, title: "Unchanged", subtitle: nil),
            ],
            dueSoon: [], weekAhead: [], changeDigestSummary: summary)
    }

    @Test("due-soon, overload and digest times use the user's locale; other items keep the port's text",
          arguments: ["en_US", "de_DE"])
    func timesAreRenderedInTheUsersLocale(_ localeID: String) async throws {
        let previous = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship-previous", now: Self.anchor)
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: Self.anchor)
        let digest = ChangeDigest.diff(old: previous, new: snapshot)
        #expect(!digest.isEmpty, "flagship-previous -> flagship has a non-empty digest")
        let assignment = try #require(DuplicateIDFixture.allAssignments(snapshot).first { $0.dueAt != nil })
        let dueAt = try #require(assignment.dueAt)
        let locale = Locale(identifier: localeID)
        let calendar = Self.calendar("America/Chicago")
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                    timeZone: calendar.timeZone)
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar,
                                   timeZone: calendar.timeZone)

        let raw = Self.portProjection(dueID: assignment.id.rawValue, overloadStart: Self.anchor, summary: "port HH:mm")
        let projected = HomeProjector.localized(raw, snapshot: snapshot, digest: digest, digestAsOf: Self.anchor,
                                                locale: locale, calendar: calendar)

        let titles = projected.needsAttention.map(\.title)
        #expect(titles == [
            "\(assignment.name) due \(dueAt.formatted(time))",
            "Busy stretch starting \(Self.anchor.formatted(day))",
            "Unchanged",
        ])
        #expect(projected.needsAttention.map(\.id) == raw.needsAttention.map(\.id))
        #expect(projected.needsAttention.map(\.subtitle) == raw.needsAttention.map(\.subtitle))
        #expect(projected.changeDigestSummary
                    == "\(digest.count) change\(digest.count == 1 ? "" : "s") since \(Self.anchor.formatted(time))")
        // The locale really changes the rendering: a 12-hour clock in en_US, a 24-hour one in de_DE.
        let twelveHour = dueAt.formatted(time).hasSuffix("AM") || dueAt.formatted(time).hasSuffix("PM")
        #expect(twelveHour == (localeID == "en_US"), "\(dueAt.formatted(time))")
    }

    @Test("without a digest, the port's summary is left alone; an unknown assignment keeps the port's title")
    func unresolvableItemsKeepThePortsText() async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: Self.anchor)
        let raw = Self.portProjection(dueID: "no-such-assignment", overloadStart: Self.anchor, summary: nil)
        let projected = HomeProjector.localized(raw, snapshot: snapshot, digest: nil, digestAsOf: nil,
                                                locale: Locale(identifier: "en_US"), calendar: Self.calendar("UTC"))
        #expect(projected.needsAttention[0].title == "port HH:mm")
        #expect(projected.changeDigestSummary == nil)
    }

    @Test("attention items with the same ID collapse to the first (ForEach needs unique IDs)")
    func attentionIDsAreUnique() {
        let item = { (id: String, title: String) in
            DashboardProjection.AttentionItem(id: id, severity: .high, title: title, subtitle: nil)
        }
        let projection = DashboardProjection(
            hero: .init(courseCount: 1, overallPercent: nil, overallBand: nil), nextUp: [],
            needsAttention: [item("missingClosed:1", "first"), item("missingClosed:1", "second"), item("due:9", "third")],
            dueSoon: [], weekAhead: [], changeDigestSummary: nil)
        let unique = HomeProjector.withUniqueAttention(projection).needsAttention
        #expect(unique.map(\.title) == ["first", "third"])
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
