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

    /// The production sample session: the bundled flagship persona, never the network.
    public init(clock: any DateProviding = SystemDateProvider()) {
        self.init(clock: clock, makeGateway: { try await SampleDataCanvasGateway.make(dateProvider: clock) })
    }

    /// Tests inject the gateway factory.
    init(clock: any DateProviding, makeGateway: @escaping @Sendable () async throws -> any CanvasGateway) {
        self.clock = clock
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
        do {
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

    private func resolvedGateway() async throws -> any CanvasGateway {
        if let gateway { return gateway }
        let made = try await makeGateway()
        gateway = made
        return made
    }

    private func currentUpdate() -> HomeUpdate {
        HomeUpdate(generation: generation, snapshot: snapshot, digest: digest, digestAsOf: digestAsOf,
                   freshness: FreshnessRules.state(of: record, now: clock.now()))
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
