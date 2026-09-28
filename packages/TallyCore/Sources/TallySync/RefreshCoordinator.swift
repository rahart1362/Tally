import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyStore

/// WP-D01 (architecture.md §3.4): the per-account refresh orchestrator. One instance owns one
/// account's `CanvasGateway` and `SnapshotStore` and is the single place that decides whether a
/// trigger starts a network fetch, tracks the account's monotonic generation and sign-out epoch,
/// and commits (or discards) whatever the fetch returns. Multi-account fan-out (D3b) wraps one
/// instance of this per account; that composition lives outside this file.
///
/// **Single-flight.** Every trigger that arrives while a fetch is already running joins that run:
/// `FreshnessRules.shouldStart` returns `false` for *any* trigger, manual included, whenever
/// `RefreshRecord.inFlightSince` is set, so at most one `CanvasGateway.fetchSnapshot` call is ever
/// in flight per account.
///
/// **Generations and epochs.** Each run that actually starts is stamped with
/// `committedGeneration + 1` at the moment it starts (a monotonically increasing counter this
/// coordinator alone owns) and captures the current `epoch`. `bumpEpochAndCancel()` (called by
/// `SignOutUseCase`, WP-SEC-06) bumps the epoch and best-effort cancels the fetch; when that run's
/// result later lands, `finish` discards it outright because its captured epoch no longer matches.
/// Separately, even within one epoch, a commit is only ever applied if its generation is still
/// greater than whatever is already committed — `SnapshotStore.commit` enforces this on disk as a
/// defensive backstop (`SnapshotStoreError.staleGeneration`), and this type honours the same rule
/// in memory first, so "a slow, older refresh can never overwrite a newer one" holds even if some
/// other writer committed a newer generation to the same store while this run's fetch was still
/// in flight.
///
/// **Subscribers and retirement (SH-1).** Every `events()` call gets its own stream, so any
/// number of consumers each see every event. `shutdown()` (which `bumpEpochAndCancel()` calls on
/// sign-out) retires the coordinator: it discards any run in flight, refuses new runs, finishes
/// every subscriber's stream and releases the decoded snapshot. A coordinator serves one
/// signed-in account once; the composition root makes a new one for the next sign-in.
public actor RefreshCoordinator {
    /// Emitted to every `events()` subscriber for the UI (one `RefreshStatusModel`, architecture
    /// §3.1, consumes this).
    public enum Event: Sendable, Equatable {
        case stateChanged(FreshnessState)
        /// A new generation landed in the store, with the digest against whatever was committed
        /// immediately before it (`.empty` for the account's very first snapshot).
        case committed(generation: UInt64, digest: ChangeDigest)
    }

    private let gateway: any CanvasGateway
    private let store: SnapshotStore
    private let clock: any DateProviding
    private let liveRefreshBudget: Duration
    private let foregroundHardCeiling: Duration
    private let backgroundBudget: Duration
    private let minAutoRefreshInterval: Duration

    private var record: RefreshRecord
    private var previousSnapshot: CanvasSnapshot?
    private var committedGeneration: UInt64
    /// The user's "What changed" thresholds (UserState.digestThresholds); applied at the next commit.
    private var digestThresholds: DigestThresholds = .default
    private var epoch: UInt64 = 0
    /// The task running this run's `supervise`/`finish` sequence end to end (what single-flight
    /// callers join). Distinct from `currentFetchTask`, the raw network call `bumpEpochAndCancel`
    /// also reaches for, since a plain `Task { }` is not a structured child of its creator and so
    /// is not automatically cancelled by cancelling the outer one.
    private var inFlight: Task<Void, Never>?
    private var currentFetchTask: Task<CanvasSnapshot, any Error>?

    /// SH-2: every caller suspended in `run` on the run in flight, keyed by an ID that is never
    /// reused. Resumed with `true` when the run finishes, or `false` when that caller is cancelled
    /// first. The count is the run's joiner count: its fetch is cancelled once it drops to zero.
    private var runWaiters: [UInt64: CheckedContinuation<Bool, Never>] = [:]
    private var nextWaiterID: UInt64 = 0
    /// Set once every caller waiting on the run in flight has been cancelled. `finish` then
    /// discards the run's outcome, and a caller arriving meanwhile waits the run out rather than
    /// joining it. Reset when the next run starts.
    private var runAbandoned = false

    /// One continuation per live `events()` subscriber, keyed by an ID that is never reused, so a
    /// subscriber's `onTermination` removes exactly its own entry and nobody else's.
    private var subscribers: [UInt64: AsyncStream<Event>.Continuation] = [:]
    private var nextSubscriberID: UInt64 = 0
    /// Set by `shutdown()` and never cleared.
    private var isShutDown = false

    /// Whether the glance projection built at commit time may include grade values
    /// (`UserState.showGradesInGlance`, encryption.md D-E3, PMO R10 — never defaulted to `true`).
    /// The composition root keeps this current from `UserStateStore`; that wiring lives outside
    /// this file, which only ever reads whatever value it was last given.
    public var includeGrades: Bool

    /// Called when the user changes the "What changed" threshold in Settings; the next commit uses it.
    public func updateDigestThresholds(_ thresholds: DigestThresholds) {
        digestThresholds = thresholds
    }

    public init(
        gateway: any CanvasGateway,
        store: SnapshotStore,
        clock: any DateProviding,
        initialSnapshot: CanvasSnapshot?,
        initialRecord: RefreshRecord = RefreshRecord(),
        includeGrades: Bool = false,
        liveRefreshBudget: Duration = TallyConfig.liveRefreshBudget,
        foregroundHardCeiling: Duration = TallyConfig.foregroundHardCeiling,
        backgroundBudget: Duration = TallyConfig.backgroundBudget,
        minAutoRefreshInterval: Duration = TallyConfig.minAutoRefreshInterval
    ) {
        self.gateway = gateway
        self.store = store
        self.clock = clock
        self.liveRefreshBudget = liveRefreshBudget
        self.foregroundHardCeiling = foregroundHardCeiling
        self.backgroundBudget = backgroundBudget
        self.minAutoRefreshInterval = minAutoRefreshInterval
        self.includeGrades = includeGrades
        previousSnapshot = initialSnapshot
        committedGeneration = initialSnapshot?.generation ?? 0
        record = initialRecord.restoredAfterLaunch() // no in-flight mark survives a relaunch
    }

    /// A coordinator released without `shutdown()` still ends every subscriber's `for await`
    /// loop, so a consumer that holds only its stream never waits forever on a dead actor.
    deinit {
        for continuation in subscribers.values { continuation.finish() }
    }

    /// The same derivation `FreshnessRules.state` would give a caller who read `events()` from the
    /// start; useful for a caller that only wants "what does the UI show right now".
    public var currentState: FreshnessState { FreshnessRules.state(of: record, now: clock.now()) }

    // MARK: - Subscribers (SH-1)

    /// A new, independent event stream for one subscriber. Its first element is
    /// `.stateChanged(currentState)`, so a subscriber never needs a separate `currentState` read
    /// and never replays a backlog from before it subscribed. After that it receives every event
    /// this coordinator emits; concurrent subscribers never split events between them. It buffers
    /// `.bufferingNewest(TallyConfig.refreshEventBufferLimit)`, so a subscriber that stops reading
    /// holds a bounded backlog. Cancelling the consuming task, or dropping the stream, removes
    /// only this subscriber. After `shutdown()`, the returned stream is already finished.
    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream(
            bufferingPolicy: .bufferingNewest(TallyConfig.refreshEventBufferLimit))
        guard !isShutDown else {
            continuation.finish()
            return stream
        }
        let id = nextSubscriberID
        nextSubscriberID &+= 1
        // Weak on both hops: a stream (held by whoever consumes it) must never keep this actor alive.
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in await self?.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        continuation.yield(.stateChanged(currentState))
        return stream
    }

    /// Retires this coordinator (SH-1). It discards any run in flight: the fetch is cancelled and
    /// a late result is never committed or held. Later `run` calls return without fetching, so a
    /// retired coordinator can never re-create a store that sign-out has purged. Every
    /// subscriber's stream finishes, later `events()` calls return an already-finished stream,
    /// and the decoded snapshot is released. Idempotent.
    public func shutdown() {
        isShutDown = true
        discardInFlightRun()
        let finishing = Array(subscribers.values)
        subscribers.removeAll()
        for continuation in finishing { continuation.finish() }
        previousSnapshot = nil
    }

    /// Sign-out or account removal (`SignOutUseCase`, WP-SEC-06, security.md §3.2 step 9): bumps
    /// the epoch so any in-flight (or already-landed-but-not-yet-finished) run's result is
    /// discarded, best-effort cancels the underlying fetch, resets the visible freshness state to
    /// `.noCache` — honest, since the account's cache is about to be purged by the rest of that
    /// use case anyway — and then `shutdown()`s, so every subscriber sees `.noCache` as its last
    /// event before its stream finishes. Does not itself touch the store, notifications or
    /// credentials. Idempotent.
    public func bumpEpochAndCancel() {
        discardInFlightRun()
        record = RefreshRecord()
        emit(.stateChanged(currentState))
        shutdown()
    }

    /// Makes the run in flight, if any, unable to land: its captured epoch no longer matches, so
    /// `finish` discards whatever it returns. Best-effort cancels its fetch as well, and drops the
    /// in-flight mark the same way a relaunch does, since that run will now never record an outcome.
    private func discardInFlightRun() {
        epoch += 1
        currentFetchTask?.cancel()
        inFlight?.cancel()
        record = record.restoredAfterLaunch()
    }

    private func removeSubscriber(_ id: UInt64) {
        subscribers[id] = nil
    }

    /// Live subscribers. Internal, for tests.
    var subscriberCount: Int { subscribers.count }

    /// Whether a decoded snapshot is still held. Internal, for tests.
    var holdsDecodedSnapshot: Bool { previousSnapshot != nil }

    /// Callers waiting on the run in flight. Internal, for tests.
    var waiterCount: Int { runWaiters.count }

    /// Starts a refresh for `trigger`, or joins one already running (single-flight). Returns once
    /// this call's own outcome is known: either the run it started, or the run it joined.
    ///
    /// **Cancellation (SH-2).** A cancelled caller stops waiting at once and returns
    /// `currentState` (usually still `.refreshing`). The run keeps going while any caller is still
    /// waiting on it; once every caller waiting on it has been cancelled, its fetch is cancelled
    /// and its outcome discarded (see `finish`). A caller that is already cancelled neither starts
    /// nor joins a run. One that arrives while an abandoned run winds down waits it out, then
    /// decides afresh. After `shutdown()`, returns `currentState` without fetching.
    @discardableResult
    public func run(trigger: RefreshTrigger) async -> FreshnessState {
        while !isShutDown, !Task.isCancelled {
            let runTask: Task<Void, Never>
            if let inFlight {
                runTask = inFlight
            } else {
                let now = clock.now()
                guard FreshnessRules.shouldStart(trigger, record: record, now: now, minInterval: minAutoRefreshInterval) else {
                    break
                }
                runTask = startRun(trigger: trigger, at: now)
            }
            // An abandoned run reports nothing, but it holds the single-flight slot until its
            // fetch winds down: wait it out, then go round again.
            let waitingOutAbandonedRun = runAbandoned
            await waitForRun(runTask)
            if !waitingOutAbandonedRun { break }
        }
        return currentState
    }

    // MARK: - One run

    /// Begins a run: records and publishes that it started, starts its fetch, and starts the task
    /// that supervises the fetch to the end. The fetch starts here, synchronously, not inside the
    /// supervising task, so it already exists by the time any caller waits on (or gives up on)
    /// this run: `callerCancelled` can always reach it.
    private func startRun(trigger: RefreshTrigger, at now: Date) -> Task<Void, Never> {
        let myEpoch = epoch
        let attemptGeneration = committedGeneration + 1
        record.began(trigger, at: now)
        emit(.stateChanged(currentState))
        runAbandoned = false

        let previous = previousSnapshot
        let fetchTask = Task<CanvasSnapshot, any Error> { [gateway, clock] in
            try await gateway.fetchSnapshot(previous: previous, now: clock.now())
        }
        currentFetchTask = fetchTask
        let runTask = Task { [weak self] in
            guard let self else { return }
            await self.superviseAndFinish(fetchTask, trigger: trigger, myEpoch: myEpoch, attemptGeneration: attemptGeneration)
        }
        inFlight = runTask
        return runTask
    }

    private func superviseAndFinish(_ fetchTask: Task<CanvasSnapshot, any Error>, trigger: RefreshTrigger,
                                    myEpoch: UInt64, attemptGeneration: UInt64) async {
        let outcome = await supervise(fetchTask, trigger: trigger)
        await finish(myEpoch: myEpoch, attemptGeneration: attemptGeneration, outcome: outcome)
        inFlight = nil
        currentFetchTask = nil
        let waiting = Array(runWaiters.values)
        runWaiters.removeAll()
        for continuation in waiting { continuation.resume(returning: true) }
    }

    /// Suspends until `runTask`'s run has finished or this caller is cancelled, whichever comes
    /// first. The cancellation handler cannot touch actor state itself, so it hops back on.
    private func waitForRun(_ runTask: Task<Void, Never>) async {
        let id = nextWaiterID
        nextWaiterID &+= 1
        let runFinished = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                runWaiters[id] = continuation
            }
        } onCancel: {
            Task { [weak self] in await self?.callerCancelled(id) }
        }
        // Resumed because the run finished: also let its task end, so that by the time `run`
        // returns normally, nothing of that run still holds this coordinator.
        if runFinished { await runTask.value }
    }

    /// A caller waiting on the run in flight was cancelled, so it stops waiting at once. If it
    /// was the last caller still waiting, nobody wants this run any more: the run is abandoned
    /// and its fetch cancelled. A run still shared with a caller that is waiting keeps going.
    private func callerCancelled(_ id: UInt64) {
        guard let continuation = runWaiters.removeValue(forKey: id) else { return } // the run already finished
        continuation.resume(returning: false)
        guard runWaiters.isEmpty else { return }
        runAbandoned = true
        currentFetchTask?.cancel()
    }

    /// Waits on the run's fetch, signalling `.delayed` at `liveRefreshBudget` **without**
    /// cancelling it, and giving up (cancelling) only once the trigger's own ceiling elapses —
    /// background triggers get `backgroundBudget` (≈25 s, inside the OS's ~30 s), everything else
    /// gets `foregroundHardCeiling` (architecture §3.4).
    private func supervise(_ fetchTask: Task<CanvasSnapshot, any Error>, trigger: RefreshTrigger)
        async -> Result<CanvasSnapshot, any Error> {
        if await timedOut(waitingFor: fetchTask, timeout: liveRefreshBudget) {
            emit(.stateChanged(.delayed(showing: record.lastSuccessAt)))
            let ceiling = trigger == .background ? backgroundBudget : foregroundHardCeiling
            let remaining = ceiling - liveRefreshBudget
            if remaining > .zero {
                if await timedOut(waitingFor: fetchTask, timeout: remaining) { fetchTask.cancel() }
            } else {
                fetchTask.cancel()
            }
        }

        do { return .success(try await fetchTask.value) }
        catch { return .failure(error) }
    }

    /// True if `timeout` elapsed before `task` finished. Never cancels `task` itself: only the
    /// losing side of the race — the timer, or the "wait for task" competitor — is cancelled, per
    /// `withTaskGroup`'s structured cancellation, which does not reach outside the group.
    private func timedOut<T: Sendable>(waitingFor task: Task<T, any Error>, timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = try? await task.value; return false }
            group.addTask { try? await Task.sleep(for: timeout); return true }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func finish(myEpoch: UInt64, attemptGeneration: UInt64, outcome: Result<CanvasSnapshot, any Error>) async {
        // A sign-out landed while this run was in flight: `bumpEpochAndCancel` already reset
        // `record` and published `.noCache`, so there is nothing left to do with this result.
        guard myEpoch == epoch else { return }

        // SH-2: every caller gave up on this run before it finished. Discard the outcome rather
        // than record it as a failure: under the existing mapping a cancelled fetch reports
        // `.offline` (CanvasClient maps every below-HTTP failure, cancellation included, to it)
        // or `.unknown`, and `FreshnessRules.state` would then tell the user they are offline,
        // or that refreshing failed, when all that happened is that they left. The record already
        // has a transition for a run that ended without an outcome, `restoredAfterLaunch()`: the
        // state reverts to the last real outcome, and `lastAttemptAt` stays, so
        // `FreshnessRules.shouldStart` still throttles automatic triggers by this attempt. A
        // success that beat the cancellation is discarded too: no caller is waiting for it.
        guard !runAbandoned else {
            record = record.restoredAfterLaunch()
            emit(.stateChanged(currentState))
            return
        }

        switch outcome {
        case .failure(let error):
            // The cache is never touched on failure (architecture §3.4).
            record.failed((error as? RefreshFailure) ?? .unknown)
            emit(.stateChanged(currentState))

        case .success(let fetched):
            guard attemptGeneration > committedGeneration else {
                // Another commit already landed a newer generation while this fetch was running.
                // Nothing to write, but valid fresher data exists, so the state still clears to fresh.
                record.succeeded(dataFetchedAt: clock.now())
                emit(.stateChanged(currentState))
                return
            }
            let restampedSnapshot = restamped(fetched, generation: attemptGeneration)
            // CS-05: degrade before persisting, not after — a snapshot that blew past the item
            // budget must never even reach `SnapshotStore`'s encode/seal path at full size.
            let stamped = SnapshotBudget.enforce(restampedSnapshot).snapshot
            let digest = ChangeDigest.diff(old: previousSnapshot, new: stamped, thresholds: digestThresholds)
            do {
                try await store.commit(stamped, includeGrades: includeGrades)
                committedGeneration = stamped.generation
                previousSnapshot = stamped
                record.succeeded(dataFetchedAt: stamped.fetchedAt)
                emit(.committed(generation: stamped.generation, digest: digest))
                emit(.stateChanged(currentState))
            } catch let error as SnapshotStoreError {
                switch error {
                case .staleGeneration(_, let current):
                    // The store's own backstop caught what our in-memory guard above did not: some
                    // other writer committed `current` (> our attempt) to this same account while
                    // we were fetching. Adopt it rather than treat this as a failure.
                    committedGeneration = current
                    if case .loaded(let onDisk) = await store.loadSnapshot() { previousSnapshot = onDisk }
                    record.succeeded(dataFetchedAt: clock.now())
                    emit(.stateChanged(currentState))
                }
            } catch {
                record.failed(.unknown)
                emit(.stateChanged(currentState))
            }
        }
    }

    /// The gateway stamps a placeholder generation (`(previous?.generation ?? 0) + 1`); this
    /// coordinator owns the real, monotonic counter, so every commit is re-stamped with it.
    private func restamped(_ snapshot: CanvasSnapshot, generation: UInt64) -> CanvasSnapshot {
        CanvasSnapshot(
            generation: generation, accountKey: snapshot.accountKey, host: snapshot.host, fetchedAt: snapshot.fetchedAt,
            profile: snapshot.profile, courses: snapshot.courses, groups: snapshot.groups,
            gradingPeriods: snapshot.gradingPeriods, planner: snapshot.planner, events: snapshot.events,
            announcements: snapshot.announcements, courseColors: snapshot.courseColors, sections: snapshot.sections)
    }

    /// Yields `event` to every live subscriber. Internal (not private) only so tests can drive the
    /// per-subscriber buffering bound directly.
    func emit(_ event: Event) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
