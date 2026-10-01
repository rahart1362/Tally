import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("AlertEngine: missing, due soon, grade posted, below goal, overload, conflict, sync")
struct AlertEngineTests {
    static let now = Date(timeIntervalSince1970: 1_790_600_400) // fixtures' anchor, 2026-09-28T13:00:00Z

    private func assignment(
        due: Date? = nil, lock: Date? = nil, types: [String] = ["online_upload"], submission: Submission?
    ) -> Assignment {
        Assignment(id: "a1", courseID: "c1", groupID: "g1", name: "Test", dueAt: due, lockAt: lock,
                  pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                  submission: submission, submissionTypes: types)
    }

    private func submission(
        score: Double? = nil, submittedAt: Date? = nil, postedAt: Date? = nil, excused: Bool = false,
        missing: Bool = false, workflowState: String = "unsubmitted"
    ) -> Submission {
        Submission(score: score, grade: nil, submittedAt: submittedAt, gradedAt: postedAt, postedAt: postedAt,
                  excused: excused, missing: missing, late: false, workflowState: workflowState, id: "s1")
    }

    // MARK: - A1/A2 missing

    @Test func missingOpenIsHighByDefault() {
        let now = Self.now
        let a = assignment(due: now.addingTimeInterval(-3600), submission: submission(missing: true))
        let alert = AlertEngine.missingAlert(assignment: a, now: now)
        #expect(alert?.kind == .missingOpen(assignmentID: "a1"))
        #expect(alert?.severity == .high)
    }

    @Test func missingOpenIsCriticalWithinTheLockWindow() {
        let now = Self.now
        let a = assignment(due: now.addingTimeInterval(-3600), lock: now.addingTimeInterval(3600),
                          submission: submission(missing: true))
        let alert = AlertEngine.missingAlert(assignment: a, now: now)
        #expect(alert?.severity == .critical)
    }

    @Test func missingClosedIsMediumAndGroupedPerCourse() {
        let now = Self.now
        let a = assignment(due: now.addingTimeInterval(-3600), lock: now.addingTimeInterval(-60),
                          submission: submission(missing: true))
        let alert = AlertEngine.missingAlert(assignment: a, now: now)
        #expect(alert?.kind == .missingClosed(courseID: "c1"))
        #expect(alert?.severity == .medium)
    }

    @Test func excusedNeverFires() {
        let now = Self.now
        let a = assignment(due: now.addingTimeInterval(-3600), submission: submission(excused: true, missing: true))
        #expect(AlertEngine.missingAlert(assignment: a, now: now) == nil)
    }

    @Test func noDigitalSubmissionExpectedNeedsCanvasToFlagMissing() {
        let now = Self.now
        let notFlagged = assignment(due: now.addingTimeInterval(-3600), types: ["none"],
                                   submission: submission(missing: false, workflowState: "unsubmitted"))
        #expect(AlertEngine.missingAlert(assignment: notFlagged, now: now) == nil)
        let flagged = assignment(due: now.addingTimeInterval(-3600), types: ["none"], submission: submission(missing: true))
        #expect(AlertEngine.missingAlert(assignment: flagged, now: now) != nil)
    }

    @Test func notYetDueIsNotMissing() {
        let now = Self.now
        let a = assignment(due: now.addingTimeInterval(3600), submission: submission())
        #expect(AlertEngine.missingAlert(assignment: a, now: now) == nil)
    }

    // MARK: - A3 due soon

    @Test func dueSoonBandsByHoursAndWeight() {
        let now = Self.now
        func alert(hours: Double, priority: Double, weight: Double) -> Alert? {
            let a = assignment(due: now.addingTimeInterval(hours * 3600), submission: submission())
            return AlertEngine.dueSoonAlert(assignment: a, priorityScore: priority, weight: weight, now: now)
        }
        #expect(alert(hours: 2, priority: 65, weight: 0.2)?.severity == .critical)
        #expect(alert(hours: 2, priority: 40, weight: 0.2)?.severity == .high, "under 24h is High regardless of priority")
        #expect(alert(hours: 20, priority: 10, weight: 0.01)?.severity == .high)
        #expect(alert(hours: 50, priority: 10, weight: 0.10)?.severity == .medium)
        #expect(alert(hours: 50, priority: 10, weight: 0.01) == nil, "under the medium weight floor: Next Up only")
        #expect(alert(hours: 100, priority: 10, weight: 0.5) == nil, "past the 72h window entirely")
    }

