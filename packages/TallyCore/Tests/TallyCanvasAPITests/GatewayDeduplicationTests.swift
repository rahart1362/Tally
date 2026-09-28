import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// CS-07 (crash-safety-2.md, CS7-2b): `LiveCanvasGateway` removes repeated identifiers once, where
/// it assembles the `CanvasSnapshot`, keeping the first occurrence of each ID per collection.
///
/// The responses below are the recorded fixtures with repeats spliced in, the two ways Canvas
/// produces them: a paginated list repeats an item when the data changes between page fetches,
/// and a course comes back once per enrollment.
@Suite("LiveCanvasGateway: repeated identifiers are removed at the boundary (CS-07)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct GatewayDeduplicationTests {
    private struct NeverRefresh: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    private static func gateway(host: String, transport: ReplayTransport,
                                logger: any TallyLogger = NoOpLogger()) -> LiveCanvasGateway {
        let credential = CanvasCredential(host: host, userID: "dedupe", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                      refresher: NeverRefresh(), clock: TestClock())
        return LiveCanvasGateway(host: host, accountKey: AccountKey("dedupe"),
                                 client: CanvasClient(host: host, transport: transport, tokens: tokens), logger: logger)
    }

    // MARK: - JSON surgery on recorded fixtures

    private static func json(_ path: String) throws -> Any { try JSONSerialization.jsonObject(with: Fixtures.data(path)) }
    private static func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    /// A copy of `object` with its `key` changed, so the test can tell which occurrence survived.
    private static func repeatOf(_ object: Any, key: String = "name") -> [String: Any] {
        var copy = object as? [String: Any] ?? [:]
        copy[key] = "\(copy[key] ?? "") (repeat)"
        return copy
    }

    private static func sidecarHeaders(_ path: String) throws -> HTTPHeaders {
        struct Sidecar: Decodable { let headers: [String: String] }
        return HTTPHeaders(try JSONDecoder().decode(Sidecar.self, from: Fixtures.data(path)).headers)
    }

    private static func ok(_ body: Data, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponse {
        HTTPResponse(status: 200, headers: headers, body: body)
    }

    // MARK: - Every collection, one repeat each (grading-periods persona: all eight sections)

    /// Serves the grading-periods persona with one repeated ID in every collection:
    /// a course (listed twice, as for two enrollments), an assignment group, an assignment within a
    /// group, across groups and across courses, a grading period, a planner item, a calendar event
    /// and an announcement.
    static func gradingPeriodsWithOneRepeatPerCollection() async throws -> ReplayTransport {
        let base = "personas/grading-periods"
        let transport = try ReplayTransport.persona("grading-periods")

        var courses = try json("\(base)/courses.json") as? [Any] ?? []
        courses.append(repeatOf(courses[0]))

        var algebra = try json("\(base)/assignment_groups/90411.json") as? [[String: Any]] ?? []
        let repeatedGroup = repeatOf(algebra[0])
        var first = algebra[0]["assignments"] as? [Any] ?? []
        first.append(repeatOf(first[0]))                                   // within a group
        algebra[0]["assignments"] = first
        var second = algebra[1]["assignments"] as? [Any] ?? []
        second.append(repeatOf(first[1]))                                  // across groups
        algebra[1]["assignments"] = second
        algebra.append(repeatedGroup)                                      // a repeated group
        var chemistry = try json("\(base)/assignment_groups/90412.json") as? [[String: Any]] ?? []
        var chemistryFirst = chemistry[0]["assignments"] as? [Any] ?? []
        chemistryFirst.append(repeatOf(first[2]))                          // across courses
        chemistry[0]["assignments"] = chemistryFirst

        var periods = try json("\(base)/grading_periods/90411.json") as? [String: Any] ?? [:]
        var periodList = periods["grading_periods"] as? [Any] ?? []
        periodList.append(repeatOf(periodList[0], key: "title"))
        periods["grading_periods"] = periodList

        var planner = try json("\(base)/planner_items.json") as? [Any] ?? []
        planner.append(planner[0])
        var events = try json("\(base)/calendar_events.chunk1.json") as? [Any] ?? []
        events.append(repeatOf(events[0], key: "title"))
        var announcements = try json("\(base)/announcements.chunk1.json") as? [Any] ?? []
        announcements.append(repeatOf(announcements[0], key: "title"))

        let bodies: [(String, Data)] = [
            ("/api/v1/courses", try data(courses)),
            ("/api/v1/courses/90411/assignment_groups", try data(algebra)),
            ("/api/v1/courses/90412/assignment_groups", try data(chemistry)),
            ("/api/v1/courses/90411/grading_periods", try data(periods)),
            ("/api/v1/planner/items", try data(planner)),
            ("/api/v1/calendar_events", try data(events)),
            ("/api/v1/announcements", try data(announcements)),
        ]
        for (path, body) in bodies {
            await transport.inject(response: ok(body), times: 1) { $0.url.path == path }
        }
        return transport
    }

    @Test func theGatewayKeepsTheFirstOccurrenceInEveryCollection() async throws {
        let transport = try await Self.gradingPeriodsWithOneRepeatPerCollection()
        let logger = RecordingLogger()
        let snapshot = try await Self.gateway(host: "northgate.instructure.example", transport: transport, logger: logger)
            .fetchSnapshot(previous: nil, now: TestClock().now())

        // Counts only, one event per collection that lost repeats, in `SnapshotCollection` order.
        // The repeated group's own assignments leave with it, so they are not counted again.
        #expect(logger.events == [
            .duplicateIDsDropped(.courses, count: 1), .duplicateIDsDropped(.assignmentGroups, count: 1),
            .duplicateIDsDropped(.assignments, count: 3), .duplicateIDsDropped(.gradingPeriods, count: 1),
            .duplicateIDsDropped(.plannerItems, count: 1), .duplicateIDsDropped(.events, count: 1),
            .duplicateIDsDropped(.announcements, count: 1),
        ])

        #expect(snapshot.courses.map(\.id) == ["90411", "90412", "90413", "90414"])
        #expect(snapshot.courses[0].name == "Algebra II", "the first occurrence, not the repeat")
        #expect(await transport.requests().filter { $0.url.path == "/api/v1/courses/90411/assignment_groups" }.count == 1,
                "a repeated course is dropped before its per-course requests, so they are not sent twice")

        let algebra = snapshot.groups["90411"] ?? []
        #expect(algebra.map(\.id) == ["310400", "310401", "310402"])
        #expect(!algebra[0].name.hasSuffix("(repeat)"))
        let allAssignments = snapshot.courses.flatMap { (snapshot.groups[$0.id] ?? []).flatMap(\.assignments) }
        #expect(Set(allAssignments.map(\.id)).count == allAssignments.count, "assignment IDs are unique account-wide")
        #expect(allAssignments.allSatisfy { !$0.name.hasSuffix("(repeat)") })
        #expect(algebra[0].assignments.count == 17 && algebra[1].assignments.count == 6)
        #expect((snapshot.groups["90412"] ?? [])[0].assignments.count == 6)

        let periods = snapshot.gradingPeriods["90411"] ?? []
        #expect(periods.map(\.id) == ["2201", "2202", "2203"])
        #expect(!periods[0].title.hasSuffix("(repeat)"))
        #expect(snapshot.gradingPeriods["90412"]?.map(\.id) == ["2201", "2202", "2203"],
                "the same period in two courses is not a repeat: periods are de-duplicated per course")

        #expect(Set(snapshot.planner.map(\.id)).count == snapshot.planner.count)
        #expect(snapshot.planner.count == 38)
        #expect(snapshot.events.map(\.id.rawValue).filter { $0 == "5510003" }.count == 1)
        #expect(snapshot.events.allSatisfy { !$0.title.hasSuffix("(repeat)") })
        #expect(snapshot.announcements.map(\.id.rawValue).filter { $0 == "4401001" }.count == 1)
        #expect(snapshot.announcements.allSatisfy { !$0.title.hasSuffix("(repeat)") })
    }

    // MARK: - A repeat across a page boundary (flagship: two-page planner and calendar)

    @Test func aRepeatAcrossAPageBoundaryIsDropped() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let plannerFirst = try Self.json("personas/flagship/planner_items.page1.json") as? [Any] ?? []
        var plannerSecond = try Self.json("personas/flagship/planner_items.page2.json") as? [Any] ?? []
        plannerSecond.insert(plannerFirst[plannerFirst.count - 1], at: 0) // the page shifted by one between fetches
        let eventsFirst = try Self.json("personas/flagship/calendar_events.chunk1.page1.json") as? [Any] ?? []
        var eventsSecond = try Self.json("personas/flagship/calendar_events.chunk1.page2.json") as? [Any] ?? []
        eventsSecond.insert(eventsFirst[eventsFirst.count - 1], at: 0)

        let plannerHeaders = try Self.sidecarHeaders("personas/flagship/planner_items.page2.headers.json")
        let eventHeaders = try Self.sidecarHeaders("personas/flagship/calendar_events.chunk1.page2.headers.json")
        await transport.inject(response: Self.ok(try Self.data(plannerSecond), headers: plannerHeaders)) {
            $0.url.path == "/api/v1/planner/items" && ($0.url.query ?? "").contains("page=bookmark")
        }
        await transport.inject(response: Self.ok(try Self.data(eventsSecond), headers: eventHeaders)) {
            $0.url.path == "/api/v1/calendar_events" && ($0.url.query ?? "").contains("page=bookmark")
        }

        let logger = RecordingLogger()
        let snapshot = try await Self.gateway(host: "canvas.northfield.example", transport: transport, logger: logger)
            .fetchSnapshot(previous: nil, now: TestClock().now())

        #expect(snapshot.planner.count == plannerFirst.count + plannerSecond.count - 1)
        #expect(Set(snapshot.planner.map(\.id)).count == snapshot.planner.count)
        #expect(snapshot.events.count == eventsFirst.count + eventsSecond.count - 1)
        #expect(Set(snapshot.events.map(\.id)).count == snapshot.events.count)
        #expect(logger.events == [.duplicateIDsDropped(.plannerItems, count: 1), .duplicateIDsDropped(.events, count: 1)])
    }

    // MARK: - Duplicate-free data is untouched

    /// Every persona and the stress snapshot are duplicate-free (checked here), and for them the
    /// de-duplication is the identity: the same value, and nothing logged.
    @Test(arguments: Fixtures.personas)
    func aPersonaWithoutRepeatsIsUnchangedAndNothingIsLogged(_ persona: String) async throws {
        let transport = try ReplayTransport.persona(persona)
        let host = try #require(try CanvasManifest.personaRoutes(persona).first?.host)
        let logger = RecordingLogger()
        let snapshot = try await Self.gateway(host: host, transport: transport, logger: logger)
            .fetchSnapshot(previous: nil, now: TestClock().now())
        #expect(logger.events.isEmpty)
        let again = SnapshotDeduplication.deduplicated(snapshot)
        #expect(again.snapshot == snapshot)
        #expect(again.dropped.isEmpty)
    }

    @Test func theStressSnapshotIsUnchanged() {
        let stress = StressSnapshotFixture.make()
        #expect(Set(stress.courses.map(\.id)).count == stress.courses.count)
        let assignments = stress.courses.flatMap { (stress.groups[$0.id] ?? []).flatMap(\.assignments) }
        #expect(Set(assignments.map(\.id)).count == assignments.count)
        let result = SnapshotDeduplication.deduplicated(stress)
        #expect(result.snapshot == stress)
        #expect(result.dropped.isEmpty)
    }

    /// The pure function on the hand-built fixture: every kind of repeat, and which occurrence stays.
    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func deduplicationRestoresTheDuplicateFreeFixture(_ kind: DuplicateIDFixture.Kind) {
        let repeated = DuplicateIDFixture.snapshot(duplicating: kind)
        let result = SnapshotDeduplication.deduplicated(repeated)
        #expect(result.snapshot == DuplicateIDFixture.base(), "first occurrence wins: the repeat is what goes")
        #expect(result.dropped.values.reduce(0, +) >= 1)
        #expect(SnapshotDeduplication.deduplicated(DuplicateIDFixture.base()).dropped.isEmpty)
    }
}
