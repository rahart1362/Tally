import Foundation
import Observation
import Synchronization
import TallyDomain

/// The Home shell's model (perf-app-runtime.md §2.1, §7 step 6). Main-actor and `@Observable`, but
/// it stores only small `Equatable` projections, never a `CanvasSnapshot`; every property is set
/// only when it changed, so an unchanged refresh re-renders nothing, and a view that reads one
/// property is invalidated by that property alone.
///
/// Updates flow `HomeDataSource` → `HomeProjector` (an actor: the dashboard build and every row
/// run off the main actor) → here. A projection built from an older generation than the one on
/// screen is dropped.
@MainActor
@Observable
public final class HomeModel {
    public enum Phase: Equatable, Sendable {
        /// Waiting for the first projection: the shell shows skeletons.
        case loading
        case loaded
        /// The first load failed with nothing to show.
        case failed
    }

    public private(set) var phase: Phase = .loading
    public private(set) var dashboard: DashboardProjection = .empty
    public private(set) var studentDisplayName: String?
    public private(set) var greeting: HomeProjection.Greeting = .morning
    public private(set) var courses: [HomeProjection.CourseRow] = []
    public private(set) var events: [HomeProjection.EventRow] = []
    public private(set) var toDo: [HomeProjection.ToDoRow] = []
    public private(set) var freshness: FreshnessState = .noCache
    /// When the on-screen projection goes stale by itself; the shell re-projects then.
    public private(set) var validUntil: Date = .distantFuture

    /// Internal so lifecycle tests can hold weak references.
    let source: any HomeDataSource
    let projector: HomeProjector
    private let clock: any DateProviding
    private let subscription = TaskBox()
    private let timeChanges = TaskBox()
    /// Owns the manual refresh run (pull-to-refresh and the hero's button), so it ends with the
    /// model, never with a view (plan 06 row 7, SH-2: cancelling the only caller of
    /// `RefreshCoordinator.run` abandons the fetch). `manualRun` lets a second pull or tap join the
    /// run already going instead of starting, or cancelling, one.
    private let manualRunOwner = TaskBox()
    @ObservationIgnored private var manualRun: Task<Void, Never>?
    /// The generation on screen, and the newest one handed to the projector.
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var installedGeneration: UInt64 = 0
    @ObservationIgnored private var hasStarted = false

    public init(source: any HomeDataSource, projector: HomeProjector = HomeProjector(),
                clock: any DateProviding = SystemDateProvider()) {
        self.source = source
        self.projector = projector
        self.clock = clock
    }

