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
    /// Hard cap on one HTTP response body (CS-05, crash-safety.md): a real Canvas page is a
    /// few hundred KB at most (`perPage` items); this is generous headroom, not a realistic
    /// size, so it only ever rejects a runaway or hostile response before it reaches a mapper.
    public static let maxResponseBodyBytes = 10 * 1024 * 1024

    // Storage and performance
    public static let snapshotSizeBudgetBytes = 5 * 1024 * 1024
    public static let snapshotDecodeBudget: Duration = .milliseconds(100)
    public static let warmStartBudget: Duration = .milliseconds(300)
    /// Total items (courses + assignments + planner + events + announcements) a snapshot may
    /// carry before `SnapshotBudget` degrades it (CS-05). The charter's synthetic stress
    /// persona is ~20 courses x 250 assignments (~5,000 items); this leaves wide headroom
    /// while still bounding worst-case memory from a corrupt or adversarial account.
    public static let maxSnapshotItems = 20_000

    // Notifications
    public static let pendingNotificationCap = 60 // headroom under iOS's ~64 (UNVERIFIED)

    // Change digest (WP-A07, architecture §3.4: "course-score deltas at or above a threshold")
    /// Percentage points. A course-level score move smaller than this (e.g. a 0.01 pt
    /// rounding change) never appears in the "What changed" digest; engineering choice,
    /// not from a PMO ruling — the AlertEngine A6 thresholds are for a different signal
    /// (a health alert on a *drop*, one-directional) and are not reused here, since the
    /// digest reports any clearing move, a rise or a fall.
    public static let courseScoreChangeThreshold: Double = 0.5

    // App lock (ADR 0001, security.md WP-SEC-07): re-lock grace period after backgrounding.
    public static let appLockGraceImmediately: Duration = .zero
    public static let appLockGraceOneMinute: Duration = .seconds(60) // ADR 0001 default
    public static let appLockGraceFiveMinutes: Duration = .seconds(5 * 60)
    public static let appLockGraceFifteenMinutes: Duration = .seconds(15 * 60)

    // Family linking (family-linking.md §6.7): client-side write-amplification throttle —
    // "at most 5 invite codes per student per day" — enforced locally before W1 is ever called.
    public static let maxInvitesPerDay = 5
    public static let invitesPerDayWindow: Duration = .seconds(24 * 60 * 60)
}

extension Duration {
    /// Seconds as `TimeInterval`, for `Date` arithmetic.
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
