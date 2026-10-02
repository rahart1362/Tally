#if DEBUG
import Foundation
import Synchronization
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like `AccountLifecycleTestSupport`, whose harness it uses.
///
/// M3-B1's test doubles: a scripted StoreKit source, a recording background scheduler, synthetic
/// transaction facts, and a rig that wires them to a real `SubscriptionEngine`, a real
/// `EntitlementGate` and (for the lapse tests) a real account: a coordinator over the flagship
/// persona, the reminders pipeline over a `FakeReminderPlatform`. Every value is synthetic.
enum SubscriptionFixtures {
    static let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
    /// The flagship replay's anchor (2026-09-21T14:13:20Z), as the reminders tests use it.
    static let now = ReminderTestSupport.anchor
    static let day: TimeInterval = 24 * 60 * 60

    static func active(until offset: TimeInterval = 300 * day, productID: String = products.studentAnnual,
                       verified: Bool = true) -> SubscriptionFacts {
        SubscriptionFacts(productID: productID, isVerified: verified, expirationDate: now.addingTimeInterval(offset),
                          renewalState: .subscribed, signedDate: now.addingTimeInterval(-60))
    }

    static func expired(at offset: TimeInterval = -60) -> SubscriptionFacts {
        SubscriptionFacts(productID: products.studentAnnual, isVerified: true, expirationDate: now.addingTimeInterval(offset),
                          renewalState: .expired, signedDate: now.addingTimeInterval(-30))
    }

    /// Polls an async `condition` every 5 ms until it holds or `timeout` passes (generous for the
    /// sanitizer runs); true when it held.
    static func eventually(timeout: Duration = .seconds(30), _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    static func refunded(at offset: TimeInterval = -120) -> SubscriptionFacts {
        SubscriptionFacts(productID: products.studentAnnual, isVerified: true, expirationDate: now.addingTimeInterval(300 * day),
                          revocationDate: now.addingTimeInterval(offset), signedDate: now.addingTimeInterval(-30))
    }
}

/// A StoreKit stand-in the test scripts: the facts each read returns (optionally held until
/// released), the purchase outcome, and a log of what the engine had granted (the gate's state, the
/// record's expiry) each time it asked for the unfinished transactions to be finished.
final class ScriptedEntitlementSource: EntitlementSourcing {
    struct Finish: Sendable, Equatable {
        let gateState: EntitlementState?
        let recordedUntil: Date?
    }

    private struct State {
        var facts: [SubscriptionFacts] = []
        var holdReads = false
        var held: [CheckedContinuation<Void, Never>] = []
        var reads = 0
        var listens = 0
        var onUpdate: (@Sendable () async -> Void)?
        var purchaseOutcome: SubscriptionPurchaseOutcome = .purchased
        var factsAfterPurchase: [SubscriptionFacts]?
        var finishes: [Finish] = []
    }

    private let state: Mutex<State>
    private let gate: EntitlementGate
    private let records: any EntitlementRecordStoring

    init(facts: [SubscriptionFacts] = [], gate: EntitlementGate, records: any EntitlementRecordStoring) {
        state = Mutex(State(facts: facts))
        self.gate = gate
        self.records = records
    }

    var reads: Int { state.withLock { $0.reads } }
    var listens: Int { state.withLock { $0.listens } }
    var finishes: [Finish] { state.withLock { $0.finishes } }

    func setFacts(_ facts: [SubscriptionFacts]) { state.withLock { $0.facts = facts } }

    func setPurchase(_ outcome: SubscriptionPurchaseOutcome, factsAfter: [SubscriptionFacts]? = nil) {
        state.withLock { $0.purchaseOutcome = outcome; $0.factsAfterPurchase = factsAfter }
    }

    /// Every later read waits until `release()`.
    func holdReads() { state.withLock { $0.holdReads = true } }

    func release() {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.holdReads = false
            defer { state.held.removeAll() }
            return state.held
        }
        for continuation in waiting { continuation.resume() }
    }

    /// A verified `Transaction.updates` element, as the StoreKit adapter delivers it: the engine's
    /// grant runs, then the transaction would be finished.
    func deliverUpdate() async {
        let onUpdate = state.withLock { $0.onUpdate }
        await onUpdate?()
    }

