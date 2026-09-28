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
}
