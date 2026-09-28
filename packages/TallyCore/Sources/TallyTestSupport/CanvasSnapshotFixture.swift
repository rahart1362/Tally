import Foundation
import TallyDomain

/// A small, hand-built `CanvasSnapshot` for `TallyStore` tests (crash injection, generation
/// guards, glance projection). Distinct from the real Canvas fixtures under `fixtures/canvas`,
/// which exist for the Canvas API mapping/contract tests, not the store layer.
public enum CanvasSnapshotFixture {
    public static func make(
        generation: UInt64 = 1,
        accountKey: AccountKey = AccountKey("test-account"),
        host: String = "canvas.example.edu",
        fetchedAt: Date = Date(timeIntervalSince1970: 1_790_600_400),
        courseCount: Int = 2,
        dueItemCount: Int = 3,
        hiddenTotalsForFirstCourse: Bool = false
    ) -> CanvasSnapshot {
        let courses: [Course] = (0..<courseCount).map { i in
            let id: CanvasID<Course> = CanvasID("\(100 + i)")
            return Course(
                id: id, name: "Sample Course \(i)", courseCode: "CRS\(100 + i)", term: nil, teachers: [],
                timeZone: nil, appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                gradeVisibility: (i == 0 && hiddenTotalsForFirstCourse) ? .hiddenTotals : .visible,
                scores: ComputedScores(currentScore: Double(70 + i * 5), finalScore: Double(70 + i * 5),
                                       currentGrade: nil, finalGrade: nil),
                currentPeriodScores: nil, htmlURL: nil)
        }
        let firstCourseID = courses.first?.id
        let planner: [PlannerItem] = (0..<dueItemCount).map { i in
            PlannerItem(
                id: "assignment:\(i)", courseID: firstCourseID,
                title: "Assignment number \(i) with a title long enough to need truncation for the glance projection",
                plannableType: "assignment", dueAt: fetchedAt.addingTimeInterval(Double(i) * 3600),
                pointsPossible: 100, submitted: false, graded: false, missing: i == 0, late: false,
                excused: false, markedComplete: false, htmlURL: nil)
        }
        return CanvasSnapshot(
            generation: generation, accountKey: accountKey, host: host, fetchedAt: fetchedAt,
            profile: UserProfile(id: "9001", name: "Sample Student", shortName: "Sample", timeZone: nil, calendarFeedURL: nil),
            courses: courses, groups: [:], gradingPeriods: [:], planner: planner, events: [], announcements: [],
            courseColors: [:],
            sections: Dictionary(uniqueKeysWithValues: SnapshotSection.allCases.filter(\.isRequired).map {
                ($0, SectionStatus(fetchedAt: fetchedAt, carriedForward: false))
            }))
    }
}
