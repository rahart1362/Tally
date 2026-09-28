import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("CanvasSnapshot envelope")
struct CanvasSnapshotTests {
    let now = TestClock().now()

    private func snapshot() -> CanvasSnapshot {
        let course: CanvasID<Course> = "51845"
        let submission = Submission(score: 93, grade: "93", submittedAt: now, gradedAt: now, postedAt: now,
                                    excused: false, missing: false, late: false, workflowState: "graded")
        let assignment = Assignment(id: "1204400", courseID: course, groupID: "51842", name: "Lab Report 1", dueAt: now,
                                    lockAt: nil, pointsPossible: 100, gradingType: .points, omitFromFinalGrade: false,
                                    htmlURL: URL(string: "https://canvas.northfield.example/courses/51845/assignments/1204400"),
                                    submission: submission)
        let group = AssignmentGroup(id: "51842", name: "Labs", position: 1, weight: 40,
                                    rules: DropRules(dropLowest: 1, neverDrop: ["1204400"]), assignments: [assignment])
        return CanvasSnapshot(
            generation: 7, accountKey: AccountKey("a1b2c3"), host: "canvas.northfield.example", fetchedAt: now,
            profile: UserProfile(id: "4820117", name: "Alex Sample", shortName: "Alex", timeZone: "America/Chicago", calendarFeedURL: nil),
            courses: [Course(id: course, name: "Biology 101", courseCode: "BIO 101", term: nil, teachers: [], timeZone: nil,
                             appliesGroupWeights: true, hasGradingPeriods: false, currentGradingPeriodID: nil,
                             gradeVisibility: .visible,
                             scores: ComputedScores(currentScore: 93.4, finalScore: 35.31, currentGrade: "A", finalGrade: "F"),
                             currentPeriodScores: nil, htmlURL: nil)],
            groups: [course: [group]], gradingPeriods: [:], planner: [], events: [], announcements: [],
            courseColors: [course: "#2563EB"],
            sections: [.courses: SectionStatus(fetchedAt: now, carriedForward: false),
                       .announcements: SectionStatus(fetchedAt: now.addingTimeInterval(-3600), carriedForward: true)])
    }

    @Test func roundTripsExactly() throws {
        let original = snapshot()
        let decoded = try JSONDecoder().decode(CanvasSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.schemaVersion == CanvasSnapshot.currentSchemaVersion)
    }

    @Test func idKeyedMapsEncodeAsJSONObjects() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(snapshot()), as: UTF8.self)
        #expect(json.contains(##""courseColors":{"51845":"#2563EB"}"##))
        #expect(json.contains(#""groups":{"51845":[{"#))
        #expect(json.contains(#""sections":{"announcements":{"#))
    }

    @Test func requiredSectionsAreTheFourAllOrNothingOnes() {
        #expect(Set(SnapshotSection.allCases.filter(\.isRequired)) == [.profile, .courses, .assignmentGroups, .planner])
    }
}
