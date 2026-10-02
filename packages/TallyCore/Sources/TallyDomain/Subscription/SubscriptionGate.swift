import Foundation

/// What the subscription decides (PAY-07; PRD §11.2 "Free vs paid").
public enum SubscriptionFeature: String, Sendable, CaseIterable {
    /// A Canvas refresh once the account has a committed snapshot: launch, foreground, manual
    /// (pull-to-refresh, the hero's button), background, the "Refresh Tally" intent.
    case refresh
    /// The one-time first sync after sign-in (a refresh with no committed snapshot): always free.
    case firstSync
    /// A pending background-refresh request (`BGAppRefreshTaskRequest`).
    case backgroundRefreshSchedule
    /// Scheduling Tally's reminders.
    case reminders
    /// The widgets' content (the glance).
    case widgetData
    /// App Intents and Shortcuts that read Tally's data.
    case intentData
    /// Courses, Course Detail and what-if, To-Do, Calendar, Insights (M3-B2 draws their locks).
    case fullApp
    /// The last saved snapshot, read only (the Dashboard after a lapse): always.
    case savedSnapshot
    /// Sign out & erase: always.
    case signOutAndErase
}

/// PAY-07: the gating table, pure. One decision per feature from `EntitlementPolicy`'s state:
///
/// | Feature | `.demo` | `.preview` | `.entitled(until:)` | `.lapsed` |
/// |---|---|---|---|---|
/// | `firstSync`, `savedSnapshot`, `signOutAndErase` | yes | yes | yes | yes |
/// | every other feature | yes | no | while `now < until + offlineGrace` | no |
///
/// With enforcement off (`SubscriptionConfig.isGatingEnforced`, on since M3-B2 shipped the paywall;
/// tests inject `false`) every answer is yes.
public struct SubscriptionGate: Sendable, Equatable {
    public let isEnforced: Bool
    public let offlineGrace: Duration

    public init(isEnforced: Bool = SubscriptionConfig.isGatingEnforced,
                offlineGrace: Duration = SubscriptionConfig.offlineGracePeriod) {
        self.isEnforced = isEnforced
        self.offlineGrace = offlineGrace
    }

    public func allows(_ feature: SubscriptionFeature, in state: EntitlementState, at now: Date) -> Bool {
        guard isEnforced else { return true }
        switch feature {
        case .firstSync, .savedSnapshot, .signOutAndErase:
            return true
        case .refresh, .backgroundRefreshSchedule, .reminders, .widgetData, .intentData, .fullApp:
            switch state {
            case .demo:
                return true
            case .entitled(let until):
                return EntitlementAccess.covers(entitledUntil: until, at: now, isEnforced: true, offlineGrace: offlineGrace)
            case .preview, .lapsed:
                return false
            }
        }
    }

    /// A refresh for `trigger`: the first sync (no committed snapshot yet) is free, whatever the
    /// state; every later refresh needs the trial or the subscription. The trigger itself does not
    /// change the answer (PRD §11.2: launch, manual and background alike).
    public func allowsRefresh(_ trigger: RefreshTrigger, hasCommittedSnapshot: Bool, in state: EntitlementState,
                              at now: Date) -> Bool {
        allows(hasCommittedSnapshot ? .refresh : .firstSync, in: state, at: now)
    }
}

/// PAY-07: what every gated path asks (the coordinator's refresh and glance writes, a reminders
/// pass, the background schedule). The app's conformance is `EntitlementGate`.
public protocol EntitlementGating: Sendable {
    /// A refresh: the first sync is free, every later one needs the subscription.
    func allowsRefresh(_ trigger: RefreshTrigger, hasCommittedSnapshot: Bool) async -> Bool
    func allows(_ feature: SubscriptionFeature) async -> Bool
    /// PAY-04: the expiry the glance mirrors (`GlanceProjection.entitledUntil`), nil without one.
    func glanceEntitledUntil() async -> Date?
}

/// No gate: everything allowed, nothing mirrored. `AccountEnvironment`'s default (tests, previews,
/// and any path the composition root has not given the app's gate).
public struct UngatedEntitlement: EntitlementGating {
    public init() {}
    public func allowsRefresh(_ trigger: RefreshTrigger, hasCommittedSnapshot: Bool) async -> Bool { true }
    public func allows(_ feature: SubscriptionFeature) async -> Bool { true }
    public func glanceEntitledUntil() async -> Date? { nil }
}

/// The app's one gate (PAY-07): the active account's entitlement state, which the subscription
/// engine sets (from the Keychain record at launch, then from StoreKit), decided by
/// `SubscriptionGate`'s table at the clock's `now`.
///
/// **Launch.** Until the first `update(_:)` there is no state. While enforced, a decision waits for
/// it (the engine reads the record within milliseconds of app init) for at most
/// `resolutionTimeout`, then fails closed: the first sync stays free, everything else is refused.
/// Not enforced, nothing waits and everything is allowed.
public actor EntitlementGate: EntitlementGating {
    public nonisolated let isEnforced: Bool
    private let table: SubscriptionGate
    private let clock: any DateProviding
    private let resolutionTimeout: Duration
    private var state: EntitlementState?
    private var waiters: [UInt64: CheckedContinuation<EntitlementState?, Never>] = [:]
    private var nextWaiterID: UInt64 = 0

    public init(isEnforced: Bool = SubscriptionConfig.isGatingEnforced, clock: any DateProviding = SystemDateProvider(),
                state: EntitlementState? = nil, offlineGrace: Duration = SubscriptionConfig.offlineGracePeriod,
                resolutionTimeout: Duration = SubscriptionConfig.launchResolutionTimeout) {
        self.isEnforced = isEnforced
        table = SubscriptionGate(isEnforced: isEnforced, offlineGrace: offlineGrace)
        self.clock = clock
        self.state = state
        self.resolutionTimeout = resolutionTimeout
    }

    /// The state every later decision uses; the first call also answers the decisions waiting for it.
    public func update(_ newState: EntitlementState) {
        state = newState
        let waiting = waiters
        waiters.removeAll()
        for continuation in waiting.values { continuation.resume(returning: newState) }
    }

    /// The current state, nil before the first `update(_:)`.
    public var current: EntitlementState? { state }

    public func allowsRefresh(_ trigger: RefreshTrigger, hasCommittedSnapshot: Bool) async -> Bool {
        guard isEnforced else { return true }
        guard let state = await resolved() else { return !hasCommittedSnapshot }
        return table.allowsRefresh(trigger, hasCommittedSnapshot: hasCommittedSnapshot, in: state, at: clock.now())
    }

    public func allows(_ feature: SubscriptionFeature) async -> Bool {
        guard isEnforced else { return true }
        guard let state = await resolved() else { return table.allows(feature, in: .preview, at: clock.now()) }
        return table.allows(feature, in: state, at: clock.now())
    }

    public func glanceEntitledUntil() async -> Date? {
        guard isEnforced else { return state?.entitledUntil }
        return await resolved()?.entitledUntil
    }

    /// The state, waiting (enforced) for the launch's first one for at most `resolutionTimeout`.
    private func resolved() async -> EntitlementState? {
        if let state { return state }
        let id = nextWaiterID
        nextWaiterID &+= 1
        let timeout = resolutionTimeout
        let timer = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.giveUp(id)
        }
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<EntitlementState?, Never>) in
            waiters[id] = continuation
        }
        timer.cancel()
        return answer
    }

    private func giveUp(_ id: UInt64) {
        waiters.removeValue(forKey: id)?.resume(returning: nil)
    }
}
