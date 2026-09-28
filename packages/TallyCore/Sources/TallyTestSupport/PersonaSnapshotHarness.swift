import Foundation
import TallyCanvasAPI
import TallyDomain

/// Fetches a real `CanvasSnapshot` for a fixture persona through the exact production pipeline
/// (`CanvasClient` -> `LiveCanvasGateway`) over `ReplayTransport`, matching the pattern
/// `TallySyncTests.RefreshCoordinatorTests` already uses in `TallyCore` (and the pinned app-core
/// review worktree's own `FlagshipSnapshotHarness`, generalised here to any persona so
/// `TallyDomainTests`/`TallyPerfTests` don't each reimplement it). Never fabricated data — every
/// field comes from `fixtures/canvas/personas/<persona>`.
public enum PersonaSnapshotHarness {
    public struct UnknownPersona: Error, CustomStringConvertible {
        public let persona: String
        public var description: String { "\(persona): no routes in fixtures/canvas/manifest.json" }
    }

    private struct AlwaysFail: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    public static func fetchSnapshot(persona: String, now: Date) async throws -> CanvasSnapshot {
        let routes = try CanvasManifest.personaRoutes(persona)
        guard let host = routes.first?.host else { throw UnknownPersona(persona: persona) }
        let transport = try ReplayTransport.persona(persona)
        let credential = CanvasCredential(host: host, userID: "harness-user", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                     refresher: AlwaysFail(), clock: TestClock(now))
        let client = CanvasClient(host: host, transport: transport, tokens: tokens)
        let gateway = LiveCanvasGateway(host: host, accountKey: AccountKey("\(persona)-harness"), client: client)
        return try await gateway.fetchSnapshot(previous: nil, now: now)
    }
}
