import Foundation

/// Pure freshness rules. State is derived from facts plus "now", so the
/// 10-second rule needs one timer (`nextTransition`), not polling.
public enum FreshnessRules {
    public static func state(
        of record: RefreshRecord,
        now: Date,
        budget: Duration = TallyConfig.liveRefreshBudget
    ) -> FreshnessState {
        let showing = record.lastSuccessAt
        if let started = record.inFlightSince {
            let elapsed = now.timeIntervalSince(started)
            return elapsed >= budget.timeInterval ? .delayed(showing: showing) : .refreshing(showing: showing)
        }
        switch record.lastFailure {
        case .offline?: return .offline(showing: showing)
        case .authExpired?: return .authExpired(showing: showing)
        case let failure?: return .failed(failure, showing: showing)
        case nil: break
        }
        if let showing { return .fresh(at: showing) }
        return .noCache
    }

    /// The instant the derived state changes without a new event, if any.
    /// Only an in-flight refresh crossing the budget does.
    public static func nextTransition(
        of record: RefreshRecord,
        after now: Date,
        budget: Duration = TallyConfig.liveRefreshBudget
    ) -> Date? {
        guard let started = record.inFlightSince else { return nil }
        let deadline = started.addingTimeInterval(budget.timeInterval)
        return deadline > now ? deadline : nil
    }

    /// Manual refresh always runs. Automatic triggers join an in-flight run
    /// and are throttled by the last *attempt*, so an offline device is not hammered.
    public static func shouldStart(
        _ trigger: RefreshTrigger,
        record: RefreshRecord,
        now: Date,
        minInterval: Duration = TallyConfig.minAutoRefreshInterval
    ) -> Bool {
        if record.inFlightSince != nil { return false }
        if trigger == .manual { return true }
        guard let last = record.lastAttemptAt else { return true }
        return now.timeIntervalSince(last) >= minInterval.timeInterval
    }

    /// When the "data hasn't refreshed" warning is due (PMO R17), if there is data.
    public static func staleWarningDate(
        of record: RefreshRecord,
        after: Duration = TallyConfig.staleWarningAfter
    ) -> Date? {
        record.lastSuccessAt?.addingTimeInterval(after.timeInterval)
    }
}
