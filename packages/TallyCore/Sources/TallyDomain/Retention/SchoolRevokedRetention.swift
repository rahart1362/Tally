import Foundation

/// EB-26 (compliance-us §3: "Retention after the school turns Tally off, or the subscription
/// lapses"; C.R.S. 6-1-1308.5(2)(a)(III); SOPIPA 22584(d) [S25]). Pure: given the persisted
/// `RefreshRecord` and the current time, says whether the automatic data erase is due. Never
/// erases, persists or schedules anything itself — `LaunchBootstrapper` reads this at launch, and
/// `AccountSignOut.eraseSavedData` does the actual purge, the same path "Erase Saved Data" uses.
public enum SchoolRevokedRetention {
    /// `true` once the school-revoked state has been continuous for at least `retentionDays`
    /// (`RefreshRecord.schoolDisabledSince`, started the first time a refresh fails with
    /// `.schoolDisabled` and left alone by every later one of the same kind). `false` while the
    /// state has never been recorded, or no longer is: `RefreshRecord.succeeded` and any other
    /// failure category clear `schoolDisabledSince`, so a school that re-enables Tally — even
    /// briefly — resets the clock, and the next continuous run starts over.
    public static func isExpired(_ record: RefreshRecord, now: Date,
                                 retentionDays: Int = SubscriptionConfig.schoolRevokedRetentionDays) -> Bool {
        guard let since = record.schoolDisabledSince, retentionDays > 0 else { return false }
        let window = Double(retentionDays) * 24 * 60 * 60
        return now.timeIntervalSince(since) >= window
    }
}
