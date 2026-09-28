import Foundation
import Testing
import TallyPlatform
@testable import Tally

/// Hosted unit tests for the composition root (implementation brief: "Swift
/// Testing, @Suite"). These run on the iOS 26 simulator (WP-E02); TallyCore's
/// own suites already cover the Linux-testable logic.
///
/// `@MainActor`: `AppEnvironment.live()` is main-actor-isolated (it builds the
/// main-actor `WebAuthPresenter` and the `@MainActor @Observable` `AppModel`).
@Suite("Composition root")
@MainActor
struct AppEnvironmentTests {
    @Test("live() builds synchronously, with no thrown error")
    func liveConstruction() {
        let environment = AppEnvironment.live()
        environment.logger.log(.appLaunch)
    }

    @Test("the built app's bundle identifier matches Identity.xcconfig")
    func bundleIdentifierMatchesIdentity() {
        #expect(Bundle.main.bundleIdentifier == "dev.tally-app.tally")
    }

    @Test("the background-refresh task identifier derives from the bundle identifier")
    func backgroundRefreshTaskIdentifier() {
        let expected = (Bundle.main.bundleIdentifier ?? "") + ".refresh"
        #expect(BackgroundRefresh.taskIdentifier == expected)
        #expect(BackgroundRefresh.taskIdentifier == "dev.tally-app.tally.refresh")
    }
}
