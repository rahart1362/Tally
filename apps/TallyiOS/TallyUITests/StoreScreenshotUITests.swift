import XCTest

/// MVP-3 (ASC-12, R14 in `docs/pmo/reviews/app-store-compliance.md`; UX-WP-23 in
/// `docs/pmo/reviews/ux-ui.md`): the App Store screenshot pipeline's capture suite. It runs ONLY
/// from the "Store screenshots" workflow (`.github/workflows/store-screenshots.yml`, dispatchable
/// on its own or called by "Release gate"), which sets `TALLY_STORE_SHOTS`; everywhere else (CI,
/// local runs) every method skips in `setUpWithError`, the same gate `AuditTourUITests` uses for
/// `AUDIT_APPEARANCE`.
///
/// Eight scenes, each ONE capture, at rest (pmo-ux-common.md's visual quality bar: "captures only
/// at rest"), in Sample Data / the bundled flagship persona (synthetic data only, ASC-11): the
/// Dashboard hero with its trend, Courses with the sparklines, Course detail (grades + chart),
/// the What-If sheet, To-Do, Calendar, Insights, and (scene 8) parent mode.
///
/// **Scene 8 is parent mode, not a composited widget render.** The Home Screen itself is not
/// reachable in XCUITest (the brief's own framing), and the brief allows widget renders "only if
/// they are honest renders of the real widget views" — `WidgetFamilyRenderTests` (TallyAppTests,
/// M3-D's own file, outside this work package's ownership) already produces honest, hosted
/// renders with the real `containerBackground`, but not at every combination this pipeline needs:
/// its own `spanishSnapshot` is light-only (no dark+es), and extending it would mean editing a
/// file owned by another work package. The brief's explicit fallback applies instead: "otherwise
/// use parent mode" — real app UI, already proven reachable in both languages by
/// `AuditTourUITests.testN_sampleDataAndParentMode` and `ReviewPathUITests`'s own walk.
///
/// Appearance and language are read the same way `AuditTourUITests` reads `AUDIT_APPEARANCE` /
/// `AUDIT_LANGUAGE`: the workflow sets the simulator's own appearance with `simctl ui ...
/// appearance` *before* `xcodebuild test` runs (`XCUIDevice.shared.appearance` alone does not
/// reliably repaint it — `AuditTourUITests`'s own doc comment, run 37649050231), and
/// `TEST_RUNNER_STORE_SHOTS_APPEARANCE` / `TEST_RUNNER_STORE_SHOTS_LANGUAGE` land here as
/// `STORE_SHOTS_APPEARANCE` / `STORE_SHOTS_LANGUAGE` (the `TEST_RUNNER_` prefix is `xcodebuild`'s
/// own mechanism for reaching the UI test runner process). Each capture's attachment is named
/// `NN-<scene>` only; `scripts/release/screenshots.py` adds the `-<light|dark>-<en|es>` suffix
/// once it knows this leg's own appearance and language (read from the workflow's own per-leg
/// artifact name, `store-shots-<appearance>-<language>`) — the same division of labour
/// `audit-tour.yml` already uses between the Swift suite (scene content) and the workflow's own
/// per-leg naming (appearance/language).
///
/// **Unlike `AuditTourUITests`, every assertion here is hard** (`continueAfterFailure` stays
/// `false`, `TallyUITestCase`'s own default): these are the actual Store-bound captures, so a
/// scene whose content failed to load must fail the run loudly, never silently capture a blank
/// or broken screen.
final class StoreScreenshotUITests: TallyUITestCase {
    private static var language: String {
        ProcessInfo.processInfo.environment["STORE_SHOTS_LANGUAGE"] ?? "en"
    }

    override class var currentLocaleArguments: [String] {
        // MVP-3 gate-2 review (I6): the target listing is es-MX (docs/pmo/08-localization-and-
        // external-grades.md:190), not es-US -- every CLDR Spanish locale renders day-first dates
        // ("21 oct"), but the capture ran under es_US, which (on this host/runtime) read
        // month-first instead. es_MX matches the actual listing locale.
        language == "es" ? ["-AppleLanguages", "(es)", "-AppleLocale", "es_MX"] : pinnedLocaleArguments
    }

