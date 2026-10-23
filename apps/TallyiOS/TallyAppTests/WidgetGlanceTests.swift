import MachO
import SwiftUI
import TallyDomain
import TallyPlatform
import TallyStore
import TallyTestSupport
import WidgetKit
import XCTest
@testable import TallyGlance

/// Plan 06 step 11's memory gate (M2-C2 brief W-1; perf-app-runtime.md §2.2 item 6: the widget's
/// design budget is a 15 MB peak, half the ~30 MB limit seen in field crash reports). An
/// `XCTestCase` because Swift Testing has no performance metrics.
///
/// Each iteration does what the widget process does for one timeline: read the glance through the
/// widget's own reader (real Keychain items, the widget-audience key only), plan the timeline,
/// build WidgetKit's `Timeline`, and render both widgets for its first entry. The glance is the
/// largest the builder writes: every due slot taken, twelve courses, grades on. CI's ios-build
/// reads the xcresult's metrics and fails when the median "Memory Physical" delta passes 5 MB
/// (perf/widget-budgets.json, scripts/ci/check_perf_budgets.py). The test host's absolute peak is
/// reported, not budgeted: it is the whole app process, not the widget.
///
/// Skipped under a sanitizer, like `SampleLoadPerformanceTests` (app-core report D6): the ASan and
/// TSan allocators and shadow memory make a memory measurement meaningless, and the gate reads the
/// main run. Under TSan this `measure` also aborted once ("ThreadSanitizer: BUS … in
/// objc_release_x8" on a background thread, run 36453374066, 0 TSan reports), cause not traced.
/// The same widget work runs under both sanitizers without `measure` in
/// `WidgetGlanceRenderTests.oneTimelineEndToEnd`.
@MainActor
final class WidgetGlanceTests: XCTestCase {
    /// A small widget on a 6.1-inch iPhone, in points, rendered at 3x like a device.
    private static let widgetSize = CGSize(width: 170, height: 170)
    private static let renderScale: CGFloat = 3

