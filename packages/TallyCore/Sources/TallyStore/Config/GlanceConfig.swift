import TallyDomain

/// WP-C03's named constants, on the shared `TallyConfig` (see `StoreConfig.swift` for why this
/// extends rather than edits `TallyDomain`'s `TallyConfig.swift`).
extension TallyConfig {
    /// Glance is "a few KB" (architecture.md §3.3); this is the budget WP-C03 must stay under.
    public static let glanceSizeBudgetBytes = 16 * 1024

    /// At most this many "due soon" items ride along in the glance (encryption.md §3.3 allowlist).
    public static let glanceDueItemLimit = 8

    /// Of those, this many stay for open overdue items when upcoming ones would fill every slot:
    /// the widget counts them ("N overdue"), and the launch paint's 5 "Due soon" rows
    /// (`HomeGlance.dueSoonLimit`) still fit in the rest.
    public static let glanceOverdueItemReserve = 3

    /// Planner/assignment titles in the glance are truncated to this length (encryption.md §3.3).
    public static let glanceTitleMaxLength = 40
}
