import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("AppLockPolicy: cold launch, background grace period, and the three old bypasses")
struct AppLockPolicyTests {
    let clock = TestClock()

    // MARK: - The three bypasses found in the old code (security.md SEC-05) — regression tests.

    @Test("Bypass 1: cold launch used to start unlocked")
    func coldLaunchLocksWhenEnabled() {
        let policy = AppLockPolicy(isEnabled: true)
        #expect(policy.state == .locked)
    }

    @Test func coldLaunchStaysUnlockedWhenLockIsDisabled() {
        let policy = AppLockPolicy(isEnabled: false)
        #expect(policy.state == .unlocked)
    }

    @Test("Bypass 2: biometrics-unavailable used to fail open")
    func biometryUnavailableKeepsLocked() {
        var policy = AppLockPolicy(isEnabled: true)
        let changed = policy.authenticationCompleted(.biometryUnavailable, for: .unlock)
        #expect(!changed)
        #expect(policy.state == .locked)
    }

    @Test("Bypass 3: biometric lockout used to fail open (same canEvaluatePolicy path as bypass 2)")
    func biometryLockoutKeepsLocked() {
        var policy = AppLockPolicy(isEnabled: true)
        let changed = policy.authenticationCompleted(.biometryLockout, for: .unlock)
        #expect(!changed)
        #expect(policy.state == .locked)
    }

    // MARK: - Every non-success result keeps the app locked (security.md "any LAError keeps it locked")

    @Test(arguments: [
        AppLockPolicy.AuthResult.failedOrCancelled,
        .biometryUnavailable,
        .biometryLockout,
        .passcodeNotSet,
    ])
    func everyNonSuccessResultKeepsLocked(_ result: AppLockPolicy.AuthResult) {
        var policy = AppLockPolicy(isEnabled: true)
        let changed = policy.authenticationCompleted(result, for: .unlock)
        #expect(!changed)
        #expect(policy.state == .locked)
    }

    @Test func successfulAuthenticationUnlocks() {
        var policy = AppLockPolicy(isEnabled: true)
        let changed = policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        #expect(changed)
        #expect(policy.state == .unlocked)
    }

    // MARK: - Disabling requires successful authentication (MASVS-AUTH-3)

    @Test func disablingWithoutSuccessfulAuthDoesNothing() {
        var policy = AppLockPolicy(isEnabled: true)
        let changed = policy.authenticationCompleted(.failedOrCancelled, for: .disableLock)
        #expect(!changed)
        #expect(policy.isEnabled)
        #expect(policy.state == .locked)
    }

    @Test func disablingWithSuccessfulAuthTurnsTheLockOffAndUnlocks() {
        var policy = AppLockPolicy(isEnabled: true)
        let changed = policy.authenticationCompleted(.success(via: .passcode), for: .disableLock)
        #expect(changed)
        #expect(!policy.isEnabled)
        #expect(policy.state == .unlocked)
    }

    @Test func enablingRequiresNoAuthentication() {
        var policy = AppLockPolicy(isEnabled: false)
        policy.enable(now: clock.now())
        #expect(policy.isEnabled)
        // Enabling from an already-unlocked session does not itself force a lock.
        #expect(policy.state == .unlocked)
    }

    // MARK: - Privacy cover on `.inactive` (security.md "App-switcher snapshot")

    @Test func privacyCoverShowsOnInactiveEvenWhileUnlocked() {
        var policy = AppLockPolicy(isEnabled: true)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        #expect(!policy.showsPrivacyCover)
        policy.scenePhaseChanged(to: .inactive, now: clock.now())
        #expect(policy.showsPrivacyCover)
    }

    @Test func noPrivacyCoverWhenLockIsDisabled() {
        var policy = AppLockPolicy(isEnabled: false)
        policy.scenePhaseChanged(to: .inactive, now: clock.now())
        #expect(!policy.showsPrivacyCover)
    }

    @Test func inactiveAloneNeverStartsTheGracePeriodTimer() {
        var policy = AppLockPolicy(isEnabled: true, gracePeriod: .fifteenMinutes)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.scenePhaseChanged(to: .inactive, now: clock.now())
        clock.advance(by: .seconds(3600))
        policy.scenePhaseChanged(to: .active, now: clock.now())
        #expect(policy.state == .unlocked)
    }

    // MARK: - Background grace period (ADR 0001: Immediately / 1 / 5 / 15 min; default 1 min)

