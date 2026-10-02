import Foundation
import SwiftUI
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
import WidgetKit
@testable import TallyGlance

/// Plan 08 XG-02, §4.4 row 14: the Standing widget's states, from the `external-grades` persona
/// (synthetic, `fixtures/canvas/personas/external-grades`) through the glance and the timeline.
/// "Grades aren't in Canvas" for an opted-in student whose school keeps grades elsewhere; "choose
/// to show grades" only for a student who has not opted in (before, every opted-in student with no
/// band was told to opt in).
@MainActor
@Suite("Widget Standing states: the external-grades persona (plan 08 XG-02)")
struct WidgetStandingStatesTests {
    /// The persona's anchor, 2026-09-28T13:00:00Z.
    private static let anchor = Date(timeIntervalSince1970: 1_790_600_400)
    private static let enUS = Locale(identifier: "en_US")
    /// The persona without SPAN-2, its one course graded in Canvas: a `.noneInCanvas` school.
    private static let noneInCanvas: Set<String> = ["ENG-10", "ALG2", "BIO-H", "ART-1", "ADVISORY"]

    private static func persona(keeping codes: Set<String>? = nil,
                                account: AccountKey? = nil) async throws -> CanvasSnapshot {
        let full = try await PersonaSnapshotHarness.fetchSnapshot(persona: "external-grades", now: anchor)
        let courses = full.courses.filter { codes?.contains($0.courseCode) ?? true }
        let ids = Set(courses.map(\.id))
        return CanvasSnapshot(
            generation: full.generation, accountKey: account ?? full.accountKey, host: full.host, fetchedAt: full.fetchedAt,
            profile: full.profile, courses: courses, groups: full.groups.filter { ids.contains($0.key) },
            gradingPeriods: full.gradingPeriods.filter { ids.contains($0.key) }, planner: full.planner,
            events: full.events, announcements: full.announcements, courseColors: full.courseColors,
            sections: full.sections)
    }

    /// The Standing widget's summary for the glance the app would commit, a minute after the fetch.
    private static func summary(_ snapshot: CanvasSnapshot, includeGrades: Bool) throws -> GlanceSummary {
        // M3-B2: enforcement is on, so the glance carries the student's entitlement.
        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: includeGrades,
                                                   entitledUntil: GlanceStoreFixture.entitledUntil)
        return try summary(of: .loaded(glance))
    }

    private static func summary(of result: GlanceReadResult) throws -> GlanceSummary {
        let plan = GlanceTimelinePlanner.plan(for: result, now: anchor.addingTimeInterval(60), calendar: .current)
        guard case .summary(let summary) = plan.current.content else {
            throw StandingStateError.noSummary("\(plan.current.content)")
        }
        return summary
    }

    private enum StandingStateError: Error { case noSummary(String) }

    /// The Standing widget's two lines for `grades`, in en_US, or nil when it shows a band.
    private static func lines(_ grades: GlanceGradeSummary) -> [String]? {
        GlanceText.standingMessage(grades).map { message in
            [message.title, message.detail].map { resource in
                var resource = resource
                resource.locale = enUS
                return String(localized: resource)
            }
        }
    }

    private static let hidden = ["Grades are hidden", "They appear here only if you choose to show grades in widgets."]
    private static let notInCanvas = ["Grades aren't in Canvas", "Your school doesn't appear to post grades there."]
    private static let noneYet = ["No grades yet", "Your average appears here once grades are posted in Canvas."]

    @Test("Opted in, the school keeps grades outside Canvas: 'Grades aren't in Canvas'")
    func optedInNotInCanvas() async throws {
        let summary = try Self.summary(try await Self.persona(keeping: Self.noneInCanvas), includeGrades: true)
        #expect(summary.grades == .notInCanvas)
        #expect(summary.standing == nil)
        #expect(Self.lines(summary.grades) == Self.notInCanvas)
    }

    @Test("Not opted in: 'Grades are hidden … choose to show grades', whatever the grades are")
    func notOptedIn() async throws {
        for codes in [nil, Self.noneInCanvas] {
            let summary = try Self.summary(try await Self.persona(keeping: codes), includeGrades: false)
            #expect(summary.grades == .notOptedIn)
            #expect(Self.lines(summary.grades) == Self.hidden)
        }
    }

    @Test("Opted in, nothing to average yet and no sign of grades outside Canvas: 'No grades yet'")
    func optedInNoneYet() async throws {
        let summary = try Self.summary(try await Self.persona(keeping: ["ART-1", "ADVISORY"]), includeGrades: true)
        #expect(summary.grades == .noneYet)
        #expect(Self.lines(summary.grades) == Self.noneYet)
    }

    @Test("Opted in with SPAN-2 graded in Canvas: the band of the average, and no message")
    func optedInWithABand() async throws {
        let summary = try Self.summary(try await Self.persona(), includeGrades: true)
        #expect(summary.grades == .band(.aRange))
        #expect(summary.standing == .aRange)
        #expect(Self.lines(summary.grades) == nil)
    }

    @Test("'Choose to show grades' is said only to a student who has not opted in")
    func chooseToShowOnlyWhenNotOptedIn() {
        for grades in [GlanceGradeSummary.notOptedIn, .noneYet, .notInCanvas, .band(.cRange)] {
            let says = Self.lines(grades)?.joined(separator: " ").contains("choose to show grades") ?? false
            #expect(says == (grades == .notOptedIn), "\(grades)")
        }
    }

    private static let widgetSize = CGSize(width: 170, height: 170)

    private static func png(_ grades: GlanceGradeSummary, redacted: Bool = false) -> Data? {
        let summary = GlanceSummary(nextUp: nil, laterCount: 0, overdueCount: 0, grades: grades, asOf: anchor,
                                    isStale: false, asOfIsBeforeToday: false)
        let view = StandingWidgetView(entry: GlanceEntry(date: anchor, content: .summary(summary)))
            .frame(width: widgetSize.width, height: widgetSize.height)
        let renderer = ImageRenderer(content: Group { if redacted { view.redacted(reason: .privacy) } else { view } })
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }

    @Test("Each state renders differently, and a band is still hidden while the iPhone is locked")
    func eachStateRenders() throws {
        let states: [GlanceGradeSummary] = [.notOptedIn, .noneYet, .notInCanvas, .band(.aRange)]
        let images = try states.map { try #require(Self.png($0)) }
        #expect(Set(images).count == states.count, "two Standing states draw the same pixels")
        let lockedA = try #require(Self.png(.band(.aRange), redacted: true))
        let lockedF = try #require(Self.png(.band(.fRange), redacted: true))
        #expect(lockedA == lockedF, "a locked Standing widget's pixels depend on the band")
    }

    @Test("End to end: the app commits the persona opted in, the widget reads it, plans and says 'Grades aren't in Canvas'")
    func endToEnd() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        let account = GlanceStoreFixture.account("external-grades")
        let snapshot = try await Self.persona(keeping: Self.noneInCanvas, account: account)
        let committed = try await fixture.ownerStore(account).commit(snapshot, includeGrades: true,
                                                                     entitledUntil: GlanceStoreFixture.entitledUntil)
        #expect(committed.schemaVersion == 2)

        let result = await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read()
        #expect(result == .loaded(committed))
        let summary = try Self.summary(of: result)
        #expect(summary.grades == .notInCanvas)
        #expect(Self.lines(summary.grades) == Self.notInCanvas)
        #expect(Self.png(summary.grades) != nil)
    }
}