    /// Subscribes to the source, then loads. Runs once, from the shell's `.task`.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        let updates = await source.updates()
        subscription.replace(with: Task { [weak self] in
            for await update in updates {
                await self?.receive(update)
            }
        })
        await source.refresh(.launch)
    }

    /// The day, the wall clock or the time zone changed (the shell forwards the system
    /// notifications): every date-relative row may be wrong, so project again now.
    public func clockDidChange() {
        timeChanges.replace(with: Task { [weak self] in
            await self?.reproject()
        })
    }

    /// A manual refresh, awaited to the end. It runs in the task this model owns, so cancelling
    /// the caller stops only the waiting, never the refresh.
    public func refresh() async {
        await manualRefreshRun().value
    }

    /// The hero's refresh button (perf-app-runtime.md §1.4 H9): starts the manual refresh, or joins
    /// the one already going. Never an unstructured `Task` in the view.
    public func requestRefresh() {
        _ = manualRefreshRun()
    }

    /// Pull-to-refresh (perf-app-runtime.md §7 step 7): returns when the refresh settles or after
    /// `budget` (`TallyConfig.liveRefreshBudget`, 10 s), whichever comes first, so the spinner never
    /// runs to the 60 s ceiling; by then the freshness is `.delayed` and the breadcrumb takes over.
    /// The refresh keeps going in the task this model owns and the screen self-heals when it
    /// lands. If the caller (`.refreshable`'s task) is cancelled, it stops waiting at once and the
    /// refresh still runs to its commit.
    public func refreshUntilSettledOrDelayed(budget: Duration = TallyConfig.liveRefreshBudget) async {
        let run = manualRefreshRun()
        let gate = ResumeGate()
        await withTaskCancellationHandler {
            // Not a task group: a group waits for every child, and `run.value` never ends early,
            // so a group would always wait for the refresh. Whichever finishes first opens the gate.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.install(continuation)
                let timer = Task {
                    do { try await Task.sleep(for: budget) } catch { return } // cancelled: the run won
                    gate.open()
                }
                Task {
                    await run.value
                    timer.cancel()
                    gate.open()
                }
            }
        } onCancel: {
            gate.open()
        }
    }

    /// The manual refresh in flight, or a new one: `source.refresh(.manual)` in a task this model
    /// owns (`manualRunOwner`), which only `end()` cancels.
    private func manualRefreshRun() -> Task<Void, Never> {
        if let manualRun { return manualRun }
        let run = Task { [weak self, source] in
            await source.refresh(.manual)
            self?.manualRun = nil
        }
        manualRun = run
        manualRunOwner.replace(with: run)
        return run
    }

    /// Re-projects only if `validUntil` has passed (the shell's `.task(id: validUntil)` timer, and
    /// the scene becoming active after a while in the background).
    public func projectIfStale() async {
        guard clock.now() >= validUntil else { return }
        await reproject()
    }

    /// Sleeps until `validUntil`, then re-projects if it is still due. Cancelled (and restarted) by
    /// the shell's `.task(id: validUntil)` whenever `validUntil` changes.
    public func reprojectWhenStale() async {
        let delay = validUntil.timeIntervalSince(clock.now())
        if delay > 0 {
            guard delay.isFinite else { return }
            try? await Task.sleep(for: .seconds(delay))
        }
        guard !Task.isCancelled else { return }
        await projectIfStale()
    }

    /// Ends the subscriptions, the source and the projector: the snapshot is released.
    public func end() async {
        subscription.cancel()
        timeChanges.cancel()
        manualRunOwner.cancel()
        manualRun = nil
        await source.end()
        await projector.end()
    }

    /// Freshness-only updates (`.refreshing`, `.delayed`, …) touch `freshness` alone; only a new
    /// snapshot generation is installed and projected.
    private func receive(_ update: HomeUpdate) async {
        if freshness != update.freshness { freshness = update.freshness }
        guard update.snapshot != nil else {
            if case .failed = update.freshness, phase == .loading { phase = .failed }
            return
        }
        guard update.generation != installedGeneration else { return }
        installedGeneration = update.generation
        await projector.install(update)
        guard let projection = await projector.project(now: clock.now()) else { return }
        apply(projection)
    }

    private func reproject() async {
        guard let projection = await projector.project(now: clock.now()) else { return }
        apply(projection)
    }

    /// Assigns only what changed, and nothing from an older generation than the one on screen.
    func apply(_ projection: HomeProjection) {
        guard projection.generation >= generation else { return }
        generation = projection.generation
        if dashboard != projection.dashboard { dashboard = projection.dashboard }
        if studentDisplayName != projection.studentDisplayName { studentDisplayName = projection.studentDisplayName }
        if greeting != projection.greeting { greeting = projection.greeting }
        if courses != projection.courses { courses = projection.courses }
        if events != projection.events { events = projection.events }
        if toDo != projection.toDo { toDo = projection.toDo }
        if validUntil != projection.validUntil { validUntil = projection.validUntil }
        if phase != .loaded { phase = .loaded }
    }
}

/// Resumes one continuation exactly once, whoever opens it first: the refresh finishing, the
/// budget passing or the caller being cancelled. Opening before the continuation is installed
/// (a caller cancelled up front) resumes it as soon as it is.
private nonisolated final class ResumeGate: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var isOpen = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow = state.withLock { state -> Bool in
            if state.isOpen { return true }
            state.continuation = continuation
            return false
        }
        if resumeNow { continuation.resume() }
    }

    func open() {
        let pending = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.isOpen = true
            let taken = state.continuation
            state.continuation = nil
            return taken
        }
        pending?.resume()
    }
}
