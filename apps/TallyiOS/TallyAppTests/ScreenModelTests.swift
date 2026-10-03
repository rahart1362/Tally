import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// A `CanvasGateway` that serves one fixed snapshot.
actor ServingGateway: CanvasGateway {
    private let snapshot: CanvasSnapshot

    init(_ snapshot: CanvasSnapshot) {
        self.snapshot = snapshot
    }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        snapshot
    }
}

enum ScreenModelSupport {
    static func projector() -> HomeProjector {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return HomeProjector(calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    /// A started `HomeModel` over the flagship persona at the fixtures' capture instant.
    @MainActor
    static func startedModel(localStore: any LocalScreenStateStoring = InMemoryLocalScreenStateStore(),
                             userState: any UserStateAccess = InMemoryUserStateAccess())
        async throws -> (HomeModel, FakeHomeSource, CanvasSnapshot) {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ScreenFixtures.anchor)
        let source = FakeHomeSource(HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: ScreenFixtures.anchor)))
        let model = HomeModel(source: source, projector: projector(), clock: TestClock(ScreenFixtures.anchor),
                              localStore: localStore, userState: userState)
        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })
        return (model, source, snapshot)
    }

    /// A temporary, vault-sealed store directory for one account.
    static func sealer(_ account: AccountKey) throws -> (URL, VaultSealer) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tally-m3-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(directory, excludeFromBackup: true)
        let sealer = VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        return (directory, sealer)
    }
}

/// M3-A: `HomeModel` carries every screen's projection, each set only when it changed, and keeps
/// the student's course order across new generations (UX-WP-14).
@Suite("M3-A: HomeModel screens and the student's local state", .serialized)
@MainActor
struct HomeModelScreenTests {
    @Test("a projection fills every screen")
    func screensAreProjected() async throws {
        let (model, _, snapshot) = try await ScreenModelSupport.startedModel()
        #expect(model.courseCards.map(\.id) == snapshot.courses.map(\.id))
        #expect(model.courseDetails.count == 5)
        #expect(model.toDoScreen.sections.first?.kind == .missing)
        #expect(model.calendarScreen.week.count == 7)
        #expect(model.insightsScreen.completion != nil)
        #expect(model.account.host == "canvas.northfield.example")
        #expect(!model.isSampleData, "a FakeHomeSource is not sample mode")
    }

    @Test("a move shows at once, is kept in the local store, and survives the next generation")
    func moveCoursesPersists() async throws {
        let store = InMemoryLocalScreenStateStore()
        let (model, source, snapshot) = try await ScreenModelSupport.startedModel(localStore: store)
        let before = model.courseCards.map(\.id)
        model.moveCourses(fromOffsets: IndexSet(integer: 0), toOffset: before.count)
        let moved = Array(before.dropFirst()) + [before[0]]
        #expect(model.courseCards.map(\.id) == moved)
        #expect(model.local.courseOrder == moved)
        await model.local.awaitSaved()
        #expect(await store.load().courseOrder == moved)

        await source.send(HomeTestSupport.update(snapshot, generation: 2, freshness: .fresh(at: ScreenFixtures.anchor)))
        #expect(try await AccountTestSupport.eventually { await model.projector.projectionCount == 2 })
        #expect(model.courseCards.map(\.id) == moved, "a new generation reverted the student's order")
    }

    @Test("a new Home over the same store opens in the stored order and with the stored done marks")
    func storedStateIsRestored() async throws {
        let store = InMemoryLocalScreenStateStore()
        let (first, _, _) = try await ScreenModelSupport.startedModel(localStore: store)
        let reversed = Array(first.courseCards.map(\.id).reversed())
        first.local.setCourseOrder(reversed)
        let done: CanvasID<Assignment> = "1204405"
        first.local.setDone([done], done: true)
        await first.local.awaitSaved()

        let (second, _, _) = try await ScreenModelSupport.startedModel(localStore: store)
        #expect(second.courseCards.map(\.id) == reversed)
        #expect(second.local.isDone(done))
        second.local.setDone([done], done: false)
        #expect(!second.local.isDone(done))
    }