    @Test func submittedOrExcusedNeverDueSoon() {
        let now = Self.now
        let submitted = assignment(due: now.addingTimeInterval(3600), submission: submission(submittedAt: now))
        #expect(AlertEngine.dueSoonAlert(assignment: submitted, priorityScore: 90, weight: 0.5, now: now) == nil)
        let excused = assignment(due: now.addingTimeInterval(3600), submission: submission(excused: true))
        #expect(AlertEngine.dueSoonAlert(assignment: excused, priorityScore: 90, weight: 0.5, now: now) == nil)
    }

    @Test func overdueIsNotDueSoon() {
        let now = Self.now
        let a = assignment(due: now.addingTimeInterval(-60), submission: submission())
        #expect(AlertEngine.dueSoonAlert(assignment: a, priorityScore: 90, weight: 0.5, now: now) == nil)
    }

    // MARK: - A4 grade posted

    @Test func newlyPostedGradeFires() {
        let now = Self.now
        let previous = assignment(submission: submission(score: nil, postedAt: nil))
        let current = assignment(submission: submission(score: 9, postedAt: now))
        let alert = AlertEngine.gradePostedAlert(previous: previous, current: current, availability: .available)
        #expect(alert?.severity == .info)
        #expect(alert?.kind == .gradePosted(submissionID: "s1", postedAt: now))
    }

    @Test func unchangedPostedAtDoesNotRefire() {
        let now = Self.now
        let previous = assignment(submission: submission(score: 9, postedAt: now))
        let current = assignment(submission: submission(score: 9, postedAt: now))
        #expect(AlertEngine.gradePostedAlert(previous: previous, current: current, availability: .available) == nil)
    }

    @Test func stillUnpostedDoesNotFire() {
        let current = assignment(submission: submission(score: nil, postedAt: nil))
        #expect(AlertEngine.gradePostedAlert(previous: nil, current: current, availability: .available) == nil)
    }

    // MARK: - A5 below goal (hysteresis)

    @Test func belowGoalHysteresisRequiresRisingAboveTheCushion() {
        // Not yet active: fires only strictly below goal.
        #expect(AlertEngine.belowGoalIsActive(currentScore: 79.9, goal: 80, wasActive: false))
        #expect(!AlertEngine.belowGoalIsActive(currentScore: 80.0, goal: 80, wasActive: false))
        // Once active: needs goal + hysteresis (0.5) to clear, not just goal.
        #expect(AlertEngine.belowGoalIsActive(currentScore: 80.2, goal: 80, wasActive: true))
        #expect(!AlertEngine.belowGoalIsActive(currentScore: 80.6, goal: 80, wasActive: true))
    }

    @Test func belowGoalSkipsHiddenGrades() {
        let alert = AlertEngine.belowGoalAlert(
            courseID: "c1", currentScore: 70, goal: 80, wasActive: false, availability: .hiddenByInstructor)
        #expect(alert == nil)
    }

    @Test func belowGoalNeedsAGoal() {
        #expect(AlertEngine.belowGoalAlert(courseID: "c1", currentScore: 70, goal: nil, wasActive: false, availability: .available) == nil)
    }

    // MARK: - A6 significant drop

    @Test func significantDropFromOneRefresh() {
        let alert = AlertEngine.significantDropAlert(
            courseID: "c1", currentScore: 85, previousRefreshScore: 89, score14DaysAgo: nil,
            weekOf: Self.now, belowGoalIsFiring: false, availability: .available)
        #expect(alert?.severity == .medium)
    }

