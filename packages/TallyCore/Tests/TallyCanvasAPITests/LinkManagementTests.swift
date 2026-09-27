import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Family link-management use cases: S1, O1, W1-W3 (FAM-06)")
struct LinkManagementTests {
    private let host = "canvas.northfield.example"

    private func coordinator(clock: TestClock) -> TokenCoordinator {
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "token-1",
                                          refreshToken: "refresh-1", accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        return TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                refresher: RecordingRefresher(), clock: clock)
    }

    private func jsonResponse(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: HTTPHeaders(["Content-Type": "application/json"]), body: Data(body.utf8))
    }

    // MARK: - S1 / O1 (reads)

    @Test func listObserveesDecodesTheRealFixture() async throws {
        let transport = try ReplayTransport.personaAccount("parent-observer", host: host)
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let observees = try await LinkedUsersUseCase(client: client).listObservees()
        #expect(observees.count == 1)
        #expect(observees[0].canvasUserID == "4820117")
        #expect(observees[0].name == "Alex Sample")
    }

    /// No recorded fixture for S1 (only O1's shape was captured) — built in-test from
    /// Instructure's own documented "User" shape (same as O1's; family-linking.md §2.4,
    /// https://canvas.instructure.com/doc/api/user_observees.html), matching
    /// `fixtures/canvas/schemas/Observee.schema.json`'s required fields.
    @Test func listObserversDecodesAHandBuiltResponse() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(
            response: jsonResponse(200, #"[{"id":"9001","name":"Jamie Parent","created_at":"2026-01-01T00:00:00Z","sortable_name":"Parent, Jamie","short_name":"Jamie","avatar_url":"https://canvas.northfield.example/images/avatar.png","observation_link_root_account_ids":["10"]}]"#),
            matching: { $0.url.path == FamilyEndpoints.observersPath })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let observers = try await LinkedUsersUseCase(client: client).listObservers()
        #expect(observers == [ObservedUser(canvasUserID: "9001", name: "Jamie Parent",
                                           avatarURL: URL(string: "https://canvas.northfield.example/images/avatar.png"))])
    }

    // MARK: - W1: create a pairing code

    @Test func createInviteDecodesTheCodeAndExpiry() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(
            response: jsonResponse(200, #"{"user_id":"4820117","code":"X7Q2KP","expires_at":"2026-10-04T13:00:00Z","workflow_state":"active"}"#),
            matching: { $0.url.path == FamilyEndpoints.pairingCodesPath && $0.method == .post })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = CreateInviteUseCase(client: client, familyCapable: true, clock: TestClock())
        let invite = try await useCase.createInvite(recentInviteTimestamps: [])
        #expect(invite.code == "X7Q2KP")
        #expect(invite.expiresAt == CanvasDate.parse("2026-10-04T13:00:00Z"))
        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests[0].method == .post)
    }

    @Test func createInviteWithoutTheScopeNeverCallsCanvas() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = CreateInviteUseCase(client: client, familyCapable: false, clock: TestClock())
        await #expect(throws: LinkManagementError.scopeMissing) {
            _ = try await useCase.createInvite(recentInviteTimestamps: [])
        }
        #expect(await transport.requestCount == 0)
    }

    /// family-linking.md §2.2 / §4.4: Canvas's own 401 (no `WWW-Authenticate`) for a school
    /// with self-registration off — reached only once the registry has already confirmed
    /// the scope is present, so this can only mean the school-side policy, not a missing scope.
    @Test func createInviteMapsA401ToSelfRegistrationOffWhenTheScopeIsPresent() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("401-insufficient-scopes"),
                               matching: { $0.url.path == FamilyEndpoints.pairingCodesPath })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = CreateInviteUseCase(client: client, familyCapable: true, clock: TestClock())
        await #expect(throws: LinkManagementError.selfRegistrationOff) {
            _ = try await useCase.createInvite(recentInviteTimestamps: [])
        }
    }

    @Test func createInviteIsThrottledAfterFiveInTheWindow() async throws {
        let clock = TestClock()
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: clock))
        let useCase = CreateInviteUseCase(client: client, familyCapable: true, clock: clock)
        let recent = (0..<5).map { clock.now().addingTimeInterval(-Double($0) * 60) } // 5 within the last few minutes
        do {
            _ = try await useCase.createInvite(recentInviteTimestamps: recent)
            Issue.record("expected .throttled")
        } catch LinkManagementError.throttled(let nextAllowedAt) {
            #expect(nextAllowedAt > clock.now())
        }
        #expect(await transport.requestCount == 0) // the throttle never reaches Canvas
    }

    @Test func createInviteIsNotThrottledOnceTheOldestFallsOutsideTheWindow() async throws {
        let clock = TestClock()
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(
            response: jsonResponse(200, #"{"user_id":"4820117","code":"AB12CD","expires_at":"2026-10-04T13:00:00Z","workflow_state":"active"}"#),
            matching: { $0.url.path == FamilyEndpoints.pairingCodesPath })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: clock))
        let useCase = CreateInviteUseCase(client: client, familyCapable: true, clock: clock)
        var recent = (0..<4).map { _ in clock.now() }
        recent.append(clock.now().addingTimeInterval(-TallyConfig.invitesPerDayWindow.timeInterval - 1))
        let invite = try await useCase.createInvite(recentInviteTimestamps: recent)
        #expect(invite.code == "AB12CD")
    }

    // MARK: - W2: add a student by code

    @Test func addStudentByCodeSendsTheCodeInTheFormBodyNeverTheQuery() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(
            response: jsonResponse(200, #"{"id":"4820117","name":"Alex Sample","created_at":"2026-01-01T00:00:00Z","sortable_name":"Sample, Alex","short_name":"Alex","observation_link_root_account_ids":["10"]}"#),
            matching: { $0.url.path == FamilyEndpoints.observeesPath && $0.method == .post })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = AddStudentByCodeUseCase(client: client, familyCapable: true)
        let observee = try await useCase.addStudent(pairingCode: "X7Q2KP")
        #expect(observee.canvasUserID == "4820117")
        let requests = await transport.requests()
        #expect(requests.count == 1)
        #expect(requests[0].url.query == nil || !(requests[0].url.query ?? "").contains("X7Q2KP"))
        #expect(String(decoding: requests[0].body ?? Data(), as: UTF8.self).contains("pairing_code=X7Q2KP"))
        #expect(requests[0].headers["Content-Type"] == FormBody.contentType)
    }

    @Test func addStudentByCodeMapsA422ToInvalidOrExpiredCode() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(
            response: jsonResponse(422, #"{"errors":[{"message":"Invalid pairing code."}]}"#),
            matching: { $0.url.path == FamilyEndpoints.observeesPath })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = AddStudentByCodeUseCase(client: client, familyCapable: true)
        await #expect(throws: LinkManagementError.invalidOrExpiredCode) {
            _ = try await useCase.addStudent(pairingCode: "BADCOD")
        }
    }

    @Test func addStudentByCodeWithoutTheScopeNeverCallsCanvas() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = AddStudentByCodeUseCase(client: client, familyCapable: false)
        await #expect(throws: LinkManagementError.scopeMissing) {
            _ = try await useCase.addStudent(pairingCode: "X7Q2KP")
        }
        #expect(await transport.requestCount == 0)
    }

    // MARK: - W3: unlink

    @Test func unlinkSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: jsonResponse(200, #"{"id":"4820117"}"#),
                               matching: { $0.url.path == FamilyEndpoints.observeePath("4820117") && $0.method == .delete })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        try await UnlinkStudentUseCase(client: client, familyCapable: true).unlink(observeeCanvasUserID: "4820117")
    }

    @Test func unlinkTreatsA404AsAlreadyUnlinked() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("404-not-found"),
                               matching: { $0.url.path == FamilyEndpoints.observeePath("4820117") })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        try await UnlinkStudentUseCase(client: client, familyCapable: true).unlink(observeeCanvasUserID: "4820117")
    }

    @Test func unlinkWithoutTheScopeNeverCallsCanvas() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let useCase = UnlinkStudentUseCase(client: client, familyCapable: false)
        await #expect(throws: LinkManagementError.scopeMissing) {
            try await useCase.unlink(observeeCanvasUserID: "4820117")
        }
        #expect(await transport.requestCount == 0)
    }

    // MARK: - Authorization: canvas_login + force_login on the parent path

    @Test func parentAuthorizeURLAlwaysCarriesBothFlags() {
        var rng = SeededRandom(seed: 7)
        let request = AuthorizationRequest.begin(host: host, clientID: "client-1",
                                                 redirectURI: URL(string: "https://tally-app.dev/oauth/callback")!,
                                                 now: TestClock().now(), forceLogin: true, canvasLogin: true, using: &rng)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        #expect(values["canvas_login"] == "1")
        #expect(values["force_login"] == "1")
    }

    @Test func studentAuthorizeURLNeverCarriesCanvasLogin() {
        var rng = SeededRandom(seed: 7)
        let request = AuthorizationRequest.begin(host: host, clientID: "client-1",
                                                 redirectURI: URL(string: "https://tally-app.dev/oauth/callback")!,
                                                 now: TestClock().now(), using: &rng)
        #expect(!request.url.absoluteString.contains("canvas_login"))
    }
}
