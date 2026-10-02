import Foundation
import TallyDomain
import TallySync

/// What the engine publishes after each step, for `SubscriptionModel` (M3-B2 draws it).
public nonisolated struct SubscriptionStatus: Sendable, Equatable {
    /// The account's entitlement, as the gate decides with it: StoreKit's answer, or the Keychain
    /// record's until StoreKit answers.
    public var accountState: EntitlementState
    /// M3-B3: how the account holds whatever currently entitles it (a purchase or a school's
    /// assigned seat), from `EntitlementPolicy.holding` over StoreKit's facts. **Nil before StoreKit
    /// has answered this launch:** the Keychain record (`accountState`'s offline source) carries no
    /// ownership, so the launch's first, unverified publish cannot say; a view should show today's
    /// purchase UI until it is known, same as `.purchase`.
    public var holding: SubscriptionHolding?
    /// StoreKit has answered since this launch (PAY-04: re-verified at every launch).
    public var isVerifiedThisLaunch: Bool
    /// Ask to Buy: a purchase is waiting for a parent's approval.
    public var isPurchasePending: Bool

    public init(accountState: EntitlementState, holding: SubscriptionHolding?, isVerifiedThisLaunch: Bool,
               isPurchasePending: Bool) {
        self.accountState = accountState
        self.holding = holding
        self.isVerifiedThisLaunch = isVerifiedThisLaunch
        self.isPurchasePending = isPurchasePending
    }
}

