import Foundation

/// The words a Tally notification's `filterCriteria` carries, and the predicate a Focus filter
/// applies to them (integrations.md §2.6: a "Study" or "Exam" Focus shows only the chosen courses
/// and mutes the less urgent alerts).
///
/// iOS silences a notification whose criteria do not match the Focus filter's predicate (WWDC22
/// "Meet Focus filters"). Tally's notifications do not set `filterCriteria` yet (the scheduler,
/// `UNNotificationScheduler`, is not this work package's file), so the predicate always lets a
/// notification with no criteria through: a Focus filter never silences a reminder by accident.
/// Once the scheduler writes `criteria(courseID:level:)` on each notification, the filter takes
/// effect with no change here.
public enum FocusFilterCriteria {
    /// insights-at-a-glance.md §2.2's severities.
    public enum Level: String, Sendable, CaseIterable {
        case critical, high, medium, info
    }

    /// The levels "Only urgent alerts" lets through.
    public static let urgentLevels: [Level] = [.critical, .high]

    /// ";course=123;level=high;": the course's opaque Canvas ID (none for an alert about no single
    /// course) and the alert's level, each between separators so one can never match inside another
    /// (";course=12;" is not in ";course=123;").
    public static func criteria(courseID: String?, level: Level) -> String {
        ";" + (courseID.map(courseToken(for:)) ?? "") + levelToken(for: level)
    }

    /// The Focus filter's notification predicate over a notification's criteria string (SELF), or
    /// `nil` when the filter keeps every course and every level (nothing to filter). A notification
    /// with no criteria always passes.
    public static func predicate(courseIDs: [String], onlyUrgent: Bool) -> NSPredicate? {
        var conditions: [NSPredicate] = []
        if !courseIDs.isEmpty {
            conditions.append(anyToken(Set(courseIDs).sorted().map(courseToken(for:))))
        }
        if onlyUrgent {
            conditions.append(anyToken(urgentLevels.map(levelToken(for:))))
        }
        guard !conditions.isEmpty else { return nil }
        return NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "SELF == nil"),
            NSCompoundPredicate(andPredicateWithSubpredicates: conditions),
        ])
    }

    static func courseToken(for courseID: String) -> String { "course=\(courseID);" }

    static func levelToken(for level: Level) -> String { "level=\(level.rawValue);" }

    /// True when the criteria contain any of `tokens`, each preceded by a separator.
    private static func anyToken(_ tokens: [String]) -> NSPredicate {
        NSCompoundPredicate(orPredicateWithSubpredicates: tokens.map { NSPredicate(format: "SELF CONTAINS %@", ";\($0)") })
    }
}
