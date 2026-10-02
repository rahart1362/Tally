#if DEBUG
import StoreKit
import Testing
import TallyDomain
@testable import TallyFeatures

/// PAY-02's ownership input: how `StoreKitEntitlementSource` maps StoreKit's `ownershipType`. An
/// organization's assigned seat (raw value `"ASSIGNED"`, named `.assigned` only from the iOS 27 SDK)
/// entitles like a purchase (owner decision 2026-10-02); Family Sharing and any type this build does
/// not know never entitle (`EntitlementPolicy` rule 2).
@Suite("StoreKit ownership: purchases and assigned seats entitle, anything else fails closed")
struct SubscriptionOwnershipTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let type: Transaction.OwnershipType
        let expected: SubscriptionFacts.Ownership
        var testDescription: String { type.rawValue }
    }

    static let rows: [Row] = [
        Row(type: .purchased, expected: .purchased),
        Row(type: .familyShared, expected: .familyShared),
        Row(type: Transaction.OwnershipType(rawValue: "ASSIGNED"), expected: .assigned),
        Row(type: Transaction.OwnershipType(rawValue: "assigned"), expected: .other),
        Row(type: Transaction.OwnershipType(rawValue: "SOME_FUTURE_TYPE"), expected: .other),
    ]

    @Test("Each StoreKit ownership type maps to one plain value", arguments: rows)
    func maps(_ row: Row) {
        #expect(StoreKitEntitlementSource.ownership(row.type) == row.expected)
    }

    @Test("Only purchases and assigned seats can entitle")
    func entitling() {
        #expect(Self.rows.filter { StoreKitEntitlementSource.ownership($0.type).entitles }.map(\.type.rawValue)
            == [Transaction.OwnershipType.purchased.rawValue, "ASSIGNED"])
    }
}
#endif