    @Test func defaultGracePeriodIsOneMinute() {
        #expect(AppLockPolicy.GracePeriod.default == .oneMinute)
        #expect(AppLockPolicy(isEnabled: true).gracePeriod == .oneMinute)
    }

    @Test(arguments: AppLockPolicy.GracePeriod.allCases)
    func relocksAfterBackgroundLongerThanItsGracePeriod(_ grace: AppLockPolicy.GracePeriod) {
        var policy = AppLockPolicy(isEnabled: true, gracePeriod: grace)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.scenePhaseChanged(to: .background, now: clock.now())
        clock.advance(by: grace.duration)
        clock.advance(by: .seconds(1)) // strictly longer than the grace period
        policy.scenePhaseChanged(to: .active, now: clock.now())
        #expect(policy.state == .locked)
    }

    @Test(arguments: [AppLockPolicy.GracePeriod.oneMinute, .fiveMinutes, .fifteenMinutes])
    func staysUnlockedWithinItsGracePeriod(_ grace: AppLockPolicy.GracePeriod) {
        var policy = AppLockPolicy(isEnabled: true, gracePeriod: grace)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.scenePhaseChanged(to: .background, now: clock.now())
        clock.advance(by: .seconds(max(0, grace.duration.timeInterval - 1)))
        policy.scenePhaseChanged(to: .active, now: clock.now())
        #expect(policy.state == .unlocked)
    }

    @Test func immediatelyRelocksEvenAfterAnInstant() {
        var policy = AppLockPolicy(isEnabled: true, gracePeriod: .immediately)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.scenePhaseChanged(to: .background, now: clock.now())
        policy.scenePhaseChanged(to: .active, now: clock.now())
        #expect(policy.state == .locked)
    }

    @Test func disablingTheLockClearsAnyPendingBackgroundTimer() {
        var policy = AppLockPolicy(isEnabled: true, gracePeriod: .fifteenMinutes)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.scenePhaseChanged(to: .background, now: clock.now())
        policy.authenticationCompleted(.success(via: .passcode), for: .disableLock)
        clock.advance(by: .seconds(3600))
        policy.scenePhaseChanged(to: .active, now: clock.now())
        #expect(policy.state == .unlocked) // the lock is off; nothing should relock it
    }

    // MARK: - Biometric-enrolment change requires passcode re-auth (security.md §3.3)

    @Test func enrollmentChangeForcesRelockAndPasscodeOnly() {
        var policy = AppLockPolicy(isEnabled: true, enrollmentToken: Data([1, 2, 3]))
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.observedEnrollmentToken(Data([9, 9, 9]), now: clock.now())
        #expect(policy.state == .locked)
        #expect(policy.requiredCredential == .passcodeOnly)
    }

    @Test func afterEnrollmentChangeANewBiometricSuccessDoesNotUnlock() {
        var policy = AppLockPolicy(isEnabled: true, enrollmentToken: Data([1, 2, 3]))
        policy.observedEnrollmentToken(Data([9, 9, 9]), now: clock.now())
        let changed = policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        #expect(!changed)
        #expect(policy.state == .locked)
    }

    @Test func afterEnrollmentChangeAPasscodeSuccessUnlocksAndClearsTheRequirement() {
        var policy = AppLockPolicy(isEnabled: true, enrollmentToken: Data([1, 2, 3]))
        policy.observedEnrollmentToken(Data([9, 9, 9]), now: clock.now())
        let changed = policy.authenticationCompleted(.success(via: .passcode), for: .unlock)
        #expect(changed)
        #expect(policy.state == .unlocked)
        #expect(policy.requiredCredential == .biometricsOrPasscode)
    }

    @Test func firstEverEnrollmentObservationOnlySeedsTheBaseline() {
        var policy = AppLockPolicy(isEnabled: true, enrollmentToken: nil)
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.observedEnrollmentToken(Data([1, 2, 3]), now: clock.now())
        #expect(policy.state == .unlocked)
        #expect(policy.requiredCredential == .biometricsOrPasscode)
    }

    @Test func noEnrollmentChangeDoesNothing() {
        var policy = AppLockPolicy(isEnabled: true, enrollmentToken: Data([1, 2, 3]))
        policy.authenticationCompleted(.success(via: .biometric), for: .unlock)
        policy.observedEnrollmentToken(Data([1, 2, 3]), now: clock.now())
        #expect(policy.state == .unlocked)
        #expect(policy.requiredCredential == .biometricsOrPasscode)
    }
}
