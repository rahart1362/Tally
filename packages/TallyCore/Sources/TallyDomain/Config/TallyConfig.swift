import Foundation

/// Every tunable number in Tally, named once (architecture.md §3.1).
/// Values marked UNVERIFIED are engineering estimates pending measurement.
public enum TallyConfig {
    // Refresh (kit 01 §3, 02 §4)
    public static let liveRefreshBudget: Duration = .seconds(10)
    public static let backgroundBudget: Duration = .seconds(25)
    public static let foregroundHardCeiling: Duration = .seconds(60)
    public static let minAutoRefreshInterval: Duration = .seconds(5 * 60)
    public static let bgEarliestBegin: Duration = .seconds(60 * 60)
    public static let staleWarningAfter: Duration = .seconds(24 * 60 * 60) // PMO R17

    // Canvas API
    public static let perPage = 100 // UNVERIFIED maximum
    public static let maxPagesPerResource = 50
    public static let maxConcurrentRequests = 3
    public static let lowQuotaThreshold = 100.0 // UNVERIFIED; X-Rate-Limit-Remaining units
    public static let backoffBase: Duration = .seconds(1)
    public static let contextCodesPerRequest = 10
    public static let plannerWindowDays = -14...60
    public static let announcementWindowDays = 14

    // Storage and performance
    public static let snapshotSizeBudgetBytes = 5 * 1024 * 1024
    public static let snapshotDecodeBudget: Duration = .milliseconds(100)
    public static let warmStartBudget: Duration = .milliseconds(300)

    // Notifications
    public static let pendingNotificationCap = 60 // headroom under iOS's ~64 (UNVERIFIED)
}

extension Duration {
    /// Seconds as `TimeInterval`, for `Date` arithmetic.
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
