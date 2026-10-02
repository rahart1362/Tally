#if DEBUG
import Foundation
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like `ReminderAnswersRig` and the lifecycle test doubles it runs on.
///
/// M3-E2 (FAM-08 wiring): a reminders pass plans the parent reminders of the account's observer
/// subjects with M3-E1's planner, beside the account's own, and schedules them with words from
/// TallyStrings' renderer only. Over the bundled sample family (two fictional students): every
/// family reminder is scheduled with text, names the student (or "Your student" with Hide Student
/// Names on), and carries none of that student's scores or letter grades; a second pass changes
/// nothing; and with no observer subjects (every account today) no family reminder appears.
///
/// Serialized with the account-lifecycle suites: every pass runs through `ReminderPipeline`'s
/// process-wide queue.
extension AccountLifecycleSuites {
    @Suite("FAM-08 wiring: a reminders pass schedules the observer subjects' parent reminders, never a grade")
    struct FamilyReminderWiringTests {
        /// The sample family's capture instant: every fixture date is as captured.
        static let now = Date(timeIntervalSince1970: 1_790_600_400) // 2026-09-28T13:00:00Z

        struct StaticObservers: ObserverSubjectSource {
            let subjects: [ObserverSubjectSnapshot]
            func observerSubjects(of account: AccountKey) async -> [ObserverSubjectSnapshot] { subjects }
        }

        static func observers() async throws -> [ObserverSubjectSnapshot] {
            let roster = try await SampleFamilyRoster.load()
            var subjects: [ObserverSubjectSnapshot] = []
            for (index, student) in roster.students.enumerated() {
                let observee = try #require(roster.observees[student.canvasUserID])
                let snapshot = try await roster.replay.snapshot(of: observee, now: now)
                // The first student with names shown and due reminders on; the second with names hidden.
                let settings = FamilySubjectNotificationSettings(dueRemindersEnabled: index == 0, hideStudentNames: index == 1)
                subjects.append(ObserverSubjectSnapshot(subject: student.subject, name: student.name, snapshot: snapshot,
                                                        settings: settings))
            }
            return subjects
        }

        /// Every score and letter grade a student's courses carry, as text a notification could show.
        static func gradeTexts(of snapshot: CanvasSnapshot) -> Set<String> {
            var texts: Set<String> = []
            for course in snapshot.courses {
                for scores in [course.scores, course.currentPeriodScores].compactMap({ $0 }) {
                    for score in [scores.currentScore, scores.finalScore].compactMap({ $0 }) {
                        texts.insert(String(format: "%.1f", score))
                        texts.insert(String(format: "%.0f%%", score))
                    }
                    for grade in [scores.currentGrade, scores.finalGrade].compactMap({ $0 }) where grade.count > 1 {
                        texts.insert(grade)
                    }
                }
            }
            return texts
        }

        @Test("Parent reminders are scheduled per student with the renderer's words, never a grade; idempotent; none without observers")
        func observerSubjectsReachThePass() async throws {
            let observers = try await Self.observers()
            #expect(observers.count == 2)
            let rig = try ReminderAnswersRig(now: Self.now)
            // The account's own snapshot: the first student's, as any snapshot would do.
            let coordinator = rig.coordinator(over: observers[0].snapshot)

            let none = await ReminderPipeline.reconcile(coordinator: coordinator, environment: rig.environment,
                                                        timeZone: ReminderAnswersRig.timeZone, locale: Locale(identifier: "en_US"))
            let ownOnly = await rig.platform.pendingContents()
            #expect(none != nil)
            #expect(!ownOnly.keys.contains { id in observers.contains { id.contains(".\($0.subject.id.rawValue).") } },
                    "a family reminder without observer subjects")

            let source = StaticObservers(subjects: observers)
            let outcome = await ReminderPipeline.reconcile(coordinator: coordinator, environment: rig.environment,
                                                           timeZone: ReminderAnswersRig.timeZone, locale: Locale(identifier: "en_US"),
                                                           observers: source)
            let pending = await rig.platform.pendingContents()
            for subject in observers {
                let family = pending.filter { $0.key.contains(".\(subject.subject.id.rawValue).") }
                #expect(!family.isEmpty, "no parent reminder for \(subject.name)")
                let firstName = StudentNameText.firstName(of: subject.name)
                let grades = Self.gradeTexts(of: subject.snapshot)
                for (id, content) in family {
                    let text = content.title + " " + content.body
                    #expect(!content.title.isEmpty && !content.body.isEmpty, "\(id) has no words")
                    #expect(!text.contains("%"), "\(id) shows a percentage: \(text)")
                    for grade in grades {
                        #expect(!text.contains(grade), "\(id) shows the grade '\(grade)': \(text)")
                    }
                    if subject.settings.hideStudentNames {
                        #expect(!text.contains(firstName), "\(id) names a hidden student: \(text)")
                        #expect(content.title.contains("Your student"), "\(id): \(content.title)")
                    } else {
                        #expect(content.title.hasPrefix(firstName), "\(id): \(content.title)")
                    }
                }
            }
            guard case .reconciled(let scheduled, _) = outcome else {
                Issue.record("the pass did not reconcile: \(String(describing: outcome))")
                return
            }
            #expect(scheduled > 0)

            let again = await ReminderPipeline.reconcile(coordinator: coordinator, environment: rig.environment,
                                                         timeZone: ReminderAnswersRig.timeZone, locale: Locale(identifier: "en_US"),
                                                         observers: source)
            #expect(again == .reconciled(scheduled: 0, cancelled: 0))
        }

        @Test("Each planned parent reminder finds its assignment again from E1's identifier (no reminder dropped silently)")
        func everyPlannedReminderHasAMessage() async throws {
            let observers = try await Self.observers()
            let format = ReminderTimeFormat(timeZone: ReminderAnswersRig.timeZone, locale: Locale(identifier: "en_US"))
            let account = AccountKey("acct")
            let planned = FamilyReminderPlan.plan(accountKey: account, subjects: observers + observers, now: Self.now,
                                                  format: format, cap: TallyConfig.pendingNotificationCap)
            let inputs = observers.map {
                FamilySubjectPlanInput(subjectID: $0.subject.id, studentName: $0.name,
                                       candidates: ReminderSubjects(snapshot: $0.snapshot, now: Self.now).candidates,
                                       settings: $0.settings)
            }
            let raw = FamilyNotificationPlanner.plan(accountKey: account, subjects: inputs, now: Self.now, timeZone: format.timeZone)
            #expect(raw.allSatisfy { FamilyReminderPlan.canvasID(of: $0, accountKey: account) != nil })
            // Only a week ahead with nothing due in its 7 days has nothing honest to say.
            let dropped = Set(raw.map(\.id)).subtracting(planned.map(\.reminder.id))
            #expect(dropped.allSatisfy { $0.contains(".weekAhead.") }, "dropped: \(dropped)")
            #expect(Set(planned.map(\.reminder.id)).count == planned.count, "a student listed twice was planned twice")
            #expect(FamilyReminderPlan.plan(accountKey: account, subjects: observers, now: Self.now, format: format, cap: 0).isEmpty)
        }
    }
}
#endif
