import Foundation
import Observation
import TallyDomain

/// PAY-07: the subscription's state, observable on `AppModel.subscription`, for M3-B2's paywall,
/// locked-feature cards, Settings → Subscription and the lapse notice ("Subscribe to refresh —
/// showing saved data from <time>"). M3-B1 draws nothing: no view reads this yet.
///
/// It mirrors what `SubscriptionEngine` publishes; the engine does the work off the main actor.
@MainActor
@Observable
public final class SubscriptionModel {
    /// Explicit and nonisolated (plan 06 A2): an implicit deinit in this default-`MainActor` module
    /// is main-actor isolated, and an isolated deinit aborts iOS 26.0-26.3 runtimes
    /// (swiftlang/swift#88036); CI's `nm` gate keeps it out of every shipping binary.
    nonisolated deinit {}

    /// The account's entitlement, as the gate decides with it: StoreKit's answer, or the Keychain
    /// record's until StoreKit answers. `nil` until the launch's first state.
    public private(set) var accountState: EntitlementState?
    /// M3-B3: how the account holds whatever currently entitles it. `nil` before StoreKit has
    /// answered this launch (`SubscriptionStatus.holding`): Settings and the school-revoked notice
    /// show today's purchase UI (as if `.purchase`) until it is known.
    public private(set) var holding: SubscriptionHolding?
    /// StoreKit has answered since this launch (PAY-04: re-verified at every launch).
    public private(set) var isVerifiedThisLaunch = false
    /// Ask to Buy: a purchase is waiting for a parent's approval (M3-B2 says so).
    public private(set) var isPurchasePending = false
    /// `SubscriptionConfig.isGatingEnforced`, unless a test injects otherwise.
    public let isEnforced: Bool
    /// The engine, when the composition root built one (nil in tests and previews that never buy).
    @ObservationIgnored public let engine: SubscriptionEngine?
    @ObservationIgnored private let table: SubscriptionGate
    @ObservationIgnored private let clock: any DateProviding
    @ObservationIgnored private var isStarted = false

    public init(engine: SubscriptionEngine? = nil, clock: any DateProviding = SystemDateProvider()) {
        self.engine = engine
        isEnforced = engine?.gate.isEnforced ?? SubscriptionConfig.isGatingEnforced
        table = SubscriptionGate(isEnforced: isEnforced)
        self.clock = clock
    }

    /// What a session shows (`EntitlementState.inSession`): sample data is `.demo`; before the
    /// account's first sync a lapse reads as `.preview`.
    public func state(isSampleMode: Bool, firstSyncSucceeded: Bool) -> EntitlementState {
        (accountState ?? .preview).inSession(isSampleMode: isSampleMode, firstSyncSucceeded: firstSyncSucceeded)
    }

    /// Whether `feature` is available now in that session (the gating table at the clock's now).
    public func allows(_ feature: SubscriptionFeature, isSampleMode: Bool, firstSyncSucceeded: Bool) -> Bool {
        table.allows(feature, in: state(isSampleMode: isSampleMode, firstSyncSucceeded: firstSyncSucceeded), at: clock.now())
    }

    /// Once, at app init (`TallyApp.init`, never a view): connects this model to the engine, then
    /// starts it (the `Transaction.updates` listener and the launch verification). Later calls do
    /// nothing.
    public func start() {
        guard !isStarted, let engine else { return }
        isStarted = true
        let observer: @Sendable (SubscriptionStatus) async -> Void = { @MainActor [weak self] status in
            self?.receive(status)
        }
        Task {
            await engine.observe(observer)
            await engine.start()
        }
    }

    /// The scene became active: StoreKit re-verifies.
    public func foreground() {
        guard let engine else { return }
        Task { await engine.foreground() }
    }

    /// The scene entered the background: the background refresh is requested again (B6).
    public func sceneDidEnterBackground() {
        guard let engine else { return }
        Task { await engine.sceneDidEnterBackground() }
    }

    func receive(_ status: SubscriptionStatus) {
        if accountState != status.accountState { accountState = status.accountState }
        if holding != status.holding { holding = status.holding }
        if isVerifiedThisLaunch != status.isVerifiedThisLaunch { isVerifiedThisLaunch = status.isVerifiedThisLaunch }
        if isPurchasePending != status.isPurchasePending { isPurchasePending = status.isPurchasePending }
    }

    /// M3-B3: whether the account's entitlement is a school's assigned seat, not this Apple
    /// Account's own purchase. `false` before StoreKit has answered (`holding == nil`), so a view
    /// shows today's purchase UI until it is known.
    public var isSchoolSeat: Bool { holding == .schoolSeat }
}
