import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// A `HomeDataSource` a test drives by hand: every `send` reaches every live subscriber.
actor FakeHomeSource: HomeDataSource {
    private var current: HomeUpdate
    private var continuations: [AsyncStream<HomeUpdate>.Continuation] = []

    init(_ initial: HomeUpdate) {
        current = initial
    }

    func updates() -> AsyncStream<HomeUpdate> {
        let (stream, continuation) = AsyncStream<HomeUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuations.append(continuation)
        continuation.yield(current)
        return stream
    }

    func refresh(_ trigger: RefreshTrigger) async {}

    func end() {
        for continuation in continuations { continuation.finish() }
        continuations.removeAll()
    }

    func send(_ update: HomeUpdate) {
        current = update
        for continuation in continuations { continuation.yield(update) }
    }
}

/// A source whose manual refresh takes `latency`, then lands the next generation (launch refreshes
/// land nothing). It records how many manual refreshes started, finished and were cancelled.
actor SlowHomeSource: HomeDataSource {
    private let fake: FakeHomeSource
    private let snapshot: CanvasSnapshot
    private let latency: Duration
    private var generation: UInt64 = 1
    private(set) var manualStarted = 0
    private(set) var manualLanded = 0
    private(set) var manualCancelled = 0

    init(snapshot: CanvasSnapshot, latency: Duration) {
        self.snapshot = snapshot
        self.latency = latency
        fake = FakeHomeSource(HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: HomeTestSupport.anchor)))
    }

    func updates() async -> AsyncStream<HomeUpdate> { await fake.updates() }

    func refresh(_ trigger: RefreshTrigger) async {
        guard trigger == .manual else { return }
        manualStarted += 1
        do {
            try await Task.sleep(for: latency)
        } catch {
            manualCancelled += 1
            return
        }
        generation += 1
        manualLanded += 1
        await fake.send(HomeTestSupport.update(snapshot, generation: generation,
                                               freshness: .fresh(at: HomeTestSupport.anchor.addingTimeInterval(60))))
    }

    func end() async { await fake.end() }
}

enum HomeTestSupport {
    /// The flagship persona's capture instant, so every section has items.
    static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    static func update(_ snapshot: CanvasSnapshot?, generation: UInt64, freshness: FreshnessState) -> HomeUpdate {
        HomeUpdate(generation: generation, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: freshness)
    }

