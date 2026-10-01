import Foundation
import Observation
import TallyDomain
import TallyStrings

/// SEC-07 (security.md WP-SEC-07; ADR 0001 "App lock"; ux-ui.md §3.7.8): the app lock's state on
/// the main actor. The rules live in TallyDomain's pure `AppLockPolicy`; this model only feeds it
/// the launch preference, the scene phase and the authenticator's results, and persists the
/// setting.
///
/// ADR 0001's launch order, as `RootView` renders it:
/// 1. **privacy cover**: `LaunchPlaceholderView` until `configure(with:)` has run;
/// 2. **lock**: `LockView` while `isLocked` (the cached Home is never rendered under it);
/// 3. **cached render**: the route's content once unlocked;
/// 4. **handshake**: the Home's launch refresh starts from the Home's own `.task`, so after unlock.
///
/// Every result other than `.success` leaves the app locked (`AppLockPolicy.authenticationCompleted`
/// has exactly one unlocking case), and a user cancel raises no alert: the lock view keeps its
/// button (ux-ui.md §3.7.8).
@MainActor
@Observable
public final class AppLockModel {
    /// Explicit and nonisolated (plan 06 A2): in this default-`MainActor` module an implicit deinit
    /// is main-actor isolated, and an isolated deinit aborts iOS 26.0-26.3 runtimes
    /// (swiftlang/swift#88036). CI's `nm` gate keeps isolated deinits out of every binary.
    nonisolated deinit {}

    public static var unlockReason: String { String(localized: L10n.Lock.unlockReason()) }
    public static var disableReason: String { String(localized: L10n.Lock.disableReason()) }

    public private(set) var policy = AppLockPolicy(isEnabled: false)
    /// False until the launch has read the stored setting; until then the app shows only the
    /// launch cover.
    public private(set) var isConfigured = false
    public private(set) var isAuthenticating = false
    /// The last unlock attempt's result when it did not unlock: the lock view words its message
    /// from it (only `.passcodeNotSet` changes what it offers). A cancel is not an error.
    public private(set) var lastFailure: AppLockPolicy.AuthResult?
    public private(set) var availability: AppLockAvailability = .unavailable
    /// Goes up each time the app becomes locked, so the lock view auto-prompts once per lock
    /// (ux-ui.md §3.7.8: "auto-prompts once").
    public private(set) var lockEpisode = 0

    @ObservationIgnored private var autoPromptedEpisode = 0
    @ObservationIgnored private var scenePhase: AppLockPolicy.Phase = .active
    private let authenticator: any AppLockAuthenticating
    private let preferences: any AppLockPreferenceStoring
    private let clock: any DateProviding
    private let unlockTask = TaskBox()
    private let persistTask = TaskBox()

    public init(authenticator: any AppLockAuthenticating = UnavailableAppLockAuthenticator(),
                preferences: any AppLockPreferenceStoring = InMemoryAppLockPreferenceStore(),
                clock: any DateProviding = SystemDateProvider()) {
        self.authenticator = authenticator
        self.preferences = preferences
        self.clock = clock
    }

    public var isEnabled: Bool { policy.isEnabled }
    public var isLocked: Bool { policy.state == .locked }
    public var gracePeriod: AppLockPolicy.GracePeriod { policy.gracePeriod }
    /// ADR 0001 step 1 and security.md's app-switcher row: an opaque cover whenever the lock is on
    /// and the scene is not active, locked or not.
    public var showsPrivacyCover: Bool { policy.showsPrivacyCover }

    /// Cold launch (ADR 0001: "Locks on cold launch"): a fresh policy from the stored setting,
    /// locked whenever the lock is on, whatever state the app was last left in.
    public func configure(with preference: AppLockPreference) {
        policy = AppLockPolicy(isEnabled: preference.isEnabled, gracePeriod: preference.gracePeriod)
        if scenePhase != .active { policy.scenePhaseChanged(to: scenePhase, now: clock.now()) }
        if isLocked { lockEpisode += 1 }
        lastFailure = nil
        isConfigured = true
    }

    /// `ScenePhase` changes (`RootView`). `.inactive` puts the cover up; a return from
    /// `.background` after the grace period locks again.
    public func scenePhaseChanged(to phase: AppLockPolicy.Phase) {
        scenePhase = phase
        guard isConfigured else { return }
        let wasLocked = isLocked
        policy.scenePhaseChanged(to: phase, now: clock.now())
        if !wasLocked, isLocked {
            lockEpisode += 1
            lastFailure = nil
        }
    }

    /// One `.deviceOwnerAuthentication` attempt. Any result but `.success` keeps the app locked.
    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let result = await authenticator.authenticate(reason: Self.unlockReason)
        isAuthenticating = false
        lastFailure = policy.authenticationCompleted(result, for: .unlock) ? nil : result
    }

    /// The lock view's button: an unlock attempt owned by this model, never by a view.
    public func requestUnlock() {
        unlockTask.replace(with: Task { [weak self] in await self?.unlock() })
    }

    /// The lock view's first appearance for each lock: prompts once, then leaves the button.
    public func autoPromptIfNeeded() async {
        guard isLocked, autoPromptedEpisode != lockEpisode else { return }
        autoPromptedEpisode = lockEpisode
        await refreshAvailability()
        guard availability != .passcodeNotSet else {
            lastFailure = .passcodeNotSet
            return
        }
        await unlock()
    }

    public func refreshAvailability() async {
        availability = await authenticator.availability()
    }

    /// Settings (UX-WP-20, M3-A): turning the lock **on** needs no authentication, but it needs a
    /// device passcode (security.md §3.3: "`passcodeNotSet` means the toggle is unavailable");
    /// turning it **off** needs a successful authentication (MASVS-AUTH-3). Returns whether the
    /// setting changed; it is persisted when it did.
    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != policy.isEnabled else { return true }
        if enabled {
            await refreshAvailability()
            guard case .available = availability else { return false }
            policy.enable(now: clock.now())
        } else {
            guard !isAuthenticating else { return false }
            isAuthenticating = true
            let result = await authenticator.authenticate(reason: Self.disableReason)
            isAuthenticating = false
            guard policy.authenticationCompleted(result, for: .disableLock) else { return false }
        }
        await persist()
        return true
    }

    public func setGracePeriod(_ period: AppLockPolicy.GracePeriod) async {
        policy.setGracePeriod(period)
        await persist()
    }

    /// Sign-out and erase (`AppModel.signOut()`): the lock goes off and the app unlocks at once, so
    /// Welcome shows. security.md §3.3: with no device passcode, sign-out is the only way out of a
    /// lock, so the setting must not survive it. The stored setting is removed by the sign-out's
    /// purge step.
    func resetForSignOut() {
        policy = AppLockPolicy(isEnabled: false)
        if scenePhase != .active { policy.scenePhaseChanged(to: scenePhase, now: clock.now()) }
        lastFailure = nil
    }

    /// Waits for the last persisted change (tests).
    func awaitPersistence() async {
        await persistTask.value()
    }

    private func persist() async {
        let preference = AppLockPreference(isEnabled: policy.isEnabled, gracePeriod: policy.gracePeriod)
        let preferences = self.preferences
        // Its own task: a Settings view that goes away mid-save never cancels the write.
        let saving = Task {
            do { try await preferences.save(preference) } catch {}
        }
        persistTask.replace(with: saving)
        await saving.value
    }
}
