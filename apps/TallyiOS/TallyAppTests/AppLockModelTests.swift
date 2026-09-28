#if DEBUG
import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallyFeatures

/// SEC-07 (security.md WP-SEC-07; ADR 0001; ux-ui.md §3.7.8) on the main actor: `AppLockModel` over
/// a scripted authenticator. The rules themselves are TallyDomain's `AppLockPolicy`
/// (`AppLockPolicyTests`, Linux); these check that the model feeds it the launch, the scene phase
/// and every result, and persists the setting.
///
/// The privacy cover on `.inactive` is checked here at the scene-phase level (the input
/// `RootView` forwards from SwiftUI's `scenePhase`); `AppLockUITests` checks it in the running app.
@Suite("AppLockModel: cold launch, scene phase, results, the setting")
@MainActor
struct AppLockModelTests {
    private func model(_ results: [AppLockPolicy.AuthResult] = [.success(via: .biometric)],
                       availability: AppLockAvailability = .available(.faceID),
                       stored: AppLockPreference? = nil, clock: TestClock = TestClock())
        -> (AppLockModel, ScriptedAuthenticator, InMemoryAppLockPreferenceStore) {
        let authenticator = ScriptedAuthenticator(results, availability: availability)
        let preferences = InMemoryAppLockPreferenceStore(stored)
        return (AppLockModel(authenticator: authenticator, preferences: preferences, clock: clock), authenticator, preferences)
    }

    @Test("cold launch: locked when the setting is on, unlocked when it is off")
    func coldLaunchLocksWhenEnabled() {
        let (on, _, _) = model()
        on.configure(with: AppLockPreference(isEnabled: true))
        #expect(on.isConfigured && on.isLocked)
        #expect(on.lockEpisode == 1)
        let (off, _, _) = model()
        off.configure(with: .disabled)
        #expect(off.isConfigured && !off.isLocked)
    }

    @Test("the privacy cover shows on .inactive (and .background) when the lock is on, unlocked or not, and never when it is off")
    func privacyCoverOnInactive() async {
        let (lock, _, _) = model()
        lock.configure(with: AppLockPreference(isEnabled: true))
        await lock.unlock()
        #expect(!lock.isLocked)
        #expect(!lock.showsPrivacyCover)
        lock.scenePhaseChanged(to: .inactive)
        #expect(lock.showsPrivacyCover, "no cover on .inactive")
        #expect(!lock.isLocked, ".inactive alone must not lock")
        lock.scenePhaseChanged(to: .active)
        #expect(!lock.showsPrivacyCover)

        let (off, _, _) = model()
        off.configure(with: .disabled)
        off.scenePhaseChanged(to: .inactive)
        #expect(!off.showsPrivacyCover)
    }

    @Test("a scene that is already inactive at configure time is covered at once")
    func inactiveBeforeConfigureIsCovered() {
        let (lock, _, _) = model()
        lock.scenePhaseChanged(to: .inactive)
        lock.configure(with: AppLockPreference(isEnabled: true))
        #expect(lock.showsPrivacyCover)
    }

    @Test("every non-success result keeps the app locked, with no alert state beyond the result", arguments: [
        AppLockPolicy.AuthResult.failedOrCancelled, .biometryUnavailable, .biometryLockout, .passcodeNotSet,
    ])
    func everyFailureStaysLocked(_ result: AppLockPolicy.AuthResult) async {
        let (lock, authenticator, _) = model([result])
        lock.configure(with: AppLockPreference(isEnabled: true))
        await lock.unlock()
        #expect(lock.isLocked, "\(result) unlocked the app")
        #expect(lock.lastFailure == result)
        #expect(authenticator.attempts == 1)
    }

    @Test("success unlocks; the lock view auto-prompts once per lock")
    func autoPromptOncePerLock() async {
        let clock = TestClock()
        let (lock, authenticator, _) = model([.failedOrCancelled, .success(via: .biometric), .success(via: .passcode)], clock: clock)
        lock.configure(with: AppLockPreference(isEnabled: true, gracePeriod: .immediately))
        await lock.autoPromptIfNeeded()
        #expect(lock.isLocked && lock.lastFailure == .failedOrCancelled) // a cancel: no second prompt
        await lock.autoPromptIfNeeded()
        #expect(authenticator.attempts == 1, "the lock view prompted twice for one lock")
        await lock.unlock() // the button
        #expect(!lock.isLocked)

        // Back from the background after the grace period: a new lock, prompted once again.
        lock.scenePhaseChanged(to: .background)
        clock.advance(by: .seconds(1))
        lock.scenePhaseChanged(to: .active)
        #expect(lock.isLocked && lock.lockEpisode == 2)
        await lock.autoPromptIfNeeded()
        #expect(authenticator.attempts == 3)
        #expect(!lock.isLocked)
    }

