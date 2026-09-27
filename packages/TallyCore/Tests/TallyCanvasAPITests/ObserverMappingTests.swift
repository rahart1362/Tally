import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// FAM-03 (stretch): observer `submission`-as-array mapping, and the family-linking.md §6.1
/// disputed point about how `observed_user` is embedded in the Courses response.
@Suite("Observer mapping: submission arrays and the courses observed_user question (FAM-03 stretch)")
struct ObserverMappingTests {
    private let northfieldHost = "canvas.northfield.example"
    private let alexUserID = "4820117" // parent-observer's northfield observee (== flagship's own user)
    private let jordanUserID = "6603318" // parent-observer's northgate observee (== grading-periods' own user)

    /// **Finding**: neither `personas/parent-observer/northfield/courses.json` nor the
    /// northgate one embeds an `observed_user` key anywhere. Each course's `enrollments`
    /// array instead gains a second row — the observer's own (`type: "observer"`,
    /// `associated_user_id` naming the observee) — alongside the observee's ordinary
    /// `type: "student"` row with `computed_current_score` etc., byte-for-byte like a
    /// self-view response. That resolves family-linking.md §6.1's disputed row in favour of
    /// "the Courses API appending the observee's own enrollment rows instead": `CourseMapper`
    /// (WP-B03) already selects the first `student`-type row regardless of who is asking, so
    /// it needs no change to map an observer's courses response correctly.
    @Test func courseMapperAlreadyHandlesTheObserverCoursesResponse() throws {
        let courses = try CourseMapper.map(Fixtures.data("personas/parent-observer/northfield/courses.json"), host: northfieldHost).items
        #expect(courses.count == 5)
        let bio = try #require(courses.first { $0.id == "51845" })
        // Same score the flagship (self-view) fixture reports for Alex Sample in BIO 101.
        #expect(bio.scores?.currentScore == 93.4 && bio.scores?.currentGrade == "A")

        // Cross-check: the raw JSON truly has no "observed_user" key and an observer row
        // whose associated_user_id names the observee.
        let raw = try JSONSerialization.jsonObject(with: Fixtures.data("personas/parent-observer/northfield/courses.json")) as! [[String: Any]]
        let enrollments = raw[0]["enrollments"] as! [[String: Any]]
        #expect(!enrollments.contains { $0["observed_user"] != nil })
        let observerRow = try #require(enrollments.first { $0["type"] as? String == "observer" })
        #expect(observerRow["associated_user_id"] as? String == alexUserID)
        #expect(enrollments.contains { $0["type"] as? String == "student" })
    }

    @Test func everyNorthfieldCourseAssignmentGroupFileDecodesForTheObservee() throws {
        for courseID in ["51845", "51842", "51847", "51843", "51846"] as [CanvasID<Course>] {
            let mapped = try ObserverAssignmentGroupMapper.map(
                Fixtures.data("personas/parent-observer/northfield/assignment_groups/\(courseID.rawValue).json"),
                courseID: courseID, observeeUserID: alexUserID)
            #expect(mapped.dropped == 0)
            #expect(!mapped.items.flatMap(\.assignments).isEmpty)
        }
    }

    @Test func submissionArrayEntryIsSelectedByObserveeUserID() throws {
        let assignments = try ObserverAssignmentGroupMapper.map(
            Fixtures.data("personas/parent-observer/northfield/assignment_groups/51845.json"),
            courseID: "51845", observeeUserID: alexUserID
        ).items.flatMap(\.assignments)
        let lab1 = try #require(assignments.first { $0.id == "1204446" })
        #expect(lab1.submission?.score == 47.0 && lab1.submission?.grade == "47")
        #expect(lab1.submission?.workflowState == "graded" && lab1.submission?.excused == false)
    }

    /// A submission array entry for a *different* observee must never be picked up as this
    /// observee's own grade — the whole point of "map it per observee".
    @Test func wrongObserveeIDYieldsNoSubmissionNotTheOtherStudentsGrade() throws {
        let json = """
        [{"id":"1","assignments":[{"id":"9","name":"Shared quiz","submission":[
            {"user_id":"111","score":10.0,"workflow_state":"graded"},
            {"user_id":"222","score":90.0,"workflow_state":"graded"}
        ]}]}]
        """
        let mine = try ObserverAssignmentGroupMapper.map(Data(json.utf8), courseID: "9", observeeUserID: "111")
            .items.flatMap(\.assignments).first
        #expect(mine?.submission?.score == 10.0)
        let unknown = try ObserverAssignmentGroupMapper.map(Data(json.utf8), courseID: "9", observeeUserID: "999")
            .items.flatMap(\.assignments).first
        #expect(unknown?.submission == nil) // no entry for this observee: treated like an ungraded item, not a crash
    }

    @Test func northgateObserveeAlsoDecodesCleanly() throws {
        for courseID in ["90411", "90412", "90413", "90414"] as [CanvasID<Course>] {
            let mapped = try ObserverAssignmentGroupMapper.map(
                Fixtures.data("personas/parent-observer/northgate/assignment_groups/\(courseID.rawValue).json"),
                courseID: courseID, observeeUserID: jordanUserID)
            #expect(mapped.dropped == 0)
        }
        let courses = try CourseMapper.map(Fixtures.data("personas/parent-observer/northgate/courses.json"),
                                           host: "northgate.instructure.example").items
        #expect(courses.count == 4)
    }
}
