import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyTestSupport

/// Item 3 (LIVE-FIX-2/LIVE-3): the brief's own live check -- "show 304s on a second refresh,
/// with the byte savings" -- gated on the SAME two required variables as every other live
/// suite, plus the optional `TALLY_LIVE_ETAG_CACHE_FILE` (unset, this whole suite is skipped,
/// never failed, exactly like the observer path without its own token).
@Suite("LIVE-FIX-2/LIVE-3 item 3: a 304 reuses the cached body, with real byte savings",
      .enabled(if: LiveCanvasEnvironment.isLive && LiveCanvasEnvironment.config?.etagCacheFile != nil))
struct LiveETagCacheTests {
    @Test("Two back-to-back refreshes over the SAME etag-backed client: the second is mostly 304s")
    func secondRefreshIsMostly304s() async throws {
        let config = LiveCanvasEnvironment.config! // swiftlint:disable:this force_unwrapping -- gated by .enabled(if:)
        // Its own session (not `LiveStudentFixture.shared`): that fixture is memoized without an
        // etag store, shared by the other suites, and fetched at most once per process -- this
        // suite needs its own etag-enabled client fetched TWICE in the same process.
        let session = LiveCanvasHarness.makeSession(config, accessToken: config.studentToken, userID: "live-student-etag")
        let accountKey = AccountKey("live-student-etag")
        let gateway = LiveCanvasGateway(host: config.host, accountKey: accountKey, client: session.client, logger: session.logger)

        _ = try await gateway.fetchSnapshot(previous: nil, now: Date())
        let firstRunBytes = await session.meter.byteCount
        let firstRunRequests = await session.meter.requestCount

        // The second run reuses the SAME cache file (and, within this one process, the same
        // `CanvasClient`/etag store instance) -- every request this time carries `If-None-Match`
        // for whatever the first run just cached.
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: Date())
        let totalBytes = await session.meter.byteCount
        let totalRequests = await session.meter.requestCount
        let secondRunBytes = totalBytes - firstRunBytes
        let secondRunRequests = totalRequests - firstRunRequests

        #expect(!snapshot.courses.isEmpty, "the second refresh must still produce a real, usable snapshot from the cached bodies")
        #expect(secondRunRequests == firstRunRequests, "the second run makes exactly the same requests, just conditional ones")
        let savedPercent = firstRunBytes > 0 ? Int((1 - Double(secondRunBytes) / Double(firstRunBytes)) * 100) : 0
        // Brief: "show 304s on a second refresh, with the byte savings" -- exact format.
        print("LIVE-ETAG | firstRunBytes=\(firstRunBytes) secondRunBytes=\(secondRunBytes) savedPercent=\(savedPercent) requests=\(secondRunRequests)")
        #expect(secondRunBytes < firstRunBytes, "a second, unchanged refresh must transfer far fewer bytes than the first")
    }
}
