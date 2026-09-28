import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// R-1 (resilience.md): a rate limit never becomes a retry storm. Before R-1, `CanvasClient`'s
/// `.rateLimited` branch handed `BackoffPolicy` the whole budget on every attempt and never
/// subtracted the time already spent, so a persistent 429 was retried until the caller cancelled:
/// 1,501 requests in 4 s with a 1-5 ms policy and a 200 ms budget, and with the production policy
/// a request every few seconds for as long as anyone waited, with `Retry-After` ignored
/// (`.build-res/logs/r1-repro-before.log`). Canvas's API policy expects clients to back off.
///
/// Every test runs on a `VirtualClock`: backoff waits are recorded and skipped, so a policy that
/// waits for seconds runs in microseconds, and each test can check exactly how long the client
/// waited and how much (virtual) time the call took.
@Suite("CanvasClient: rate limits are bounded retries, never a storm (R-1)", .timeLimit(.minutes(1)))
struct CanvasClientRateLimitTests {
    private let host = "canvas.northfield.example"
    private let profilePath = "/api/v1/users/self/profile"
    private let profileJSON = #"{"id":"4820117","name":"Alex Sample","short_name":"Alex","time_zone":"America/New_York"}"#

    private func tokens() -> TokenCoordinator {
        let clock = TestClock()
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "token-1", refreshToken: "refresh-1",
                                          accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        return TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                refresher: RecordingRefresher(), clock: clock)
    }

    /// The production policy (1 s base, 8 s cap) unless a test says otherwise, a seeded RNG, the
    /// virtual clock, and `TestClock`'s instant (2026-09-28T13:00:00Z) as the wall clock.
    private func client(_ transport: ScriptedTransport, clock: VirtualClock,
                        backoff: BackoffPolicy = BackoffPolicy()) -> CanvasClient {
        CanvasClient(host: host, transport: transport, tokens: tokens(), backoff: backoff, rng: SeededRandom(seed: 1),
                     clock: clock, wallClock: TestClock())
    }

    private func fetchProfile(_ client: CanvasClient, budget: Duration) async -> Result<Data, RefreshFailure> {
        do { return .success(try await client.fetchOne(path: profilePath, budget: budget)) } catch { return .failure(error) }
    }

    // MARK: - The retry cap

    /// With a budget far too long to matter, the cap alone ends the call: one request plus
    /// `maxRateLimitRetries` retries, then `.rateLimited`. Both rate-limit shapes Canvas uses.
    @Test(arguments: [ScriptedTransport.rateLimited(), ScriptedTransport.rateLimitedForbidden()])
    func aPersistentRateLimitStopsAtTheRetryCap(_ rateLimited: HTTPResponse) async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([rateLimited])
        let result = await fetchProfile(client(transport, clock: clock), budget: .seconds(3_600))

        #expect(result == .failure(.rateLimited))
        #expect(await transport.requestCount == 1 + CanvasClient.maxRateLimitRetries)
        #expect(clock.sleeps.count == CanvasClient.maxRateLimitRetries)
    }

    /// Exponential with a floor: retry `n` waits between half and all of `min(1 s * 2^n, 8 s)`, so
    /// never at once (full jitter could draw zero) and never less than 0.5 s, 1 s, 2 s, 4 s.
    @Test func rateLimitBackoffHasAnExponentialFloor() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited()])
        _ = await fetchProfile(client(transport, clock: clock), budget: .seconds(3_600))

        let ceilings: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]
        #expect(clock.sleeps.count == ceilings.count)
        for (sleep, ceiling) in zip(clock.sleeps, ceilings) {
            #expect(sleep >= ceiling / 2 && sleep <= ceiling, "waited \(sleep) against a step of \(ceiling)")
        }
    }

    // MARK: - The budget

    /// The default 10 s budget, the production policy, and 1 s of latency per request: the call
    /// ends `.rateLimited` inside its budget, having never started a wait it could not finish.
    @Test func aPersistent429EndsInsideTheBudget() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited()], clock: clock, latency: .seconds(1))
        let budget = TallyConfig.liveRefreshBudget
        let result = await fetchProfile(client(transport, clock: clock), budget: budget)

        #expect(result == .failure(.rateLimited))
        #expect(await transport.requestCount <= 1 + CanvasClient.maxRateLimitRetries)
        #expect(clock.elapsed <= budget, "the call took \(clock.elapsed) of virtual time against a \(budget) budget")
    }

    /// crash-safety-2.md F-6's reproduction: a 1-5 ms policy and a 200 ms budget made 1,501
    /// requests in 4 s before R-1.
    @Test func theF6ReproductionNowMakesAtMostTheCapsRequests() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited()], clock: clock, latency: .milliseconds(2))
        let budget = Duration.milliseconds(200)
        let result = await fetchProfile(client(transport, clock: clock, backoff: BackoffPolicy(base: .milliseconds(1), maxDelay: .milliseconds(5))),
                                        budget: budget)

        #expect(result == .failure(.rateLimited))
        #expect(await transport.requestCount <= 1 + CanvasClient.maxRateLimitRetries)
        #expect(clock.elapsed <= budget)
    }

    /// The same elapsed-time budget bounds server-error retries: a 500 that arrives after the
    /// budget is already spent is not retried.
    @Test func aServerErrorAfterTheBudgetIsSpentIsNotRetried() async {
        let clock = VirtualClock()
        let serverError = HTTPResponse(status: 500, body: Data(#"{"errors":[{"message":"An error occurred."}]}"#.utf8))
        let transport = ScriptedTransport([serverError, ScriptedTransport.ok(profileJSON)], clock: clock, latency: .seconds(2))
        let result = await fetchProfile(client(transport, clock: clock), budget: .seconds(1))

        #expect(result == .failure(.server))
        #expect(await transport.requestCount == 1)
        #expect(clock.sleeps.isEmpty)
    }

    // MARK: - Retry-After

    @Test func aRetryAfterInSecondsIsObeyed() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited(retryAfter: "3"), ScriptedTransport.ok(profileJSON)])
        let result = await fetchProfile(client(transport, clock: clock), budget: TallyConfig.liveRefreshBudget)

        #expect(result == .success(Data(profileJSON.utf8)))
        #expect(await transport.requestCount == 2)
        #expect(clock.sleeps == [.seconds(3)], "the policy's own first step is at most 1 s, so the 3 s must come from Retry-After")
    }

    /// An HTTP-date `Retry-After` is measured from the response's own `Date` header, and without
    /// one from the wall clock (`TestClock`: 2026-09-28T13:00:00Z).
    @Test(arguments: [
        (date: "Mon, 28 Sep 2026 09:15:00 GMT", retryAfter: "Mon, 28 Sep 2026 09:15:04 GMT", wait: Duration.seconds(4)),
        (date: nil, retryAfter: "Mon, 28 Sep 2026 13:00:06 GMT", wait: Duration.seconds(6)),
        (date: nil, retryAfter: "Monday, 28-Sep-26 13:00:05 GMT", wait: Duration.seconds(5)),
        (date: nil, retryAfter: "Mon Sep 28 13:00:07 2026", wait: Duration.seconds(7)),
    ] as [(date: String?, retryAfter: String, wait: Duration)])
    func aRetryAfterHTTPDateIsObeyed(_ headers: (date: String?, retryAfter: String, wait: Duration)) async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited(retryAfter: headers.retryAfter, date: headers.date),
                                           ScriptedTransport.ok(profileJSON)])
        let result = await fetchProfile(client(transport, clock: clock), budget: TallyConfig.liveRefreshBudget)

        #expect(result == .success(Data(profileJSON.utf8)))
        #expect(clock.sleeps == [headers.wait])
    }

    /// A `Retry-After` longer than what is left of the budget ends the call at once, as
    /// `.rateLimited`: no wait at all, rather than a wait that runs past the budget.
    @Test(arguments: ["120", "Mon, 28 Sep 2026 13:02:00 GMT"])
    func aRetryAfterPastTheBudgetStopsWithoutWaiting(_ retryAfter: String) async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited(retryAfter: retryAfter), ScriptedTransport.ok(profileJSON)])
        let result = await fetchProfile(client(transport, clock: clock), budget: TallyConfig.liveRefreshBudget)

        #expect(result == .failure(.rateLimited))
        #expect(await transport.requestCount == 1)
        #expect(clock.sleeps.isEmpty)
        #expect(clock.elapsed == .zero)
    }

    // MARK: - Recovery

    @Test func a429ThenA200Succeeds() async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited(), ScriptedTransport.ok(profileJSON)])
        let result = await fetchProfile(client(transport, clock: clock), budget: TallyConfig.liveRefreshBudget)

        #expect(result == .success(Data(profileJSON.utf8)))
        #expect(await transport.requestCount == 2)
        #expect(clock.sleeps.count == 1)
        #expect(clock.sleeps.allSatisfy { $0 >= .milliseconds(500) && $0 <= .seconds(1) })
    }

    // MARK: - Family linking: its calls have no coordinator above them to cancel a runaway retry

    private func linkClient(_ transport: ScriptedTransport, clock: VirtualClock) -> CanvasClient {
        client(transport, clock: clock)
    }

    /// Every family-linking call, S1/O1 reads and W1-W3 writes, against a persistent 429 with 1 s
    /// of latency per request: each ends as `.network(.rateLimited)` inside
    /// `FamilyEndpoints.requestBudget`, after at most the cap's requests.
    @Test(arguments: ["listObservers", "listObservees", "createInvite", "addStudent", "unlink"])
    func aPersistent429EndsEveryLinkManagementCallInsideItsBudget(_ call: String) async {
        let clock = VirtualClock()
        let transport = ScriptedTransport([ScriptedTransport.rateLimited()], clock: clock, latency: .seconds(1))
        let client = linkClient(transport, clock: clock)
        var outcome: LinkManagementError?
        do {
            switch call {
            case "listObservers": _ = try await LinkedUsersUseCase(client: client).listObservers()
            case "listObservees": _ = try await LinkedUsersUseCase(client: client).listObservees()
            case "createInvite":
                _ = try await CreateInviteUseCase(client: client, familyCapable: true, clock: TestClock())
                    .createInvite(recentInviteTimestamps: [])
            case "addStudent": _ = try await AddStudentByCodeUseCase(client: client, familyCapable: true).addStudent(pairingCode: "X7Q2KP")
            default: try await UnlinkStudentUseCase(client: client, familyCapable: true).unlink(observeeCanvasUserID: "4820117")
            }
        } catch {
            outcome = error
        }

        #expect(outcome == .network(.rateLimited))
        #expect(await transport.requestCount <= 1 + CanvasClient.maxRateLimitRetries)
        #expect(clock.elapsed <= FamilyEndpoints.requestBudget, "\(call) took \(clock.elapsed) of virtual time")
    }

    // MARK: - Parsing Retry-After

    private let reference = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z

    @Test func delaySecondsParse() {
        #expect(RetryAfter.delay("0", reference: reference) == .zero)
        #expect(RetryAfter.delay("120", reference: reference) == .seconds(120))
        #expect(RetryAfter.delay(" 7 ", reference: reference) == .seconds(7))
        #expect(RetryAfter.delay("000000000000000000005", reference: reference) == .seconds(5))
        // Far past any budget, and capped rather than overflowing.
        #expect(RetryAfter.delay(String(repeating: "9", count: 40), reference: reference) == .seconds(RetryAfter.longestDelaySeconds))
    }

    @Test func everyHTTPDateFormParsesToTheSameInstant() {
        let expected = Date(timeIntervalSince1970: 784_111_777) // 1994-11-06T08:49:37Z, RFC 9110's own example
        let now = Date(timeIntervalSince1970: 1_000_000_000) // 2001: "94" is 1994, not 2094
        #expect(HTTPDate.parse("Sun, 06 Nov 1994 08:49:37 GMT", now: now) == expected)
        #expect(HTTPDate.parse("Sunday, 06-Nov-94 08:49:37 GMT", now: now) == expected)
        #expect(HTTPDate.parse("Sun Nov  6 08:49:37 1994", now: now) == expected)
    }

    @Test func aDateAlreadyPastIsAZeroWait() {
        #expect(RetryAfter.delay("Mon, 28 Sep 2026 12:59:00 GMT", reference: reference) == .zero)
    }

    @Test func malformedValuesAreIgnored() {
        for value in ["", "-5", "1.5", "+3", "soon", "Mon, 28 Sep 2026 13:00:06 UTC", "Mon, 31 Sep 2026 13:00:06 GMT",
                      "Mon, 28 Sep 2026 24:00:00 GMT", "Mon, 28 Sep 26 13:00:06 GMT", "Mon, 28 Sepx 2026 13:00:06 GMT"] {
            #expect(RetryAfter.delay(value, reference: reference) == nil, "\(value)")
        }
        let response = HTTPResponse(status: 429)
        #expect(RetryAfter.delay(in: response, now: reference) == nil)
    }

    @Test func rfc850TwoDigitYearsFollowRFC9110sFiftyYearRule() {
        let now = Date(timeIntervalSince1970: 1_790_600_400) // 2026
        let in2076 = HTTPDate.parse("Tuesday, 01-Sep-76 00:00:00 GMT", now: now)
        let in1977 = HTTPDate.parse("Wednesday, 01-Sep-77 00:00:00 GMT", now: now)
        #expect(in2076.map { Calendar.utcGregorian.component(.year, from: $0) } == 2076)
        #expect(in1977.map { Calendar.utcGregorian.component(.year, from: $0) } == 1977)
    }
}

private extension Calendar {
    static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }
}
