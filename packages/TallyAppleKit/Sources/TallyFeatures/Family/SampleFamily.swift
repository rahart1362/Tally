import Foundation
import Synchronization
import TallyCanvasAPI
import TallyDomain
import TallyReplay
import TallySampleFixtures

/// FAM-14 (family-linking.md §10): "Explore with Sample Data" can reach parent mode. The bundled
/// `sample-family` persona (M3-E1: one fictional observer, two fictional students at one fictional
/// school; `CanvasFixtures/family-manifest.json`) replayed through the production decoders,
/// `LinkedUsersUseCase` (FAM-06), `CourseMapper` and `ObserverAssignmentGroupMapper` (FAM-03), the
/// same path `SampleFamilyHarness` proves on Linux. Never the network, never persisted (ASC-14).
///
/// Each student's courses come from Canvas's per-observee `GET /users/:id/courses`, so each decodes
/// on its own (M3-E1 report §3: the merged observer `/courses` composition, FAM-04, is not built).
nonisolated struct SampleFamilyReplay: Sendable {
    static let manifestName = "family-manifest.json"
    static let accountKey = AccountKey("sample-family")

    let client: CanvasClient
    let host: String
    let school: String
    let anchor: Date
    let timeZone: TimeZone

    private struct ManifestFile: Decodable {
        let anchor: Date
        let timeZone: String
        let host: String
        let school: String
        let routes: [RouteFixture]
    }

    /// Reads the bundled family manifest (file I/O: call it off the main actor). `root` replaces the
    /// bundled fixtures folder in tests.
    static func make(root: URL? = nil) throws -> SampleFamilyReplay {
        let root = try root ?? SampleDataFixtureBundle.resourceRoot()
        let data = try Data(contentsOf: root.appendingPathComponent(manifestName))
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(ManifestFile.self, from: data)
        guard let timeZone = TimeZone(identifier: file.timeZone) else { throw SampleDataError.manifestMalformed }
        let credential = CanvasCredential(host: file.host, userID: "sample-family", accessToken: "sample-mode",
                                          refreshToken: "unused", accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: SampleFamilyCredentialStore(credential),
                                      refresher: SampleFamilyNeverRefresh(), clock: SystemDateProvider())
        let client = CanvasClient(host: file.host, transport: ReplayTransport(routes: file.routes, root: root), tokens: tokens)
        return SampleFamilyReplay(client: client, host: file.host, school: file.school, anchor: file.anchor, timeZone: timeZone)
    }

    /// O1: the linked students, as Canvas lists them.
    func observees() async throws -> [ObservedUser] {
        try await LinkedUsersUseCase(client: client).listObservees()
    }

    /// The observer's own profile (the student-side sample's "Linked in Canvas" row).
    func observer() async throws -> ObservedUser {
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile")
        let profile = try ProfileMapper.map(data)
        return ObservedUser(canvasUserID: profile.id.rawValue, name: profile.name, avatarURL: nil)
    }

    /// One student's snapshot, its Canvas dates moved forward to look current (`SnapshotDateRebaser`).
    func snapshot(of student: ObservedUser, now: Date) async throws -> CanvasSnapshot {
        let coursesQuery = CanvasQuery.courses() + [("include[]", "observed_users")]
        let groupsQuery = CanvasQuery.assignmentGroups() + [("include[]", "observed_users")]
        let courseData = try await client.fetchOne(path: "/api/v1/users/\(student.canvasUserID)/courses", query: coursesQuery)
        let courses = try CourseMapper.map(courseData, host: host).items
        var groups: [CanvasID<Course>: [AssignmentGroup]] = [:]
        for course in courses where groups[course.id] == nil {
            let data = try await client.fetchOne(path: "/api/v1/courses/\(course.id.rawValue)/assignment_groups", query: groupsQuery)
            groups[course.id] = try ObserverAssignmentGroupMapper.map(data, courseID: course.id,
                                                                      observeeUserID: student.canvasUserID).items
        }
        // Stamped with the replay's own time, as the live gateway stamps a fetch (the rebase keeps it).
        let fetched = SectionStatus(fetchedAt: now, carriedForward: false)
        let snapshot = CanvasSnapshot(
            generation: 1, accountKey: Self.accountKey, host: host, fetchedAt: now,
            profile: UserProfile(id: CanvasID(student.canvasUserID), name: student.name, shortName: nil,
                                 timeZone: timeZone.identifier, calendarFeedURL: nil),
            courses: courses, groups: groups, gradingPeriods: [:], planner: [], events: [], announcements: [],
            courseColors: [:],
            sections: [.profile: fetched, .courses: fetched, .assignmentGroups: fetched, .planner: fetched])
        return SnapshotDateRebaser.rebase(snapshot, anchor: anchor, now: now, timeZone: timeZone)
    }

    /// The opaque subject key of a sample student (no name in it, §6.2).
    static func subject(of student: ObservedUser) -> Subject {
        Subject(id: SubjectKey("\(accountKey.rawValue).\(student.canvasUserID)"),
                kind: .observee(canvasUserID: student.canvasUserID))
    }
}

