import Foundation

/// Every number the reminders feature uses that TallyCore's `InsightsConfig` does not already name
/// (insights-at-a-glance.md §3.3; ux-ui.md §3.2 stage 6).
public nonisolated enum RemindersConfig {
    /// §3.3 #4: the evening digest is sent "only if something is due in the next 48 h".
    public static let digestWindow: Duration = .seconds(48 * 60 * 60)
    /// §3.3 #5: the Sunday week-ahead summary counts the next 7 days.
    public static let weekAheadWindow: Duration = .seconds(7 * 24 * 60 * 60)
    /// "busiest Thursday" is named only when that day has at least this many items due.
    public static let busiestDayMinimum = 2
    /// ux-ui.md §3.2 stage 6: "If dismissed, the card doesn't return for 7 days."
    public static let tipSnooze: Duration = .seconds(7 * 24 * 60 * 60)
    /// A date this many days away (or less) is named by its weekday ("Fri at 11:59 PM"); beyond
    /// it, by month and day.
    public static let weekdayNamingDays = 6
}