    @Test func significantDropOver14Days() {
        let alert = AlertEngine.significantDropAlert(
            courseID: "c1", currentScore: 85, previousRefreshScore: 86, score14DaysAgo: 91,
            weekOf: Self.now, belowGoalIsFiring: false, availability: .available)
        #expect(alert != nil)
    }

    @Test func significantDropIsSupersededByBelowGoal() {
        let alert = AlertEngine.significantDropAlert(
            courseID: "c1", currentScore: 60, previousRefreshScore: 90, score14DaysAgo: nil,
            weekOf: Self.now, belowGoalIsFiring: true, availability: .available)
        #expect(alert == nil)
    }

    @Test func smallDropDoesNotFire() {
        let alert = AlertEngine.significantDropAlert(
            courseID: "c1", currentScore: 88, previousRefreshScore: 89, score14DaysAgo: nil,
            weekOf: Self.now, belowGoalIsFiring: false, availability: .available)
        #expect(alert == nil)
    }

    // MARK: - A7 overload cluster

    @Test func fourOrMoreItemsInA48hWindowFires() {
        let now = Self.now
        let items = (0..<4).map { AlertEngine.LoadItem(dueAt: now.addingTimeInterval(Double($0) * 3600), weight: 0.01, courseID: "c1") }
        let alerts = AlertEngine.overloadClusters(items, now: now)
        #expect(alerts.count == 1)
        #expect(alerts[0].severity == .high, "window starts within 48h of now")
    }

    @Test func heavySingleCourseWeightFiresWithFewItems() {
        let now = Self.now
        let items = [
            AlertEngine.LoadItem(dueAt: now.addingTimeInterval(3 * 86_400), weight: 0.10, courseID: "c1"),
            AlertEngine.LoadItem(dueAt: now.addingTimeInterval(3 * 86_400 + 3600), weight: 0.08, courseID: "c1"),
        ]
        let alerts = AlertEngine.overloadClusters(items, now: now)
        #expect(alerts.count == 1)
        #expect(alerts[0].severity == .medium, "window starts beyond 48h out")
    }

    @Test func lightLoadDoesNotFire() {
        let now = Self.now
        let items = [
            AlertEngine.LoadItem(dueAt: now.addingTimeInterval(3600), weight: 0.02, courseID: "c1"),
            AlertEngine.LoadItem(dueAt: now.addingTimeInterval(2 * 3600), weight: 0.02, courseID: "c2"),
        ]
        #expect(AlertEngine.overloadClusters(items, now: now).isEmpty)
    }

    @Test func itemsBeyondTheHorizonAreIgnored() {
        let now = Self.now
        let items = (0..<4).map { AlertEngine.LoadItem(dueAt: now.addingTimeInterval((11 + Double($0)) * 86_400), weight: 0.01, courseID: "c1") }
        #expect(AlertEngine.overloadClusters(items, now: now).isEmpty)
    }

    @Test func aBusyStretchProducesOneAlertNotARun() {
        let now = Self.now
        // 10 items spread every 6h over 2.5 days: many overlapping qualifying
        // windows, but adjacent-window merging should collapse them.
        let items = (0..<10).map { AlertEngine.LoadItem(dueAt: now.addingTimeInterval(Double($0) * 6 * 3600), weight: 0.01, courseID: "c1") }
        let alerts = AlertEngine.overloadClusters(items, now: now)
        #expect(alerts.count < 4, "expected merging to avoid one alert per qualifying window, got \(alerts.count)")
    }

    // MARK: - A8 schedule conflict

