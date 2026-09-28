import Foundation
import Testing
@testable import TallyFeatures

/// perf-app-runtime.md §2.2 rule 4 and §7 steps 5–6: sessions are exclusive and nothing from one
/// outlives it. After `exitSample()` no reference to the sample session or its model survives, so
/// its decoded snapshot is gone too.
@Suite("Lifecycle: nothing from a sample session outlives exitSample()", .serialized)
@MainActor
struct LifecycleLeakTests {
    /// Polls `condition` on the main actor for up to `timeout` (teardown finishes on other actors).
    private func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test("the sample model and session are released after exitSample(), twice over")
    func sampleSessionIsReleasedAfterExit() async throws {
        let app = AppModel()
        app.bootstrap()
        for _ in 0..<2 {
            app.enterSample()
            weak var model = app.sample
            weak var session = app.sample?.session
            #expect(model != nil)
            #expect(session != nil)

            await app.sampleDidAppear()
            #expect(try await eventually { model?.snapshot?.courses.count == 5 })

            app.exitSample()
            #expect(app.route == .welcome)
            #expect(app.sample == nil)
            #expect(try await eventually { model == nil && session == nil },
                    "a sample model or session outlived exitSample()")
        }
    }
}
