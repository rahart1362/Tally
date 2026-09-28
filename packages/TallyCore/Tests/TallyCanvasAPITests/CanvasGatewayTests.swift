import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("CanvasGateway.fetchSnapshot: composition and partial-failure policy")
struct CanvasGatewayTests {
    private let host = "canvas.northfield.example"
    private let anchor = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z, the fixtures' anchor

    private func gateway(_ transport: ReplayTransport, backoff: BackoffPolicy = BackoffPolicy(base: .milliseconds(1), maxDelay: .milliseconds(5)))
        -> (gateway: LiveCanvasGateway, refresher: RecordingRefresher) {
        let refresher = RecordingRefresher()
        let clock = TestClock(anchor)
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "token-1", refreshToken: "refresh-1",
                                          accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        let coordinator = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                           refresher: refresher, clock: clock)
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator, backoff: backoff)
        return (LiveCanvasGateway(host: host, accountKey: AccountKey("test-account"), client: client), refresher)
    }

    @Test func flagshipSnapshotMatchesMapperOutputsAndStaysUnderTheRequestBudget() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let (gateway, _) = gateway(transport)
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: anchor)

        let expectedCourses = try CourseMapper.map(Fixtures.data("personas/flagship/courses.json"), host: host).items
        #expect(snapshot.courses == expectedCourses)
        #expect(snapshot.profile.name == "Alex Sample")

        let course = try #require(expectedCourses.first { $0.courseCode == "MATH 122" })
        let expectedGroups = try AssignmentGroupMapper.map(Fixtures.data("personas/flagship/assignment_groups/\(course.id.rawValue).json"),
                                                           courseID: course.id).items
        #expect(snapshot.groups[course.id] == expectedGroups)

        // Flagship has no weighted-period courses, so no grading_periods calls are made.
        #expect(snapshot.gradingPeriods.isEmpty)
        #expect(!snapshot.planner.isEmpty && !snapshot.events.isEmpty && !snapshot.announcements.isEmpty && !snapshot.courseColors.isEmpty)

        let requestCount = await transport.requestCount
        #expect(requestCount <= 19)
        #expect(requestCount == 13) // matches the persona's own declared request_count

        for section in SnapshotSection.allCases {
            #expect(snapshot.sections[section]?.carriedForward == false)
        }
    }

    @Test func optionalSectionFailureCarriesForwardFromThePreviousSnapshot() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let (gateway, _) = gateway(transport)
        let previous = try await gateway.fetchSnapshot(previous: nil, now: anchor)
        #expect(!previous.courseColors.isEmpty)

        await transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 3,
                               matching: { $0.url.path == "/api/v1/users/self/colors" })
        let later = anchor.addingTimeInterval(3600)
        let next = try await gateway.fetchSnapshot(previous: previous, now: later)

        #expect(next.courseColors == previous.courseColors) // carried forward, unchanged
        let status = try #require(next.sections[.colors])
        #expect(status.carriedForward)
        #expect(status.fetchedAt == previous.sections[.colors]?.fetchedAt) // "its own timestamp" (architecture §3.2)
        // The required sections still refreshed normally in the same pass.
        #expect(next.sections[.courses]?.carriedForward == false)
        #expect(next.fetchedAt == later)
    }

    @Test func requiredSectionFailureThrowsAndProducesNoSnapshot() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let (gateway, _) = gateway(transport)
        await transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 3,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        await #expect(throws: RefreshFailure.server) {
            _ = try await gateway.fetchSnapshot(previous: nil, now: anchor)
        }
    }

    @Test func a401OnARequiredCallRefreshesExactlyOnceThenSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let (gateway, refresher) = gateway(transport)
        await transport.inject(response: try ReplayTransport.errorResponse("401-invalid-access-token"), times: 1,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: anchor)
        #expect(snapshot.profile.name == "Alex Sample")
        #expect(refresher.callCount == 1)
    }

    @Test func largePersonaChunksContextCodesAtTenAndPaginatesEachChunk() async throws {
        let transport = try ReplayTransport.persona("large")
        let (gateway, _) = gateway(transport)
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: anchor)
        // 12 courses -> chunks of 10 and 2 (TallyConfig.contextCodesPerRequest), each chunk
        // independently paginated (announcements' first chunk is itself 2 pages on this fixture).
        #expect(!snapshot.events.isEmpty && !snapshot.announcements.isEmpty)
        #expect(Set(snapshot.courses.map(\.id)).count == 12)
    }
}