    @Test func examVsClassOverlapIsHigh() {
        let now = Self.now
        let exam = AlertEngine.ScheduleItem(id: "exam", start: now, end: now.addingTimeInterval(3600), isExam: true)
        let classTime = AlertEngine.ScheduleItem(id: "class", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400))
        let alerts = AlertEngine.scheduleConflicts([exam, classTime])
        #expect(alerts.count == 1)
        #expect(alerts[0].severity == .high)
        #expect(alerts[0].kind == .scheduleConflict(idA: "class", idB: "exam"))
    }

    @Test func dueTimeDuringClassIsInfo() {
        let now = Self.now
        let classTime = AlertEngine.ScheduleItem(id: "class", start: now, end: now.addingTimeInterval(3600))
        let due = AlertEngine.ScheduleItem(id: "due1", start: now.addingTimeInterval(1800))
        #expect(AlertEngine.scheduleConflicts([classTime, due]).first?.severity == .info)
    }

    @Test func twoDueItemsWithin30MinIsInfo() {
        let now = Self.now
        let a = AlertEngine.ScheduleItem(id: "due1", start: now)
        let b = AlertEngine.ScheduleItem(id: "due2", start: now.addingTimeInterval(25 * 60))
        #expect(AlertEngine.scheduleConflicts([a, b]).first?.severity == .info)
    }

    @Test func dueItemsFarApartDoNotConflict() {
        let now = Self.now
        let a = AlertEngine.ScheduleItem(id: "due1", start: now)
        let b = AlertEngine.ScheduleItem(id: "due2", start: now.addingTimeInterval(3600))
        #expect(AlertEngine.scheduleConflicts([a, b]).isEmpty)
    }

    @Test func twoExamsOverlappingIsHigh() {
        let now = Self.now
        let a = AlertEngine.ScheduleItem(id: "exam1", start: now, end: now.addingTimeInterval(3600), isExam: true)
        let b = AlertEngine.ScheduleItem(id: "exam2", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(5400), isExam: true)
        #expect(AlertEngine.scheduleConflicts([a, b]).first?.severity == .high)
    }

    // MARK: - A12 sync/sign-in

    @Test func authExpiredIsHigh() {
        var record = RefreshRecord()
        record.began(.launch, at: Self.now.addingTimeInterval(-10))
        record.failed(.authExpired)
        let alerts = AlertEngine.syncAlerts(
            refresh: record, now: Self.now, notificationsAuthorized: true, remindersEnabled: true,
            backgroundRefreshEnabled: true, schoolEnabled: true)
        #expect(alerts.map(\.kind) == [.sync(.authExpired)])
        #expect(alerts[0].severity == .high)
    }

    @Test func staleOver24hIsMediumWhenNotAuthExpired() {
        var record = RefreshRecord()
        record.succeeded(dataFetchedAt: Self.now.addingTimeInterval(-25 * 3600))
        let alerts = AlertEngine.syncAlerts(
            refresh: record, now: Self.now, notificationsAuthorized: true, remindersEnabled: true,
            backgroundRefreshEnabled: true, schoolEnabled: true)
        #expect(alerts.map(\.kind) == [.sync(.staleOver24h)])
    }

    @Test func notificationsOffWithRulesOnIsMedium() {
        let alerts = AlertEngine.syncAlerts(
            refresh: RefreshRecord(), now: Self.now, notificationsAuthorized: false, remindersEnabled: true,
            backgroundRefreshEnabled: true, schoolEnabled: true)
        #expect(alerts.contains { $0.kind == .sync(.notificationsOffRulesOn) && $0.severity == .medium })
    }

    @Test func notificationsOffWithRulesOffDoesNotFire() {
        let alerts = AlertEngine.syncAlerts(
            refresh: RefreshRecord(), now: Self.now, notificationsAuthorized: false, remindersEnabled: false,
            backgroundRefreshEnabled: true, schoolEnabled: true)
        #expect(!alerts.contains { $0.kind == .sync(.notificationsOffRulesOn) })
    }

    @Test func backgroundRefreshOffIsInfo() {
        let alerts = AlertEngine.syncAlerts(
            refresh: RefreshRecord(), now: Self.now, notificationsAuthorized: true, remindersEnabled: true,
            backgroundRefreshEnabled: false, schoolEnabled: true)
        #expect(alerts.contains { $0.kind == .sync(.backgroundRefreshOff) && $0.severity == .info })
    }

    @Test func schoolNotEnabledIsHigh() {
        let alerts = AlertEngine.syncAlerts(
            refresh: RefreshRecord(), now: Self.now, notificationsAuthorized: true, remindersEnabled: true,
            backgroundRefreshEnabled: true, schoolEnabled: false)
        #expect(alerts.contains { $0.kind == .sync(.schoolNotEnabled) && $0.severity == .high })
    }

    @Test func noConditionsMeansNoAlerts() {
        let alerts = AlertEngine.syncAlerts(
            refresh: RefreshRecord(), now: Self.now, notificationsAuthorized: true, remindersEnabled: true,
            backgroundRefreshEnabled: true, schoolEnabled: true)
        #expect(alerts.isEmpty)
    }

    // MARK: - §2.3 dismiss / worsen / snooze

    @Test func noPriorStateIsAlwaysVisible() {
        let alert = Alert(kind: .belowGoal(courseID: "c1"), severity: .high)
        #expect(AlertEngine.isVisible(alert, state: nil, now: Self.now))
    }

    @Test func dismissedStaysHiddenOnARoutineRefresh() {
        let alert = Alert(kind: .belowGoal(courseID: "c1"), severity: .high)
        let state = AlertState(dismissedAt: Self.now, dismissedSeverity: .high)
        #expect(!AlertEngine.isVisible(alert, state: state, now: Self.now.addingTimeInterval(3600)))
    }

    @Test func dismissedReappearsOnHigherSeverity() {
        let worse = Alert(kind: .belowGoal(courseID: "c1"), severity: .critical)
        let state = AlertState(dismissedAt: Self.now, dismissedSeverity: .high)
        #expect(AlertEngine.isVisible(worse, state: state, now: Self.now))
    }

    @Test func dismissedReappearsWhenTheGapWorsensEnough() {
        let alert = Alert(kind: .belowGoal(courseID: "c1"), severity: .high)
        let state = AlertState(dismissedAt: Self.now, dismissedSeverity: .high)
        #expect(!AlertEngine.isVisible(alert, state: state, now: Self.now, gapGrewBy: 1.0))
        #expect(AlertEngine.isVisible(alert, state: state, now: Self.now, gapGrewBy: 2.0))
    }

    @Test func snoozedIsHiddenUntilItPasses() {
        let alert = Alert(kind: .belowGoal(courseID: "c1"), severity: .high)
        let state = AlertState(snoozedUntil: Self.now.addingTimeInterval(3600))
        #expect(!AlertEngine.isVisible(alert, state: state, now: Self.now))
        #expect(AlertEngine.isVisible(alert, state: state, now: Self.now.addingTimeInterval(3601)))
    }

    @Test func aNewAlertTypeOnTheSameSubjectHasNoPriorStateAndIsVisible() {
        // A3 (due:<id>) and A1 (missing:<id>) have different dedupe keys, so
        // dismissing A3 leaves no state for A1's key: it is visible by
        // construction, matching "a new type… is a worsening" (§2.3).
        let dueSoon = Alert(kind: .dueSoon(assignmentID: "a1"), severity: .high)
        let missing = Alert(kind: .missingOpen(assignmentID: "a1"), severity: .high)
        #expect(dueSoon.dedupeKey != missing.dedupeKey)
        #expect(AlertEngine.isVisible(missing, state: nil, now: Self.now))
    }

    // MARK: - Severity ranking

    @Test func rankOrdersSeverityThenPriority() {
        let low = Alert(kind: .dueSoon(assignmentID: "a1"), severity: .medium, priority: 90)
        let high = Alert(kind: .dueSoon(assignmentID: "a2"), severity: .high, priority: 1)
        #expect(high.rank > low.rank, "severity band always outranks priority within a lower band")
    }

    @Test func dedupeKeysAreStableAndDistinct() {
        let a = Alert(kind: .missingOpen(assignmentID: "111"), severity: .high)
        let b = Alert(kind: .missingOpen(assignmentID: "111"), severity: .critical)
        let c = Alert(kind: .missingOpen(assignmentID: "222"), severity: .high)
        #expect(a.dedupeKey == b.dedupeKey, "same subject, different severity: same key")
        #expect(a.dedupeKey != c.dedupeKey)
    }
}