    func currentFacts() async -> [SubscriptionFacts] {
        let mustWait = state.withLock { state -> Bool in
            state.reads += 1
            return state.holdReads
        }
        if mustWait {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    guard state.holdReads else { return true }
                    state.held.append(continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        return state.withLock { $0.facts }
    }

    func finishUnfinished() async {
        let finish = Finish(gateState: await gate.current, recordedUntil: await records.load().record?.studentUntil)
        state.withLock { $0.finishes.append(finish) }
    }

    func listen(onUpdate: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        state.withLock { $0.listens += 1; $0.onUpdate = onUpdate }
        return Task {}
    }

    func purchase(_ productID: String, onGranted: @escaping @Sendable () async -> Void) async -> SubscriptionPurchaseOutcome {
        let outcome = state.withLock { state -> SubscriptionPurchaseOutcome in
            if state.purchaseOutcome == .purchased, let facts = state.factsAfterPurchase { state.facts = facts }
            return state.purchaseOutcome
        }
        if outcome == .purchased { await onGranted() }
        return outcome
    }
}

/// The background-refresh request, recorded: whether one is pending, and every call.
final class RecordingBackgroundScheduler: BackgroundRefreshScheduling {
    private let state = Mutex((pending: Date?.none, schedules: 0, cancels: 0))

    var pending: Date? { state.withLock { $0.pending } }
    var schedules: Int { state.withLock { $0.schedules } }
    var cancels: Int { state.withLock { $0.cancels } }

    func schedule(earliestBegin: Date) async { state.withLock { $0.pending = earliestBegin; $0.schedules += 1 } }
    func cancel() async { state.withLock { $0.pending = nil; $0.cancels += 1 } }
    func isScheduled() async -> Bool { state.withLock { $0.pending != nil } }
}

/// A real engine and gate over the scripted source, an in-memory record store and the recording
/// scheduler, at a fixed clock; and, on demand, a real account for the engine's effects.
struct SubscriptionRig: Sendable {
    let gate: EntitlementGate
    let records: InMemoryEntitlementRecordStore
    let source: ScriptedEntitlementSource
    let scheduler: RecordingBackgroundScheduler
    let engine: SubscriptionEngine
    let clock: TestClock

    init(enforced: Bool = true, facts: [SubscriptionFacts] = [], record: EntitlementRecord? = nil,
         now: Date = SubscriptionFixtures.now) {
        clock = TestClock(now)
        gate = EntitlementGate(isEnforced: enforced, clock: clock, resolutionTimeout: .seconds(30))
        records = InMemoryEntitlementRecordStore(record)
        source = ScriptedEntitlementSource(facts: facts, gate: gate, records: records)
        scheduler = RecordingBackgroundScheduler()
        engine = SubscriptionEngine(source: source, records: records, gate: gate, scheduler: scheduler,
                                    products: SubscriptionFixtures.products, clock: clock)
    }

    /// Starts the engine and waits for the launch verification.
    func started() async -> SubscriptionRig {
        await engine.start()
        await engine.settle()
        return self
    }

    /// `unattachedAccount`, attached to the engine.
    func attachedAccount(permission: ReminderPermission = .authorized) async throws -> SubscriptionAccount {
        let account = try await unattachedAccount(permission: permission)
        await engine.accountAttached(account.coordinator, environment: account.environment)
        return account
    }

    /// A signed-in account for the effects: an environment carrying this rig's gate and a
    /// `FakeReminderPlatform`, and a coordinator over the flagship snapshot, committed to the
    /// account's store (so its glance can be rewritten). Not attached to the engine.
    func unattachedAccount(permission: ReminderPermission = .authorized) async throws -> SubscriptionAccount {
        let harness = try AccountHarness()
        let platform = FakeReminderPlatform(permission: permission)
        let reloads = CallCounter()
        let root = harness.root
        let environment = AccountEnvironment(
            storeRoot: { root }, credentialStore: harness.credentials, keyring: harness.keyring,
            lockPreferences: harness.lockPreferences, transport: harness.transport, notifications: platform,
            reloadWidgets: { reloads.increment() }, clock: FixedClock(now: SubscriptionFixtures.now),
            gatewayOverride: { account in FlagshipAccountGateway(account: account.accountKey) }, entitlement: gate)
        let snapshot = try await FlagshipAccountGateway.flagship(account: harness.account)
        let store = environment.snapshotStore(for: harness.account, root: root)
        try await store.commit(snapshot, includeGrades: false)
        let coordinator = RefreshCoordinator(gateway: FlagshipAccountGateway(account: harness.account), store: store,
                                             clock: FixedClock(now: SubscriptionFixtures.now), initialSnapshot: snapshot,
                                             entitlement: gate)
        return SubscriptionAccount(harness: harness, platform: platform, reloads: reloads, environment: environment,
                                   store: store, coordinator: coordinator)
    }
}

/// The account `SubscriptionRig.attachedAccount` builds.
struct SubscriptionAccount: Sendable {
    let harness: AccountHarness
    let platform: FakeReminderPlatform
    let reloads: CallCounter
    let environment: AccountEnvironment
    let store: SnapshotStore
    let coordinator: RefreshCoordinator

    func reminderPass() async -> ReminderPassOutcome? {
        await ReminderPipeline.reconcile(coordinator: coordinator, environment: environment,
                                         timeZone: ReminderTestSupport.timeZone, locale: ReminderTestSupport.locale)
    }

    func glance() async -> GlanceProjection? {
        guard case .loaded(let glance) = await store.loadGlance() else { return nil }
        return glance
    }
}
#endif
