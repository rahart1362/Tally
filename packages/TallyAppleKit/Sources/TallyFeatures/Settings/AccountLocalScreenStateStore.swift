import Foundation
import TallyDomain
import TallyStore

/// A signed-in account's `LocalScreenState` (M3-A O3): the course order and To-Do "done" marks, kept
/// in the account's sealed `UserState` (v4 `courseOrder` and `doneAssignments`), and the "grades
/// kept outside Canvas" answers (v5 `gradesOutsideCanvasOverride`, plan 08 XG-04), so they survive
/// a relaunch. Every save goes through `UserStateAccess.update`, which hands the answers to the
/// account's `RefreshCoordinator` (the glance, the digest). Sample mode keeps
/// `InMemoryLocalScreenStateStore` (ASC-14: sample data is never persisted). After a save that
/// changed the done marks, `onDoneMarksChanged` runs (one reminders pass: an item marked done
/// stops reminding, M3-C O2); a course reorder alone does not.
public actor AccountLocalScreenStateStore: LocalScreenStateStoring {
    private let access: any UserStateAccess
    private let onDoneMarksChanged: @Sendable () async -> Void
    private var latestRevision: UInt64 = 0
    /// The done marks last read or saved; `nil` until then, so the first save always counts.
    private var knownDoneAssignments: Set<CanvasID<Assignment>>?

    public init(access: any UserStateAccess, onDoneMarksChanged: @escaping @Sendable () async -> Void = {}) {
        self.access = access
        self.onDoneMarksChanged = onDoneMarksChanged
    }

    public func load() async -> LocalScreenState {
        let state = await access.load()
        knownDoneAssignments = state.doneAssignments
        return LocalScreenState(courseOrder: state.courseOrder, doneAssignments: state.doneAssignments,
                                gradeAvailabilityOverrides: state.gradeAvailabilityOverrides, revision: latestRevision)
    }

    /// Keeps `state` unless a newer revision was already saved. A save the store refuses (a state
    /// written by a newer build, `AccountUserStateAccess.AccessError`) leaves the marks in memory
    /// for this session only.
    public func save(_ state: LocalScreenState) async {
        guard state.revision >= latestRevision else { return }
        latestRevision = state.revision
        let order = state.courseOrder
        let done = state.doneAssignments
        let overrides = state.gradeAvailabilityOverrides
        do {
            try await access.update { stored in
                stored.courseOrder = order
                stored.doneAssignments = done
                stored.gradeAvailabilityOverrides = overrides
            }
        } catch {
            return
        }
        let doneMarksChanged = done != knownDoneAssignments
        knownDoneAssignments = done
        if doneMarksChanged { await onDoneMarksChanged() }
    }
}

/// Where the Dashboard's reminders tip keeps its dismissal (M3-C O1).
public nonisolated protocol ReminderTipDismissalStoring: Sendable {
    func dismissedUntil() async -> Date?
    func setDismissedUntil(_ date: Date) async
}

/// The signed-in account's: `UserState.reminderTipDismissedUntil`, so a dismissal outlives a relaunch.
public nonisolated struct UserStateTipDismissalStore: ReminderTipDismissalStoring {
    private let access: any UserStateAccess

    public init(access: any UserStateAccess) {
        self.access = access
    }

    public func dismissedUntil() async -> Date? {
        await access.load().reminderTipDismissedUntil
    }

    public func setDismissedUntil(_ date: Date) async {
        _ = try? await access.update { $0.reminderTipDismissedUntil = date }
    }
}
