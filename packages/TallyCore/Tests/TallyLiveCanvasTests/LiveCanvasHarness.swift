import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyTestSupport

/// Builds the real `CanvasClient` + `MeteringTransport` pair every live test shares, and a few
/// small pieces of glue the brief's assertions need that no product code currently assembles
/// (building `ReminderCandidate`s from a snapshot is normally `TallyFeatures`' job, iOS-only —
/// TallyCore itself exposes no snapshot -> candidates step; see live1-report.md's open items).
enum LiveCanvasHarness {
    /// `e2e_oauth.py` writes only the bare access token (RUNBOOK.md: "write the access token
    /// only to secrets/<token-secret>"), never a refresh token, so this harness has nothing to
    /// refresh with. That's fine for a single short-lived run against a token the brief's own
    /// rules say to mint fresh right before running (`e2e_oauth.py --persona ...`): a public-
    /// client Canvas access token lives 120 minutes (RUNBOOK.md finding 2). If a live run ever
    /// needed a refresh mid-flight, this throws plainly rather than silently fabricate one.
    private struct NoRefreshTokenAvailable: Error, Sendable {}
    private struct Unrefreshable: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw NoRefreshTokenAvailable() }
    }

    /// One persona's client, its metering transport (for the LIVE-PERF line), and its logger
    /// (so a test can assert nothing unexpected was logged, e.g. zero duplicate-ID drops).
    struct Session {
        let client: CanvasClient
        let meter: MeteringTransport
        let logger: RecordingLogger
    }

    static func makeSession(_ config: LiveCanvasEnvironment.Config, accessToken: String, userID: String) -> Session {
        let transport = LiveURLSessionTransport(forceScheme: config.scheme, forcePort: config.port)
        let meter = MeteringTransport(wrapping: transport)
        // Fresh for the duration of one short-lived run (NoRefreshTokenAvailable's doc comment).
        let credential = CanvasCredential(host: config.host, userID: userID, accessToken: accessToken,
                                          refreshToken: "", accessTokenExpiresAt: Date().addingTimeInterval(60 * 60))
        let store = InMemoryCredentialStore(credential)
        let coordinator = TokenCoordinator(initial: credential, store: store, refresher: Unrefreshable(), clock: SystemDateProvider())
        let client = CanvasClient(host: config.host, transport: meter, tokens: coordinator)
        return Session(client: client, meter: meter, logger: RecordingLogger())
    }

    /// Every assignment in the snapshot, as a `ReminderCandidate` (`isExam: false`, `priority:
    /// 0`, `markedDone: false`) -- TallyCore has no "exam" signal of its own (that classification
    /// lives in app-layer heuristics, out of scope here) and the planner only reads `priority`
    /// for the Time-Sensitive threshold on the final due reminder, not for sanity. This is
    /// exactly what the brief's assertion 3 needs: real candidates, from the real live snapshot,
    /// run through the real, unmodified `ReminderPlanner`.
    static func candidates(from snapshot: CanvasSnapshot) -> [ReminderCandidate] {
        snapshot.groups.values.flatMap { $0 }.flatMap(\.assignments).map { ReminderCandidate(assignment: $0) }
    }
}