    @Test("a store keeps the newest of two saves that arrive out of order")
    func newestSaveWins() async {
        let store = InMemoryLocalScreenStateStore()
        await store.save(LocalScreenState(courseOrder: ["b"], revision: 2))
        await store.save(LocalScreenState(courseOrder: ["a"], revision: 1))
        #expect(await store.load().courseOrder == ["b"])
    }
}

/// UX-WP-20 / DG-1: the "What changed" threshold, "All" or points, globally and per course, is
/// written to `UserState.digestThresholds` and reaches `RefreshCoordinator.updateDigestThresholds`.
@Suite("M3-A: Settings' What-changed threshold", .serialized)
@MainActor
struct SettingsThresholdTests {
    @Test("every change is written to UserState: All, points, per course, and back to the default")
    func writesUserState() async throws {
        let access = InMemoryUserStateAccess()
        let settings = SettingsModel(userState: access)
        await settings.load()
        #expect(settings.thresholds == .default)

        settings.setEveryChange(true)
        await settings.awaitSaved()
        #expect(await access.load().digestThresholds.global == .all)

        settings.setEveryChange(false)
        settings.setGlobalPoints(2)
        settings.setGlobalPoints(100) // clamped to the stepper's range
        let math: CanvasID<Course> = "51842"
        settings.setThreshold(.all, for: math)
        await settings.awaitSaved()
        var stored = await access.load().digestThresholds
        #expect(stored.global == .points(SettingsModel.pointRange.upperBound))
        #expect(stored.threshold(for: math) == .all)

        settings.setThreshold(nil, for: math)
        await settings.awaitSaved()
        stored = await access.load().digestThresholds
        #expect(stored.perCourse[math] == nil)
        #expect(settings.thresholds == stored)
        #expect(!settings.saveFailed)
    }

    /// The flagship world moves MATH 122 by 0.01 points between `flagship-previous` and `flagship`
    /// (fixtures/canvas/expected/digest/flagship.json): hidden by the 0.5-point default, reported
    /// once MATH 122 is set to "All".
    @Test("a signed-in account's thresholds are sealed on disk and reach the coordinator's next digest",
          .timeLimit(.minutes(2)))
    func accountThresholdsReachTheCoordinator() async throws {
        let previous = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship-previous", now: ScreenFixtures.anchor)
        let current = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ScreenFixtures.anchor)
        let math: CanvasID<Course> = "51842"

        func committedDigest(setting threshold: ScoreChangeThreshold?) async throws -> (ChangeDigest?, UserStateLoadResult) {
            let account = AccountKey("m3-threshold-\(UUID().uuidString)")
            let (directory, sealer) = try ScreenModelSupport.sealer(account)
            let coordinator = RefreshCoordinator(
                gateway: ServingGateway(current), store: SnapshotStore(root: directory, accountKey: account, sealer: sealer),
                clock: SystemDateProvider(), initialSnapshot: previous)
            let runtime = AccountRuntime()
            await runtime.install(coordinator)
            let userStateStore = UserStateStore(root: directory, accountKey: account, sealer: sealer)
            let settings = SettingsModel(userState: AccountUserStateAccess(store: userStateStore, runtime: runtime))
            await settings.load()
            if let threshold { settings.setThreshold(threshold, for: math) }
            await settings.awaitSaved()

            let events = await coordinator.events()
            _ = await coordinator.run(trigger: .manual)
            var digest: ChangeDigest?
            for await event in events {
                if case .committed(_, let committed) = event {
                    digest = committed
                    break
                }
            }
            return (digest, await userStateStore.load())
        }

        let (defaultDigest, untouched) = try await committedDigest(setting: nil)
        #expect(untouched == .absent, "nothing was changed, so nothing was written")
        #expect(defaultDigest?.courseScoreChanges.contains { $0.courseID == math } == false)

