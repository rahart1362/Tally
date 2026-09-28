import Foundation
import Testing
@testable import TallyFeatures

/// perf-app-runtime.md §2.2 rule 4 and §7 steps 5–6: sessions are exclusive and nothing from one
/// outlives it. After `exitSample()` no reference to the Home model, its projector or the sample
/// session survives, so the decoded snapshot is gone too.
@Suite("Lifecycle: nothing from a sample session outlives exitSample()", .serialized)
@MainActor
struct LifecycleLeakTests {
    /// Polls `condition` on the main actor for up to `timeout` (teardown finishes on other actors;
    /// generous for the sanitizer runs, as `HomeTestSupport.waitUntil` explains).
    private func eventually(timeout: Duration = .seconds(30), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test("the Home model, its projector and its sample session are released after exitSample(), twice over")
    func sampleSessionIsReleasedAfterExit() async throws {
        let app = AppModel()
        app.bootstrap()
        for _ in 0..<2 {
            app.enterSample()
            weak var model = app.home
            weak var projector = app.home?.projector
            weak var session = app.home?.source as? SampleSession
            #expect(model != nil && projector != nil && session != nil)

            await app.home?.start()
            #expect(try await eventually { model?.dashboard.hero.courseCount == 5 })

            app.exitSample()
            #expect(app.route == .welcome)
            #expect(app.home == nil)
            #expect(try await eventually { model == nil && projector == nil && session == nil },
                    "a Home model, projector or sample session outlived exitSample()")
        }
    }
}