/// What parent mode starts from: the school and the linked students, in Canvas's order.
nonisolated struct SampleFamilyRoster: Sendable {
    let replay: SampleFamilyReplay
    let students: [FamilyStudent]
    /// The observees as Canvas listed them, for each student's gateway.
    let observees: [String: ObservedUser]

    /// Off the main actor: the manifest read and the O1 replay. Students repeated in the list are
    /// kept once (the first), so a subject key never repeats (crash-safety-2.md §8).
    @concurrent
    static func load(root: URL? = nil) async throws -> SampleFamilyRoster {
        let replay = try SampleFamilyReplay.make(root: root)
        var seen: Set<String> = []
        let observees = try await replay.observees().filter { seen.insert($0.canvasUserID).inserted }
        let students = observees.map {
            FamilyStudent(subject: SampleFamilyReplay.subject(of: $0), canvasUserID: $0.canvasUserID, name: $0.name,
                          school: replay.school)
        }
        return SampleFamilyRoster(replay: replay, students: students,
                                  observees: Dictionary(observees.map { ($0.canvasUserID, $0) }, uniquingKeysWith: { first, _ in first }))
    }
}

/// One sample student's `CanvasGateway`, for that student's `SampleSession` (each refresh replays).
actor SampleFamilyStudentGateway: CanvasGateway {
    private let replay: SampleFamilyReplay
    private let student: ObservedUser

    init(replay: SampleFamilyReplay, student: ObservedUser) {
        self.replay = replay
        self.student = student
    }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        try await replay.snapshot(of: student, now: now)
    }
}

/// FAM-06's link writes and S1, for the family screens. A signed-in account has none yet (the
/// account's one `CanvasClient` is not reachable from Settings; M3-E2 report, open items), so today
/// only sample mode supplies one.
nonisolated protocol FamilyLinkService: Sendable {
    func listObservers() async throws(LinkManagementError) -> [ObservedUser]
    func createInvite() async throws(LinkManagementError) -> PairingInvite
    func addStudent(pairingCode: String) async throws(LinkManagementError) -> ObservedUser
    func unlink(observeeCanvasUserID: String) async throws(LinkManagementError)
}

/// The scripted outcomes UI tests choose (`FamilyTestHooks`); `nil` in normal use.
nonisolated enum SampleFamilyOutcome: String, Sendable {
    /// §7.6 "Student, no observers": S1 lists nobody.
    case noObservers
    /// §7.6 "Invite refused": W1 answers 401.
    case inviteRefused
    /// §7.6 "Scope missing on Tally's key".
    case scopeMissing
    /// §7.6 "Link removed": the last sample student's link disappears as parent mode opens.
    case linkRemoved
}

/// Sample mode's link service: no network, nothing kept. The observer is the persona's (S1); a new
/// invite is a made-up code; adding a student always fails as an unknown code would (§7.6 "Code
/// rejected": a sample code is never checked with a school); unlinking succeeds locally.
actor SampleFamilyLinkService: FamilyLinkService {
    private let outcome: SampleFamilyOutcome?
    private let clock: any DateProviding
    private var replay: SampleFamilyReplay?

    init(outcome: SampleFamilyOutcome? = SampleFamilyLinkService.scriptedOutcome(), clock: any DateProviding = SystemDateProvider(),
         replay: SampleFamilyReplay? = nil) {
        self.outcome = outcome
        self.clock = clock
        self.replay = replay
    }

    /// The UI-test hook's outcome, never in a shipping build.
    nonisolated static func scriptedOutcome() -> SampleFamilyOutcome? {
        #if DEBUG || TALLY_TEST_HOOKS
        return FamilyTestHooks.outcome()
        #else
        return nil
        #endif
    }

    func listObservers() async throws(LinkManagementError) -> [ObservedUser] {
        if outcome == .noObservers { return [] }
        do {
            let replay = try resolvedReplay()
            return [try await replay.observer()]
        } catch {
            throw .network(.contract)
        }
    }

    func createInvite() async throws(LinkManagementError) -> PairingInvite {
        switch outcome {
        case .inviteRefused?: throw .selfRegistrationOff
        case .scopeMissing?: throw .scopeMissing
        default: break
        }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let code = String((0..<FamilyUIConfig.pairingCodeLength).map { _ in alphabet.randomElement() ?? "X" })
        return PairingInvite(code: code, expiresAt: clock.now().addingTimeInterval(FamilyUIConfig.pairingCodeLifetime.timeInterval))
    }

    func addStudent(pairingCode: String) async throws(LinkManagementError) -> ObservedUser {
        if outcome == .scopeMissing { throw .scopeMissing }
        throw .invalidOrExpiredCode
    }

    func unlink(observeeCanvasUserID: String) async throws(LinkManagementError) {
        if outcome == .scopeMissing { throw .scopeMissing }
    }

    private func resolvedReplay() throws -> SampleFamilyReplay {
        if let replay { return replay }
        let made = try SampleFamilyReplay.make()
        replay = made
        return made
    }
}

/// Never called: the replay's credential never expires.
private nonisolated struct SampleFamilyNeverRefresh: TokenRefreshing {
    func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
        throw AuthError.reauthRequired
    }
}

/// The replay's credential, in memory only (ASC-14: sample mode persists nothing).
private nonisolated final class SampleFamilyCredentialStore: CredentialStore {
    private let stored: Mutex<CanvasCredential?>

    init(_ credential: CanvasCredential) {
        stored = Mutex(credential)
    }

    func load() async -> CanvasCredential? { stored.withLock { $0 } }
    func save(_ credential: CanvasCredential) async throws { stored.withLock { $0 = credential } }
    func delete() async { stored.withLock { $0 = nil } }
}
