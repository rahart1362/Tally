import Foundation
import Synchronization
import TallyCanvasAPI
import TallyDomain
import TallyReplay

/// ASC-14 "Explore with Sample Data": errors this module raises itself, as opposed to whatever
/// `CanvasGateway`/`RefreshFailure` reports once the replay is running.
nonisolated enum SampleDataError: Error {
    case bundleResourceMissing(String)
    case manifestMalformed
}

/// The bundled subset of `fixtures/canvas` this target ships (Package.swift: `resources:
/// [.copy("CanvasFixtures")]`) — only the flagship persona plus the 404 fallback (implementation
/// brief: "only the personas the sample mode needs, e.g. flagship"). `CanvasFixtures` is a single
/// top-level directory directly under this target's `Sources/TallyFeatures/` root, deliberately:
/// SwiftPM's `.copy(_:)` places a resource "at the top level of the resulting bundle" (Apple's
/// package-resources documentation), so naming it one level deep here removes any ambiguity about
/// whether an intermediate path prefix would survive into the bundle. Resolves through
/// `Bundle.module`, never `Bundle.main`: `TallyFeatures` is a library target, and `Bundle.module`
/// is the one path that is correct both hosted inside `Tally.app` (TallyAppTests) and inside a
/// plain SwiftPM test run, whereas `Fixtures.root()` (`TallyTestSupport`, keyed off `#filePath`)
/// resolves a source-tree path that does not exist on a device or in the shipped app.
nonisolated enum SampleDataFixtureBundle {
    static let root = "CanvasFixtures"

    /// Trimmed `manifest.json` shape (see `CanvasFixtures/manifest.json`'s own `$comment` for
    /// provenance/regeneration): just the flagship persona's routes, anchor and time zone, decoded
    /// with the same `convertFromSnakeCase` strategy the test manifest parser uses, so
    /// `RouteFixture` (public, from `TallyReplay`) decodes unchanged.
    private nonisolated struct ManifestFile: Decodable {
        let anchor: Date
        let timeZone: String
        let host: String
        let routes: [RouteFixture]
    }

    /// CI (run 36336754587) proved via the actual `CpResource` build log line that `.copy(_:)`
    /// places the whole folder, by name, at the bundle's top level:
    /// `.../TallyAppleKit_TallyFeatures.bundle/CanvasFixtures`. The right way to ask Foundation
    /// for a *folder's own* URL is to treat the folder's name as the resource itself
    /// (`forResource: "CanvasFixtures", withExtension: nil`) — `url(forResource: nil,
    /// withExtension: nil, subdirectory:)`, tried first, asks a different question ("what's
    /// *inside* this subdirectory") and returned nil here. Falls back to manually joining
    /// `Bundle.module.resourceURL`, in case a future SwiftPM/Xcode version lays this out
    /// differently again — checked against the actual filesystem rather than assumed.
    static func resourceRoot() throws -> URL {
        if let url = Bundle.module.url(forResource: root, withExtension: nil) {
            return url
        }
        if let base = Bundle.module.resourceURL {
            let candidate = base.appendingPathComponent(root)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        throw SampleDataError.bundleResourceMissing(root)
    }

    nonisolated struct Manifest {
        let anchor: Date
        let timeZone: TimeZone
        let host: String
        let routes: [RouteFixture]
    }

    static func loadManifest(root: URL) throws -> Manifest {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        // `CanvasJSON.decoder()` (TallyCanvasAPI): the same custom date parser every Canvas DTO
        // uses, not Foundation's `.iso8601` (which the codebase avoids — see its doc comment).
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(ManifestFile.self, from: data)
        guard let timeZone = TimeZone(identifier: file.timeZone) else { throw SampleDataError.manifestMalformed }
        return Manifest(anchor: file.anchor, timeZone: timeZone, host: file.host, routes: file.routes)
    }
}

/// A `CanvasGateway` that never touches the network (ASC-14: "No network calls in sample mode").
/// Composes the exact same production pipeline a live account uses — `CanvasClient` ->
/// `LiveCanvasGateway`, DTOs and mappers included — over `TallyReplay.ReplayTransport` pointed at
/// the bundled flagship fixtures, then rebases every Canvas-content date forward so due dates
/// look current (`SnapshotDateRebaser`, per `fixtures/canvas/README.md`).
///
/// Built only through `make(dateProvider:)`, which does the bundle I/O off the main actor: a
/// synchronous actor `init` runs on its caller (SE-0327), which for `TallyFeatures` code is the
/// main actor, so the initialiser itself is pure (perf-app-runtime.md §4.1, §7 step 5).
public actor SampleDataCanvasGateway: CanvasGateway {
    private let live: LiveCanvasGateway
    private let anchor: Date
    private let timeZone: TimeZone

    /// Locates the bundled fixtures and decodes their manifest, off the main actor (`@concurrent`
    /// runs on the global executor whatever the caller's isolation).
    /// - Parameters:
    ///   - dateProvider: only for tests (`SystemDateProvider()` in production); lets a test pin
    ///     "now" instead of racing the real clock.
    ///   - logger: receives the gateway's privacy-safe events (plan 06 A8: CS-07's
    ///     `duplicateIDsDropped` counts); the app passes its `OSLogPlatformLogger`.
    @concurrent
    public static func make(
        dateProvider: any DateProviding = SystemDateProvider(), logger: any TallyLogger = NoOpLogger()
    ) async throws -> SampleDataCanvasGateway {
        try await make(dateProvider: dateProvider, logger: logger, threadProbe: nil)
    }

    /// Tests only: `threadProbe` receives `pthread_main_np() != 0` from inside the I/O, so a test
    /// can prove the manifest is never read on the main thread; `root` replays a copy of the
    /// fixtures instead of the bundled ones.
    @concurrent
    static func make(
        dateProvider: any DateProviding, logger: any TallyLogger = NoOpLogger(),
        threadProbe: (@Sendable (_ onMainThread: Bool) -> Void)?, root: URL? = nil
    ) async throws -> SampleDataCanvasGateway {
        threadProbe?(pthread_main_np() != 0)
        let root = try root ?? SampleDataFixtureBundle.resourceRoot()
        let manifest = try SampleDataFixtureBundle.loadManifest(root: root)
        return SampleDataCanvasGateway(manifest: manifest, root: root, dateProvider: dateProvider, logger: logger)
    }

    /// Pure construction over an already-loaded manifest.
    private init(
        manifest: SampleDataFixtureBundle.Manifest, root: URL, dateProvider: any DateProviding, logger: any TallyLogger
    ) {
        let transport = ReplayTransport(routes: manifest.routes, root: root)
        let accountKey = AccountKey("sample-flagship")
        // A credential that never expires: `ReplayTransport` never inspects the bearer token, and
        // there is no real Canvas account to refresh against, so a `TokenRefreshing` that always
        // fails is the honest choice (it must never be called).
        let credential = CanvasCredential(host: manifest.host, userID: "sample", accessToken: "sample-mode",
                                          refreshToken: "unused", accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: SampleCredentialStore(credential),
                                     refresher: NeverRefresh(), clock: dateProvider)
        let client = CanvasClient(host: manifest.host, transport: transport, tokens: tokens)
        live = LiveCanvasGateway(host: manifest.host, accountKey: accountKey, client: client, logger: logger)
        anchor = manifest.anchor
        timeZone = manifest.timeZone
    }

    public func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        // `previous` is intentionally not forwarded: sample mode has no optional-section carry-
        // forward story of its own (every flagship section is present in every replay), and
        // reusing a caller's real-account `previous` here would be a category error.
        let fetched = try await live.fetchSnapshot(previous: nil, now: now)
        return SnapshotDateRebaser.rebase(fetched, anchor: anchor, now: now, timeZone: timeZone)
    }
}

/// Never called (see `SampleDataCanvasGateway.init`'s comment); exists only because
/// `TokenCoordinator` requires a `TokenRefreshing`.
private nonisolated struct NeverRefresh: TokenRefreshing {
    func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
        throw AuthError.reauthRequired
    }
}

/// The sample session's credential, in memory only: sample mode never persists anything (ASC-14).
/// `TokenCoordinator` requires a `CredentialStore`; this replaced the test-support in-memory store
/// the gateway used before plan 06 A1.
private nonisolated final class SampleCredentialStore: CredentialStore {
    private let stored: Mutex<CanvasCredential?>

    init(_ credential: CanvasCredential) {
        stored = Mutex(credential)
    }

    func load() async -> CanvasCredential? { stored.withLock { $0 } }
    func save(_ credential: CanvasCredential) async throws { stored.withLock { $0 = credential } }
    func delete() async { stored.withLock { $0 = nil } }
}