    /// Polls `condition` on the main actor for up to `timeout`.
    @MainActor
    static func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

/// perf-app-runtime.md §7 step 6: `HomeModel` holds small projections built off the main actor,
/// re-projects exactly once when `validUntil` passes, and never shows an older generation over a
/// newer one.
@Suite("HomeModel: projections, validUntil, generations")
@MainActor
struct HomeModelTests {
    @Test("crossing validUntil recomputes exactly once; before it, nothing is recomputed")
    func crossingValidUntilRecomputesExactlyOnce() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: HomeTestSupport.anchor)
        let clock = TestClock(HomeTestSupport.anchor)
        let source = FakeHomeSource(HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: HomeTestSupport.anchor)))
        let projector = HomeProjector()
        let model = HomeModel(source: source, projector: projector, clock: clock)
        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })
        #expect(await projector.projectionCount == 1)

        let validUntil = model.validUntil
        #expect(validUntil > clock.now())
        await model.projectIfStale() // not stale yet
        #expect(await projector.projectionCount == 1)

        clock.advance(by: .seconds(validUntil.timeIntervalSince(clock.now()) + 1))
        await model.projectIfStale() // crossed: exactly one recompute
        #expect(await projector.projectionCount == 2)
        #expect(model.validUntil > clock.now())
        await model.projectIfStale() // the new validUntil is ahead again
        #expect(await projector.projectionCount == 2)
    }

    @Test("a projection from an older generation never replaces a newer one")
    func staleGenerationsAreDropped() async throws {
        let model = HomeModel(source: FakeHomeSource(HomeTestSupport.update(nil, generation: 0, freshness: .noCache)))
        func projection(_ generation: UInt64, courseCount: Int) -> HomeProjection {
            HomeProjection(
                generation: generation,
                dashboard: DashboardProjection(hero: .init(courseCount: courseCount, overallPercent: nil, overallBand: nil),
                                               nextUp: [], needsAttention: [], dueSoon: [], weekAhead: [],
                                               changeDigestSummary: nil),
                studentDisplayName: nil, greeting: .morning, courses: [], events: [], toDo: [],
                validUntil: .distantFuture)
        }
        model.apply(projection(2, courseCount: 7))
        model.apply(projection(1, courseCount: 3))
        #expect(model.dashboard.hero.courseCount == 7)
        model.apply(projection(3, courseCount: 9))
        #expect(model.dashboard.hero.courseCount == 9)
    }

    @Test("a freshness-only update changes freshness and never re-projects")
    func freshnessOnlyUpdatesDoNotReproject() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: HomeTestSupport.anchor)
        let source = FakeHomeSource(HomeTestSupport.update(snapshot, generation: 1, freshness: .refreshing(showing: nil)))
        let projector = HomeProjector()
        let model = HomeModel(source: source, projector: projector)
        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })

        await source.send(HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: HomeTestSupport.anchor)))
        #expect(try await HomeTestSupport.waitUntil { model.freshness == .fresh(at: HomeTestSupport.anchor) })
        #expect(await projector.projectionCount == 1)
    }

    // MARK: - Pull-to-refresh (perf-app-runtime.md §7 step 7, plan 06 row 7)

    private static func startedModel(latency: Duration) async throws -> (HomeModel, SlowHomeSource) {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: HomeTestSupport.anchor)
        let source = SlowHomeSource(snapshot: snapshot, latency: latency)
        let model = HomeModel(source: source)
        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })
        return (model, source)
    }

    /// Polls an actor-backed count until it reaches `expected`.
    private static func landed(_ source: SlowHomeSource, _ expected: Int) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while await source.manualLanded < expected {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test("pull-to-refresh returns at the live budget while a slow refresh runs; the refresh still lands")
    func pullToRefreshReturnsAtTheBudget() async throws {
        let (model, source) = try await Self.startedModel(latency: .milliseconds(900))
        let started = ContinuousClock.now
        await model.refreshUntilSettledOrDelayed(budget: .milliseconds(200))
        let waited = ContinuousClock.now - started
        #expect(waited >= .milliseconds(200) && waited < .milliseconds(800), "returned after \(waited)")
        #expect(await source.manualLanded == 0, "returned only once the refresh had landed")

        #expect(try await Self.landed(source, 1), "the refresh never landed")
        #expect(try await HomeTestSupport.waitUntil { model.freshness == .fresh(at: HomeTestSupport.anchor.addingTimeInterval(60)) })
        #expect(await model.projector.projectionCount == 2)
    }

    @Test("a fast refresh: pull-to-refresh returns as soon as it settles")
    func pullToRefreshReturnsWhenSettled() async throws {
        let (model, source) = try await Self.startedModel(latency: .milliseconds(50))
        let started = ContinuousClock.now
        await model.refreshUntilSettledOrDelayed(budget: .seconds(10))
        #expect(ContinuousClock.now - started < .seconds(3))
        #expect(await source.manualLanded == 1)
    }

    /// Plan 06 row 7 (SH-2): cancelling the only caller of `RefreshCoordinator.run` abandons the
    /// fetch, so the view's `.refreshable` task must never be the run's owner.
    @Test("cancelling the pull-to-refresh task ends the wait at once; the refresh still commits")
    func cancellingThePullDoesNotCancelTheRefresh() async throws {
        let (model, source) = try await Self.startedModel(latency: .milliseconds(500))
        let pull = Task { await model.refreshUntilSettledOrDelayed(budget: .seconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        let cancelledAt = ContinuousClock.now
        pull.cancel()
        await pull.value
        #expect(ContinuousClock.now - cancelledAt < .milliseconds(300), "the cancelled pull kept waiting")

        #expect(try await Self.landed(source, 1), "the refresh was abandoned with the view's task")
        #expect(await source.manualCancelled == 0)
    }

    @Test("a second pull and the hero's button join the refresh in flight; none cancels it")
    func manualRefreshesJoinTheRunInFlight() async throws {
        let (model, source) = try await Self.startedModel(latency: .milliseconds(300))
        model.requestRefresh()
        model.requestRefresh()
        async let pull: Void = model.refreshUntilSettledOrDelayed(budget: .seconds(10))
        await model.refresh()
        await pull
        #expect(await source.manualStarted == 1)
        #expect(await source.manualLanded == 1)
        #expect(await source.manualCancelled == 0)
    }
}
