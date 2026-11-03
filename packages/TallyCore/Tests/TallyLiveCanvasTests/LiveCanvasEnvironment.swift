import Foundation

/// LIVE-1 (docs/pmo/reviews/live1-report.md, canvas-e2e/PLAN-live-testing.md): every test in
/// this target is opt-in, gated on two environment variables so `swift test` and CI stay
/// unaffected:
///   - `TALLY_LIVE_CANVAS_URL`: the Canvas host to hit, e.g. `http://127.0.0.1:8790`.
///   - `TALLY_LIVE_TOKEN_FILE`: a path to a file holding one bearer access token (the student
///     persona), exactly as `~/canvas-e2e/tools/e2e_oauth.py --persona student` writes it
///     (RUNBOOK.md). Never read into a literal, never printed, never logged.
///
/// A third, optional variable gates the observer-path test alone:
///   - `TALLY_LIVE_OBSERVER_TOKEN_FILE`: same shape, for the observer persona
///     (`e2e_oauth.py --persona observer`). Its own test is skipped (not failed) without it.
///
/// Rule (brief + pmo-common-rules-v2.md §7): never print or commit a token. Every function
/// here either returns the raw string to a caller that attaches it as a bearer header, or
/// returns nothing; none of them ever appear in a `print`, `#expect` message, or log.
enum LiveCanvasEnvironment {
    struct Config {
        /// Bare hostname (`127.0.0.1`), no port and no scheme. **Finding F3**
        /// (live1-report.md): `CanvasClient.host` is passed straight into
        /// `URLComponents.host` with nothing else ever set on the authority
        /// (`CanvasClient.url(path:query:)`, `Sources/TallyCanvasAPI/Client/CanvasClient.swift:68-76`)
        /// -- there is no way to give `CanvasClient` a custom port at all, and the force-unwrap
        /// on that line (`components.url!`, disabled-lint comment: "scheme/host/path are always
        /// well-formed here") traps instead of failing cleanly the moment a caller's `host`
        /// string isn't a bare hostname (confirmed: passing `"127.0.0.1:8790"` as `host` crashed
        /// this harness with "Unexpectedly found nil while unwrapping an Optional value" at that
        /// line, not a thrown `RefreshFailure`). `CanvasClient.init(host:)` has no doc comment or
        /// precondition stating that contract. Production never hits this (every institution host
        /// comes from the verified directory/registry as a bare hostname on 443), so this harness
        /// keeps `host` bare too and restores both the port and the scheme itself, in
        /// `LiveURLSessionTransport`, right before the real socket call.
        let scheme: String
        let host: String
        let port: Int?
        let studentToken: String
        let observerToken: String?
        /// Item 3 (LIVE-FIX-2/LIVE-3): a file this harness may read and write a plain-JSON
        /// `[String: ETagCacheEntry]` cache to (`TALLY_LIVE_ETAG_CACHE_FILE`), so running this
        /// script twice in a row shows real 304s on the second run -- never sealed, never under
        /// `StoreLocation.privateRoot()` (this is test-only scratch, not the shipping app's own
        /// store; `SealedETagStore`'s own round-trip is covered by `TallyStoreTests` instead).
        /// `nil` (unset) disables it entirely, same as every other opt-in piece of this target.
        let etagCacheFile: String?
    }

    /// Read once per process; environment variables don't change mid-run.
    static let config: Config? = loadConfig()

    private static func loadConfig() -> Config? {
        let env = ProcessInfo.processInfo.environment
        guard let urlString = env["TALLY_LIVE_CANVAS_URL"], !urlString.isEmpty,
              let tokenPath = env["TALLY_LIVE_TOKEN_FILE"], !tokenPath.isEmpty,
              let url = URL(string: urlString), let host = url.host
        else { return nil }
        guard let studentToken = readToken(at: tokenPath) else { return nil }
        let observerToken = env["TALLY_LIVE_OBSERVER_TOKEN_FILE"].flatMap(readToken(at:))
        let etagCacheFile = env["TALLY_LIVE_ETAG_CACHE_FILE"].flatMap { $0.isEmpty ? nil : $0 }
        return Config(scheme: url.scheme ?? "https", host: host, port: url.port, studentToken: studentToken,
                     observerToken: observerToken, etagCacheFile: etagCacheFile)
    }

    private static func readToken(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `true` once both required variables resolve to a usable config -- the trait every
    /// `@Suite`/`@Test` in this target gates on (`.enabled(if:)`), so an unset environment
    /// skips cleanly instead of failing.
    static var isLive: Bool { config != nil }

    /// `true` when the observer token is also present, for the observer-only test.
    static var hasObserver: Bool { config?.observerToken != nil }
}
