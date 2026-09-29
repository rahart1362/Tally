#if DEBUG
import Foundation
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like the lifecycle support it uses (`ScriptedAuthenticator`, `AccountHarness`, the
/// DEBUG `CanvasSnapshot.restamped(accountKey:generation:)`).
///
/// UX-WP-20 (S-7) after M2: Settings' App Lock toggle over M2-C1's `AppLockModel` API, never the
/// system Face ID sheet (a scripted authenticator answers). `setEnabled(_:)` returns `false` when
/// the device has no passcode or the authentication fails, and the toggle then snaps back.
@Suite("M3-A: Settings' App Lock toggle (AppLockSettingsModel over a scripted authenticator)")
@MainActor
struct AppLockSettingsTests {
    private struct Setup {
        let settings: AppLockSettingsModel
        let lock: AppLockModel
        let authenticator: ScriptedAuthenticator
        let preferences: InMemoryAppLockPreferenceStore
    }

    /// A configured, unlocked lock (Settings is reachable only then) and its Settings rows, loaded.
    private func setup(_ results: [AppLockPolicy.AuthResult] = [.success(via: .biometric)],
                       availability: AppLockAvailability = .available(.faceID),
                       enabled: Bool = false) async -> Setup {
        let authenticator = ScriptedAuthenticator(enabled ? [.success(via: .biometric)] + results : results,
                                                  availability: availability)
        let stored = enabled ? AppLockPreference(isEnabled: true) : nil
        let preferences = InMemoryAppLockPreferenceStore(stored)
        let lock = AppLockModel(authenticator: authenticator, preferences: preferences, clock: TestClock())
        lock.configure(with: stored ?? .disabled)
        if enabled { await lock.unlock() }
        let settings = AppLockSettingsModel(lock: lock)
        await settings.load()
        return Setup(settings: settings, lock: lock, authenticator: authenticator, preferences: preferences)
    }

    @Test("with a passcode: turning it on moves the switch at once, needs no authentication, and is saved")
    func turningOnIsSaved() async {
        let setup = await setup()
        #expect(setup.settings.hasLoaded && !setup.settings.isOn && setup.settings.isToggleEnabled)
        #expect(setup.settings.footer.contains("Face ID or your passcode"))

        setup.settings.requestEnabled(true)
        #expect(setup.settings.isOn, "the switch did not move at once")
        #expect(setup.settings.isChanging && !setup.settings.isToggleEnabled, "a second tap could start a second change")
        await setup.settings.awaitChange()
        #expect(setup.settings.isOn && setup.lock.isEnabled && !setup.settings.isChanging)
        #expect(await setup.preferences.load() == .found(AppLockPreference(isEnabled: true)))
        #expect(setup.authenticator.attempts == 0, "turning the lock on asked for an authentication")
    }

    @Test("no device passcode: the toggle is unavailable, says why, and snaps back off if asked anyway")
    func noPasscodeSnapsBack() async {
        let setup = await setup(availability: .passcodeNotSet)
        #expect(!setup.settings.isToggleEnabled, "security.md §3.3: passcodeNotSet means the toggle is unavailable")
        #expect(setup.settings.footer.contains("set a passcode"))

        await setup.settings.setEnabled(true)
        #expect(!setup.settings.isOn, "the switch stayed on with no passcode")
        #expect(!setup.lock.isEnabled)
        #expect(await setup.preferences.load() == .notFound, "a setting was saved with no passcode")
    }

    @Test("turning it off needs an authentication; every non-success snaps the switch back on", arguments: [
        AppLockPolicy.AuthResult.failedOrCancelled, .biometryLockout, .biometryUnavailable, .passcodeNotSet,
    ])
    func failedAuthenticationSnapsBack(_ result: AppLockPolicy.AuthResult) async {
        let setup = await setup([result], enabled: true)
        #expect(setup.settings.isOn && !setup.lock.isLocked)

        setup.settings.requestEnabled(false)
        #expect(!setup.settings.isOn, "the switch did not move at once")
        await setup.settings.awaitChange()
        #expect(setup.settings.isOn, "\(result): the switch stayed off while the lock is still on")
        #expect(setup.lock.isEnabled)
        #expect(await setup.preferences.load() == .found(AppLockPreference(isEnabled: true)))
        #expect(setup.authenticator.attempts == 2, "the unlock, then one attempt to turn it off")
    }

    @Test("turning it off with a successful authentication is saved")
    func turningOffIsSaved() async {
        let setup = await setup([.success(via: .passcode)], enabled: true)
        await setup.settings.setEnabled(false)
        #expect(!setup.settings.isOn && !setup.lock.isEnabled)
        #expect(await setup.preferences.load() == .found(AppLockPreference(isEnabled: false)))
    }

    @Test("the grace period is saved with the setting")
    func gracePeriodIsSaved() async {
        let setup = await setup(enabled: true)
        #expect(setup.settings.gracePeriod == .default)
        await setup.settings.setGracePeriod(.fiveMinutes)
        #expect(setup.settings.gracePeriod == .fiveMinutes && setup.lock.gracePeriod == .fiveMinutes)
        #expect(await setup.preferences.load() == .found(AppLockPreference(isEnabled: true, gracePeriod: .fiveMinutes)))
        #expect(AppLockSettingsModel.label(for: .fiveMinutes) == "After 5 minutes")
    }

    @Test("a device that cannot authenticate for another reason: turning on is unavailable, turning off may be tried")
    func otherwiseUnavailable() async {
        let off = await setup(availability: .unavailable)
        #expect(!off.settings.isToggleEnabled)
        let on = await setup([.failedOrCancelled], availability: .unavailable, enabled: true)
        #expect(on.settings.isToggleEnabled)
    }
}

/// M2-C2 OI5: "Show Grades in Widgets" is `UserState.showGradesInGlance`, off unless the student turns
/// it on (PMO R10), saved in the account's sealed user state beside the "What changed" thresholds,
/// and read by the account's coordinator when it is built, so its commits' glances follow it.
@Suite("M3-A: Show Grades in Widgets, and the coordinator's settings at launch", .serialized)
@MainActor
struct WidgetGradesSettingTests {
    @Test("off by default; the toggle is sealed on disk without losing a threshold saved just before it")
    func toggleIsSaved() async throws {
        let account = AccountKey("m3-widget-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let store = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        let settings = SettingsModel(userState: AccountUserStateAccess(store: store, runtime: AccountRuntime()))
        await settings.load()
        #expect(!settings.showGradesInWidgets, "grades in widgets must be opt-in (PMO R10)")

        settings.setEveryChange(true)
        settings.setShowGradesInWidgets(true)
        #expect(settings.showGradesInWidgets)
        await settings.awaitSaved()
        #expect(!settings.widgetSaveFailed && !settings.saveFailed)
        guard case .loaded(let saved) = await store.load() else {
            Issue.record("the UserState file was not written")
            return
        }
        #expect(saved.showGradesInGlance)
        #expect(saved.digestThresholds.global == .all, "the widget setting's save lost the threshold saved before it")

        let reopened = SettingsModel(userState: AccountUserStateAccess(store: store, runtime: AccountRuntime()))
        await reopened.load()
        #expect(reopened.showGradesInWidgets)
    }

    @Test("a UserState this build must not overwrite: the toggle reports that it was not saved")
    func unsavedToggleSaysSo() async throws {
        let settings = SettingsModel(userState: RefusingUserStateAccess())
        await settings.load()
        settings.setShowGradesInWidgets(true)
        await settings.awaitSaved()
        #expect(settings.widgetSaveFailed && !settings.saveFailed)
    }

    @Test("the account's coordinator starts from its stored settings: the opt-in reaches the glance, the thresholds the digest",
          .timeLimit(.minutes(2)))
    func coordinatorStartsFromStoredSettings() async throws {
        let previous = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship-previous", now: ScreenFixtures.anchor)
        let current = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ScreenFixtures.anchor)
        let math: CanvasID<Course> = "51842"

        /// The coordinator `AccountSessionFactory` builds over a store holding `previous`, and its
        /// first commit (of `current`).
        func firstCommit(stored: UserState?) async throws -> (includeGrades: Bool, digest: ChangeDigest?, glance: GlanceProjection?) {
            let harness = try AccountHarness(gateway: { account in
                ServingGateway(current.restamped(accountKey: account.accountKey, generation: 2))
            })
            let account = harness.account
            let snapshots = harness.environment.snapshotStore(for: account, root: harness.root)
            _ = try await snapshots.commit(previous.restamped(accountKey: account, generation: 1), includeGrades: false)
            if let stored {
                try await UserStateStore(root: harness.root, accountKey: account, sealer: harness.environment.sealer(for: account))
                    .save(stored)
            }
            let coordinator = await AccountSessionFactory.coordinator(for: harness.record, root: harness.root,
                                                                      environment: harness.environment)
            let includeGrades = await coordinator.includeGrades
            let events = await coordinator.events()
            _ = await coordinator.run(trigger: .manual)
            var digest: ChangeDigest?
            for await event in events {
                if case .committed(_, let committed) = event {
                    digest = committed
                    break
                }
            }
            var glance: GlanceProjection?
            if case .loaded(let written) = await snapshots.loadGlance() { glance = written }
            return (includeGrades, digest, glance)
        }

        let defaults = try await firstCommit(stored: nil)
        #expect(!defaults.includeGrades)
        let defaultGlance = try #require(defaults.glance)
        #expect(defaultGlance.overallGradeBand == nil && defaultGlance.courses.allSatisfy { $0.currentGrade == nil },
                "a grade in the glance without the opt-in (PMO R10)")
        #expect(defaults.digest?.courseScoreChanges.contains { $0.courseID == math } == false)

        let opted = try await firstCommit(stored: UserState(showGradesInGlance: true,
                                                            digestThresholds: DigestThresholds(perCourse: [math: .all])))
        #expect(opted.includeGrades, "the stored opt-in never reached the coordinator")
        let optedGlance = try #require(opted.glance)
        #expect(optedGlance.courses.contains { $0.currentGrade != nil }, "the opted-in glance carries no grade")
        #expect(opted.digest?.courseScoreChanges.contains { $0.courseID == math } == true,
                "the stored threshold never reached the coordinator's first digest")
    }

    @Test("the launch's prepare() (before start()) already projects in the stored course order")
    func prepareProjectsInTheStoredOrder() async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ScreenFixtures.anchor)
        let reversed = Array(snapshot.courses.map(\.id).reversed())
        let store = InMemoryLocalScreenStateStore()
        await store.save(LocalScreenState(courseOrder: reversed, revision: 1))
        let source = FakeHomeSource(HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: ScreenFixtures.anchor)))
        let model = HomeModel(source: source, projector: ScreenModelSupport.projector(), clock: TestClock(ScreenFixtures.anchor),
                              localStore: store)
        await model.prepare()
        #expect(model.phase == .loaded)
        #expect(model.courseCards.map(\.id) == reversed, "the launch's first projection ignored the student's order")
        await model.end()
    }
}

