import Foundation
import Testing
import TallyDomain
@testable import TallyFeatures

/// ASC-14: `fixtures/canvas/README.md`'s "Rebasing for demo mode" rule, applied at the
/// `CanvasSnapshot` layer instead of raw JSON (see `SnapshotDateRebaser`'s doc comment for why).
@Suite("SnapshotDateRebaser: day offset and DST-safe wall-clock shifting")
struct SnapshotDateRebaserTests {
    private let chicago = TimeZone(identifier: "America/Chicago")!

    @Test("dayOffset counts whole local-calendar days, not elapsed seconds")
    func dayOffsetWholeDays() {
        // 2026-09-28T13:00:00Z (the flagship anchor) to 2026-09-29T02:00:00Z is only 13h later,
        // but it crosses into the next Chicago calendar day (anchor is 08:00 CDT local on the
        // 28th; the second instant is 21:00 CDT local, also the 28th — so this should be 0,
        // proving the rule counts *calendar* days, not `elapsed / 86400`).
        let anchor = ISO8601DateFormatter().date(from: "2026-09-28T13:00:00Z")!
        let sameLocalDay = ISO8601DateFormatter().date(from: "2026-09-29T02:00:00Z")! // 21:00 CDT on the 28th
        #expect(SnapshotDateRebaser.dayOffset(from: anchor, to: sameLocalDay, in: chicago) == 0)

        let nextLocalDay = ISO8601DateFormatter().date(from: "2026-09-29T13:00:00Z")! // 08:00 CDT on the 29th
        #expect(SnapshotDateRebaser.dayOffset(from: anchor, to: nextLocalDay, in: chicago) == 1)
    }

    @Test("a shift across the fall-back DST boundary preserves local wall-clock time")
    func preservesWallClockAcrossFallBack() {
        // America/Chicago falls back on 2026-11-01. Anchor a date before it and shift to a date
        // 4 days later, after it.
        let anchor = ISO8601DateFormatter().date(from: "2026-10-30T13:00:00Z")! // 08:00 CDT
        let now = ISO8601DateFormatter().date(from: "2026-11-03T13:00:00Z")! // 07:00 CST (fallen back)
        let days = SnapshotDateRebaser.dayOffset(from: anchor, to: now, in: chicago)
        #expect(days == 4)

        // A fixture due date the evening before the fall-back, 23:59 local (CDT).
        let dueAt = ISO8601DateFormatter().date(from: "2026-10-31T23:59:00-05:00")!
        let snapshot = makeSnapshot(dueAt: dueAt)

        let rebased = SnapshotDateRebaser.rebase(snapshot, anchor: anchor, now: now, timeZone: chicago)
        let shiftedDue = rebased.groups.values.first!.first!.assignments.first!.dueAt!

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chicago
        let originalComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueAt)
        let shiftedComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: shiftedDue)

        // Wall-clock time of day is unchanged...
        #expect(originalComponents.hour == shiftedComponents.hour)
        #expect(originalComponents.minute == shiftedComponents.minute)
        // ...but the calendar date moved by exactly `days`.
        #expect(shiftedComponents.day == 4) // Oct 31 + 4 days = Nov 4
        #expect(shiftedComponents.month == 11)
    }

    @Test("fetchedAt and section timestamps are never shifted — they are real fetch times, not fixture dates")
    func neverShiftsFetchMetadata() {
        let anchor = ISO8601DateFormatter().date(from: "2026-09-28T13:00:00Z")!
        let now = ISO8601DateFormatter().date(from: "2026-10-05T13:00:00Z")!
        let snapshot = makeSnapshot(dueAt: anchor)
        let rebased = SnapshotDateRebaser.rebase(snapshot, anchor: anchor, now: now, timeZone: chicago)
        #expect(rebased.fetchedAt == snapshot.fetchedAt)
        #expect(rebased.sections == snapshot.sections)
    }

    @Test("a zero day offset is a pure no-op (same object graph)")
    func zeroOffsetIsNoOp() {
        let anchor = ISO8601DateFormatter().date(from: "2026-09-28T13:00:00Z")!
        let snapshot = makeSnapshot(dueAt: anchor)
        let rebased = SnapshotDateRebaser.rebase(snapshot, anchor: anchor, now: anchor, timeZone: chicago)
        #expect(rebased == snapshot)
    }

    // MARK: - Fixture

    private func makeSnapshot(dueAt: Date) -> CanvasSnapshot {
        let courseID: CanvasID<Course> = "51845"
        let course = Course(id: courseID, name: "Biology 101", courseCode: "BIO 101", term: nil, teachers: [],
                            timeZone: nil, appliesGroupWeights: false, hasGradingPeriods: false,
                            currentGradingPeriodID: nil, gradeVisibility: .visible,
                            scores: ComputedScores(currentScore: 93.4, finalScore: 93.4, currentGrade: "A", finalGrade: "A"),
                            currentPeriodScores: nil, htmlURL: nil)
        let assignment = Assignment(id: "1", courseID: courseID, groupID: "10", name: "Lab Report 4", dueAt: dueAt,
                                    lockAt: nil, pointsPossible: 20, gradingType: .points, omitFromFinalGrade: false,
                                    htmlURL: nil, submission: nil)
        let group = AssignmentGroup(id: "10", name: "Labs", position: 1, weight: nil, rules: DropRules(), assignments: [assignment])
        return CanvasSnapshot(
            generation: 1, accountKey: AccountKey("test"), host: "canvas.northfield.example", fetchedAt: dueAt,
            profile: UserProfile(id: "1", name: "Alex Sample", shortName: "Alex", timeZone: nil, calendarFeedURL: nil),
            courses: [course], groups: [courseID: [group]], gradingPeriods: [:], planner: [], events: [],
            announcements: [], courseColors: [:],
            sections: [.profile: SectionStatus(fetchedAt: dueAt, carriedForward: false)])
    }
}