        let (allDigest, written) = try await committedDigest(setting: .all)
        guard case .loaded(let stored) = written else {
            Issue.record("the UserState file was not written: \(written)")
            return
        }
        #expect(stored.digestThresholds.threshold(for: math) == .all)
        let change = try #require(allDigest?.courseScoreChanges.first { $0.courseID == math })
        #expect(abs(change.delta - 0.01) < 0.000_1)
    }

    @Test("a UserState written by a newer build reads as the defaults and is never overwritten")
    func refusesToOverwrite() async throws {
        let account = AccountKey("m3-refuse-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        // A newer build's user state: schema 99, which this build must keep and report.
        let url = StoreLayout(root: directory, accountKey: account).url(for: .userState)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let future = Data(#"{"schemaVersion":99}"#.utf8)
        try SealedFileAccess(sealer: sealer, isOwner: true).write(future, .userState, to: url, excludeFromBackup: true)
        let store = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        #expect(await store.load() == .unavailable(.keepAndReport))

        let access = AccountUserStateAccess(store: store, runtime: AccountRuntime())
        #expect(await access.load() == UserState(), "an unreadable state reads as the defaults")
        await #expect(throws: AccountUserStateAccess.AccessError.notWritable(.keepAndReport)) {
            try await access.update { $0.digestThresholds = DigestThresholds(global: .all) }
        }
        #expect(SealedFileAccess(sealer: sealer, isOwner: true).read(.userState, at: url) == .plaintext(future),
                "the newer build's file was changed")
    }
}

/// UX-WP-16: the what-if sheet runs the domain engine only through `GradeWork`, and every edit
/// replaces the computation before it.
@Suite("M3-A: What-if (GradeWork only)", .serialized)
@MainActor
struct WhatIfModelTests {
    private static func mathSetup() async throws -> WhatIfSetup {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let math = try #require(snapshot.courses.first { $0.courseCode == "MATH 122" })
        return try #require(screens.courseDetails[math.id]?.whatIf)
    }

    @Test("the baseline is the engine's current score, and with no hypothetical scores the projection equals it")
    func baseline() async throws {
        let model = WhatIfModel(setup: try await Self.mathSetup())
        await model.start()
        let baseline = try #require(model.baseline)
        #expect(abs(baseline - 90.1) < 0.01, "engine parity with Canvas's 90.1")
        #expect(model.projected == baseline)
        #expect(model.delta == 0)
        #expect(model.goalOutcome != nil)
    }

    @Test("typing, stepping, quick-fill and reset; scores stay within the points possible")
    func editing() async throws {
        let setup = try await Self.mathSetup()
        let model = WhatIfModel(setup: setup)
        await model.start()
        let exam = try #require(setup.groups.first { $0.name == "Exams" }?.items.first)

        model.setScore(0, for: exam.id)
        await model.settle()
        let low = try #require(model.projected)
        #expect(low < (model.baseline ?? 0), "a zero on an exam lowers the grade")
        let direct = try await GradeWork.scores(applying: [.init(assignmentID: exam.id, score: 0)], to: setup.input)
        #expect(low == direct.currentScore)

        model.setScore(10_000, for: exam.id)
        #expect(model.scores[exam.id] == exam.pointsPossible)
        model.fill(exam.id, percent: 90)
        #expect(model.scores[exam.id] == exam.pointsPossible * 0.9)

        let quiz = try #require(setup.groups.first { $0.name == "Quizzes" }?.items.first)
        model.step(quiz.id, up: true)
        #expect(model.scores[quiz.id] == WhatIfModel.stepPoints)
        model.step(quiz.id, up: false)
        model.step(quiz.id, up: false)
        #expect(model.scores[quiz.id] == 0)

        model.reset()
        await model.settle()
        #expect(model.scores.isEmpty)
        #expect(model.projected == model.baseline)
    }

    @Test("a burst of edits lands on the answer for the last one")
    func burstLandsOnTheLastEdit() async throws {
        let setup = try await Self.mathSetup()
        let model = WhatIfModel(setup: setup)
        await model.start()
        let exam = try #require(setup.groups.first { $0.name == "Exams" }?.items.first)
        for points in stride(from: 0.0, through: 60, by: 5) { model.setScore(points, for: exam.id) }
        await model.settle()
        let expected = try await GradeWork.scores(applying: [.init(assignmentID: exam.id, score: 60)], to: setup.input)
        #expect(model.projected == expected.currentScore)
    }

