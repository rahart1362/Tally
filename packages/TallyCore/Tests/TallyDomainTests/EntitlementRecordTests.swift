import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// PAY-04: the offline record and the one access rule for surfaces without StoreKit. Expiry and
/// grace at their boundaries, a clock set back, roles, and what the record may contain.
@Suite("EntitlementRecord and EntitlementAccess (PAY-04): expiry and the offline grace")
struct EntitlementRecordTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 60 * 60
    static let grace = SubscriptionConfig.offlineGracePeriod.timeInterval

    static func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

    @Test("Access fails closed exactly offlineGracePeriod after the expiry")
    func graceBoundary() {
        let until = Self.at(-Self.grace)
        #expect(!EntitlementAccess.covers(entitledUntil: until, at: Self.now, isEnforced: true), "at the boundary: locked")
        #expect(EntitlementAccess.covers(entitledUntil: until, at: Self.at(-1), isEnforced: true), "one second before: open")
        #expect(EntitlementAccess.covers(entitledUntil: Self.at(30 * Self.day), at: Self.now, isEnforced: true))
        #expect(EntitlementAccess.accessEnds(entitledUntil: until) == Self.now)
        #expect(EntitlementAccess.accessEnds(entitledUntil: nil) == nil)
    }

    @Test("No expiry: no access (fails closed)")
    func noExpiryNoAccess() {
        #expect(!EntitlementAccess.covers(entitledUntil: nil, at: Self.now, isEnforced: true))
    }

    @Test("A clock set back before a time the device reached cannot extend access")
    func clockSetBack() {
        let until = Self.at(-2 * Self.day) // within the grace at `now`
        #expect(EntitlementAccess.covers(entitledUntil: until, at: Self.now, isEnforced: true))
        // The device had already reached now + 2 days (the glance's asOf), then its clock went back.
        #expect(!EntitlementAccess.covers(entitledUntil: until, at: Self.now, notBefore: Self.at(2 * Self.day), isEnforced: true))
        // A notBefore in the past changes nothing.
        #expect(EntitlementAccess.covers(entitledUntil: until, at: Self.now, notBefore: Self.at(-10 * Self.day), isEnforced: true))
    }

    @Test("Not enforced (main until M3-B2): every surface is open, with or without an expiry")
    func notEnforcedIsOpen() {
        #expect(EntitlementAccess.covers(entitledUntil: nil, at: Self.now, isEnforced: false))
        #expect(EntitlementAccess.covers(entitledUntil: Self.at(-400 * Self.day), at: Self.now, isEnforced: false))
        #expect(SubscriptionConfig.isGatingEnforced == false, "the switch stays off on main until M3-B2 ships the paywall")
        #expect(EntitlementAccess.covers(entitledUntil: nil, at: Self.now), "the default follows the switch")
    }

    @Test("The record's state: entitled inside the grace, lapsed after it, preview without an expiry")
    func recordState() {
        let record = EntitlementRecord(studentUntil: Self.at(-Self.day), verifiedAt: Self.at(-2 * Self.day))
        #expect(record.state(for: .student, now: Self.now) == .entitled(until: Self.at(-Self.day)))
        #expect(record.state(for: .student, now: Self.at(-Self.day + Self.grace)) == .lapsed(since: Self.at(-Self.day)))
        #expect(record.state(for: .student, now: Self.at(-Self.day + Self.grace - 1)) == .entitled(until: Self.at(-Self.day)))
        #expect(record.state(for: .parent, now: Self.now) == .preview, "a student expiry never unlocks the parent role")
        #expect(EntitlementRecord(verifiedAt: Self.now).state(for: .student, now: Self.now) == .preview)
    }

    @Test("The record's state ignores a clock set back before its verification")
    func recordAntiRollback() {
        let record = EntitlementRecord(studentUntil: Self.at(-2 * Self.day), verifiedAt: Self.at(2 * Self.day))
        #expect(record.state(for: .student, now: Self.now) == .lapsed(since: Self.at(-2 * Self.day)))
    }

    @Test("Recording a verification: the role's expiry, or none; the other role kept; verifiedAt as measured")
    func recording() {
        let start = EntitlementRecord(studentUntil: Self.at(10 * Self.day), parentUntil: Self.at(20 * Self.day),
                                      verifiedAt: Self.at(5 * Self.day))
        let renewed = start.recording(.entitled(until: Self.at(375 * Self.day)), for: .student, verifiedAt: Self.now)
        #expect(renewed.studentUntil == Self.at(375 * Self.day))
        #expect(renewed.parentUntil == Self.at(20 * Self.day))
        #expect(renewed.verifiedAt == Self.now, "a clock once ahead must not lock the offline paths after it is corrected")
        let lapsed = renewed.recording(.lapsed(since: Self.at(-Self.day)), for: .student, verifiedAt: Self.now)
        #expect(lapsed.studentUntil == nil, "a verified lapse removes the expiry at once")
        #expect(lapsed.recording(.preview, for: .parent, verifiedAt: Self.now).parentUntil == nil)
    }

    @Test("The record holds expiry dates and a verification time only (encryption.md §3.3)")
    func recordKeys() throws {
        let record = EntitlementRecord(studentUntil: Self.now, parentUntil: Self.now, verifiedAt: Self.now)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any] ?? [:]
        #expect(Set(json.keys) == ["schemaVersion", "studentUntil", "parentUntil", "verifiedAt"])
        let decoded = try JSONDecoder().decode(EntitlementRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record && decoded.schemaVersion == 1)
    }
}

