import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain

/// LIVE-1 assertion 4: the observer path. Mirrors the existing fixture-based
/// `ObserverMappingTests` (TallyCanvasAPITests), but against the real Canvas server instead of
/// a recorded fixture: the observer's own `GET /api/v1/users/self/observees` (`LinkedUsersUseCase`,
/// real), the observer's own `GET /api/v1/courses` (real `CourseMapper`), and
/// `GET .../assignment_groups?include[]=observed_users` (real `ObserverAssignmentGroupMapper`,
/// selecting the submission array entry for Alex's own Canvas user ID).
///
/// **Finding F5** (live1-report.md), contradicting `ObserverAssignmentGroupDTO.swift`'s doc
/// comment and `ObserverMappingTests.courseMapperAlreadyHandlesTheObserverCoursesResponse`
/// (both based on a recorded fixture): on this live Canvas (`1c9f0bb`), the observer's own
/// `GET /api/v1/courses` returns **only the observer's own `type: observer` enrollment row** --
/// confirmed read-only with `CanvasQuery.courses()`'s exact query, no `student` row, so
/// `CourseMapper` (which already handles a `student` row correctly, per that fixture test)
/// has nothing to pick and `course.scores` is `nil` for every course. Adding
/// `include[]=observed_users` (confirmed read-only, below) makes Canvas include the observee's
/// `student` row (with `computed_current_score`) too. **LIVE-FIX-1**: `CanvasQuery.courses()`
/// (`Sources/TallyCanvasAPI/Client/CanvasEndpoints.swift:78-81`) now takes an
/// `includeObservedUsers` parameter that appends `("include[]", "observed_users")` for exactly
/// this call, so this test now exercises the real product query -- not a copy of it -- end to
/// end against a real Canvas response.
///
/// Gated on `TALLY_LIVE_OBSERVER_TOKEN_FILE` alone (on top of the suite-wide
/// `TALLY_LIVE_CANVAS_URL`/`TALLY_LIVE_TOKEN_FILE`): skipped, not failed, when it is unset, per
/// the brief ("Every test is skipped unless ..." -- extended here with one more opt-in variable
/// for the one persona this assertion alone needs).
@Suite("LIVE-1 assertion 4: observer path (observees=1, observed courses/grades build)",
       .enabled(if: LiveCanvasEnvironment.hasObserver))
struct LiveObserverPathTests {
    @Test("observer sees exactly 1 observee (Alex), and her observed courses/grades build")
    func observerSeesExactlyOneObserveeAndHerGradesBuild() async throws {
        let config = try #require(LiveCanvasEnvironment.config)
        let observerToken = try #require(config.observerToken)
        let session = LiveCanvasHarness.makeSession(config, accessToken: observerToken, userID: "live-observer")
        let start = Date()

        let observees = try await LinkedUsersUseCase(client: session.client).listObservees()
        #expect(observees.count == 1, "the observer should see exactly 1 observee (Alex); got \(observees.count)")
        let alex = try #require(observees.first)
        #expect(alex.name == "Alex Sample", "unexpected observee name: \(alex.name)")

        // The observer's own `/courses` call, real `CanvasClient` + real `CourseMapper`. F5's
        // extra include item (`CanvasQuery.courses()` alone is not enough for an observer --
        // see this file's doc comment) is now the product query itself.
        let observerCourseQuery = CanvasQuery.courses(includeObservedUsers: true)
        let coursePages = try await session.client.fetchAllPages(path: "/api/v1/courses", query: observerCourseQuery)
        let courses = try coursePages.flatMap { try CourseMapper.map($0, host: config.host).items }
        #expect(!courses.isEmpty, "the observer's own /courses call returned no observed courses")

        var gradeLines: [String] = []
        var built = 0
        for course in courses {
            let query = CanvasQuery.assignmentGroups() + [("include[]", "observed_users")]
            let pages = try await session.client.fetchAllPages(
                path: "/api/v1/courses/\(course.id.rawValue)/assignment_groups", query: query)
            let groups = try pages.flatMap {
                try ObserverAssignmentGroupMapper.map($0, courseID: course.id, observeeUserID: alex.canvasUserID).items
            }
            // GradeEngine over the real, observer-fetched groups -- "the observed courses/grades
            // build" means this must run to completion without throwing, for every course.
            let scores = GradeEngine.scores(course: course, groups: groups, gradingPeriods: [])
            let tallyText: String = scores.currentScore.map { "\($0)" } ?? "nil"
            let canvasText: String = course.scores?.currentScore.map { "\($0)" } ?? "nil"
            let courseCode: String = course.courseCode
            var line = "LIVE-GRADE(observer) | course="
            line += courseCode
            line += " tally="
            line += tallyText
            line += " canvas="
            line += canvasText
            gradeLines.append(line)
            built += 1
        }
        for line in gradeLines { print(line) }
        #expect(built == courses.count, "not every observed course's grade math built")

        let elapsedMS = Int(Date().timeIntervalSince(start) * 1000)
        let requests = await session.meter.requestCount
        let bytes = await session.meter.byteCount
        // Brief assertion 5, exact format, observer persona.
        print("LIVE-PERF | requests=\(requests) bytes=\(bytes) ms=\(elapsedMS) persona=observer")
    }
}
