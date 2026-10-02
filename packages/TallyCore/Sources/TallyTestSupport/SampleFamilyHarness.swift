import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyReplay

/// FAM-14's data side: fetches the `sample-family` persona (one synthetic observer, two
/// students, `fixtures/canvas/manifest.json`) through the exact production decoders —
/// `LinkedUsersUseCase` (FAM-06), `CourseMapper` (WP-B03) and `ObserverAssignmentGroupMapper`
/// (FAM-03) — and assembles one `CanvasSnapshot` per student, paired with its `Subject`.
///
/// Each student's courses come from Canvas's own per-observee endpoint, `GET
/// /api/v1/users/:observee_id/courses` (family-linking.md §2.5, VERIFIED docs/OSS), so Rowan's
/// and Skyler's course lists never need splitting out of one merged response — each decodes on
/// its own, same as `PersonaSnapshotHarness` does for a single-student persona. (Composing one
/// *merged* `/courses` response across several subjects, the bulk O3 shape family-linking.md
/// §6.1 also describes, is the not-yet-built observer snapshot composition FAM-04 was to cover;
/// nothing under `TallyDomain/Model` carries a per-course subject id today, so that composition
/// is out of this work package's reach — see the M3-E1 report's open items.)
///
/// Mirrors `PersonaSnapshotHarness`'s pattern (same fake `TokenCoordinator`/credential plumbing)
/// generalised to more than one subject behind one observer account.
public enum SampleFamilyHarness {
    public static let personaName = "sample-family"

    public struct SubjectSnapshot: Sendable, Equatable {
        public let subject: Subject
        public let displayName: String
        public let snapshot: CanvasSnapshot
    }

    private struct AlwaysFail: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    /// One observer-scoped assignment-groups query: the course-scoped O4 shape
    /// (family-linking.md §6.1), which returns `submission` as an array even for a course with
    /// only one observee enrolled — `ObserverAssignmentGroupMapper` is written for exactly that.
    private static func observerAssignmentGroupsQuery() -> [(String, String)] {
        CanvasQuery.assignmentGroups() + [("include[]", "observed_users")]
    }

    private static func observerCoursesQuery() -> [(String, String)] {
        CanvasQuery.courses() + [("include[]", "observed_users")]
    }

    /// Fetches both students' snapshots. Throws if the persona is missing from the manifest, or
    /// if any fixture fails to decode — a thrown error here is itself a sign the fixtures no
    /// longer match the production decoders, which is exactly what FAM-14's test proves never
    /// silently passes.
    public static func fetchSubjectSnapshots(now: Date) async throws -> [SubjectSnapshot] {
        let host = "canvas.sample-family.example"
        let accountKey = AccountKey(personaName)
        let transport = try ReplayTransport.persona(personaName)
        let credential = CanvasCredential(host: host, userID: "sample-family-observer", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                     refresher: AlwaysFail(), clock: TestClock(now))
        let client = CanvasClient(host: host, transport: transport, tokens: tokens)

        let observees = try await LinkedUsersUseCase(client: client).listObservees()
        var result: [SubjectSnapshot] = []
        for observee in observees {
            let courseData = try await client.fetchOne(path: "/api/v1/users/\(observee.canvasUserID)/courses", query: observerCoursesQuery())
            let courses = try CourseMapper.map(courseData, host: host).items

            var groups: [CanvasID<Course>: [AssignmentGroup]] = [:]
            for course in courses {
                let groupData = try await client.fetchOne(path: "/api/v1/courses/\(course.id.rawValue)/assignment_groups",
                                                          query: observerAssignmentGroupsQuery())
                groups[course.id] = try ObserverAssignmentGroupMapper.map(groupData, courseID: course.id, observeeUserID: observee.canvasUserID).items
            }

            let fetchedStatus = SectionStatus(fetchedAt: now, carriedForward: false)
            let snapshot = CanvasSnapshot(
                generation: 1, accountKey: accountKey, host: host, fetchedAt: now,
                profile: UserProfile(id: CanvasID(observee.canvasUserID), name: observee.name, shortName: nil,
                                     timeZone: nil, calendarFeedURL: nil),
                courses: courses, groups: groups, gradingPeriods: [:], planner: [], events: [], announcements: [],
                courseColors: [:],
                sections: [.profile: fetchedStatus, .courses: fetchedStatus, .assignmentGroups: fetchedStatus, .planner: fetchedStatus])

            result.append(SubjectSnapshot(
                subject: Subject(id: SubjectKey("\(personaName).\(observee.canvasUserID)"), kind: .observee(canvasUserID: observee.canvasUserID)),
                displayName: observee.name, snapshot: snapshot))
        }
        return result
    }
}
