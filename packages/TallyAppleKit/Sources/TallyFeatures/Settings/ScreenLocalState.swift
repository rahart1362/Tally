import Foundation
import Observation
import TallyDomain

/// User-authored, local-only state the M3 screens write: the student's course order (UX-WP-14:
/// "Edit mode reorders and persists locally"), To-Do "done" marks (UX-WP-18; PMO R16: "Mark
/// done" is local-only, Tally never writes to Canvas) and, per course, the answer to "This
/// course's grades are kept outside Canvas" (plan 08 G-3, XG-04; Automatic is absent). Opaque
/// Canvas IDs and fixed answers only, never content.
public nonisolated struct LocalScreenState: Codable, Equatable, Sendable {
    public var courseOrder: [CanvasID<Course>]
    public var doneAssignments: Set<CanvasID<Assignment>>
    public var gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride]
    /// Idea 2 (FEAT-4): the student's own per-course grade goal, a percentage; a course absent
    /// here has no goal.
    public var courseGoals: [CanvasID<Course>: Double]
    /// Increases with every change, so a store keeps the newest of two saves that race.
    public var revision: UInt64

    public init(courseOrder: [CanvasID<Course>] = [], doneAssignments: Set<CanvasID<Assignment>> = [],
                gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride] = [:],
                courseGoals: [CanvasID<Course>: Double] = [:], revision: UInt64 = 0) {
        self.courseOrder = courseOrder
        self.doneAssignments = doneAssignments
        self.gradeAvailabilityOverrides = gradeAvailabilityOverrides
        self.courseGoals = courseGoals
        self.revision = revision
    }
}

/// Where `LocalScreenState` lives. Sample mode keeps it in memory for the session (ASC-14: sample
/// data is never persisted). A signed-in account keeps it in its sealed `UserState`
/// (`AccountLocalScreenStateStore`, M3-A O3).
public nonisolated protocol LocalScreenStateStoring: Sendable {
    func load() async -> LocalScreenState
    /// Keeps `state` unless the store already holds a newer revision.
    func save(_ state: LocalScreenState) async
}

/// The session-lifetime store: sample mode's, and the default until an account store exists.
public actor InMemoryLocalScreenStateStore: LocalScreenStateStoring {
    private var state = LocalScreenState()

    public init() {}

    public func load() -> LocalScreenState { state }

    public func save(_ newState: LocalScreenState) {
        guard newState.revision >= state.revision else { return }
        state = newState
    }
}

/// The screens' view of `LocalScreenState`: main-actor and observable, so a mark or a move shows at
/// once; every change is saved in the background through the injected store.
@MainActor
@Observable
public final class ScreenLocalState {
    /// Explicit and nonisolated (plan 06 A2): an isolated deinit aborts iOS 26.0-26.3 runtimes
    /// (swiftlang/swift#88036); CI's `nm` gate keeps them out of every shipping binary.
    nonisolated deinit {}

    public private(set) var courseOrder: [CanvasID<Course>] = []
    public private(set) var doneAssignments: Set<CanvasID<Assignment>> = []
    /// Plan 08 G-3 (XG-04): the student's per-course answers; a course that is absent is Automatic.
    public private(set) var gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride] = [:]
    /// Idea 2 (FEAT-4): the student's own per-course grade goal; a course that is absent has none.
    public private(set) var courseGoals: [CanvasID<Course>: Double] = [:]

    private let store: any LocalScreenStateStoring
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var hasLoaded = false
    /// The latest save; each save carries the whole state, so the newest one wins.
    private let saving = TaskBox()

    public init(store: any LocalScreenStateStoring = InMemoryLocalScreenStateStore()) {
        self.store = store
    }

    /// Reads the stored state once (the Home shell's start).
    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        let stored = await store.load()
        revision = max(revision, stored.revision)
        courseOrder = stored.courseOrder
        doneAssignments = stored.doneAssignments
        gradeAvailabilityOverrides = stored.gradeAvailabilityOverrides
        courseGoals = stored.courseGoals
    }

    public func setCourseOrder(_ order: [CanvasID<Course>]) {
        guard order != courseOrder else { return }
        courseOrder = order
        persist()
    }

    public func isDone(_ id: CanvasID<Assignment>) -> Bool {
        doneAssignments.contains(id)
    }

    /// Marks (or unmarks) every item in `ids` as done in Tally. Returns whether anything changed
    /// (ideas2 report #3: `HomeModel.setDone` only re-projects the Dashboard then), the same
    /// pattern `setGradeAvailabilityOverride` already uses.
    @discardableResult
    public func setDone(_ ids: some Sequence<CanvasID<Assignment>>, done: Bool) -> Bool {
        var marks = doneAssignments
        for id in ids {
            if done { marks.insert(id) } else { marks.remove(id) }
        }
        guard marks != doneAssignments else { return false }
        doneAssignments = marks
        persist()
        return true
    }

    /// Sets (or, with `nil`, clears to Automatic) one course's "grades kept outside Canvas"
    /// answer. Returns whether it changed; a change is saved like any other.
    @discardableResult
    public func setGradeAvailabilityOverride(_ value: GradeAvailabilityOverride?, for course: CanvasID<Course>) -> Bool {
        guard gradeAvailabilityOverrides[course] != value else { return false }
        gradeAvailabilityOverrides[course] = value
        persist()
        return true
    }

    /// Idea 2 (FEAT-4): the student's own goal for `course`, or `nil` for none.
    public func courseGoal(for course: CanvasID<Course>) -> Double? {
        courseGoals[course]
    }

    /// Sets (or, with `nil`, clears) one course's goal. Returns whether it changed; a change is
    /// saved like any other.
    @discardableResult
    public func setCourseGoal(_ value: Double?, for course: CanvasID<Course>) -> Bool {
        guard courseGoals[course] != value else { return false }
        courseGoals[course] = value
        persist()
        return true
    }

    /// Waits for the latest save (tests).
    func awaitSaved() async {
        await saving.value()
    }

    private func persist() {
        revision &+= 1
        let state = LocalScreenState(courseOrder: courseOrder, doneAssignments: doneAssignments,
                                     gradeAvailabilityOverrides: gradeAvailabilityOverrides,
                                     courseGoals: courseGoals, revision: revision)
        let store = store
        saving.replace(with: Task { await store.save(state) })
    }
}
