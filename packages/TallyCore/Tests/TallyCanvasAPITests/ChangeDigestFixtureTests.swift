import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// WP-A07's required fixture test (implementation brief): `flagship-previous` -> `flagship`,
/// both built through `CanvasGateway.fetchSnapshot` over `ReplayTransport`, diffed with
/// `ChangeDigest.diff`. `fixtures/canvas/expected/digest/flagship.json` is the synthetic
/// generator's own world-model ground truth (its header: "ChangeDigest tests apply Tally's
/// own course-score threshold to course_score_changed"), so this test does not compare
/// against the raw file: it re-derives, category by category, what `ChangeDigest` is
/// specified to detect (architecture.md §3.4) — new/changed scores, new assignments,
/// due-date changes, new announcements, and course-score deltas clearing Tally's own
/// threshold — and checks each entry the fixture implies is really produced. The fixture's
/// "submitted" entries are intentionally not asserted: a student's own submission event is
/// not one of the categories `ChangeDigest` is specified to detect.
@Suite("ChangeDigest.diff against the flagship / flagship-previous fixture pair")
struct ChangeDigestFixtureTests {
    private let host = "canvas.northfield.example"
    private let previousAnchor = Date(timeIntervalSince1970: 1_790_514_000) // 2026-09-27T13:00:00Z
    private let anchor = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z, fixtures' anchor

    private func gateway(_ transport: ReplayTransport) -> LiveCanvasGateway {
        let refresher = RecordingRefresher()
        let clock = TestClock(anchor)
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "token-1", refreshToken: "refresh-1",
                                          accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        let coordinator = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                           refresher: refresher, clock: clock)
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator)
        return LiveCanvasGateway(host: host, accountKey: AccountKey("flagship-account"), client: client)
    }

    private func fetchBothSnapshots() async throws -> (previous: CanvasSnapshot, current: CanvasSnapshot) {
        let previousTransport = try ReplayTransport.persona("flagship-previous")
        let previous = try await gateway(previousTransport).fetchSnapshot(previous: nil, now: previousAnchor)
        let currentTransport = try ReplayTransport.persona("flagship")
        let current = try await gateway(currentTransport).fetchSnapshot(previous: nil, now: anchor)
        return (previous, current)
    }

    @Test func matchesTheGroundTruthFixtureCategoryByCategory() async throws {
        let (previous, current) = try await fetchBothSnapshots()
        let digest = ChangeDigest.diff(old: previous, new: current)

        // "newly_graded": Problem Set 6 (course 51842, assignment 1204405) went from no
        // posted score to 92.0 / 100.
        #expect(digest.gradeChanges == [
            ChangeDigest.GradeChange(courseID: "51842", assignmentID: "1204405", submissionID: "903114141",
                                     previousScore: nil, newScore: 92.0, pointsPossible: 100.0),
        ])

        // "new_assignment": Chapter 7 Reading Response (course 51843, assignment 1204439).
        #expect(digest.newAssignments == [
            ChangeDigest.NewAssignment(courseID: "51843", assignmentID: "1204439",
                                       dueAt: iso("2026-10-12T13:00:00Z")),
        ])

        // "due_date_changed": Essay 2 (course 51846, assignment 1204474) moved two days later.
        #expect(digest.dueDateChanges == [
            ChangeDigest.DueDateChange(courseID: "51846", assignmentID: "1204474",
                                       previousDueAt: iso("2026-10-04T04:59:59Z"), newDueAt: iso("2026-10-06T04:59:59Z")),
        ])

        // Three "new_announcement" entries, one per affected course.
        #expect(Set(digest.newAnnouncements.map(\.announcementID)) == ["2551006", "2551005", "2551004"])
        #expect(digest.newAnnouncements.count == 3)
        #expect(digest.newAnnouncements.first { $0.announcementID == "2551006" }?.courseID == "51845")
        #expect(digest.newAnnouncements.first { $0.announcementID == "2551005" }?.courseID == "51842")
        #expect(digest.newAnnouncements.first { $0.announcementID == "2551004" }?.courseID == "51846")

        // "course_score_changed" for MATH 122 (51842) is a real 0.01 pt move in the ground
        // truth (90.09 -> 90.1), but it never clears Tally's own 0.5 pt digest threshold.
        #expect(digest.courseScoreChanges.isEmpty)

        #expect(!digest.isEmpty)
        #expect(digest.count == 1 + 1 + 1 + 3 + 0)
    }

    @Test func theSameFlagshipSnapshotDiffedAgainstItselfIsEmpty() async throws {
        let (_, current) = try await fetchBothSnapshots()
        #expect(ChangeDigest.diff(old: current, new: current).isEmpty)
    }

    @Test func theFirstSnapshotOfAnAccountProducesAnEmptyDigestEvenWithFullFlagshipData() async throws {
        let (_, current) = try await fetchBothSnapshots()
        #expect(ChangeDigest.diff(old: nil, new: current) == .empty)
    }

    private func iso(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }
}
