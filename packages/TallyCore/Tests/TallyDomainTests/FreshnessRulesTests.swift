import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("FreshnessRules: 10-second live-refresh budget")
struct FreshnessRulesTests {
    let clock = TestClock()

    private func record(successAt: Date? = nil) -> RefreshRecord {
        var r = RefreshRecord()
        if let successAt { r.succeeded(dataFetchedAt: successAt) }
        return r
    }

    @Test func noDataMeansNoCache() {
        #expect(FreshnessRules.state(of: RefreshRecord(), now: clock.now()) == .noCache)
    }

    @Test func delayedAtExactlyTheBudgetNotBefore() {
        let saved = clock.now().addingTimeInterval(-3600)
        var r = record(successAt: saved)
        let start = clock.now()
        r.began(.launch, at: start)
        #expect(FreshnessRules.state(of: r, now: start.addingTimeInterval(9.999)) == .refreshing(showing: saved))
        let atBudget = FreshnessRules.state(of: r, now: start.addingTimeInterval(10))
        #expect(atBudget == .delayed(showing: saved))
        #expect(atBudget.showsStaleBreadcrumb)
    }

    @Test func slowFirstSyncHasNoBreadcrumb() {
        var r = RefreshRecord()
        r.began(.launch, at: clock.now())
        let state = FreshnessRules.state(of: r, now: clock.now().addingTimeInterval(30))
        #expect(state == .delayed(showing: nil))
        #expect(!state.showsStaleBreadcrumb)
    }

    @Test func lateSuccessClearsDelayed() {
        var r = record(successAt: clock.now())
        r.began(.manual, at: clock.now())
        clock.advance(by: .seconds(25))
        #expect(FreshnessRules.state(of: r, now: clock.now()).showsStaleBreadcrumb)
        r.succeeded(dataFetchedAt: clock.now())
        #expect(FreshnessRules.state(of: r, now: clock.now()) == .fresh(at: clock.now()))
    }

    @Test(arguments: RefreshFailure.allCases)
    func failuresKeepSavedDataVisible(_ failure: RefreshFailure) {
        let saved = clock.now()
        var r = record(successAt: saved)
        r.began(.foreground, at: clock.now())
        r.failed(failure)
        let state = FreshnessRules.state(of: r, now: clock.now())
        #expect(state.showing == saved)
        #expect(state.showsStaleBreadcrumb)
        switch failure {
        case .offline: #expect(state == .offline(showing: saved))
        case .authExpired: #expect(state == .authExpired(showing: saved))
        default: #expect(state == .failed(failure, showing: saved))
        }
    }

    @Test func successNeverMovesBackwards() {
        let newer = clock.now()
        var r = record(successAt: newer)
        r.succeeded(dataFetchedAt: newer.addingTimeInterval(-60))
        #expect(r.lastSuccessAt == newer)
    }

    @Test func oneTimerAtTheBudgetDeadline() {
        var r = RefreshRecord()
        #expect(FreshnessRules.nextTransition(of: r, after: clock.now()) == nil)
        let start = clock.now()
        r.began(.launch, at: start)
        #expect(FreshnessRules.nextTransition(of: r, after: start) == start.addingTimeInterval(10))
        #expect(FreshnessRules.nextTransition(of: r, after: start.addingTimeInterval(10)) == nil)
    }

    @Test func autoRefreshIsThrottledManualIsNot() {
        var r = RefreshRecord()
        #expect(FreshnessRules.shouldStart(.launch, record: r, now: clock.now()))
        r.began(.launch, at: clock.now())
        #expect(!FreshnessRules.shouldStart(.manual, record: r, now: clock.now()), "joins in-flight run")
        r.failed(.offline)
        clock.advance(by: .seconds(60))
        #expect(!FreshnessRules.shouldStart(.foreground, record: r, now: clock.now()))
        #expect(FreshnessRules.shouldStart(.manual, record: r, now: clock.now()))
        clock.advance(by: .seconds(240))
        #expect(FreshnessRules.shouldStart(.foreground, record: r, now: clock.now()))
    }

    @Test func relaunchDropsInFlightAndRoundTrips() throws {
        var r = record(successAt: clock.now())
        r.began(.background, at: clock.now())
        let restored = try JSONDecoder().decode(RefreshRecord.self, from: JSONEncoder().encode(r)).restoredAfterLaunch()
        #expect(restored.inFlightSince == nil)
        #expect(FreshnessRules.state(of: restored, now: clock.now()) == .fresh(at: clock.now()))
        #expect(FreshnessRules.staleWarningDate(of: restored) == clock.now().addingTimeInterval(86_400))
    }
}
