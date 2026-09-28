import Foundation
import TallyCanvasAPI
import TallyDomain

/// ASC-14 sample mode's data source (perf-app-runtime.md §2.1, §7 step 5). An actor: the bundled
/// replay, the DTO mapping, the date rebase and the change digest all run here, off the main
/// actor. Construction is pure; the gateway (bundle lookup and manifest decode) is built by the
/// first refresh, through `SampleDataCanvasGateway.make()`, which is `@concurrent`.
///
/// Sample data is never persisted and never reaches the background task or the "Refresh Tally"
/// intent (ASC-14's "no network calls in sample mode").
public actor SampleSession: HomeDataSource {
    private let clock: any DateProviding
    private let makeGateway: @Sendable () async throws -> any CanvasGateway
    /// When an in-flight refresh turns `.delayed` (`TallyConfig.liveRefreshBudget`; tests shorten it).
    private let liveRefreshBudget: Duration
    /// The one timer behind `.delayed` (`FreshnessRules.nextTransition`): no polling.
    private var delayedSignal: Task<Void, Never>?

    private var gateway: (any CanvasGateway)?
    private var snapshot: CanvasSnapshot?
    private var digest: ChangeDigest?
    private var digestAsOf: Date?
    private var generation: UInt64 = 0
    private var record = RefreshRecord()
    private var inFlight: Task<Void, Never>?
    private var subscribers: [UInt64: AsyncStream<HomeUpdate>.Continuation] = [:]
    private var nextSubscriberID: UInt64 = 0
    private var hasEnded = false

    /// The production sample session: the bundled flagship persona, never the network. `logger`
    /// receives the gateway's privacy-safe events (plan 06 A8).
    public init(clock: any DateProviding = SystemDateProvider(), logger: any TallyLogger = NoOpLogger()) {
        self.init(clock: clock, makeGateway: { try await SampleDataCanvasGateway.make(dateProvider: clock, logger: logger) })
    }

    /// Tests inject the gateway factory and the live-refresh budget.
    init(
        clock: any DateProviding, liveRefreshBudget: Duration = TallyConfig.liveRefreshBudget,
        makeGateway: @escaping @Sendable () async throws -> any CanvasGateway
    ) {
        self.clock = clock
        self.liveRefreshBudget = liveRefreshBudget
        self.makeGateway = makeGateway
    }

    public func updates() -> AsyncStream<HomeUpdate> {
        let (stream, continuation) = AsyncStream<HomeUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard !hasEnded else {
            continuation.finish()
            return stream
        }
        let id = nextSubscriberID
        nextSubscriberID &+= 1
        // Weak on both hops: a stream (held by whoever consumes it) never keeps the session alive.
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        continuation.yield(currentUpdate())
        return stream
    }

    public func refresh(_ trigger: RefreshTrigger) async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard !hasEnded else { return }
        let run = Task { await self.performRefresh(trigger) }
        inFlight = run
        await run.value
        inFlight = nil
    }

    public func end() {
        hasEnded = true
        inFlight?.cancel()
        delayedSignal?.cancel()
        let finishing = Array(subscribers.values)
        subscribers.removeAll()
        for continuation in finishing { continuation.finish() }
        snapshot = nil
        digest = nil
        digestAsOf = nil
        gateway = nil
    }

    private func performRefresh(_ trigger: RefreshTrigger) async {
        let now = clock.now()
        record.began(trigger, at: now)
        publish()
        scheduleDelayedSignal()
        defer { delayedSignal?.cancel() }
        do {
            #if DEBUG
            if generation > 0, let latency = Self.debugRefreshLatency {
                try await Task.sleep(for: latency)
            }
            #endif
            let gateway = try await resolvedGateway()
            let fetched = try await gateway.fetchSnapshot(previous: snapshot, now: now)
            guard !hasEnded else { return }
            // Off the main actor (perf-app-runtime.md §1.4 H7): the digest diffs two whole snapshots.
            let newDigest = ChangeDigest.diff(old: snapshot, new: fetched)
            snapshot = fetched
            generation &+= 1
            if !newDigest.isEmpty {
                digest = newDigest
                digestAsOf = fetched.fetchedAt
            }
            record.succeeded(dataFetchedAt: fetched.fetchedAt)
        } catch {
            guard !hasEnded else { return }
            record.failed(.unknown)
        }
        publish()
    }

    /// Publishes once the in-flight refresh crosses `liveRefreshBudget`, so subscribers see
    /// `.delayed` (and the breadcrumb) on time. It re-reads the transition after each sleep, so a
    /// sleep that wakes a little early against `clock` never loses the signal.
    private func scheduleDelayedSignal() {
        delayedSignal?.cancel()
        delayedSignal = Task { [weak self] in
            while let wait = await self?.secondsUntilFreshnessTransition() {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            await self?.publish()
        }
    }

    /// Seconds until the derived freshness changes without a new event, or `nil` once it has
    /// (or never will).
    private func secondsUntilFreshnessTransition() -> TimeInterval? {
        let now = clock.now()
        return FreshnessRules.nextTransition(of: record, after: now, budget: liveRefreshBudget)
            .map { $0.timeIntervalSince(now) }
    }

    #if DEBUG
    /// UI tests only: the launch argument `-TallyDebugSampleRefreshLatency <seconds>` delays every
    /// sample refresh after the first load, to exercise the slow-refresh path (perf-app-runtime.md
    /// §7 step 7: a 12-s slow refresh shows the breadcrumb, which then self-heals). Debug builds only.
    private static var debugRefreshLatency: Duration? {
        let seconds = UserDefaults.standard.double(forKey: "TallyDebugSampleRefreshLatency")
        return seconds > 0 ? .seconds(seconds) : nil
    }
    #endif

    private func resolvedGateway() async throws -> any CanvasGateway {
        if let gateway { return gateway }
        let made = try await makeGateway()
        gateway = made
        return made
    }

    private func currentUpdate() -> HomeUpdate {
        HomeUpdate(generation: generation, snapshot: snapshot, digest: digest, digestAsOf: digestAsOf,
                   freshness: FreshnessRules.state(of: record, now: clock.now(), budget: liveRefreshBudget))
    }

    private func publish() {
        guard !subscribers.isEmpty else { return }
        let update = currentUpdate()
        for continuation in subscribers.values { continuation.yield(update) }
    }

    private func removeSubscriber(_ id: UInt64) {
        subscribers[id] = nil
    }
}
