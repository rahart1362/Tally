import Foundation

/// Splits the pending-notification cap across a parent's linked subjects (family-linking.md
/// §6.5/§6.4: "The 64-cap split keeps a floor of 4 per subject" / "weighted by due-item count,
/// with a floor of 4 per subject"). Pure and deterministic, like `ReminderPlanner`'s own budget
/// logic: the same inputs always produce the same split.
public enum FamilySubjectBudget {
    /// - Parameters:
    ///   - weights: each subject's weight (the caller passes its due-item count, `max(1, …)` so
    ///     a subject with nothing due this week still gets its floor rather than zero slots —
    ///     family-linking.md never says an idle student should vanish from Notification Center).
    ///     Order is preserved only for ties; the split itself does not depend on it.
    ///   - cap: the total slots available across every subject (`TallyConfig.
    ///     pendingNotificationCap`, the same headroom-under-64 budget the student planner uses).
    ///   - floorPerSubject: the minimum slots guaranteed to each subject before the remainder is
    ///     divided by weight (`TallyConfig.familyNotificationFloorPerSubject`, 4).
    /// - Returns: subject -> slot count, summing to at most `cap` (less only when `cap` itself
    ///   is smaller than `weights.count`, in which case each subject gets at most 1 and some get
    ///   0 — never a negative count, and the total still never exceeds `cap`).
    public static func allocate(weights: [(subject: SubjectKey, weight: Int)], cap: Int, floorPerSubject: Int) -> [SubjectKey: Int] {
        guard !weights.isEmpty else { return [:] }
        let cap = max(0, cap)
        guard cap > 0 else { return Dictionary(uniqueKeysWithValues: weights.map { ($0.subject, 0) }) }

        let floor = max(0, floorPerSubject)
        // R-4-style guard (resilience.md, crash-safety-2.md F-8): when even the floors alone
        // would not fit, nobody gets their full floor — split `cap` as evenly as the floors
        // would have been, rather than let list order decide who gets starved to zero.
        guard floor * weights.count < cap else { return evenSplit(subjects: weights.map(\.subject), cap: cap) }

        var allocation = Dictionary(uniqueKeysWithValues: weights.map { ($0.subject, floor) })
        let remaining = cap - floor * weights.count
        let totalWeight = weights.reduce(0) { $0 + max(0, $1.weight) }
        guard totalWeight > 0, remaining > 0 else { return allocation }

        // Largest-remainder method over the leftover slots, weighted by due-item count.
        var usedFromRemaining = 0
        var remainders: [(subject: SubjectKey, fraction: Double)] = []
        for (subject, weight) in weights {
            let share = Double(remaining) * Double(max(0, weight)) / Double(totalWeight)
            let whole = Int(share)
            allocation[subject, default: 0] += whole
            usedFromRemaining += whole
            remainders.append((subject, share - Double(whole)))
        }
        var leftover = remaining - usedFromRemaining
        // Largest fractional remainder first; ties broken by subject id so the split is
        // reproducible across runs and platforms (never dictionary iteration order).
        for entry in remainders.sorted(by: { $0.fraction != $1.fraction ? $0.fraction > $1.fraction : $0.subject.rawValue < $1.subject.rawValue }) {
            guard leftover > 0 else { break }
            allocation[entry.subject, default: 0] += 1
            leftover -= 1
        }
        return allocation
    }

    private static func evenSplit(subjects: [SubjectKey], cap: Int) -> [SubjectKey: Int] {
        guard !subjects.isEmpty else { return [:] }
        var allocation = Dictionary(uniqueKeysWithValues: subjects.map { ($0, cap / subjects.count) })
        var leftover = cap % subjects.count
        for subject in subjects.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard leftover > 0 else { break }
            allocation[subject, default: 0] += 1
            leftover -= 1
        }
        return allocation
    }
}
