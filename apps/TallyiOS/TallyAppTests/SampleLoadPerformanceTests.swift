import XCTest
@testable import TallyFeatures

/// perf-app-runtime.md §5.2: "Sample entry → full projection (flagship) ≤ 300 ms on device; CI gate
/// ≤ 150 ms". An `XCTestCase` because Swift Testing has no performance metrics. `make ios-perf`
/// runs it in Release (5 iterations) and `scripts/ci/check_perf_budgets.py` compares the median
/// `XCTClockMetric` with `perf/budgets.json`; CPU and memory are reported, not gated.
///
/// Each iteration starts at the tap (`AppModel.enterSample()`) and stops once the Home models hold
/// the full sample dashboard.
@MainActor
final class SampleLoadPerformanceTests: XCTestCase {
    func testSampleEntryToFullProjection() throws {
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let app = AppModel()
            app.bootstrap()
            let loaded = expectation(description: "the sample dashboard is ready")
            startMeasuring()
            app.enterSample()
            Task { @MainActor in
                await app.sampleDidAppear()
                // The update lands on the main actor right after the refresh returns; yield until
                // it has, with a deadline so a failed load cannot spin forever.
                let deadline = ContinuousClock.now + .seconds(5)
                while !Self.isFullyLoaded(app), ContinuousClock.now < deadline { await Task.yield() }
                self.stopMeasuring()
                loaded.fulfill()
            }
            wait(for: [loaded], timeout: 10)
            app.exitSample()
        }
    }

    private static func isFullyLoaded(_ app: AppModel) -> Bool {
        app.sample?.snapshot?.courses.count == 5
    }
}
