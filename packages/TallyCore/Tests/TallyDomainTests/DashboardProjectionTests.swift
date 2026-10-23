import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// PERF-02: ported unchanged (in meaning — types renamed `DashboardBuilder`/`DashboardViewState`
/// -> `DashboardBuilder`/`DashboardProjection`, both now `TallyDomain`) from the pinned app-core
/// review worktree's `apps/TallyiOS/TallyAppTests/DashboardBuilderTests.swift` @ 6a98f4a
/// (UX-WP-13). Every assertion still traces back to `fixtures/canvas/personas/flagship`, per
/// `fixtures/canvas/README.md`'s persona table: 5 courses, BIO 101 93.4% A highest.
@Suite("DashboardBuilder: hero, Next up, Needs attention, Due soon, Week ahead")
struct DashboardProjectionTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)

    private func snapshot() async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: Self.fixedNow)
    }

    @Test("hero: 5 courses, an overall percent close to the README's stated mean (88.34)")
    func heroAveragesFiveCourses() async throws {
        let state = DashboardBuilder.build(from: try await snapshot(), digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(state.hero.courseCount == 5)
        let overall = try #require(state.hero.overallPercent)
        #expect(abs(overall - 88.34) < 0.5)
        #expect(state.hero.overallBand == .bRange) // 88.34 falls in 80..<90
    }

    @Test("first snapshot (no previous): no digest chip, matching architecture's no-flood-on-first-look rule")
    func noDigestOnFirstSnapshot() async throws {
        let state = DashboardBuilder.build(from: try await snapshot(), digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(state.changeDigestSummary == nil)
    }

    @Test("Next up: at most 3 items, each excluding submitted/graded/excused work")
    func nextUpExcludesResolvedWork() async throws {
        let snap = try await snapshot()
        let state = DashboardBuilder.build(from: snap, digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(state.nextUp.count <= 3)
        let allAssignments = snap.groups.values.flatMap { $0.flatMap(\.assignments) }
        let byID = Dictionary(uniqueKeysWithValues: allAssignments.map { ($0.id, $0) })
        for item in state.nextUp {
            let assignment = try #require(byID[item.id])
            if let submission = assignment.submission {
                #expect(!submission.isSubmitted)
                #expect(submission.gradedAt == nil)
                #expect(!submission.excused)
            }
            #expect(!item.reasonFactors.isEmpty)
        }
    }

    /// ideas2 report #3: `nextUp` used to hardcode `markedDone: false`, so an assignment the
    /// student had just marked done in To-Do (`PriorityScore.isExcluded`'s own `markedDone` flag,
    /// already honoured by `ReminderPlanner`/`FamilyNotificationPlanner`) kept showing in "Next
    /// up" — the one screen built to deliver "you're all caught up" could never reach that state
    /// as a result of the student's own action.
    @Test("Next up: a locally marked-done item is excluded, the same as To-Do's own exclusion")
    func nextUpExcludesLocallyMarkedDoneItems() async throws {
        let snap = try await snapshot()
        let before = DashboardBuilder.build(from: snap, digest: nil, digestAsOf: nil, now: Self.fixedNow)
        let marked = try #require(before.nextUp.first?.id, "the flagship should have open work due soon")

        let after = DashboardBuilder.build(from: snap, digest: nil, digestAsOf: nil, now: Self.fixedNow,
                                           doneAssignments: [marked])
        #expect(!after.nextUp.contains { $0.id == marked })
        #expect(after.nextUp.count <= before.nextUp.count)

        // Unmarking (an empty set, the default) restores exactly the original ranking.
        let restored = DashboardBuilder.build(from: snap, digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(restored.nextUp == before.nextUp)
    }

    @Test("Needs attention: at most 3, ranked by severity+priority descending")
    func needsAttentionIsRankedAndCapped() async throws {
        let state = DashboardBuilder.build(from: try await snapshot(), digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(state.needsAttention.count <= 3)
        let severities = state.needsAttention.map(\.severity.rawValue)
        #expect(severities == severities.sorted(by: >))
    }

    @Test("Due soon: only items due within 7 days of `now`, at most 5, sorted earliest-first")
    func dueSoonWindowAndOrder() async throws {
        let snap = try await snapshot()
        let state = DashboardBuilder.build(from: snap, digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(state.dueSoon.count <= 5)
        let horizon = Self.fixedNow.addingTimeInterval(7 * 24 * 3600)
        for item in state.dueSoon {
            let due = try #require(item.dueAt)
            #expect(due >= Self.fixedNow)
            #expect(due <= horizon)
        }
        let dueDates = state.dueSoon.compactMap(\.dueAt)
        #expect(dueDates == dueDates.sorted())
    }

    @Test("Week ahead: exactly 7 days, starting today")
    func weekAheadHasSevenDays() async throws {
        let state = DashboardBuilder.build(from: try await snapshot(), digest: nil, digestAsOf: nil, now: Self.fixedNow)
        #expect(state.weekAhead.count == 7)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        #expect(calendar.isDate(state.weekAhead[0].date, inSameDayAs: Self.fixedNow))
        // UX1-16: the strip rings/bolds today's column; only the first day is marked.
        #expect(state.weekAhead[0].isToday)
        #expect(state.weekAhead[1...].allSatisfy { !$0.isToday })
    }

    /// Idea 10 ("Add this week to Calendar") and Idea 11 ("Send my week"),
    /// `pmo-audit/.build-audit/ideas1/report.md`: each day's `items` are exactly the items
    /// `dueCount` already counts (never a class meeting or event, which the Week-ahead strip never
    /// showed either), on that day, earliest first, with Canvas's own course code when the item
    /// has one.
    @Test("Week ahead items: one per due item, same day, in order, course code resolved from Canvas")
    func weekAheadItemsMatchDueCounts() async throws {
        let snap = try await snapshot()
        let state = DashboardBuilder.build(from: snap, digest: nil, digestAsOf: nil, now: Self.fixedNow)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let coursesByCode = Dictionary(uniqueKeysWithValues: snap.courses.map { ($0.courseCode, $0) })
        for day in state.weekAhead {
            #expect(day.items.count == day.dueCount)
            for item in day.items {
                #expect(calendar.isDate(item.dueAt, inSameDayAs: day.date))
                if let code = item.courseCode {
                    #expect(coursesByCode[code] != nil, "unknown course code \(code)")
                }
            }
            let dueDates = day.items.map(\.dueAt)
            #expect(dueDates == dueDates.sorted())
        }
        #expect(state.weekAhead.flatMap(\.items).contains { $0.courseCode != nil },
               "flagship has no course-coded due item this week -- the test would pass vacuously")
    }

    @Test("digest chip: non-empty digest with an asOf date produces a summary mentioning the count")
    func digestChipSummary() async throws {
        let old = try await snapshot()
        // Craft a "new" snapshot with one course score bumped to force a non-empty digest,
        // reusing the harness's own real data rather than a hand-built fake snapshot.
        var courses = old.courses
        let idx = 0
        if !courses.isEmpty, let scores = courses[idx].scores {
            let c = courses[idx]
            courses[idx] = Course(id: c.id, name: c.name, courseCode: c.courseCode, term: c.term, teachers: c.teachers,
                                  timeZone: c.timeZone, appliesGroupWeights: c.appliesGroupWeights,
                                  hasGradingPeriods: c.hasGradingPeriods, currentGradingPeriodID: c.currentGradingPeriodID,
                                  gradeVisibility: c.gradeVisibility,
                                  scores: ComputedScores(currentScore: (scores.currentScore ?? 0) + 5, finalScore: scores.finalScore,
                                                        currentGrade: scores.currentGrade, finalGrade: scores.finalGrade),
                                  currentPeriodScores: c.currentPeriodScores, htmlURL: c.htmlURL,
                                  hasWeightedGradingPeriods: c.hasWeightedGradingPeriods,
                                  studentEnrollmentCompleted: c.studentEnrollmentCompleted)
        }
        let updated = CanvasSnapshot(
            generation: old.generation + 1, accountKey: old.accountKey, host: old.host, fetchedAt: old.fetchedAt,
            profile: old.profile, courses: courses, groups: old.groups, gradingPeriods: old.gradingPeriods,
            planner: old.planner, events: old.events, announcements: old.announcements, courseColors: old.courseColors,
            sections: old.sections)
        let digest = ChangeDigest.diff(old: old, new: updated)
        #expect(!digest.isEmpty)
        let state = DashboardBuilder.build(from: updated, digest: digest, digestAsOf: updated.fetchedAt, now: Self.fixedNow)
        let summary = try #require(state.changeDigestSummary)
        #expect(summary == DashboardProjection.ChangeSummary(count: digest.count, asOf: updated.fetchedAt))
    }
}
