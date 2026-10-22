#if DEBUG
import Foundation
import Testing
import TallyDomain
@testable import TallyFeatures

/// FEAT-2 (school-check hardening of the subscription path): the local, non-account preference's
/// lifecycle through `AppModel` — recorded when `SchoolSearchView` resolves to "not enabled," read
/// by the sample-mode interstitial and reused by "Check My School"/"Ask My School," and cleared on
/// Sign Out & Erase and on a real signed-in account. `SampleInterstitialStateTests` covers the
/// interstitial's own two states as a pure value.
extension AccountLifecycleSuites {
    @Suite("FEAT-2: the not-enabled-school preference's lifecycle through AppModel", .serialized)
    @MainActor
    struct NotEnabledSchoolTests {
        private static let account = AccountKey("feat2-not-enabled-school")

        @Test("recordNotEnabledSchool: cached at once, persisted to the injected store, and overwrites rather than appending")
        func recordsAndPersists() async throws {
            let harness = try AccountHarness()
            let model = AppModel(accountEnvironment: harness.environment)
            model.bootstrap()
            #expect(model.notEnabledSchoolName == nil)

            model.recordNotEnabledSchool("Example Not-Enabled High")
            #expect(model.notEnabledSchoolName == "Example Not-Enabled High")
            await model.awaitNotEnabledSchoolPersistence()
            #expect(await harness.notEnabledSchoolPreferences.load() == "Example Not-Enabled High")

            // A second search overwrites, never appends.
            model.recordNotEnabledSchool("Another School")
            await model.awaitNotEnabledSchoolPersistence()
            #expect(model.notEnabledSchoolName == "Another School")
            #expect(await harness.notEnabledSchoolPreferences.load() == "Another School")
        }

        @Test("launch(): the stored name is loaded before any route past .welcome can read it")
        func loadsAtLaunch() async throws {
            let harness = try AccountHarness(notEnabledSchool: "Loaded At Launch High")
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            #expect(model.route == .welcome)
            #expect(model.notEnabledSchoolName == "Loaded At Launch High")
        }

        @Test("signOut (Sign Out & Erase): clears the cached value and the stored one, independently of completeSignIn's own clear")
        func signOutClears() async throws {
            let harness = try AccountHarness(notEnabledSchool: "Cleared On Sign Out High")
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            model.completeSignIn(Self.account) // .welcome -> .signedIn; already clears it once
            model.recordNotEnabledSchool("Reseeded Before Sign Out") // prove signOut() clears on its own
            await model.awaitNotEnabledSchoolPersistence()
            #expect(model.notEnabledSchoolName == "Reseeded Before Sign Out")

            model.signOut()
            await model.awaitNotEnabledSchoolPersistence()
            #expect(model.route == .welcome)
            #expect(model.notEnabledSchoolName == nil)
            #expect(await harness.notEnabledSchoolPreferences.load() == nil)
        }

        @Test("completeSignIn: a real signed-in account clears the stored name; a no-op from sample mode leaves it")
        func completeSignInClears() async throws {
            let harness = try AccountHarness(notEnabledSchool: "Cleared On Sign In High")
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            #expect(model.notEnabledSchoolName == "Cleared On Sign In High")

            model.enterSample()
            model.completeSignIn(Self.account) // guarded: a no-op from .sample
            #expect(model.route == .sample)
            #expect(model.notEnabledSchoolName == "Cleared On Sign In High")

            model.exitSample()
            model.completeSignIn(Self.account) // .welcome -> .signedIn: the real transition
            await model.awaitNotEnabledSchoolPersistence()
            #expect(model.route == .signedIn(Self.account))
            #expect(model.notEnabledSchoolName == nil)
            #expect(await harness.notEnabledSchoolPreferences.load() == nil)
        }

        @Test("checkMySchool: with a stored name, leaves the Welcome stack's next appearance at that school's page")
        func checkMySchoolSeedsTheWelcomeDestination() async throws {
            let harness = try AccountHarness(notEnabledSchool: "Check My School High")
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            model.enterSample()

            model.checkMySchool()
            #expect(model.route == .welcome)
            #expect(model.consumePendingWelcomeRoute() == .schoolNotEnabled(school: "Check My School High"))
            // Consumed: a second read (a later plain .welcome entry) finds nothing to replay.
            #expect(model.consumePendingWelcomeRoute() == nil)
        }

        @Test("exitSample (\"Exit Sample Data\"): leaves no destination, even with a name stored — only checkMySchool() seeds one")
        func exitSampleLeavesNoDestination() async throws {
            let harness = try AccountHarness(notEnabledSchool: "Plain Exit High")
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            model.enterSample()

            model.exitSample()
            #expect(model.route == .welcome)
            #expect(model.consumePendingWelcomeRoute() == nil)
        }

        @Test("checkMySchool: with no stored name, behaves exactly like exitSample (the App-Review path)")
        func checkMySchoolFallsBackWithNoStoredName() {
            let model = AppModel()
            model.bootstrap()
            model.enterSample()

            model.checkMySchool()
            #expect(model.route == .welcome)
            #expect(model.notEnabledSchoolName == nil)
            #expect(model.consumePendingWelcomeRoute() == nil)
        }

        @Test("checkMySchool is guarded: a no-op outside .sample")
        func checkMySchoolIsGuarded() {
            let model = AppModel()
            model.checkMySchool() // .launching
            #expect(model.route == .launching)
            model.bootstrap()
            model.checkMySchool() // .welcome
            #expect(model.route == .welcome)
        }
    }
}
#endif
