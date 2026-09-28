import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyTestSupport

/// Shared by several suites: fetches a real `CanvasSnapshot` for the flagship persona through the
/// exact production pipeline (`CanvasClient` -> `LiveCanvasGateway`) over
/// `TallyTestSupport.ReplayTransport`, matching the pattern `TallySyncTests.RefreshCoordinatorTests`
/// already uses in `TallyCore`. Never fabricated data — every field comes from
/// `fixtures/canvas/personas/flagship`.
enum FlagshipSnapshotHarness {
    private struct AlwaysFail: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    static func fetchSnapshot(now: Date = Date(timeIntervalSince1970: 1_790_000_000)) async throws -> CanvasSnapshot {
        let host = "canvas.northfield.example"
        let transport = try ReplayTransport.persona("flagship")
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                     refresher: AlwaysFail(), clock: FixedClock(now: now))
        let client = CanvasClient(host: host, transport: transport, tokens: tokens)
        let gateway = LiveCanvasGateway(host: host, accountKey: AccountKey("flagship-test"), client: client)
        return try await gateway.fetchSnapshot(previous: nil, now: now)
    }
}

struct FixedClock: DateProviding {
    let fixedNow: Date
    init(now: Date) { fixedNow = now }
    func now() -> Date { fixedNow }
}