/// PAY-03, PAY-04, PAY-07: the subscription engine, one per process. The composition root builds
/// it; `TallyApp.init` starts it once.
///
/// 1. **Launch** (`start()`): the `Transaction.updates` listener starts, then the launch
///    verification runs. The Keychain record's state reaches the gate first (a read of
///    milliseconds), so no decision waits on StoreKit; then StoreKit re-verifies (PAY-04: at every
///    launch) and its answer replaces it.
/// 2. **Foreground** (`foreground()`, the scene's `.active`): StoreKit re-verifies.
/// 3. **`Transaction.updates`**: each verified update re-verifies, then the transaction is
///    finished; a purchase does the same through `purchase(_:)`.
/// 4. **Each verification**, one at a time: `EntitlementPolicy` → the Keychain record → the gate
///    → the effects → StoreKit's unfinished transactions finished (only now, after granting) →
///    the status published.
///
/// **Effects (PAY-07)**, each when its answer changes: the background-refresh request is scheduled
/// or withdrawn; a reminders pass runs, which withdraws every pending Tally reminder when the gate
/// says no; the glance's `entitledUntil` is rewritten and the widgets reload. The signed-in
/// account comes from `AppModel` (`accountAttached`); the engine never resolves it itself, which
/// would move the launch's snapshot decode.
///
/// With enforcement off (`SubscriptionConfig.isGatingEnforced`, on since M3-B2; tests inject `false`)
/// every gate answer is "allowed", so no effect ever withdraws anything; the engine still verifies,
/// records and mirrors.
public actor SubscriptionEngine {
    public nonisolated let gate: EntitlementGate
    public nonisolated let products: SubscriptionProducts
    public nonisolated let role: SubscriptionRole
    private let source: any EntitlementSourcing
    private let records: any EntitlementRecordStoring
    private let scheduler: any BackgroundRefreshScheduling
    private let clock: any DateProviding

    private var started = false
    private var listener: Task<Void, Never>?
    /// The verification queue's tail: verifications run one at a time, in order.
    private var tail: Task<Void, Never>?
    private var record: EntitlementRecord?
    private var status: SubscriptionStatus?
    private var applied: Applied?
    /// What the background-refresh request last became, from a verified state only: the record's
    /// state at launch never schedules or withdraws it, so a launch asks once, with StoreKit's answer.
    private var backgroundRequested: Bool?
    private var isPurchasePending = false
    private weak var coordinator: RefreshCoordinator?
    private var environment: AccountEnvironment?
    private var observer: (@Sendable (SubscriptionStatus) async -> Void)?

    /// What the effects last acted on.
    private nonisolated struct Applied: Equatable {
        var remindersAllowed: Bool
        var entitledUntil: Date?
    }

    nonisolated enum Reason: Sendable, Equatable {
        case launch, foreground, transactionUpdate, purchase
    }

    public init(source: any EntitlementSourcing = NoEntitlementSource(),
                records: any EntitlementRecordStoring = InMemoryEntitlementRecordStore(), gate: EntitlementGate,
                scheduler: any BackgroundRefreshScheduling = NoBackgroundRefreshScheduler(),
                products: SubscriptionProducts, role: SubscriptionRole = .student,
                clock: any DateProviding = SystemDateProvider()) {
        self.source = source
        self.records = records
        self.gate = gate
        self.scheduler = scheduler
        self.products = products
        self.role = role
        self.clock = clock
    }

    /// Where every status goes (`SubscriptionModel`). Set before `start()`.
    public func observe(_ observer: @escaping @Sendable (SubscriptionStatus) async -> Void) {
        self.observer = observer
    }

    /// Once, at app init (`TallyApp`, never a view): the `Transaction.updates` listener, then the
    /// launch verification. Later calls do nothing.
    public func start() {
        guard !started else { return }
        started = true
        listener = source.listen { [weak self] in
            await self?.verify(.transactionUpdate)
        }
        enqueue(.launch)
    }

    /// Stops listening to `Transaction.updates` (tests: each StoreKit Testing session gets its own
    /// engine). The app's engine lives as long as the process and never stops.
    public func stop() {
        listener?.cancel()
        listener = nil
    }

    /// The scene became active: StoreKit re-verifies (`currentEntitlements` on each foreground).
    public func foreground() async {
        await verify(.foreground)
    }

    /// The launch verification and every verification queued before this call, awaited (tests).
    public func settle() async {
        await tail?.value
    }

    /// PAY-03, for M3-B2's paywall: buys `role`'s product. A verified purchase is granted (one
    /// verification) before StoreKit's transaction is finished. Ask to Buy returns `.pending`, and
    /// the approval arrives through `Transaction.updates`.
    public func purchase(_ role: SubscriptionRole) async -> SubscriptionPurchaseOutcome {
        let outcome = await source.purchase(products.productID(for: role)) { [weak self] in
            await self?.verify(.purchase)
        }
        if outcome == .pending, !(status?.accountState.isActiveEntitlement ?? false) {
            isPurchasePending = true
            await publish()
        }
        return outcome
    }

    /// The signed-in account's coordinator is attached (`AppModel.attach`): its glance is brought
    /// in line with the gate now (a glance written before the gate knew may carry an older expiry).
    /// Held weakly, so sign-out's release of the coordinator is never delayed.
    public func accountAttached(_ coordinator: RefreshCoordinator, environment: AccountEnvironment?) async {
        self.coordinator = coordinator
        self.environment = environment
        if await coordinator.entitlementDidChange() { environment?.reloadWidgets() }
        // A lapse StoreKit found before the account attached: the launch's own reminders pass may
        // have run with the Keychain record's (earlier) answer, so one more pass withdraws.
        if let applied, !applied.remindersAllowed, let environment {
            await ReminderPipeline.reconcile(coordinator: coordinator, environment: environment)
        }
    }

    /// Sign-out: the account is gone.
    public func accountDetached() {
        coordinator = nil
        environment = nil
    }

    /// Whether an account's coordinator is attached (tests).
    var isAccountAttached: Bool { coordinator != nil }

    /// PAY-11 (M3-B1 O2): Sign out & erase. The Keychain record is deleted and this engine forgets its
    /// copy, after any verification already queued (so none writes the old record back). The App
    /// Store subscription itself is untouched; a later verification records StoreKit's answer afresh.
    public func eraseRecord() async {
        let previous = tail
        let erase = Task { [weak self] in
            await previous?.value
            await self?.forgetRecord()
        }
        tail = erase
        await erase.value
    }

    private func forgetRecord() async {
        record = nil
        await records.reset()
    }

    /// B6: the scene entered the background; the background refresh is requested again (it
    /// replaces the pending request) while the gate allows it.
    public func sceneDidEnterBackground() async {
        await requestBackgroundRefreshIfAllowed()
    }

    /// B6: a background run ended; the next one is requested while the gate allows it.
    public func backgroundRunFinished() async {
        await requestBackgroundRefreshIfAllowed()
    }

    // MARK: - Verification

    func verify(_ reason: Reason) async {
        await enqueue(reason).value
    }

    @discardableResult
    private func enqueue(_ reason: Reason) -> Task<Void, Never> {
        let previous = tail
        let next = Task { [weak self] in
            await previous?.value
            await self?.run(reason)
        }
        tail = next
        return next
    }

    private func run(_ reason: Reason) async {
        if reason == .launch {
            // The record first: the gate resolves within milliseconds of app init, before StoreKit.
            // The record carries no ownership (EntitlementRecord.swift), so the holding is unknown
            // until StoreKit's facts arrive below.
            record = await records.load().record
            let offline = record?.state(for: role, now: clock.now()) ?? .preview
            await apply(offline, holding: nil, verified: false)
        }
        let facts = await source.currentFacts()
        let verifiedAt = clock.now()
        let state = EntitlementPolicy.accountState(facts, role: role, products: products, now: verifiedAt)
        let holding = EntitlementPolicy.holding(facts, role: role, products: products, now: verifiedAt)
        let updated = (record ?? EntitlementRecord(verifiedAt: verifiedAt)).recording(state, for: role, verifiedAt: verifiedAt)
        do {
            try await records.save(updated)
            record = updated
        } catch {
            // The Keychain refused (before first unlock): the gate still has StoreKit's answer, and
            // the next verification writes the record.
        }
        await apply(state, holding: holding, verified: true)
        // Granted (recorded and gated): only now may StoreKit's unfinished transactions be finished.
        await source.finishUnfinished()
    }

    private func apply(_ state: EntitlementState, holding: SubscriptionHolding?, verified: Bool) async {
        await gate.update(state)
        if state.isActiveEntitlement { isPurchasePending = false }
        let current = Applied(remindersAllowed: await gate.allows(.reminders), entitledUntil: state.entitledUntil)
        let previous = applied
        applied = current
        if verified {
            let allowed = await gate.allows(.backgroundRefreshSchedule)
            // Only an entitlement requests the background refresh and only a lapse withdraws it. A
            // preview (StoreKit shows no transaction: never subscribed, or not readable yet, as
            // before the first unlock) leaves it as it is: a request it leaves behind runs into the
            // coordinator's own gate, and the next background entry asks the gate again.
            let decisive = allowed || state.isLapse
            if decisive, backgroundRequested != allowed {
                backgroundRequested = allowed
                if allowed {
                    await scheduler.schedule(earliestBegin: earliestBackgroundRefresh())
                } else {
                    await scheduler.cancel()
                }
            }
        }
        if let coordinator, let environment {
            if previous?.entitledUntil != current.entitledUntil, await coordinator.entitlementDidChange() {
                environment.reloadWidgets()
            }
            if let previous, previous.remindersAllowed != current.remindersAllowed {
                await ReminderPipeline.reconcile(coordinator: coordinator, environment: environment)
            }
        }
        status = SubscriptionStatus(accountState: state, holding: holding,
                                    isVerifiedThisLaunch: verified || (status?.isVerifiedThisLaunch ?? false),
                                    isPurchasePending: isPurchasePending)
        await publish()
    }

    private func publish() async {
        guard let status else { return }
        var current = status
        current.isPurchasePending = isPurchasePending
        self.status = current
        await observer?(current)
    }

    private func requestBackgroundRefreshIfAllowed() async {
        guard await gate.allows(.backgroundRefreshSchedule) else { return }
        await scheduler.schedule(earliestBegin: earliestBackgroundRefresh())
    }

    private func earliestBackgroundRefresh() -> Date {
        clock.now().addingTimeInterval(SubscriptionConfig.backgroundRefreshEarliestBegin.timeInterval)
    }
}

extension EntitlementState {
    /// A trial or subscription (not a preview, a lapse or sample data): Ask to Buy's pending flag
    /// clears on one.
    nonisolated var isActiveEntitlement: Bool {
        if case .entitled = self { return true }
        return false
    }

    /// A verified end of the trial or subscription (expired, refunded, revoked).
    nonisolated var isLapse: Bool {
        if case .lapsed = self { return true }
        return false
    }
}