    @Test("with no device passcode the lock view never evaluates; it offers only sign-out")
    func passcodeNotSetOffersOnlySignOut() async {
        let (lock, authenticator, _) = model([.success(via: .passcode)], availability: .passcodeNotSet)
        lock.configure(with: AppLockPreference(isEnabled: true))
        await lock.autoPromptIfNeeded()
        #expect(lock.isLocked)
        #expect(lock.lastFailure == .passcodeNotSet)
        #expect(authenticator.attempts == 0)
    }

    @Test("turning the lock off needs a successful authentication; a failed one keeps it on")
    func disablingNeedsAuthentication() async {
        let (lock, _, preferences) = model([.failedOrCancelled, .success(via: .passcode)],
                                           stored: AppLockPreference(isEnabled: true))
        lock.configure(with: AppLockPreference(isEnabled: true))
        #expect(await !lock.setEnabled(false), "the lock turned off without authentication")
        #expect(lock.isEnabled)
        #expect(await lock.setEnabled(false))
        #expect(!lock.isEnabled && !lock.isLocked)
        #expect(await preferences.load() == .found(AppLockPreference(isEnabled: false)))
    }

    @Test("turning the lock on needs a device passcode, no authentication, and persists")
    func enablingNeedsAPasscode() async {
        let (noPasscode, _, _) = model(availability: .passcodeNotSet)
        noPasscode.configure(with: .disabled)
        #expect(await !noPasscode.setEnabled(true))
        #expect(!noPasscode.isEnabled)

        let (lock, authenticator, preferences) = model()
        lock.configure(with: .disabled)
        #expect(await lock.setEnabled(true))
        #expect(lock.isEnabled && !lock.isLocked, "turning the lock on must not lock the open app")
        #expect(authenticator.attempts == 0)
        await lock.setGracePeriod(.fifteenMinutes)
        #expect(await preferences.load() == .found(AppLockPreference(isEnabled: true, gracePeriod: .fifteenMinutes)))
    }

    @Test("sign-out turns the lock off and unlocks at once")
    func resetForSignOut() {
        let (lock, _, _) = model()
        lock.configure(with: AppLockPreference(isEnabled: true))
        #expect(lock.isLocked)
        lock.resetForSignOut()
        #expect(!lock.isLocked && !lock.isEnabled && !lock.showsPrivacyCover)
    }
}

/// `HomeGlance`: the first paint from the sealed glance (perf-app-runtime.md §2.4 L4, D-P1).
@Suite("HomeGlance: the glance's first paint")
struct HomeGlanceTests {
    @Test("the hero count, the due-soon rule (the next 7 days, soonest first, at most 5) and the freshness")
    func glanceMapping() {
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let hour: TimeInterval = 3600
        let due = [-2.0, 1, 2, 3, 4, 5, 6, 200].map { offset in
            GlanceDueItem(id: "item-\(offset)", courseShortCode: "BIO 101", title: "Item \(offset)",
                          dueAt: now.addingTimeInterval(offset * hour), missing: false, late: false, excused: false,
                          submitted: false)
        }
        let glance = GlanceProjection(generation: 4, asOf: now.addingTimeInterval(-600), overallGradeBand: nil,
                                      courses: (0..<3).map { GlanceCourse(id: CanvasID("\($0)"), shortCode: "C\($0)", currentGrade: nil) },
                                      dueSoon: due)
        let home = HomeGlance.make(from: glance, now: now)
        #expect(home.generation == 4)
        #expect(home.dashboard.hero.courseCount == 3)
        #expect(home.dashboard.hero.overallPercent == nil)
        #expect(home.dashboard.dueSoon.map(\.id) == ["item-1.0", "item-2.0", "item-3.0", "item-4.0", "item-5.0"])
        #expect(home.dashboard.dueSoon.first?.courseCode == "BIO 101")
        #expect(home.freshness == .fresh(at: now.addingTimeInterval(-600)))
        #expect(home.dashboard.nextUp.isEmpty && home.dashboard.needsAttention.isEmpty)
    }
}
#endif