extension AccountLifecycleSuites {
    /// M2-C1 O8: the signed-in Home's `UserStateAccess` is the account's sealed `UserStateStore`, under
    /// the store root the launch or the sign-in resolved off the main actor.
    @Suite("M3-A: the signed-in Home's Settings use the account's sealed UserState", .serialized)
    @MainActor
    struct AccountUserStateWiringTests {
        private func userStateStore(_ harness: AccountHarness) -> UserStateStore {
            UserStateStore(root: harness.root, accountKey: harness.account, sealer: harness.environment.sealer(for: harness.account))
        }

        @Test("a signed-in launch: the resolution carries the store root, and the Home's Settings read and write the account's file")
        func launchHomeUsesTheAccountsUserState() async throws {
            let harness = try AccountHarness()
            try await harness.seedSignedInAccount()
            try await userStateStore(harness).save(UserState(showGradesInGlance: true))
            #expect(await LaunchBootstrapper(environment: harness.environment).resolve().storeRoot == harness.root)

            let model = AppModel(accountRuntime: AccountRuntime(resolve: { [environment = harness.environment] in
                await AccountSessionFactory.activeCoordinator(environment)
            }), accountEnvironment: harness.environment)
            await model.launch()
            let home = try #require(model.home)
            #expect(home.userState is AccountUserStateAccess, "the signed-in Home's Settings are in memory")
            let settings = SettingsModel(userState: home.userState)
            await settings.load()
            #expect(settings.showGradesInWidgets, "the Home's Settings did not read the account's UserState")
            settings.setShowGradesInWidgets(false)
            await settings.awaitSaved()
            #expect(await userStateStore(harness).load() == .loaded(UserState(showGradesInGlance: false)))

            await model.awaitLaunchWork()
            await home.end()
            await model.accountRuntime.end()
        }