    /// MVP-3 gate-2 review (I5): a STORE-ONLY fixed instant, not the shared
    /// `TestHooks.fixedNowWednesday` (which the accessibility audit also uses and which this file
    /// must not change). `12:00:00Z` is early morning in the flagship persona's own time zone
    /// (`America/Chicago`, fixtures/canvas/manifest.json), which made "Good afternoon" and
    /// "Updated Wed 12:00 PM" read as UTC artifacts once the capture ran in that zone (see
    /// `launchApp(arguments:)` below). `17:00:00Z` is midday (12:00 PM CDT) in Chicago instead.
    private static let fixedNowChicagoMidday = TestHooks.fixedNow("2026-10-14T17:00:00Z")

    override class var defaultTestHookArguments: [String] { fixedNowChicagoMidday }

    private static var appearance: XCUIDevice.Appearance {
        ProcessInfo.processInfo.environment["STORE_SHOTS_APPEARANCE"] == "dark" ? .dark : .light
    }

    /// MVP-3 gate-2 review (I5): every launch in this suite runs in the flagship persona's own
    /// time zone instead of the CI runner's UTC, so its fixture deadlines/lecture times (stored
    /// in UTC, e.g. an 11:59 PM CDT deadline as `T04:59:59Z`) render as the wall-clock times a
    /// Chicago student actually sees, not raw UTC ("Due Sat at 4:59 AM"). Overrides
    /// `TallyUITestCase.launchApp(arguments:)` (not wrapped: `app.launchEnvironment` must be set
    /// before `.launch()`, and the base method launches inline) to add exactly one entry on top of
    /// its own setup.
    @MainActor
    @discardableResult
    override func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += Self.currentLocaleArguments + TestHooks.entitled + Self.defaultTestHookArguments + arguments
        app.launchEnvironment.merge(Self.watchdogEnvironment) { _, armed in armed }
        app.launchEnvironment["TZ"] = "America/Chicago"
        app.launch()
        return app
    }

    /// The Home shell's tab bar items, by this leg's language (`AuditTourUITests.tabLabel`'s own
    /// table, copied: the tab bar itself carries no accessibility identifier to XCUITest).
    private static let tabLabels: [String: [String: String]] = [
        "courses": ["en": "Courses", "es": "Cursos"],
        "calendar": ["en": "Calendar", "es": "Calendario"],
        "toDo": ["en": "To-Do", "es": "Por hacer"],
        "insights": ["en": "Insights", "es": "Estadísticas"],
    ]
    private static func tabLabel(_ tab: String) -> String { tabLabels[tab]?[language] ?? tabLabels[tab]?["en"] ?? "" }

    private var runs = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TALLY_STORE_SHOTS"] != nil,
                          "StoreScreenshotUITests runs only when TALLY_STORE_SHOTS is set (the Store screenshots workflow)")
        runs = true
    }

    override func tearDownWithError() throws {
        guard runs else { return }
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        XCUIDevice.shared.appearance = Self.appearance
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + TestHooks.deviceAuth("success")
            + ["-TallyTestHooks.notifications", "notDetermined:denied"])
        XCTAssertTrue(element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30),
                     "the seeded launch never painted the dashboard. Hierarchy: \(app.debugDescription)")
        return app
    }

    /// MVP-3 gate-2 review (I1, fix list item 1's "either way"): fails loudly if any `staticText`
    /// that is not itself a tab-bar label sits under the floating tab bar's own frame. Scenes with
    /// no tab bar on screen (the What-If sheet) skip silently. This is a hard check, not a
    /// heuristic: the owner's binding bar is "no content under the bars" (pmo-ux-common.md), and
    /// the app-wide `.scrollEdgeEffectStyle(.hard, for: .bottom)` fix (`TallyScreenChrome`) is what
    /// is actually supposed to prevent it — this just proves it did, on every capture, not only the
    /// ones a reviewer happens to crop.
    @MainActor
    private func assertNothingUnderTheTabBar(_ app: XCUIApplication, scene: String) {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists else { return }
        let tabBarFrame = tabBar.frame
        let tabLabels = Set(app.tabBars.buttons.allElementsBoundByIndex.map(\.label))
        let offenders = app.staticTexts.allElementsBoundByIndex.filter { text in
            text.exists && text.frame.intersects(tabBarFrame) && !tabLabels.contains(text.label)
        }
        XCTAssertTrue(offenders.isEmpty,
                     "\(scene): content under the tab bar: " +
                     "\(offenders.map { "'\($0.label)' \($0.frame)" }). Tab bar frame: \(tabBarFrame). " +
                     "Hierarchy: \(app.debugDescription)")
    }

    /// Waits at rest (`AuditTourUITests.waitUntilAtRest`'s own rule: two screenshots 0.4 s apart,
    /// pixel-identical, up to 6 s — pmo-ux-common.md's "captures only at rest"), checks nothing
    /// sits under the tab bar (I1), then attaches the screenshot as `NN-<scene>`.
    @MainActor
    private func capture(_ app: XCUIApplication, number: Int, scene: String) {
        assertNothingUnderTheTabBar(app, scene: scene)
        let settled = waitUntilAtRest(app)
        XCTAssertTrue(settled, "\(scene) never settled before capture. Hierarchy: \(app.debugDescription)")
        let name = String(format: "%02d-%@", number, scene)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func waitUntilAtRest(_ app: XCUIApplication, timeout: TimeInterval = 6, interval: TimeInterval = 0.4) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = app.screenshot().pngRepresentation
        while Date() < deadline {
            Thread.sleep(forTimeInterval: interval)
            let next = app.screenshot().pngRepresentation
            if next == previous { return true }
            previous = next
        }
        return false
    }

    // MARK: - 1: the Dashboard hero with the trend

    @MainActor
    func test01_dashboard() throws {
        resetAppState()
        let app = launchSignedIn()
        // UX-SPARK-2: the trend only shows over a real percentage (DashboardView.swift); the
        // flagship persona has five averaged courses, so it is expected here.
        XCTAssertTrue(element("dashboard.sparkline", in: app).waitForExistence(timeout: 15),
                     "no dashboard trend sparkline. Hierarchy: \(app.debugDescription)")
        capture(app, number: 1, scene: "dashboard")
        app.terminate()
    }

    // MARK: - 2: the Courses list with the sparklines

    @MainActor
    func test02_courses() throws {
        resetAppState()
        let app = launchSignedIn()
        openTab(Self.tabLabel("courses"), in: app)
        XCTAssertTrue(element("course.card", in: app).waitForExistence(timeout: 15),
                     "Courses shows no content. Hierarchy: \(app.debugDescription)")
        capture(app, number: 2, scene: "courses")
        app.terminate()
    }

    // MARK: - 3: Course detail with the grades and the chart

    @MainActor
    func test03_courseDetail() throws {
        resetAppState()
        let app = launchSignedIn()
        openTab(Self.tabLabel("courses"), in: app)
        let card = elements("course.card", in: app).element(boundBy: 0)
        XCTAssertTrue(scrollUntilHittable(card, in: app), "no course card. Hierarchy: \(app.debugDescription)")
        card.tap()
        XCTAssertTrue(element("courseDetail.hero", in: app).waitForExistence(timeout: 15),
                     "Course detail shows no content. Hierarchy: \(app.debugDescription)")
        // MVP-3 gate-2 review (I7): the Grades segment (4 summary rows) left about 220 pt of empty
        // canvas above the tab bar. Assignments is a full list, grouped by category, which fills
        // the frame; the hero card above the segments still carries the grade and its sparkline
        // (UX-WP-23's "grades + chart"), on every segment.
        let assignments = element("courseDetail.segment.assignments", in: app)
        if scrollUntilHittable(assignments, in: app) { assignments.tap() }
        capture(app, number: 3, scene: "course-detail")
        app.terminate()
    }

    // MARK: - 4: the What-If sheet

    @MainActor
    func test04_whatIf() throws {
        resetAppState()
        let app = launchSignedIn()
        openTab(Self.tabLabel("courses"), in: app)
        let card = elements("course.card", in: app).element(boundBy: 0)
        XCTAssertTrue(scrollUntilHittable(card, in: app), "no course card. Hierarchy: \(app.debugDescription)")
        card.tap()
        XCTAssertTrue(element("courseDetail.hero", in: app).waitForExistence(timeout: 15),
                     "Course detail shows no content. Hierarchy: \(app.debugDescription)")
        let whatIf = element("courseDetail.whatIf", in: app)
        XCTAssertTrue(scrollUntilHittable(whatIf, in: app), "no What-If button. Hierarchy: \(app.debugDescription)")
        whatIf.tap()
        let projected = element("whatif.projected", in: app)
        XCTAssertTrue(projected.waitForExistence(timeout: 10),
                     "What-If opened with no content. Hierarchy: \(app.debugDescription)")
        app.swipeUp() // fully presented, like AuditTourUITests.testB2_firstCourseMenuAndWhatIf.

        // MVP-3 gate-2 review (I3): the scene must show the feature exercised, not the empty
        // initial state (every field at its placeholder, every slider at 0, Reset disabled,
        // "Projected" equal to the course's current grade -- CourseDetailUITests' own baseline
        // phrase, "the same as your current grade", reused here for the same reason it uses it).
        // Types a score into the first item and taps a quick-fill preset on the second: the same
        // two input mechanisms CourseDetailUITests exercises separately (slider, typed digits),
        // here together with presets so the capture shows a genuinely different projection.
        XCTAssertTrue(eventually(timeout: 10) { projected.label.contains("the same as your current grade") },
                     "the baseline never landed: '\(projected.label)'")
        let firstField = elements("whatif.field", in: app).element(boundBy: 0)
        XCTAssertTrue(firstField.waitForExistence(timeout: 10), "no What-If score field. Hierarchy: \(app.debugDescription)")
        firstField.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(eventually(timeout: scaled(5)) { app.keyboards.count > 0 },
                     "the score field never took the keyboard. Hierarchy: \(app.debugDescription)")
        firstField.typeText("47")
        let secondPreset = elements("whatif.quickFill.90", in: app).element(boundBy: 1)
        XCTAssertTrue(secondPreset.waitForExistence(timeout: 5), "no second item's 90% preset. Hierarchy: \(app.debugDescription)")
        secondPreset.tap() // a tap on a different control dismisses the keyboard.
        XCTAssertTrue(eventually(timeout: 15) { !projected.label.contains("the same as your current grade") },
                     "the projection did not move after entering a score and a preset: '\(projected.label)'")
        let resetButton = element("whatif.reset", in: app)
        XCTAssertTrue(resetButton.isEnabled, "Reset stayed disabled after exercising What-If. Hierarchy: \(app.debugDescription)")

        capture(app, number: 4, scene: "what-if")
        app.terminate()
    }

    // MARK: - 5: To-Do

    @MainActor
    func test05_toDo() throws {
        resetAppState()
        let app = launchSignedIn()
        openTab(Self.tabLabel("toDo"), in: app)
        XCTAssertTrue(elementsWithPrefix("todo.row", in: app).firstMatch.waitForExistence(timeout: 15),
                     "To-Do shows no content. Hierarchy: \(app.debugDescription)")
        capture(app, number: 5, scene: "todo")
        app.terminate()
    }

    // MARK: - 6: Calendar

    @MainActor
    func test06_calendar() throws {
        resetAppState()
        let app = launchSignedIn()
        openTab(Self.tabLabel("calendar"), in: app)
        XCTAssertTrue(elements("calendar.day", in: app).firstMatch.waitForExistence(timeout: 15),
                     "Calendar shows no content. Hierarchy: \(app.debugDescription)")
        capture(app, number: 6, scene: "calendar")
        app.terminate()
    }

    // MARK: - 7: Insights

    @MainActor
    func test07_insights() throws {
        resetAppState()
        let app = launchSignedIn()
        openTab(Self.tabLabel("insights"), in: app)
        XCTAssertTrue(element("chart.trend", in: app).waitForExistence(timeout: 30),
                     "Insights shows no content. Hierarchy: \(app.debugDescription)")
        capture(app, number: 7, scene: "insights")
        app.terminate()
    }

    // MARK: - 8: parent mode (see the file's own doc comment for why, not a widget render)

    @MainActor
    func test08_parentMode() throws {
        resetAppState()
        XCUIDevice.shared.appearance = Self.appearance
        let app = launchApp()
        let exploreSampleData = element("account.exploreWithSampleData", in: app)
        XCTAssertTrue(exploreSampleData.waitForExistence(timeout: 30), "Hierarchy: \(app.debugDescription)")
        exploreSampleData.tap()
        XCTAssertTrue(element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30),
                     "the sample projection never landed. Hierarchy: \(app.debugDescription)")
        openSettings(app)
        let exploreParentMode = app.buttons["family.sample.viewAsParent"]
        XCTAssertTrue(scrollUntilHittable(exploreParentMode, in: app, maxSwipes: 30),
                     "no family.sample.viewAsParent. Hierarchy: \(app.debugDescription)")
        exploreParentMode.tap() // Settings dismisses itself (AppModel.enterSampleFamily()).
        XCTAssertTrue(element("family.switcher", in: app).waitForExistence(timeout: 15),
                     "parent mode shows no content. Hierarchy: \(app.debugDescription)")
        capture(app, number: 8, scene: "parent-mode")
        app.terminate()
    }
}
