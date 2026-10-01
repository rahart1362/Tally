// PERF-05 PA-1 (docs/pmo/reviews/perf-algorithms.md): the per-item "passes" that
// `CoreBenchmarks` times and `PerCourseScalingGateTests` gates, in one place so both always
// measure exactly the same code. Before this file existed each pass lived inline in its
// `CoreBenchmarks` test body; a scaling gate that re-typed the same loop could silently drift
// from the benchmark whose number the PMO report quotes.
//
// Every pass returns a checksum that the caller hands to `Bench.keep`: without it, a pass whose
// results are all discarded (`_ = ...`) is dead code the optimizer may delete once enough of it
// is inlined across modules, and a benchmark would then time nothing. The checksum costs a few
// additions per item.
#if !DEBUG
import Foundation
import TallyDomain

typealias OpenItem = (course: Course, groups: [AssignmentGroup], assignment: Assignment)

enum PerfPasses {
    /// PERF-05 PA-2: one `PriorityScore.WeightContext` per course, the way `DashboardBuilder`
    /// weighs items. Built inside each pass's timed region: the context's own O(n·p) build is
    /// part of what a pass costs.
    static func weightContexts(_ snapshot: CanvasSnapshot) -> [CanvasID<Course>: PriorityScore.WeightContext] {
        var contexts: [CanvasID<Course>: PriorityScore.WeightContext] = [:]
        for course in snapshot.courses {
            contexts[course.id] = PriorityScore.WeightContext(course: course, groups: snapshot.groups[course.id] ?? [],
                                                              gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
        }
        return contexts
    }

    /// `DashboardBuilder`'s "Next up" per-item work (`PriorityScore` over every item), the pass
    /// `priorityScoreAllItems` times.
    static func priorityScore(items: [OpenItem], snapshot: CanvasSnapshot, now: Date) -> Double {
        let contexts = weightContexts(snapshot)
        var checksum = 0.0
        for (course, _, assignment) in items {
            guard !PriorityScore.isExcluded(assignment: assignment, markedDone: false, now: now) else { continue }
            let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3600 }
            let weight = contexts[course.id]?.weight(of: assignment) ?? 0
            let modifiers = priorityModifiers(assignment: assignment, course: course, now: now)
            let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
            // Plan 08 L10N-02: the reason is structured now (the app phrases it).
            let reason = PriorityScore.reasonFactors(hoursUntilDue: hours, weight: weight, modifiers: modifiers)
                .map(PriorityScore.reasonPart)
            checksum += score + Double(reason.count) + (PriorityScore.band(score) == .high ? 1 : 0)
        }
        return checksum
    }

    /// `DashboardBuilder`'s "Needs attention" per-item work (A1/A2, A3, then A7 over the open
    /// future items), the pass `alertEngineAllItems` times. It looks `weight` up to twice per
    /// item, like the pre-PERF-03 app-core code it was written against.
    static func alertEngine(items: [OpenItem], snapshot: CanvasSnapshot, now: Date) -> Double {
        let contexts = weightContexts(snapshot)
        var checksum = 0.0
        var loadItems: [AlertEngine.LoadItem] = []
        for (course, _, assignment) in items {
            if let missing = AlertEngine.missingAlert(assignment: assignment, now: now) {
                checksum += Double(missing.rank)
            } else if let submission = assignment.submission, !submission.isSubmitted, !submission.excused,
                      let due = assignment.dueAt, due >= now {
                let weight = contexts[course.id]?.weight(of: assignment) ?? 0
                let hours = due.timeIntervalSince(now) / 3600
                let modifiers = priorityModifiers(assignment: assignment, course: course, now: now)
                let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
                if let dueSoon = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: score, weight: weight, now: now) {
                    checksum += Double(dueSoon.rank)
                }
            }
            if let due = assignment.dueAt, due >= now, let submission = assignment.submission,
               !submission.isSubmitted, !submission.excused {
                let weight = contexts[course.id]?.weight(of: assignment) ?? 0
                loadItems.append(AlertEngine.LoadItem(dueAt: due, weight: weight, courseID: course.id))
                checksum += weight
            }
        }
        return checksum + Double(AlertEngine.overloadClusters(loadItems, now: now).count)
    }

    /// `ReminderPlanner.plan`'s input, built untimed (the benchmark times `plan` alone).
    static func reminderCandidates(items: [OpenItem], snapshot: CanvasSnapshot, now: Date) -> [ReminderCandidate] {
        let contexts = weightContexts(snapshot)
        return items.map { course, _, assignment -> ReminderCandidate in
            let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3600 }
            let weight = contexts[course.id]?.weight(of: assignment) ?? 0
            let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight,
                                            modifiers: priorityModifiers(assignment: assignment, course: course, now: now))
            return ReminderCandidate(assignment: assignment, isExam: false, priority: score, markedDone: false)
        }
    }

    /// A `RefreshRecord` that last succeeded an hour before `now`, so `plan` also schedules the
    /// R17 sentinel (the benchmark's original setup, unchanged).
    static func reminderRefreshRecord(now: Date) -> RefreshRecord {
        var refresh = RefreshRecord()
        refresh.began(.launch, at: now.addingTimeInterval(-3600))
        refresh.succeeded(dataFetchedAt: now.addingTimeInterval(-3600))
        return refresh
    }

    static let reminderTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    static func reminderPlan(candidates: [ReminderCandidate], refresh: RefreshRecord, now: Date, label: String) -> Double {
        let plan = ReminderPlanner.plan(accountKey: AccountKey("perf-\(label)"), candidates: candidates,
                                        settings: ReminderSettings(), now: now, timeZone: reminderTimeZone, refresh: refresh)
        return Double(plan.count) + (plan.last?.fireDate.timeIntervalSince1970 ?? 0)
    }
}
#endif
