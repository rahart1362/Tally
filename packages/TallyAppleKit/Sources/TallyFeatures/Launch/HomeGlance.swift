import Foundation
import TallyDomain
import TallyStore

/// The first paint of a signed-in launch (perf-app-runtime.md §2.4 L4; decision D-P1): what the
/// sealed glance can show before the snapshot is decoded. The hero's averaged course count (its
/// percentage stays a skeleton until the full projection, D-P1; plan 08 §4.4 row 2:
/// `GlanceProjection.hero`), the due-soon rows with their course codes, and the "Updated <time>"
/// footer. Built off the main actor by `LaunchBootstrapper`.
///
/// Its freshness comes from the account's refresh record when one was written (O5, PERF-L), so the
/// first frame already says what the coordinator's first state will say (for example that the last
/// refresh found the device offline); with no record it is "fresh" at the glance's `asOf`.
///
/// The glance holds only the allow-listed fields (encryption.md §3.3): no course names, no grade
/// values unless the student opted in, titles cut to 40 characters. So every row here is a subset
/// of what the full projection shows a frame or so later, never something it contradicts.
public nonisolated struct HomeGlance: Equatable, Sendable {
    public let generation: UInt64
    /// The glance's `asOf`: the fetch time of the snapshot it was built from.
    public let asOf: Date
    public let dashboard: DashboardProjection
    public let freshness: FreshnessState

    /// Mirrors `DashboardBuilder`'s "Due soon" rule over the glance's items: due within the next
    /// 7 days, soonest first, at most 5 (DashboardProjection.swift `dueSoon`). `record` is the
    /// account's persisted refresh record, if any: the freshness is the coordinator's rule over the
    /// record it will start from (`RefreshStateStore.startingRecord`).
    public static func make(from glance: GlanceProjection, now: Date, record: RefreshRecord? = nil) -> HomeGlance {
        let horizon = now.addingTimeInterval(dueSoonWindow)
        let due = glance.dueSoon
            .filter { item in
                guard let dueAt = item.dueAt else { return false }
                return dueAt >= now && dueAt <= horizon
            }
            .prefix(dueSoonLimit)
            .map { DashboardProjection.DueItem(id: $0.id, title: $0.title, courseCode: $0.courseShortCode, dueAt: $0.dueAt) }
        let starting = RefreshStateStore.startingRecord(persisted: record, committedDataFetchedAt: glance.asOf)
        return HomeGlance(generation: glance.generation, asOf: glance.asOf,
                          dashboard: DashboardProjection(hero: DashboardProjection.Hero(courseCount: glance.courses.count, averagedCount: glance.courses.count, overallPercent: nil, overallBand: glance.overallGradeBand, exclusions: [:], school: .undetermined), nextUp: [], needsAttention: [],
                                                         dueSoon: Array(due),
                                                         weekAhead: [], changeDigestSummary: nil),
                          freshness: FreshnessRules.state(of: starting, now: now))
    }

    /// `DashboardBuilder`'s due-soon window (7 days) and row limit (5).
    static let dueSoonWindow: TimeInterval = 7 * 24 * 3600
    static let dueSoonLimit = 5
}
