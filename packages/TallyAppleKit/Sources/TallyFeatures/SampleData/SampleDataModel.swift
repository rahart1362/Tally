import Foundation
import TallyCanvasAPI
import TallyDomain

/// ASC-14: the in-memory, session-scoped state behind "Explore with Sample Data". Deliberately
/// does **not** go through `TallyStore`'s `SnapshotStore`/vault: sample data is never persisted
/// (there is nothing to protect, nothing to survive a relaunch — re-fetching the bundled replay
/// on every entry is both simpler and safer than teaching the real account's on-disk store about
/// a second, fake account), and it deliberately does **not** route through `AppModel`'s
/// `RefreshCoordinator` or the background task / Siri intent (`RefreshIntentBridge`): sample mode
/// must never be reachable from either, keeping "no network calls in sample mode" trivially true
/// by construction rather than by a runtime check alone.
///
/// Still reuses every pure rule the real Dashboard will: `FreshnessRules`/`RefreshRecord` for the
/// footer, `ChangeDigest` for the digest chip, and (via `DashboardBuilder`) the same
/// `PriorityScore`/`AlertEngine` this session's `DashboardView` renders.
@MainActor
@Observable
public final class SampleDataModel {
    public private(set) var snapshot: CanvasSnapshot?
    public private(set) var freshness: FreshnessState = .noCache
    public private(set) var digest: ChangeDigest?
    public private(set) var digestAsOf: Date?

    private let gateway: any CanvasGateway
    private let clock: any DateProviding
    private var record = RefreshRecord()
    private var isRefreshing = false

    public init(gateway: any CanvasGateway, clock: any DateProviding = SystemDateProvider()) {
        self.gateway = gateway
        self.clock = clock
    }

    /// The production entry point: the bundled flagship persona over a replay transport
    /// (`SampleDataCanvasGateway`), never the network.
    public static func live() throws -> SampleDataModel {
        usleep(60_000) // MUTATION M4b: a 60 ms main-actor stall on the sample path
        return SampleDataModel(gateway: try SampleDataCanvasGateway())
    }

    public var studentDisplayName: String? { snapshot?.profile.shortName ?? snapshot?.profile.name }

    /// Called once when sample mode is entered, and again for pull-to-refresh / the footer's
    /// button — both call this one method (ux-ui.md §3.3: "Both call the same single-flight
    /// refresh"), matching `RefreshStatusModel.refresh()`'s shape even though there is no
    /// `RefreshCoordinator` underneath it here.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = clock.now()
        record.began(.manual, at: now)
        freshness = FreshnessRules.state(of: record, now: now)

        do {
            let fetched = try await gateway.fetchSnapshot(previous: snapshot, now: now)
            let newDigest = ChangeDigest.diff(old: snapshot, new: fetched)
            snapshot = fetched
            if !newDigest.isEmpty {
                digest = newDigest
                digestAsOf = fetched.fetchedAt
            }
            record.succeeded(dataFetchedAt: fetched.fetchedAt)
        } catch {
            record.failed(.unknown)
        }
        freshness = FreshnessRules.state(of: record, now: clock.now())
    }
}