    @Test("goal mode: the lowest score that reaches the target, from GoalSeek through GradeWork")
    func goal() async throws {
        let setup = try await Self.mathSetup()
        let model = WhatIfModel(setup: setup)
        await model.start()
        let exam = try #require(setup.groups.first { $0.name == "Exams" }?.items.first)
        model.setGoal(assignment: exam.id)
        model.setGoal(percent: 85)
        await model.settle()
        let expected = try await GradeWork.goalSeek(assignmentID: exam.id, targetPercent: 85, in: setup.input)
        #expect(model.goalOutcome == expected.outcome)
        model.setGoal(percent: 150)
        #expect(model.goalPercent == 100)
    }
}

@Suite("M3-A: Course Detail's category percentages and Insights' trend (GradeWork only)", .serialized)
@MainActor
struct GradeDerivedScreenTests {
    @Test("each MATH 122 category's current percentage is the engine's")
    func categoryPercents() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let math = try #require(snapshot.courses.first { $0.courseCode == "MATH 122" })
        let input = try #require(screens.courseDetails[math.id]?.gradeInput)
        let model = CourseGradesModel()
        await model.load(input)
        let expected = try await GradeWork.scores(for: input).posted.currentGroups
        #expect(model.categoryPercents.count == 3)
        for group in expected {
            #expect(model.categoryPercents[group.groupID] == group.grade)
        }
    }

    @Test("the trend ends at today's 'Average of N courses' (engine parity), and every range has a sentence")
    func trendEndsAtTheAverage() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let formatter = ScreenFixtures.formatter()
        let result = try await GradeTrend.compute(screens.insights.trendInput, calendar: formatter.calendar,
                                                  locale: formatter.locale)
        let scores = snapshot.courses.compactMap { $0.scores?.currentScore }
        let average = scores.reduce(0, +) / Double(scores.count)
        for range in TrendRange.allCases {
            let view = try #require(result.ranges[range])
            #expect(view.hasEnoughData)
            #expect(abs((view.points.last?.percent ?? 0) - average) < 0.01, "\(range)")
            #expect(view.summary.hasSuffix(range == .term ? "this term" : range == .month ? "over the last month"
                                                : "over the last 3 months"))
            #expect(view.points.allSatisfy { $0.date >= view.start && $0.date <= view.end })
        }
        let model = InsightsModel()
        await model.load(screens.insights.trendInput, calendar: formatter.calendar, locale: formatter.locale)
        #expect(model.trend == result)
    }

    @Test("the trend recomputes each day with only the scores posted by then (R9)")
    func trendUsesTheScoresPostedByEachDay() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let course = try #require(screens.insights.trendInput.courses.first)
        let dates = course.postedAt.values.sorted()
        let cut = try #require(dates.dropFirst(dates.count / 2).first)
        let asOf = GradeTrend.inputAsOf(course, postedBefore: cut)
        for item in asOf.items {
            guard let posted = course.postedAt[item.id] else { continue }
            #expect(item.submission?.posted == (posted < cut), "\(item.id): posted \(posted), cut \(cut)")
        }
        #expect(asOf.items.filter { $0.submission?.posted == true }.count
                < course.input.items.filter { $0.submission?.posted == true }.count)

        let formatter = ScreenFixtures.formatter()
        let result = try await GradeTrend.compute(screens.insights.trendInput, calendar: formatter.calendar,
                                                  locale: formatter.locale)
        let term = try #require(result.ranges[.term])
        #expect(Set(term.points.map(\.percent)).count > 1, "a flat line: the history was not derived")
    }

    @Test("no graded history reads as 'not enough data', never a fabricated line")
    func emptyTrend() async throws {
        let formatter = ScreenFixtures.formatter()
        let result = try await GradeTrend.compute(.empty, calendar: formatter.calendar, locale: formatter.locale)
        #expect(result.ranges.values.allSatisfy { !$0.hasEnoughData && $0.points.isEmpty })
        #expect(result.ranges[.term]?.summary == "Trend appears after a couple of graded assignments.")
    }

    // MARK: - UX-SPARK: the Courses cards' and Course Detail's trend sparkline

    @Test("UX-SPARK: each course's own sparkline series matches the engine's score as of each posted day")
    func perCourseSeriesMatchesTheEngine() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let formatter = ScreenFixtures.formatter()
        let result = try await GradeTrend.compute(screens.insights.trendInput, calendar: formatter.calendar,
                                                  locale: formatter.locale)
        #expect(!result.perCourse.isEmpty)
        for course in screens.insights.trendInput.courses {
            let days = Set(course.postedAt.values.map { formatter.calendar.startOfDay(for: $0) }).sorted()
            var expected: [TrendPoint] = []
            for day in days {
                guard let end = formatter.calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                if let score = try await GradeWork.scores(for: GradeTrend.inputAsOf(course, postedBefore: end)).currentScore {
                    expected.append(TrendPoint(date: day, percent: score))
                }
            }
            if expected.count >= 2 {
                #expect(result.perCourse[course.id] == expected, "\(course.id)")
            } else {
                #expect(result.perCourse[course.id] == nil, "\(course.id): fewer than 2 graded days")
            }
        }
    }

    @Test("UX-SPARK: a course with fewer than 2 graded days has no sparkline series")
    func fewerThanTwoGradedDaysHasNoSparkline() async throws {
        let group = GradeInput.Group(id: "g1", weight: 100)
        let item = GradeInput.Item(id: "a1", groupID: "g1", pointsPossible: 10, submission: .init(score: 9))
        let input = GradeInput(weighting: .percent, groups: [group], items: [item])
        let posted = ScreenFixtures.anchor.addingTimeInterval(-86_400)
        let course = TrendInput.CourseHistory(id: "course-one-point", input: input, postedAt: [item.id: posted])
        let trendInput = TrendInput(courses: [course], termStart: nil, now: ScreenFixtures.anchor)
        let formatter = ScreenFixtures.formatter()
        let result = try await GradeTrend.compute(trendInput, calendar: formatter.calendar, locale: formatter.locale)
        #expect(result.perCourse[course.id] == nil)
    }

    @Test("UX-SPARK: a course whose grade isn't in Canvas has no sparkline; SPAN-2 (graded in Canvas) does")
    func noSparklineWhenGradeNotInCanvas() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let formatter = ExternalGrades.formatter()
        let insights = InsightsBuilder.projection(from: snapshot, formatter: formatter)
        let result = try await GradeTrend.compute(insights.trendInput, calendar: formatter.calendar, locale: formatter.locale)
        let span = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        #expect((result.perCourse[span.id]?.count ?? 0) >= 2)
        for code in ["ENG-10", "ALG2", "BIO-H", "ART-1", "ADVISORY"] {
            let course = try #require(snapshot.courses.first { $0.courseCode == code })
            #expect(result.perCourse[course.id] == nil, "\(code)")
        }
    }

    @Test("UX-SPARK: CourseSparklineBuilder guards the same threshold, and never recomputes an unchanged input")
    func sparklineBuilderAndModel() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let formatter = ScreenFixtures.formatter()
        let result = try await GradeTrend.compute(screens.insights.trendInput, calendar: formatter.calendar,
                                                  locale: formatter.locale)
        let series = try #require(result.perCourse.values.first { $0.count >= 2 })
        #expect(CourseSparklineBuilder.build(series, formatter: formatter) != nil)
        #expect(CourseSparklineBuilder.build(Array(series.prefix(1)), formatter: formatter) == nil)
        #expect(CourseSparklineBuilder.build([], formatter: formatter) == nil)

        let model = CourseSparklineModel()
        await model.load(screens.insights.trendInput, calendar: formatter.calendar, locale: formatter.locale)
        #expect(!model.series.isEmpty)
        #expect(model.series.keys.allSatisfy { result.perCourse[$0] != nil })
    }

    @Test("UX-SPARK: the sparkline's VoiceOver sentence names the direction and the bare percentages")
    func sparklineSummaryWording() {
        let locale = Locale(identifier: "en_US")
        #expect(CourseSparklineBuilder.summary(first: 82.0, last: 87.2, locale: locale)
                == "Trend: up from 82.0 to 87.2 percent")
        #expect(CourseSparklineBuilder.summary(first: 87.2, last: 82.0, locale: locale)
                == "Trend: down from 87.2 to 82.0 percent")
        #expect(CourseSparklineBuilder.summary(first: 90.0, last: 90.02, locale: locale)
                == "Trend: steady at 90.0 percent")
    }
}
