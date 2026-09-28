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
                try await owner.commit(snapshot, includeGrades: true)
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
