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
    /// Explicit and nonisolated (plan 06 A2). In this default-`MainActor` module the compiler makes an
    /// implicit deinit main-actor isolated, `@MainActor` on the class or not, and an isolated deinit
    /// (`swift_task_deinitOnExecutor`) aborts iOS 26.0-26.3 runtimes when it runs nested or in a
    /// task-local scope (swiftlang/swift#88036; the floor abort in CI run 36390172728). CI's `nm`
    /// gate keeps isolated deinits out of every shipping binary.
    nonisolated deinit {}

    public enum Phase: Equatable, Sendable {
        /// Waiting for the first projection: the shell shows skeletons.
        case loading
        /// A signed-in launch's first paint (perf-app-runtime.md §2.4 L4): the sealed glance's
        /// hero count and due-soon rows, until the full projection replaces it (L8).
        case glance
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

    // MARK: M3-A screens (each its own property, so a screen re-renders only when its rows change)

    /// The Courses tab, in the student's own order (`local.courseOrder`).
    public private(set) var courseCards: [CourseCard] = []
    public private(set) var courseDetails: [CanvasID<Course>: CourseDetailProjection] = [:]
    public private(set) var toDoScreen: ToDoProjection = .empty
    public private(set) var calendarScreen: CalendarProjection = .empty
    public private(set) var insightsScreen: InsightsProjection = .empty
    public private(set) var account: AccountProjection = .empty
    /// The student's local course order, To-Do "done" marks (never written to Canvas, R16) and
    /// "grades kept outside Canvas" answers (plan 08 G-3, XG-04).
    public let local: ScreenLocalState
    /// Settings' access to `UserState` (the "What changed" thresholds).
    public let userState: any UserStateAccess
    /// Sample mode (ASC-14): links into a real Canvas and the calendar feed have nowhere to go.
    public var isSampleData: Bool { source is SampleSession }

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
    /// The subscription and its first update (`prepare()`); shared by every caller.
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var hasEnded = false
    /// XG-04: hands a changed "grades kept outside Canvas" answer to the projector, then re-projects.
    private let overrideChanges = TaskBox()
    /// The revision of the answers last handed to the projector (`HomeProjector` keeps the newest).
    @ObservationIgnored private var overridesRevision: UInt64 = 0

    /// - Parameters:
    ///   - localStore: where the course order and "done" marks live; in memory by default (sample
    ///     mode keeps nothing, ASC-14).
    ///   - userState: Settings' `UserState`; in memory by default. A signed-in account passes an
    ///     `AccountUserStateAccess` over its `UserStateStore` and `AccountRuntime`.
    public init(source: any HomeDataSource, projector: HomeProjector = HomeProjector(),
                clock: any DateProviding = SystemDateProvider(),
                localStore: any LocalScreenStateStoring = InMemoryLocalScreenStateStore(),
                userState: any UserStateAccess = InMemoryUserStateAccess()) {
        self.source = source
        self.projector = projector
        self.clock = clock
        self.local = ScreenLocalState(store: localStore)
        self.userState = userState
    }

    /// Subscribes to the source, then loads. Runs once, from the shell's `.task`.
    ///
    /// The launch refresh (perf-app-runtime.md §2.4 L9, the handshake) starts only once the
    /// source's first update has been handled (`prepare()`): with a cached snapshot, that update
    /// is projected and applied (L7–L8) first, so the network never runs ahead of the cached paint.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await prepare()
        guard !hasEnded else { return }
        await source.refresh(.launch)
    }

    /// Subscribes to the source and handles its first update: the current state, which for a
    /// signed-in launch carries the cached snapshot (L5–L8). Idempotent: `AppModel` calls it at
    /// launch, so the projection proceeds while the app lock is still up, and `start()` awaits the
    /// same work.
    public func prepare() async {
        if let preparation {
            await preparation.value
            return
        }
        let preparing = Task { [weak self] in
            guard let self else { return }
            await self.subscribeAndHandleFirstUpdate()
        }
        preparation = preparing
        await preparing.value
    }

    /// perf-app-runtime.md §2.4 L4: the first paint, from the sealed glance, before the snapshot is
    /// decoded. Only before any projection: a full projection is never replaced by a glance.
    public func showGlance(_ glance: HomeGlance) {
        guard phase == .loading else { return }
        dashboard = glance.dashboard
        freshness = glance.freshness
        phase = .glance
    }

    private func subscribeAndHandleFirstUpdate() async {
        // M3-A: the course order first, so the first projection (at launch, `prepare()` runs
        // before `start()`) already shows the student's order; and (XG-04) the "grades kept
        // outside Canvas" answers, so it classifies every course as the glance on disk does.
        await local.load()
        let updates = await source.updates()
        guard !hasEnded else { return }
        await withCheckedContinuation { (firstHandled: CheckedContinuation<Void, Never>) in
            subscription.replace(with: Task { [weak self] in
                var signalled = false
                for await update in updates {
                    await self?.receive(update)
                    if !signalled {
                        signalled = true
                        firstHandled.resume()
                    }
                }
                if !signalled { firstHandled.resume() }
            })
        }
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

    /// Edit mode's move on the Courses tab (UX-WP-14): the list changes at once and the new order
    /// is kept locally, so every later projection uses it.
    public func moveCourses(fromOffsets source: IndexSet, toOffset destination: Int) {
        let order = CourseOrder.moving(courseCards.map(\.id), fromOffsets: source, toOffset: destination)
        local.setCourseOrder(order)
        let arranged = CourseOrder.arrange(courseCards, by: order)
        if courseCards != arranged { courseCards = arranged }
    }

    /// The student's answer to "This course's grades are kept outside Canvas" (plan 08 G-3,
    /// XG-04): `nil` is Automatic.
    public func gradeAvailabilityOverride(for course: CanvasID<Course>) -> GradeAvailabilityOverride? {
        local.gradeAvailabilityOverrides[course]
    }

    /// Course Detail's menu (XG-04): sets one course's answer (`nil`: Automatic). It is kept with
    /// the course order (`ScreenLocalState`; a signed-in account's `UserState`, which hands it to
    /// the account's `RefreshCoordinator`: the glance is rewritten and the widget reloads), and
    /// every screen is projected again at once with it.
    public func setGradeAvailabilityOverride(_ value: GradeAvailabilityOverride?, for course: CanvasID<Course>) {
        guard local.setGradeAvailabilityOverride(value, for: course) else { return }
        overridesRevision &+= 1
        let revision = overridesRevision
        let overrides = local.gradeAvailabilityOverrides
        let projector = projector
        overrideChanges.replace(with: Task { [weak self] in
            guard await projector.setGradeAvailabilityOverrides(overrides, revision: revision) else { return }
        })
    }

    /// Waits for the latest answer to reach the screens (tests).
    func awaitGradeAvailabilityOverrideApplied() async {
        await overrideChanges.value()
    }

    /// Ends the subscriptions, the source and the projector: the snapshot is released.
    public func end() async {
        hasEnded = true
        preparation?.cancel()
        subscription.cancel()
        timeChanges.cancel()
        overrideChanges.cancel()
        manualRunOwner.cancel()
        manualRun = nil
        await source.end()
        await projector.end()
    }

    /// Freshness-only updates (`.refreshing`, `.delayed`, …) touch `freshness` alone; only a new
    /// snapshot generation is installed and projected.
    private func receive(_ update: HomeUpdate) async {
        // A glance on screen keeps its "Updated <time>" until the coordinator knows better than
        // `.noCache` (its first event before the cached snapshot is installed).
        if freshness != update.freshness, !(phase == .glance && update.freshness == .noCache) {
            freshness = update.freshness
        }
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
        applyScreens(projection.screens)
        if phase != .loaded { phase = .loaded }
    }

    /// M3-A: each screen's projection, assigned only when it changed.
    private func applyScreens(_ screens: ScreenProjections) {
        let cards = CourseOrder.arrange(screens.courseCards, by: local.courseOrder)
        if courseCards != cards { courseCards = cards }
        if courseDetails != screens.courseDetails { courseDetails = screens.courseDetails }
        if toDoScreen != screens.toDo { toDoScreen = screens.toDo }
        if calendarScreen != screens.calendar { calendarScreen = screens.calendar }
        if insightsScreen != screens.insights { insightsScreen = screens.insights }
        if account != screens.account { account = screens.account }
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
