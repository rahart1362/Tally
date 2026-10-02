import Foundation
import Synchronization
import TallyDomain

/// What the subscription engine needs from StoreKit (PAY-03), as a port: TallyFeatures' engine is
/// tested with a scripted source, and `StoreKitEntitlementSource` is the real one (StoreKit 2, on
/// the device only, PRD §11.5).
public nonisolated protocol EntitlementSourcing: Sendable {
    /// Every transaction StoreKit holds for Tally's products, as plain values: the current
    /// entitlements and each product's latest transaction, with the subscription's status when
    /// StoreKit can say. Verified and unverified alike: the policy decides.
    func currentFacts() async -> [SubscriptionFacts]
    /// Finishes every unfinished verified transaction for Tally's products. The engine calls it
    /// only after it has granted what they carry (recorded and gated).
    func finishUnfinished() async
    /// Starts the `Transaction.updates` listener: for every verified update, `onUpdate` (the engine
    /// grants), then `finish()`. An unverified update is never granted and never finished. The
    /// engine calls this once, at app init.
    func listen(onUpdate: @escaping @Sendable () async -> Void) -> Task<Void, Never>
    /// A purchase of `productID`. On a verified success, `onGranted` runs before the transaction is
    /// finished.
    func purchase(_ productID: String, onGranted: @escaping @Sendable () async -> Void) async -> SubscriptionPurchaseOutcome
}

/// How a purchase ended (PAY-03). M3-B2's paywall words each one.
public nonisolated enum SubscriptionPurchaseOutcome: Sendable, Equatable {
    /// Verified, granted and finished.
    case purchased
    /// Ask to Buy: waiting for a parent's approval; it arrives later through `Transaction.updates`.
    case pending
    case cancelled
    /// StoreKit returned a transaction it could not verify: nothing granted.
    case unverified
    /// The product could not be loaded.
    case unavailable
    /// Any other failure (an interrupted purchase included: it completes later through
    /// `Transaction.updates` once the issue is resolved).
    case failed
}

/// One read of the Keychain record (PAY-04).
public nonisolated enum EntitlementRecordRead: Sendable, Equatable {
    case found(EntitlementRecord)
    case notFound
    /// The Keychain could not be read (before first unlock, or an error): nothing is known, so
    /// access fails closed until StoreKit answers.
    case unavailable

    public var record: EntitlementRecord? {
        if case .found(let record) = self { return record }
        return nil
    }
}

/// PAY-04: where the last verified entitlement is kept. The composition root injects
/// `KeychainEntitlementStore` (`TallyPlatform`, `AfterFirstUnlockThisDeviceOnly`).
public nonisolated protocol EntitlementRecordStoring: Sendable {
    func load() async -> EntitlementRecordRead
    func save(_ record: EntitlementRecord) async throws
    func reset() async
}

/// PAY-07 (perf-app-runtime.md §2.4 B6): the background-refresh request. The composition root
/// injects `BackgroundRefreshScheduler` (`TallyPlatform`, `BGTaskScheduler`).
public nonisolated protocol BackgroundRefreshScheduling: Sendable {
    /// Requests the next background refresh no earlier than `earliestBegin`, replacing any pending
    /// request (only one can be pending).
    func schedule(earliestBegin: Date) async
    /// Withdraws the pending request, if any.
    func cancel() async
    /// Whether a request is pending (what a lapse must leave false).
    func isScheduled() async -> Bool
}

/// An in-process record store: the default when the composition root injects none (tests,
/// previews). Nothing is persisted.
public nonisolated final class InMemoryEntitlementRecordStore: EntitlementRecordStoring {
    private let stored: Mutex<EntitlementRecord?>

    public init(_ record: EntitlementRecord? = nil) {
        stored = Mutex(record)
    }

    public func load() async -> EntitlementRecordRead {
        stored.withLock { $0.map(EntitlementRecordRead.found) ?? .notFound }
    }

    public func save(_ record: EntitlementRecord) async throws {
        stored.withLock { $0 = record }
    }

    public func reset() async {
        stored.withLock { $0 = nil }
    }
}

/// No StoreKit: no transactions, nothing to listen to, every purchase unavailable. The default
/// when the composition root injects no source (tests and previews that never buy).
public nonisolated struct NoEntitlementSource: EntitlementSourcing {
    public init() {}
    public func currentFacts() async -> [SubscriptionFacts] { [] }
    public func finishUnfinished() async {}
    public func listen(onUpdate: @escaping @Sendable () async -> Void) -> Task<Void, Never> { Task {} }
    public func purchase(_ productID: String, onGranted: @escaping @Sendable () async -> Void) async -> SubscriptionPurchaseOutcome {
        .unavailable
    }
}

/// No background refresh is requested (tests, previews).
public nonisolated struct NoBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    public init() {}
    public func schedule(earliestBegin: Date) async {}
    public func cancel() async {}
    public func isScheduled() async -> Bool { false }
}
