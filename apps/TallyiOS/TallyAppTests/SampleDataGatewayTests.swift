import Foundation
import Testing
@testable import TallyFeatures

/// ASC-14: `SampleDataCanvasGateway` end to end — loads the bundled flagship persona through
/// `Bundle.module` (not a source-tree path), runs it through the real `CanvasClient` ->
/// `LiveCanvasGateway` pipeline, and rebases dates so due items land near "now", not around the
/// fixture's fixed 2026-09-28 anchor.
@Suite("SampleDataCanvasGateway: bundled flagship persona, dates rebased to now")
struct SampleDataGatewayTests {
    @Test("fetchSnapshot returns the flagship persona's 5 courses with their known codes")
    func returnsFlagshipCourses() async throws {
        let gateway = try SampleDataCanvasGateway()
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: Date())
        let codes = Set(snapshot.courses.map(\.courseCode))
        #expect(codes == ["BIO 101", "MATH 122", "ENG 101", "PSY 101", "HIST 210"])
    }

    @Test("planner due dates are rebased to land within a few months of now, not fixed at 2026-09-28")
    func dueDatesLookCurrent() async throws {
        let now = Date()
        let gateway = try SampleDataCanvasGateway()
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: now)

        let dueDates = snapshot.planner.compactMap(\.dueAt)
        #expect(!dueDates.isEmpty)
        // The fixture's own planner window is -14...+60 days from "now" (TallyConfig), and
        // rebasing only ever moves a date by whole days relative to the same anchor/now pair
        // `fetchSnapshot` used — so every due date must fall inside that same window around
        // `now`, never anywhere near the fixture's original anchor day if "now" is far from it.
        let windowStart = now.addingTimeInterval(-30 * 24 * 3600)
        let windowEnd = now.addingTimeInterval(90 * 24 * 3600)
        for due in dueDates {
            #expect(due >= windowStart)
            #expect(due <= windowEnd)
        }
    }

    @Test("two fetches on the same day are byte-for-byte equal (deterministic rebasing)")
    func deterministicForTheSameDay() async throws {
        let now = Date()
        let a = try await SampleDataCanvasGateway().fetchSnapshot(previous: nil, now: now)
        let b = try await SampleDataCanvasGateway().fetchSnapshot(previous: nil, now: now)
        #expect(a.courses == b.courses)
        #expect(a.planner == b.planner)
    }
}
