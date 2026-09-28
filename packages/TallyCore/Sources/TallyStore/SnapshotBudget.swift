import Foundation
import TallyDomain

/// CS-05 (crash-safety.md): "maximum items per snapshot, and snapshot size over budget must
/// degrade gracefully, never crash." Applied at commit time (`RefreshCoordinator.finish`),
/// right before a snapshot reaches `SnapshotStore`.
///
/// Courses and assignment groups (the actual grade data) are never trimmed here: a snapshot
/// still over budget after dropping the optional sections has a genuinely pathological number
/// of courses/assignments, and silently cutting a course's assignments mid-list would corrupt
/// its grade math rather than just losing a "nice to have" list. `events`/`announcements` are
/// already-optional, carry-forward sections (`SnapshotSection.isRequired == false`); `planner`
/// is required but is safe to *trim* (keep the soonest-due items) rather than drop entirely.
public enum SnapshotBudget {
    public struct Outcome: Sendable, Equatable {
        public let snapshot: CanvasSnapshot
        public let degraded: Bool
        public let droppedEvents: Int
        public let droppedAnnouncements: Int
        public let trimmedPlannerItems: Int
    }

    /// Every item the snapshot carries. The charter's synthetic stress persona is ~20 courses x
    /// 250 assignments (~5,000 items) — nowhere near `TallyConfig.maxSnapshotItems`'s default;
    /// this only ever fires for corrupt or adversarial data (CS-03).
    public static func itemCount(_ snapshot: CanvasSnapshot) -> Int {
        snapshot.courses.count
            + snapshot.groups.values.reduce(0) { $0 + $1.reduce(0) { $0 + 1 + $1.assignments.count } }
            + snapshot.planner.count + snapshot.events.count + snapshot.announcements.count
    }

    public static func enforce(_ snapshot: CanvasSnapshot, maxItems: Int = TallyConfig.maxSnapshotItems) -> Outcome {
        guard itemCount(snapshot) > maxItems else {
            return Outcome(snapshot: snapshot, degraded: false, droppedEvents: 0, droppedAnnouncements: 0, trimmedPlannerItems: 0)
        }

        var working = snapshot
        var droppedEvents = 0, droppedAnnouncements = 0, trimmedPlanner = 0

        if !working.events.isEmpty {
            droppedEvents = working.events.count
            working = replacing(working, events: [])
        }
        if itemCount(working) > maxItems, !working.announcements.isEmpty {
            droppedAnnouncements = working.announcements.count
            working = replacing(working, announcements: [])
        }
        if itemCount(working) > maxItems, working.planner.count > max(0, maxItems) {
            let kept = working.planner
                .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
                .prefix(max(0, maxItems))
            trimmedPlanner = working.planner.count - kept.count
            working = replacing(working, planner: Array(kept))
        }

        return Outcome(snapshot: working, degraded: true, droppedEvents: droppedEvents,
                       droppedAnnouncements: droppedAnnouncements, trimmedPlannerItems: trimmedPlanner)
    }

    private static func replacing(_ s: CanvasSnapshot, events: [CalendarEvent]) -> CanvasSnapshot {
        CanvasSnapshot(generation: s.generation, accountKey: s.accountKey, host: s.host, fetchedAt: s.fetchedAt,
                       profile: s.profile, courses: s.courses, groups: s.groups, gradingPeriods: s.gradingPeriods,
                       planner: s.planner, events: events, announcements: s.announcements,
                       courseColors: s.courseColors, sections: s.sections)
    }

    private static func replacing(_ s: CanvasSnapshot, announcements: [Announcement]) -> CanvasSnapshot {
        CanvasSnapshot(generation: s.generation, accountKey: s.accountKey, host: s.host, fetchedAt: s.fetchedAt,
                       profile: s.profile, courses: s.courses, groups: s.groups, gradingPeriods: s.gradingPeriods,
                       planner: s.planner, events: s.events, announcements: announcements,
                       courseColors: s.courseColors, sections: s.sections)
    }

    private static func replacing(_ s: CanvasSnapshot, planner: [PlannerItem]) -> CanvasSnapshot {
        CanvasSnapshot(generation: s.generation, accountKey: s.accountKey, host: s.host, fetchedAt: s.fetchedAt,
                       profile: s.profile, courses: s.courses, groups: s.groups, gradingPeriods: s.gradingPeriods,
                       planner: planner, events: s.events, announcements: s.announcements,
                       courseColors: s.courseColors, sections: s.sections)
    }
}