        @Test("after the first sync's root switch, the Home's Settings write the account's file")
        func firstSyncHomeUsesTheAccountsUserState() async throws {
            let harness = try AccountHarness()
            let model = AppModel(accountEnvironment: harness.environment)
            model.bootstrap()
            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            let firstSync = try #require(model.firstSync)
            firstSync.start()
            #expect(try await HomeTestSupport.waitUntil { firstSync.isFinished || firstSync.failure != nil } && firstSync.isFinished)
            model.finishFirstSync()

            let home = try #require(model.home)
            #expect(home.userState is AccountUserStateAccess, "the signed-in Home's Settings are in memory")
            let settings = SettingsModel(userState: home.userState)
            await settings.load()
            settings.setShowGradesInWidgets(true)
            await settings.awaitSaved()
            #expect(await userStateStore(harness).load() == .loaded(UserState(showGradesInGlance: true)))

            await model.awaitLaunchWork()
            await home.end()
            await model.accountRuntime.end()
        }
    }
}

/// A user state this build must not overwrite (a newer build's file): every write is refused.
private actor RefusingUserStateAccess: UserStateAccess {
    func load() -> UserState { UserState() }

    @discardableResult
    func update(_ change: @Sendable (inout UserState) -> Void) throws -> UserState {
        throw AccountUserStateAccess.AccessError.notWritable(.keepAndReport)
    }
}
#endif
