import TallyDomain

/// CS-07 (crash-safety-2.md): removes repeated identifiers from a snapshot once, where
/// `LiveCanvasGateway` assembles it, so no consumer downstream ever sees a repeat from Canvas.
///
/// Real Canvas data can repeat an ID: a paginated list repeats an item when the data changes
/// between page fetches, and a course can come back once per enrollment. The rule is the one
/// `PriorityScore.WeightContext` already applies to groups: **the first occurrence wins**, and a
/// repeat is dropped whole (a repeated group takes its own assignment list with it).
///
/// Collections and scopes:
/// - courses, planner items, calendar events and announcements: the whole list;
/// - assignment groups and grading periods: per course (two courses can legitimately share one
///   grading period, since periods can come from an account-level set);
/// - assignments: account-wide, visiting courses in `courses` order, then groups in order, then
///   assignments in order. Every consumer keys assignments by ID alone (`ChangeDigest`,
///   `DashboardBuilder`, `NotificationID`), and Canvas assignment IDs are unique account-wide.
///
/// Consumers still survive repeats on their own (`GradeInput` and what-if callers build values
/// directly); this only guarantees that Canvas data reaches them without repeats.
enum SnapshotDeduplication {
    /// The first occurrence of each ID, in their original order, and how many repeats were dropped.
    static func firstOccurrences<Element, ID: Hashable>(_ elements: [Element], id: (Element) -> ID) -> (kept: [Element], dropped: Int) {
        var seen = Set<ID>(minimumCapacity: elements.count)
        let kept = elements.filter { seen.insert(id($0)).inserted }
        return (kept, elements.count - kept.count)
    }

    /// `snapshot` without repeated IDs, and how many repeats each collection lost (collections
    /// that lost none are absent). Returns `snapshot` itself, unchanged, when nothing repeats.
    static func deduplicated(_ snapshot: CanvasSnapshot) -> (snapshot: CanvasSnapshot, dropped: [SnapshotCollection: Int]) {
        var dropped: [SnapshotCollection: Int] = [:]
        func unique<Element, ID: Hashable>(_ elements: [Element], _ collection: SnapshotCollection,
                                           id: (Element) -> ID) -> [Element] {
            let (kept, count) = firstOccurrences(elements, id: id)
            guard count > 0 else { return elements }
            dropped[collection, default: 0] += count
            return kept
        }

        let courses = unique(snapshot.courses, .courses, id: \.id)

        // Courses in `courses` order first, then any other course the groups are keyed by, in ID
        // order, so which occurrence of an assignment counts as "first" never depends on
        // `Dictionary` iteration order.
        let listed = Set(courses.map(\.id))
        let courseOrder = courses.map(\.id) + snapshot.groups.keys.filter { !listed.contains($0) }.sorted()
        var groups = snapshot.groups
        var seenAssignments = Set<CanvasID<Assignment>>()
        for courseID in courseOrder {
            guard let original = snapshot.groups[courseID] else { continue }
            var changed = false
            let kept = unique(original, .assignmentGroups, id: \.id).map { group -> AssignmentGroup in
                let assignments = group.assignments.filter { seenAssignments.insert($0.id).inserted }
                guard assignments.count != group.assignments.count else { return group }
                dropped[.assignments, default: 0] += group.assignments.count - assignments.count
                changed = true
                return AssignmentGroup(id: group.id, name: group.name, position: group.position, weight: group.weight,
                                       rules: group.rules, assignments: assignments)
            }
            if changed || kept.count != original.count { groups[courseID] = kept }
        }

        var gradingPeriods = snapshot.gradingPeriods
        for (courseID, periods) in snapshot.gradingPeriods {
            let kept = unique(periods, .gradingPeriods, id: \.id)
            if kept.count != periods.count { gradingPeriods[courseID] = kept }
        }

        let planner = unique(snapshot.planner, .plannerItems, id: \.id)
        let events = unique(snapshot.events, .events, id: \.id)
        let announcements = unique(snapshot.announcements, .announcements, id: \.id)

        guard !dropped.isEmpty else { return (snapshot, [:]) }
        let result = CanvasSnapshot(
            generation: snapshot.generation, accountKey: snapshot.accountKey, host: snapshot.host,
            fetchedAt: snapshot.fetchedAt, profile: snapshot.profile, courses: courses, groups: groups,
            gradingPeriods: gradingPeriods, planner: planner, events: events, announcements: announcements,
            courseColors: snapshot.courseColors, sections: snapshot.sections)
        return (result, dropped)
    }
}
