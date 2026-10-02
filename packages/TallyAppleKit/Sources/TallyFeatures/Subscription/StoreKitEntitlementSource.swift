import Foundation
import StoreKit
import Synchronization
import TallyDomain

/// PAY-03: StoreKit 2, on the device only (PRD §11.5: no server, no App Store Server API). Reads
/// every transaction for Tally's two products as plain `SubscriptionFacts` for
/// `EntitlementPolicy`; listens to `Transaction.updates`; buys.
///
/// - **Every `VerificationResult` is checked.** Unverified transactions are passed on marked
///   unverified (the policy never lets them entitle), and an unverified update or purchase is
///   never granted and never finished.
/// - **`finish()` only after granting:** an update or a purchase is finished after the engine's
///   verification has recorded and gated it. After each verification the engine drains the
///   unfinished queue (`finishUnfinished`), finishing only the transactions that verification read,
///   so a transaction that arrives in between waits for the verification that grants it.
/// - **Renewal and grace state** come from the subscription's status
///   (`Transaction.subscriptionStatus`, a `Product.SubscriptionInfo.Status`), trusted only when its
///   transaction verifies; the grace period's end only from verified renewal info.
/// - **Ask to Buy:** `purchase` returns `.pending`; the approval arrives through
///   `Transaction.updates`.
///
/// Not main-actor: StoreKit's sequences are iterated off the main actor.
public nonisolated final class StoreKitEntitlementSource: EntitlementSourcing {
    private let products: SubscriptionProducts
    /// The verified transactions the last `currentFacts()` read: what its verification granted.
    private let read = Mutex<Set<UInt64>>([])

    public init(products: SubscriptionProducts) {
        self.products = products
    }

    public func currentFacts() async -> [SubscriptionFacts] {
        var facts: [SubscriptionFacts] = []
        var verifiedIDs = Set<UInt64>()
        for await result in Transaction.currentEntitlements where isTally(result) {
            facts.append(await Self.facts(from: result))
            if case .verified(let transaction) = result { verifiedIDs.insert(transaction.id) }
        }
        // The latest transaction of each product, active or not: a refund, a revocation or an expiry
        // is what makes the state `.lapsed` rather than `.preview`.
        for productID in products.all {
            if let latest = await Transaction.latest(for: productID) {
                facts.append(await Self.facts(from: latest))
                if case .verified(let transaction) = latest { verifiedIDs.insert(transaction.id) }
            }
        }
        read.withLock { $0 = verifiedIDs }
        return facts
    }

    public func finishUnfinished() async {
        let granted = read.withLock { $0 }
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result, granted.contains(transaction.id) else { continue }
            await transaction.finish()
        }
    }

    public func listen(onUpdate: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let products = products
        return Task(priority: .utility) {
            for await result in Transaction.updates {
                // Checked: an unverified update is never granted and never finished.
                guard case .verified(let transaction) = result, products.role(of: transaction.productID) != nil else {
                    continue
                }
                await onUpdate() // granted: verified, recorded, gated
                await transaction.finish()
            }
        }
    }

    public func purchase(_ productID: String, onGranted: @escaping @Sendable () async -> Void) async -> SubscriptionPurchaseOutcome {
        let product: Product
        do {
            guard let found = try await Product.products(for: [productID]).first else { return .unavailable }
            product = found
        } catch {
            return .unavailable
        }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            return .failed
        }
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return .unverified }
            await onGranted()
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .failed
        }
    }

    private func isTally(_ result: VerificationResult<Transaction>) -> Bool {
        products.role(of: result.unsafePayloadValue.productID) != nil
    }

    /// One transaction as plain values. The status (renewal state, grace period) is read only for
    /// a verified transaction, and trusted only when the status's own transaction verifies.
    static func facts(from result: VerificationResult<Transaction>) async -> SubscriptionFacts {
        let transaction: Transaction
        let isVerified: Bool
        switch result {
        case .verified(let verified):
            transaction = verified
            isVerified = true
        case .unverified(let unverified, _):
            transaction = unverified
            isVerified = false
        }
        var renewalState: SubscriptionFacts.RenewalState?
        var graceEnds: Date?
        var signedDate = transaction.signedDate
        if isVerified, let status = await transaction.subscriptionStatus, case .verified = status.transaction {
            renewalState = Self.renewalState(status.state)
            if case .verified(let renewal) = status.renewalInfo {
                graceEnds = renewal.gracePeriodExpirationDate
                signedDate = max(signedDate, renewal.signedDate)
            }
        }
        return SubscriptionFacts(productID: transaction.productID, isVerified: isVerified,
                                 expirationDate: transaction.expirationDate, revocationDate: transaction.revocationDate,
                                 isUpgraded: transaction.isUpgraded, ownership: Self.ownership(transaction.ownershipType),
                                 renewalState: renewalState, gracePeriodExpirationDate: graceEnds, signedDate: signedDate)
    }

    static func renewalState(_ state: Product.SubscriptionInfo.RenewalState) -> SubscriptionFacts.RenewalState? {
        switch state {
        case .subscribed: .subscribed
        case .expired: .expired
        case .inBillingRetryPeriod: .inBillingRetryPeriod
        case .inGracePeriod: .inGracePeriod
        case .revoked: .revoked
        default: nil
        }
    }

    static func ownership(_ type: Transaction.OwnershipType) -> SubscriptionFacts.Ownership {
        switch type {
        case .purchased: .purchased
        case .familyShared: .familyShared
        default: .other
        }
    }
}
