#if DEBUG
import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// Plan 07 M2-C1 L-3: the DEBUG live-instance counter behind "no `CanvasSnapshot` is reachable after
/// sign-out". Every test uses its own account key, so suites running in parallel never disturb
/// each other's counts.
@Suite("CanvasSnapshotInstances: a DEBUG live count per account")
struct CanvasSnapshotInstancesTests {
    private func uniqueAccount() -> AccountKey { AccountKey("instances-\(UUID().uuidString)") }

    @Test("making a snapshot counts one; copies share it; releasing every copy counts it out")
    func copiesShareOneCount() {
        let account = uniqueAccount()
        #expect(CanvasSnapshotInstances.liveCount(for: account) == 0)
        do {
            let snapshot = CanvasSnapshotFixture.make(accountKey: account)
            #expect(CanvasSnapshotInstances.liveCount(for: account) == 1)
            let copy = snapshot
            let copies = [copy, snapshot, copy]
            #expect(CanvasSnapshotInstances.liveCount(for: account) == 1, "a copy is the same value, not a new one")
            #expect(copies.count == 3)
            let second = CanvasSnapshotFixture.make(generation: 2, accountKey: account)
            #expect(CanvasSnapshotInstances.liveCount(for: account) == 2)
            withExtendedLifetime((snapshot, second)) {}
        }
        #expect(CanvasSnapshotInstances.liveCount(for: account) == 0)
    }

    @Test("decoding makes a new value; the encoded form carries no token and round-trips equal")
    func decodingCountsAndEncodingIsUnchanged() throws {
        let account = uniqueAccount()
        let original = CanvasSnapshotFixture.make(accountKey: account)
        let data = try JSONEncoder().encode(original)
        let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["schemaVersion", "generation", "accountKey", "host", "fetchedAt", "profile", "courses",
                              "groups", "gradingPeriods", "planner", "events", "announcements", "courseColors", "sections"])
        do {
            let decoded = try JSONDecoder().decode(CanvasSnapshot.self, from: data)
            #expect(decoded == original, "the token never takes part in equality")
            #expect(decoded.schemaVersion == CanvasSnapshot.currentSchemaVersion)
            withExtendedLifetime(decoded) {
                #expect(CanvasSnapshotInstances.liveCount(for: account) == 2)
            }
        }
        #expect(CanvasSnapshotInstances.liveCount(for: account) == 1)
        withExtendedLifetime(original) {}
    }

    @Test("a snapshot held by another value (an array, a box) stays counted until that holder goes")
    func heldSnapshotStaysCounted() {
        final class Holder { var snapshot: CanvasSnapshot?; init(_ s: CanvasSnapshot) { snapshot = s } }
        let account = uniqueAccount()
        var holder: Holder? = Holder(CanvasSnapshotFixture.make(accountKey: account))
        #expect(CanvasSnapshotInstances.liveCount(for: account) == 1)
        holder?.snapshot = nil
        #expect(CanvasSnapshotInstances.liveCount(for: account) == 0)
        holder = nil
        #expect(holder == nil)
    }
}
#endif