/// PAY-07: the gating table, every feature against every state, enforced and not.
@Suite("SubscriptionGate (PAY-07): the gating table")
struct SubscriptionGateTableTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    struct Row: Sendable, CustomTestStringConvertible {
        let state: EntitlementState
        let name: String
        /// What every gated feature answers in this state, enforced.
        let gated: Bool
        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(state: .demo, name: "demo (sample data)", gated: true),
        Row(state: .preview, name: "preview", gated: false),
        Row(state: .entitled(until: now.addingTimeInterval(30 * day)), name: "entitled, active", gated: true),
        Row(state: .entitled(until: now.addingTimeInterval(-2 * day)), name: "entitled, inside the offline grace", gated: true),
        Row(state: .entitled(until: now.addingTimeInterval(-3 * day)), name: "entitled, the grace just ended", gated: false),
        Row(state: .lapsed(since: now.addingTimeInterval(-60)), name: "lapsed", gated: false),
    ]

    static let alwaysAllowed: Set<SubscriptionFeature> = [.firstSync, .savedSnapshot, .signOutAndErase]

    @Test("Enforced: first sync, the saved snapshot and Sign out & erase always; the rest need access", arguments: rows)
    func enforced(_ row: Row) {
        let gate = SubscriptionGate(isEnforced: true)
        for feature in SubscriptionFeature.allCases {
            let expected = Self.alwaysAllowed.contains(feature) || row.gated
            #expect(gate.allows(feature, in: row.state, at: Self.now) == expected, "\(feature) in \(row.name)")
        }
    }

    @Test("Not enforced: every feature in every state", arguments: rows)
    func notEnforced(_ row: Row) {
        let gate = SubscriptionGate(isEnforced: false)
        for feature in SubscriptionFeature.allCases {
            #expect(gate.allows(feature, in: row.state, at: Self.now), "\(feature) in \(row.name)")
        }
    }

    @Test("Refresh: every trigger alike; the first sync (no committed snapshot) is free in every state",
          arguments: RefreshTrigger.allCases)
    func refresh(_ trigger: RefreshTrigger) {
        let gate = SubscriptionGate(isEnforced: true)
        for row in Self.rows {
            #expect(gate.allowsRefresh(trigger, hasCommittedSnapshot: false, in: row.state, at: Self.now), "\(row.name)")
            #expect(gate.allowsRefresh(trigger, hasCommittedSnapshot: true, in: row.state, at: Self.now) == row.gated,
                    "\(row.name)")
        }
    }

    @Test("The default gate follows the switch, which is off on main")
    func defaultFollowsTheSwitch() {
        #expect(SubscriptionGate().isEnforced == SubscriptionConfig.isGatingEnforced)
        #expect(SubscriptionGate().allows(.reminders, in: .lapsed(since: Self.now), at: Self.now))
    }
}

