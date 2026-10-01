import Foundation

/// Which plan an entitlement is for (PRD §11.1, §11.9). Each role has its own product in its own
/// subscription group, so a person can hold both plans; a parent plan never unlocks the student
/// role, and a student plan never unlocks the parent (observer) role. The parent role's screens
/// are M3-E's; the engine carries the role so they inherit the rule.
public enum SubscriptionRole: String, Codable, Sendable, CaseIterable {
    case student
    case parent
}

/// PAY-01: Tally's two auto-renewable products, whose IDs derive from the app's bundle ID
/// (`Identity.xcconfig`: `$(TALLY_BUNDLE_ID_PREFIX).tally`). `Products.storekit` defines the same
/// two IDs, and `scripts/ci/check_storekit_products.py` checks that its prefix matches
/// `Identity.xcconfig` and its suffixes match `SubscriptionConfig`.
public struct SubscriptionProducts: Sendable, Equatable {
    /// The app's bundle ID, e.g. `dev.tally-app.tally`.
    public let bundleID: String

    public init(bundleID: String) {
        self.bundleID = bundleID
    }

    /// "Tally Annual": `<bundle-id>.annual`.
    public var studentAnnual: String { bundleID + SubscriptionConfig.studentAnnualSuffix }
    /// "Tally Parent": `<bundle-id>.parent.annual`.
    public var parentAnnual: String { bundleID + SubscriptionConfig.parentAnnualSuffix }

    /// Both product IDs, student first.
    public var all: [String] { [studentAnnual, parentAnnual] }

    public func productID(for role: SubscriptionRole) -> String {
        switch role {
        case .student: studentAnnual
        case .parent: parentAnnual
        }
    }

    /// The role `productID` unlocks, by exact match only: the parent ID also ends in ".annual", so
    /// a suffix test would read a parent purchase as a student one.
    public func role(of productID: String) -> SubscriptionRole? {
        SubscriptionRole.allCases.first { self.productID(for: $0) == productID }
    }
}
