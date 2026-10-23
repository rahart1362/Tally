#if DEBUG
import Foundation
import Testing
import TallyDomain
@testable import TallyFeatures

/// FEAT-8 (Idea 7, "Open Canvas links in: App / Browser",
/// `pmo-audit/.build-audit/ideas1/report.md`): the preference's lifecycle through `AppModel` and
/// `HomeModel` -- Settings' picker caches at once and persists to the injected store, and it is
/// cleared on Sign Out & Erase, the same way `NotEnabledSchoolTests` covers FEAT-2's own local
/// preference.
extension AccountLifecycleSuites {
    @Suite("FEAT-8: the Canvas-link preference's lifecycle through AppModel/HomeModel", .serialized)
    @MainActor
    struct CanvasLinkPreferenceLifecycleTests {
        private static let account = AccountKey("feat8-canvas-link-preference")

        @Test("setCanvasLinkPreference: cached at once and persisted to the injected store")
        func setsAndPersists() async throws {
            let harness = try AccountHarness()
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            model.completeSignIn(Self.account)
            let home = try #require(model.home)
            #expect(home.canvasLinkPreference == .app, "today's default")

            home.setCanvasLinkPreference(.browser)
            #expect(home.canvasLinkPreference == .browser)
            await home.awaitCanvasLinkPreferencePersistence()
            #expect(await harness.canvasLinkPreferences.load() == .browser)
        }

        @Test("signOut (Sign Out & Erase): clears the stored preference")
        func signOutClears() async throws {
            let harness = try AccountHarness(canvasLinkPreference: .browser)
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            model.completeSignIn(Self.account)
            #expect(await harness.canvasLinkPreferences.load() == .browser)

            model.signOut()
            await model.awaitCanvasLinkPreferencePersistence()
            #expect(model.route == .welcome)
            #expect(await harness.canvasLinkPreferences.load() == nil)
        }

        @Test("a fresh HomeModel loads the stored preference once prepare() runs")
        func loadsAtPrepare() async throws {
            let harness = try AccountHarness(canvasLinkPreference: .browser)
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            model.completeSignIn(Self.account)
            let home = try #require(model.home)
            await home.prepare()
            #expect(home.canvasLinkPreference == .browser)
        }
    }
}
#endif
