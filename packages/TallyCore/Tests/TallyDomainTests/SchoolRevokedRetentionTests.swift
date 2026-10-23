import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// EB-26 (compliance-us §3): the automatic erase after the school has kept Tally continuously
/// disabled for `SubscriptionConfig.schoolRevokedRetentionDays`. Covers both halves: the record's
/// own `schoolDisabledSince` bookkeeping (`RefreshRecord.failed`/`succeeded`), and the pure
/// expiry rule built on it (`SchoolRevokedRetention.isExpired`).
@Suite("SchoolRevokedRetention: the automatic erase after a continuous school-revoked window")
struct SchoolRevokedRetentionTests {
    let clock = TestClock()

    // MARK: - RefreshRecord.schoolDisabledSince bookkeeping

    @Test func firstSchoolDisabledFailureStartsTheClock() {
        var record = RefreshRecord()
        let startedAt = clock.now()
        record.failed(.schoolDisabled, at: startedAt)
        #expect(record.schoolDisabledSince == startedAt)
    }

    @Test func aRepeatedSchoolDisabledFailureNeverMovesTheClockForward() {
        var record = RefreshRecord()
        let startedAt = clock.now()
        record.failed(.schoolDisabled, at: startedAt)
        clock.advance(by: .seconds(86_400))
        record.failed(.schoolDisabled, at: clock.now())
        #expect(record.schoolDisabledSince == startedAt, "a daily retry must not push the window out")
    }

    @Test func successClearsTheClock() {
        var record = RefreshRecord()
        record.failed(.schoolDisabled, at: clock.now())
        #expect(record.schoolDisabledSince != nil)
        record.succeeded(dataFetchedAt: clock.now())
        #expect(record.schoolDisabledSince == nil, "the school re-enabling Tally must reset the window")
    }

    @Test(arguments: RefreshFailure.allCases.filter { $0 != .schoolDisabled })
    func anyOtherFailureClearsTheClock(_ otherFailure: RefreshFailure) {
        var record = RefreshRecord()
        record.failed(.schoolDisabled, at: clock.now())
        record.failed(otherFailure, at: clock.now())
        #expect(record.schoolDisabledSince == nil, "\(otherFailure) must clear the school-revoked window")
    }

    // MARK: - SchoolRevokedRetention.isExpired

    @Test func neverRecordedIsNeverExpired() {
        #expect(!SchoolRevokedRetention.isExpired(RefreshRecord(), now: clock.now()))
    }

    @Test func exactlyAtTheWindowIsExpired() {
        var record = RefreshRecord()
        let startedAt = clock.now()
        record.failed(.schoolDisabled, at: startedAt)
        let atWindow = startedAt.addingTimeInterval(Double(SubscriptionConfig.schoolRevokedRetentionDays) * 86_400)
        #expect(SchoolRevokedRetention.isExpired(record, now: atWindow))
    }

    @Test func oneSecondBeforeTheWindowIsNotExpired() {
        var record = RefreshRecord()
        let startedAt = clock.now()
        record.failed(.schoolDisabled, at: startedAt)
        let justBefore = startedAt.addingTimeInterval(Double(SubscriptionConfig.schoolRevokedRetentionDays) * 86_400 - 1)
        #expect(!SchoolRevokedRetention.isExpired(record, now: justBefore))
    }

    @Test func aCustomRetentionWindowIsHonoured() {
        var record = RefreshRecord()
        let startedAt = clock.now()
        record.failed(.schoolDisabled, at: startedAt)
        #expect(SchoolRevokedRetention.isExpired(record, now: startedAt.addingTimeInterval(86_400), retentionDays: 1))
        #expect(!SchoolRevokedRetention.isExpired(record, now: startedAt.addingTimeInterval(86_399), retentionDays: 1))
    }

    @Test func zeroOrNegativeRetentionDaysNeverExpires() {
        var record = RefreshRecord()
        record.failed(.schoolDisabled, at: clock.now())
        clock.advance(by: .seconds(365 * 86_400))
        #expect(!SchoolRevokedRetention.isExpired(record, now: clock.now(), retentionDays: 0))
        #expect(!SchoolRevokedRetention.isExpired(record, now: clock.now(), retentionDays: -1))
    }
}
