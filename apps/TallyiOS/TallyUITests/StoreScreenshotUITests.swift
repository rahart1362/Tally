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
        language == "es" ? ["-AppleLanguages", "(es)", "-AppleLocale", "es_US"] : pinnedLocaleArguments
    }

    /// MVP-2i's own fixed-date hook (`TallyUITestCase.defaultTestHookArguments`'s doc comment
    /// named this suite as an expected adopter once it landed): the sample fixtures' dates are
    /// relative to today, so a Store-bound capture against the real clock would never repeat and
    /// would drift out of date on every run. `TestHooks.fixedNowWednesday` pins every scene to the
    /// same instant `AuditTourUITests` and the accessibility audit already use (a Wednesday,
    /// mid-week, chosen for representativeness).
    override class var defaultTestHookArguments: [String] { TestHooks.fixedNowWednesday }

    private static var appearance: XCUIDevice.Appearance {
        ProcessInfo.processInfo.environment["STORE_SHOTS_APPEARANCE"] == "dark" ? .dark : .light
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

    /// Waits at rest (`AuditTourUITests.waitUntilAtRest`'s own rule: two screenshots 0.4 s apart,
    /// pixel-identical, up to 6 s — pmo-ux-common.md's "captures only at rest"), then attaches the
    /// screenshot as `NN-<scene>`.
    @MainActor
    private func capture(_ app: XCUIApplication, number: Int, scene: String) {
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
        let grades = element("courseDetail.segment.grades", in: app)
        if scrollUntilHittable(grades, in: app) { grades.tap() }
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
        XCTAssertTrue(element("whatif.projected", in: app).waitForExistence(timeout: 10),
                     "What-If opened with no content. Hierarchy: \(app.debugDescription)")
        app.swipeUp() // fully presented, like AuditTourUITests.testB2_firstCourseMenuAndWhatIf.
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