    /// PERF-FIX-2 item 1 (perf1/report.md §4 opportunity 3): `GlanceReadCache` shares one
    /// Keychain-backed glance read across every widget kind one process invocation serves,
    /// instead of each kind opening the Keychain itself. Simulates `TallyWidgetsBundle`'s 5
    /// `AppIntentConfiguration` kinds (`TallyWidgets.swift`) asking for the same scope: two race
    /// concurrently (WidgetKit can ask for more than one kind's timeline at once), the rest ask
    /// only once those two have settled, like a staggered refresh. The real read -- the app
    /// commits a glance, the widget's own `GlanceReader` opens the real Keychain item through
    /// `WidgetVaultKeyReader` -- must happen exactly once (`GlanceReadCache.realReadCount`, the
    /// same call-count-probe pattern `HomeProjector.projectionCount` uses to prove "recomputes
    /// exactly once" elsewhere), and every kind must get back the one correct, loaded glance.
    func testSharedReadCacheAnswersEveryWidgetKindWithOneKeychainRead() async throws {
        let bundleID = "dev.tally-app.tally.tests.widget-shared-read.\(UUID().uuidString)"
        let appStore = KeychainVaultKeyStore(bundleID: bundleID)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-shared-read-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? appStore.deleteEverything()
        }
        let account = AccountKey.derive(host: "canvas.example.edu", userID: "shared-read")
        let snapshot = CanvasSnapshotFixture.make(accountKey: account, courseCount: 3, dueItemCount: 5)
        let owner = SnapshotStore(root: root, accountKey: account,
                                  sealer: VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: appStore),
                                                      mayCreateKeys: true))
        let committed = try await owner.commit(snapshot, includeGrades: true, entitledUntil: GlanceStoreFixture.entitledUntil)

        let reader = GlanceReader(storeRoot: root, keyStore: WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: nil))
        let cache = GlanceReadCache() // a fresh instance: never GlanceReadCache.shared in a test
        let widgetKindCount = 5 // TallyWidgetsBundle's 5 AppIntentConfiguration widgets (TallyWidgets.swift)

        async let firstKind = cache.read(.signedInStudent) { _ in await reader.read() }
        async let secondKind = cache.read(.signedInStudent) { _ in await reader.read() }
        var results = await [firstKind, secondKind]
        while results.count < widgetKindCount {
            results.append(await cache.read(.signedInStudent) { _ in await reader.read() })
        }

        XCTAssertEqual(results.count, widgetKindCount)
        for result in results {
            XCTAssertEqual(result, .loaded(committed), "every widget kind must see the one shared read's result")
        }
        let realReadCount = await cache.realReadCount
        XCTAssertEqual(realReadCount, 1, "\(widgetKindCount) widget kinds must share one Keychain-backed read, not one each")
    }

    /// PMO review (2026-10-21): the shared read must never outlive its window. A widget extension
    /// process can stay alive across timeline reloads, and a cached glance served after the app's
    /// next refresh, or after Sign Out & Erase, would show stale data, or grades on a signed-out
    /// Home Screen. Past `maxAge`, the next caller gets a fresh read with the new result.
    func testSharedReadCacheRereadsAfterItsWindow() async {
        let cache = GlanceReadCache(maxAge: .zero)
        let first = await cache.read(.signedInStudent) { _ in .noGlance }
        let second = await cache.read(.signedInStudent) { _ in .noAccount } // e.g. after sign-out
        XCTAssertEqual(first, .noGlance)
        XCTAssertEqual(second, .noAccount, "a read past the window must not be answered from the cache")
        let realReadCount = await cache.realReadCount
        XCTAssertEqual(realReadCount, 2)
    }

    /// SEC2-10: a cached entry is reused only within `maxAge` AND when a freshly captured
    /// signature still matches the one the cached read started with -- here, driven by the real
    /// `GlanceCacheSignature.capture(storeRoot:)` over a real temp directory, so this proves the
    /// cache actually calls it on every `read`, not just that the plumbing compiles.
    func testSharedReadCacheRereadsWhenTheSignatureChangesEvenInsideTheWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-signature-cache-\(UUID().uuidString)",
                                                                                  isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let accountDirectory = root.appendingPathComponent("accounts/account-a", isDirectory: true)
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: accountDirectory.appendingPathComponent("glance.v1.sealed"))

        let cache = GlanceReadCache() // the real, generous default window
        let first = await cache.read(.signedInStudent, signature: { GlanceCacheSignature.capture(storeRoot: root) }) { _ in .noGlance }
        XCTAssertEqual(first, .noGlance)

        // Still well inside maxAge, but the glance file is gone now (e.g. a purge finished
        // between the two widget-kind reads this simulates).
        try FileManager.default.removeItem(at: accountDirectory.appendingPathComponent("glance.v1.sealed"))
        let second = await cache.read(.signedInStudent, signature: { GlanceCacheSignature.capture(storeRoot: root) }) { _ in .noAccount }
        XCTAssertEqual(second, .noAccount, "a changed signature must bypass the cache even inside maxAge")
        let realReadCount = await cache.realReadCount
        XCTAssertEqual(realReadCount, 2, "the signature change must have triggered a real second read")
    }

    /// SEC2-10, with the real signature function: once the glance file disappears (a purge) or
    /// the account directory listing changes (sign-out, a fresh sign-in), the next read must not
    /// be answered from the cache, even though it is still within `maxAge`. No Keychain item is
    /// touched by the signature check itself -- only `FileManager`.
    func testGlanceCacheSignatureCapturesTheGlanceFileAndTheAccountDirectoryListing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-signature-\(UUID().uuidString)",
                                                                                  isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let accountsDirectory = root.appendingPathComponent("accounts", isDirectory: true)
        let accountDirectory = accountsDirectory.appendingPathComponent("account-a", isDirectory: true)
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        let glanceFile = accountDirectory.appendingPathComponent("glance.v1.sealed")
        try Data([1, 2, 3]).write(to: glanceFile)

        let withGlance = GlanceCacheSignature.capture(storeRoot: root)
        XCTAssertEqual(withGlance, GlanceCacheSignature.capture(storeRoot: root), "an unchanged listing must signature identically")

        try FileManager.default.removeItem(at: glanceFile)
        let glanceGone = GlanceCacheSignature.capture(storeRoot: root)
        XCTAssertNotEqual(withGlance, glanceGone, "the glance file disappearing must change the signature")

        let secondAccount = accountsDirectory.appendingPathComponent("account-b", isDirectory: true)
        try FileManager.default.createDirectory(at: secondAccount, withIntermediateDirectories: true)
        let newAccountAppeared = GlanceCacheSignature.capture(storeRoot: root)
        XCTAssertNotEqual(glanceGone, newAccountAppeared, "a changed account directory listing must change the signature")

        try FileManager.default.removeItem(at: accountsDirectory)
        XCTAssertEqual(GlanceCacheSignature.capture(storeRoot: root), GlanceCacheSignature.capture(storeRoot: nil),
                       "no accounts directory at all must signature the same as no store root")
    }

    func testGlanceTimelineMemory() throws {
        try XCTSkipIf(Self.sanitizerRuntimeIsLoaded, "memory metrics are meaningless under a sanitizer's allocator")
        let bundleID = "dev.tally-app.tally.tests.widget-memory.\(UUID().uuidString)"
        let appStore = KeychainVaultKeyStore(bundleID: bundleID)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-memory-\(UUID().uuidString)",
                                                                                 isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? appStore.deleteEverything()
        }
        let account = AccountKey.derive(host: "canvas.example.edu", userID: "memory")
        let snapshot = CanvasSnapshotFixture.make(accountKey: account, courseCount: 12, dueItemCount: 40)
        let committed = expectation(description: "the app side commits the glance")
        Task { @MainActor in
            do {
                let owner = SnapshotStore(root: root, accountKey: account,
                                          sealer: VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: appStore),
                                                              mayCreateKeys: true))
                // M3-B2: entitled, so the timeline renders the content rather than the locked message.
                try await owner.commit(snapshot, includeGrades: true, entitledUntil: GlanceStoreFixture.entitledUntil)
            } catch {
                XCTFail("the app-side commit failed: \(error)")
            }
            committed.fulfill()
        }
        wait(for: [committed], timeout: 30)

        let reader = GlanceReader(storeRoot: root, keyStore: WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: nil))
        let now = snapshot.fetchedAt.addingTimeInterval(60)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()], options: options) {
            let done = expectation(description: "one widget timeline")
            Task { @MainActor in
                let result = await reader.read()
                guard case .loaded(let glance) = result else {
                    XCTFail("the widget's reader did not load the glance: \(result)")
                    done.fulfill()
                    return
                }
                XCTAssertEqual(glance.dueSoon.count, TallyConfig.glanceDueItemLimit)
                let plan = GlanceTimelinePlanner.plan(for: result, now: now, calendar: .current)
                let timeline = Timeline(entries: plan.moments.map(GlanceEntry.init), policy: .after(plan.reloadAfter))
                if let first = timeline.entries.first {
                    Self.render(NextUpWidgetView(entry: first))
                    Self.render(StandingWidgetView(entry: first))
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 30)
        }
    }

    /// PERF-FIX-1 item 3 (perf1/report.md S4 opportunity 5): `testGlanceTimelineMemory`'s own
    /// median read **0.0000 kB** in run 39178437255's required `ios-build` job log, the same
    /// pattern unrelated metrics (`SampleLoadPerformanceTests`' CPU Cycles/Instructions Retired)
    /// showed in that run -- circumstantial evidence that some `XCTMeasureMetric` types are not
    /// populating on this CI image, rather than that the widget's own workload is unusually
    /// efficient. This is the mutation check the report itself proposes: a *permanent* sanity
    /// test, not a one-off, because the question it answers ("can `XCTMemoryMetric` register
    /// anything at all, here, right now") can change again with any future Xcode/CI image.
    ///
    /// Each iteration appends a fresh 2 MB buffer that is never freed for the rest of the test
    /// (`held` only grows), so every iteration's own before/after bracket contains a real,
    /// uncollectable allocation far larger than the budget's documented 16.384 kB page
    /// granularity (`perf/widget-budgets.json`). `check_perf_budgets.py` has no budget entry for
    /// this test, so it reports the median as an unbudgeted `PERF-REPORT` line (never gates):
    /// a non-zero report means the metric type works on this image, so `testGlanceTimelineMemory`'s
    /// own 0.0000 kB is a true (if suspiciously exact) near-zero footprint for that tiny workload,
    /// not an instrumentation gap; a 0.0000 kB report here as well means the opposite -- the
    /// metric is not measuring on this image, and `testGlanceTimelineMemory`'s PASS has to be
    /// read as "no result," not "within budget," until the image or toolchain changes.
    func testMemoryMetricCanaryRegistersADeliberateAllocation() throws {
        try XCTSkipIf(Self.sanitizerRuntimeIsLoaded, "memory metrics are meaningless under a sanitizer's allocator")
        var held: [[UInt8]] = []
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTMemoryMetric()], options: options) {
            held.append([UInt8](repeating: 0xAB, count: Self.canaryAllocationBytes))
        }
        XCTAssertGreaterThanOrEqual(held.count, options.iterationCount, "one allocation must survive per iteration")
    }

    /// Comfortably larger than the 16.384 kB page granularity `perf/widget-budgets.json` documents,
    /// so a working metric cannot mistake this for noise.
    private static let canaryAllocationBytes = 2 * 1_048_576

    /// An ASan or TSan runtime is loaded in this process (the instrumented host loads it).
    private static var sanitizerRuntimeIsLoaded: Bool {
        (0..<_dyld_image_count()).contains { index in
            guard let name = _dyld_get_image_name(index) else { return false }
            let path = String(cString: name)
            return path.contains("libclang_rt.asan") || path.contains("libclang_rt.tsan")
        }
    }

    private static func render(_ view: some View) {
        let renderer = ImageRenderer(content: view.frame(width: widgetSize.width, height: widgetSize.height))
        renderer.scale = renderScale
        _ = renderer.cgImage
    }
}