/// PAY-07: the app's stateful gate (an actor): the launch's wait for the first state, its timeout
/// (fails closed), updates, and the expiry the glance mirrors.
@Suite("EntitlementGate (PAY-07): the app's one gate", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct EntitlementGateTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let clock = FixedDate(now)

    struct FixedDate: DateProviding {
        let date: Date
        init(_ date: Date) { self.date = date }
        func now() -> Date { date }
    }

    @Test("Not enforced: allowed at once with no state, and the mirror is whatever state there is")
    func notEnforced() async {
        let gate = EntitlementGate(isEnforced: false, clock: Self.clock)
        #expect(await gate.allowsRefresh(.background, hasCommittedSnapshot: true))
        #expect(await gate.allows(.reminders))
        #expect(await gate.glanceEntitledUntil() == nil)
        await gate.update(.entitled(until: Self.now.addingTimeInterval(100)))
        #expect(await gate.glanceEntitledUntil() == Self.now.addingTimeInterval(100))
    }

    @Test("Enforced: a decision waits for the launch's first state, then answers from it")
    func waitsForTheFirstState() async {
        let gate = EntitlementGate(isEnforced: true, clock: Self.clock, resolutionTimeout: .seconds(30))
        let decision = Task { await gate.allowsRefresh(.launch, hasCommittedSnapshot: true) }
        let mirror = Task { await gate.glanceEntitledUntil() }
        try? await Task.sleep(for: .milliseconds(50))
        await gate.update(.entitled(until: Self.now.addingTimeInterval(3_600)))
        #expect(await decision.value)
        #expect(await mirror.value == Self.now.addingTimeInterval(3_600))
        #expect(await gate.current == .entitled(until: Self.now.addingTimeInterval(3_600)))
    }

    @Test("Enforced: with no state by the timeout, it fails closed (the first sync stays free)")
    func timeoutFailsClosed() async {
        let gate = EntitlementGate(isEnforced: true, clock: Self.clock, resolutionTimeout: .milliseconds(20))
        #expect(await gate.allowsRefresh(.manual, hasCommittedSnapshot: true) == false)
        #expect(await gate.allowsRefresh(.manual, hasCommittedSnapshot: false))
        #expect(await gate.allows(.reminders) == false)
        #expect(await gate.allows(.signOutAndErase))
        #expect(await gate.glanceEntitledUntil() == nil)
    }

    @Test("Enforced: a lapse refuses refresh, reminders and the background schedule; Sign out & erase stays")
    func lapseRefuses() async {
        let gate = EntitlementGate(isEnforced: true, clock: Self.clock, state: .entitled(until: Self.now.addingTimeInterval(60)))
        #expect(await gate.allows(.reminders))
        await gate.update(.lapsed(since: Self.now))
        for trigger in RefreshTrigger.allCases {
            #expect(await gate.allowsRefresh(trigger, hasCommittedSnapshot: true) == false, "\(trigger)")
        }
        #expect(await gate.allows(.reminders) == false)
        #expect(await gate.allows(.backgroundRefreshSchedule) == false)
        #expect(await gate.allows(.savedSnapshot))
        #expect(await gate.allows(.signOutAndErase))
        #expect(await gate.glanceEntitledUntil() == nil, "a lapse mirrors no expiry: the widgets lock at once")
    }

    @Test("Ungated (tests, previews): everything allowed, nothing mirrored")
    func ungated() async {
        let gate = UngatedEntitlement()
        #expect(await gate.allowsRefresh(.intent, hasCommittedSnapshot: true))
        #expect(await gate.allows(.widgetData))
        #expect(await gate.glanceEntitledUntil() == nil)
    }
}
