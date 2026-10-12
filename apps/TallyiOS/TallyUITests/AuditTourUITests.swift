import XCTest

/// PMO design-quality audit tour: screenshots plus an automated layout check of every screen and
/// state, across device x appearance x text size. It runs ONLY from the `Audit tour` workflow
/// (`.github/workflows/audit-tour.yml`, manual dispatch on any branch), which sets `AUDIT_APPEARANCE`;
/// everywhere else (CI, local runs) every method skips in `setUpWithError`, like `TallyPerfUITests`.
/// First written on `pmo/audit-tour` (run 37649050231), modelled on `MarketingTourUITests`. It
/// asserts nothing: a step that cannot be reached records a "missing-<state>" screenshot and the
/// tour goes on.
///
/// **Why many small test methods, not one tour.** `IOS_TEST_FLAGS` caps every test at
/// `-maximum-test-execution-time-allowance 300` (Makefile, read before writing this), and a single
/// method covering every screen in this brief would run far longer than that and be killed before
/// finishing. Each method below is one bounded slice (one or two app launches, a handful of
/// screens), independently safe to time out without losing the other slices' evidence. XCTest does
/// not guarantee method execution order, so each method's screenshot numbers come from a fixed,
/// hand-assigned offset (the `stepNumber = …` line at its top), not from a shared counter — the
/// names stay stable across legs and across reorderings. For the same reason, the `manifest.json`
/// / `summary.json` attachments the brief asks for are written once per method, named
/// `<letter>-manifest.json` / `<letter>-summary.json`: together they cover the whole leg.
///
/// **At rest.** Every `snap` waits via `waitUntilAtRest` (two screenshots 0.4 s apart,
/// pixel-identical, up to 6 s) before capturing; an unsettled capture is kept but suffixed
/// `-UNSETTLED` rather than dropped.
///
/// **Layout check.** Every `snap` also takes one `app.snapshot()` (a single IPC call) and walks it
/// in `analyzeLayout`, attaching `<name>.layout.json`. `isHittable` is not part of a snapshot (only
/// live `XCUIElement` queries have it), so the "hit target" check approximates hittability as
/// enabled, on-screen and non-zero-area — documented here so the Opus reviewer reads the numbers
/// correctly.
///
/// **Appearance and text size.** Set by this leg's CI matrix through the test *process's own*
/// environment, never a code change: `TEST_RUNNER_AUDIT_APPEARANCE` / `TEST_RUNNER_AUDIT_TEXT_SIZE`
/// (the `TEST_RUNNER_` prefix is `xcodebuild`'s own mechanism for reaching the UI test runner
/// process — the same one `Makefile`'s `ios-perf` target already uses for `TALLY_PERF_RUN`) land
/// here as `AUDIT_APPEARANCE` / `AUDIT_TEXT_SIZE`. Appearance is applied with `XCUIDevice.shared
/// .appearance`; text size becomes the `-UIPreferredContentSizeCategoryName` launch argument
/// already used elsewhere in this target (`WelcomeCTAUITests`).
final class AuditTourUITests: TallyUITestCase {
    // MARK: - Leg configuration (read once; never varies this file's code)

    private static var appearance: XCUIDevice.Appearance {
        ProcessInfo.processInfo.environment["AUDIT_APPEARANCE"] == "dark" ? .dark : .light
    }

    private static var textSizeArguments: [String] {
        ProcessInfo.processInfo.environment["AUDIT_TEXT_SIZE"] == "ax5"
            ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            : []
    }

    /// Plan 08 L10N-04: the leg's language, from the `Audit tour` workflow's own `language` input
    /// (`TEST_RUNNER_AUDIT_LANGUAGE`, landing here as `AUDIT_LANGUAGE`, the same mechanism as
    /// `AUDIT_APPEARANCE`/`AUDIT_TEXT_SIZE` above). Default `en` when the workflow does not set it
    /// (every dispatch before this work package, and any future one that omits it).
    private static var language: String {
        ProcessInfo.processInfo.environment["AUDIT_LANGUAGE"] ?? "en"
    }

    /// Overrides `TallyUITestCase.currentLocaleArguments`: on an `es` leg the tour launches in
    /// Spanish instead of `TallyUITestCase`'s own English pin; every other suite is untouched
    /// (plan 08 L10N-04's brief: "the tour launches with `-AppleLanguages (es) -AppleLocale
    /// es_US` in place of `TallyUITestCase`'s en pin. Every other suite keeps the pin").
    override class var currentLocaleArguments: [String] {
        language == "es" ? ["-AppleLanguages", "(es)", "-AppleLocale", "es_US"] : pinnedLocaleArguments
    }

    /// The Home shell's tab bar items, by their current leg's language. Run 38175021381 found that
    /// `.accessibilityIdentifier` on a `Tab(_:systemImage:value:)` (iOS 18's `TabView` content
    /// builder) never reaches the tab bar button XCUITest actually queries ("No matches found …
    /// IN identifiers") — a real API gap, not something this work package can fix with an
    /// identifier alone, so `openTabInTour` keeps matching by label, now picking the right one for
    /// the leg's language instead of only English's.
    private static func tabLabel(_ tab: HomeTabForTour) -> String {
        let labels: [HomeTabForTour: [String: String]] = [
            .dashboard: ["en": "Dashboard", "es": "Tablero"],
            .courses: ["en": "Courses", "es": "Cursos"],
            .calendar: ["en": "Calendar", "es": "Calendario"],
            .toDo: ["en": "To-Do", "es": "Por hacer"],
            .insights: ["en": "Insights", "es": "Estadísticas"],
        ]
        return labels[tab]?[language] ?? labels[tab]?["en"] ?? ""
    }

    private enum HomeTabForTour {
        case dashboard, courses, calendar, toDo, insights
    }

    private static let demoHost = "canvas.northfield.example"

    // MARK: - Per-method bookkeeping (a fresh instance per test method; never shared)

    private var stepNumber = 0
    private var manifestEntries: [[String: String]] = []
    private var summaryCounts: [String: [String: Int]] = [:]

    /// True once `setUpWithError` passed the workflow check; a skipped method has nothing to reset.
    private var runs = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AUDIT_APPEARANCE"] != nil,
                          "The audit tour runs only from the Audit tour workflow (it sets AUDIT_APPEARANCE)")
        runs = true
    }

    override func tearDownWithError() throws {
        // Every suite that signs in or seeds an account resets afterwards (LifecycleUITestSupport);
        // this tour does both repeatedly, so it always leaves Welcome for whichever method is next.
        guard runs else { return }
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    private func finish(_ letter: String) {
        attachJSON(summaryCounts, name: "\(letter)-summary.json")
        attachJSON(manifestEntries, name: "\(letter)-manifest.json")
    }

    // MARK: - A: Dashboard

    @MainActor
    func testA_dashboard() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 0
        resetAppState()

        let app = launchSignedIn()
        captureScreenfuls(app, screen: "dashboard", reachedVia: "signed-in launch", maxScreens: 14)

        // Reminders tip: answer it (scripted "denied") so Settings' Reminders section (method G)
        // shows the answered state instead of the un-asked one.
        scrollToTop(app)
        let turnOn = app.buttons["tip.enableReminders"]
        if scrollUntilHittable(turnOn, in: app) {
            turnOn.tap()
        }

        app.terminate()
        finish("A")
    }

    // MARK: - B: Courses + Course Detail (first course, full)

    @MainActor
    func testB_coursesAndFirstCourseDetail() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 15
        resetAppState()

        let app = launchSignedIn()
        openTabInTour(Self.tabLabel(.courses), in: app)
        captureScreenfuls(app, screen: "courses", reachedVia: "Courses tab", maxScreens: 10)

        // `captureScreenfuls` may have scrolled to the bottom (AX5 legs, 5 cards that no longer fit);
        // `goScrolling` only swipes forward, so it must start from the top to find card 1 again.
        scrollToTop(app)
        let cards = elements("course.card", in: app)
        guard goScrolling(cards.element(boundBy: 0), app, screen: "course1", state: "card", reachedVia: "Courses list, card 1"),
              element("courseDetail.hero", in: app).waitForExistence(timeout: 10) else {
            finish("B")
            app.terminate()
            return
        }
        captureScreenfuls(app, screen: "course1", reachedVia: "Courses list, card 1", maxScreens: 10)

        scrollToTop(app)
        if goScrolling(element("courseDetail.segment.grades", in: app), app, screen: "course1", state: "grades", reachedVia: "segment control") {
            snap(app, screen: "course1", state: "grades", reachedVia: "Grades segment")
        }

        app.terminate()
        finish("B")
    }

    // MARK: - B2: Course Detail menu (XG-04) + What-If sheet (first course)

    /// Split out of `testB` (CI run 37627030732: every AX5 leg timed out there — see
    /// `scrollToTop`'s doc comment). Re-navigates to course 1 rather than share state with `testB`,
    /// since each method gets a fresh app launch regardless.
    @MainActor
    func testB2_firstCourseMenuAndWhatIf() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 300
        resetAppState()

        let app = launchSignedIn()
        openTabInTour(Self.tabLabel(.courses), in: app)
        let cards = elements("course.card", in: app)
        guard goScrolling(cards.element(boundBy: 0), app, screen: "course1", state: "card-b2", reachedVia: "Courses list, card 1"),
              element("courseDetail.hero", in: app).waitForExistence(timeout: 10) else {
            finish("B2")
            app.terminate()
            return
        }

        // Any Menu you can open, fully: the toolbar's grades-outside-Canvas menu (XG-04).
        if goScrolling(element("courseDetail.menu", in: app), app, screen: "course1", state: "menu", reachedVia: "toolbar menu") {
            snap(app, screen: "course1", state: "menu", reachedVia: "tapped courseDetail.menu")
            if go(element("courseDetail.gradesOutsideCanvas", in: app), app, screen: "course1", state: "gradesOutsideCanvas",
                  reachedVia: "menu -> This course's grades are kept outside Canvas") {
                snap(app, screen: "course1", state: "gradesOutsideCanvas", reachedVia: "opened the grades-outside-Canvas picker")
                if element("courseDetail.gradesOutsideCanvas.automatic", in: app).waitForExistence(timeout: 3) {
                    element("courseDetail.gradesOutsideCanvas.automatic", in: app).tap()
                } else {
                    dismissOverlay(app)
                }
            } else {
                dismissOverlay(app)
            }
        }

        // The What-If sheet, fully presented.
        let whatIf = element("courseDetail.whatIf", in: app)
        if goScrolling(whatIf, app, screen: "course1", state: "whatIf", reachedVia: "What-If button") {
            _ = element("whatif.simulationLabel", in: app).waitForExistence(timeout: 10)
            // L10N-04: was `app.navigationBars["What-If"]` — the English nav-bar title, which
            // Spanish changes. Any on-screen element serves the same "pull the sheet up" purpose.
            app.swipeUp()
            snap(app, screen: "course1", state: "whatIf", reachedVia: "What-If button, pulled up")
            let done = element("whatif.done", in: app)
            if done.waitForExistence(timeout: 5), done.isHittable { done.tap() }
        }

        app.terminate()
        finish("B2")
    }

    // MARK: - C: Course Detail (second course, light)

    @MainActor
    func testC_secondCourseDetail() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 30
        resetAppState()

        let app = launchSignedIn()
        openTabInTour(Self.tabLabel(.courses), in: app)
        let cards = elements("course.card", in: app)
        // CI run 37639511433: missed on the smallest device at AX5 (two legs) with the default
        // 15-swipe cap; a card 44 pt tall plus huge text can need more swipes to reach.
        guard cards.count > 1,
              goScrolling(cards.element(boundBy: 1), app, screen: "course2", state: "card", reachedVia: "Courses list, card 2",
                         maxSwipes: 25),
              element("courseDetail.hero", in: app).waitForExistence(timeout: 10) else {
            snap(app, screen: "course2", state: "missing-detail", reachedVia: "Courses list, card 2")
            finish("C")
            app.terminate()
            return
        }
        snap(app, screen: "course2", state: "overview", reachedVia: "Courses list, card 2")
        if goScrolling(element("courseDetail.segment.grades", in: app), app, screen: "course2", state: "grades", reachedVia: "segment control") {
            snap(app, screen: "course2", state: "grades", reachedVia: "Grades segment")
        }

        app.terminate()
        finish("C")
    }

    // MARK: - D: Calendar

    @MainActor
    func testD_calendar() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 45
        resetAppState()

        let app = launchSignedIn()
        openTabInTour(Self.tabLabel(.calendar), in: app)
        _ = elements("calendar.day", in: app).firstMatch.waitForExistence(timeout: 15)
        snap(app, screen: "calendar", state: "weekStripAndAgenda", reachedVia: "Calendar tab")

        if go(app.buttons["calendar.options"], app, screen: "calendar", state: "optionsMenu", reachedVia: "toolbar options button") {
            snap(app, screen: "calendar", state: "optionsMenu", reachedVia: "tapped calendar.options")
            // L10N-04: was `app.buttons["Subscribe to Canvas Calendar…"]`, `app.alerts["Subscribing
            // needs your school's Canvas"]` and `note.buttons["OK"]` — English labels, which Spanish
            // changes. The menu row now has its own id; the native alert is matched structurally
            // (it has exactly one button) rather than by its localized title and button text.
            let subscribe = element("calendar.subscribeMenuItem", in: app)
            if go(subscribe, app, screen: "calendar", state: "subscribeAlert", reachedVia: "Subscribe to Canvas Calendar…") {
                let note = app.alerts.firstMatch
                if note.waitForExistence(timeout: 5) {
                    snap(app, screen: "calendar", state: "subscribeAlert", reachedVia: "Subscribe to Canvas Calendar…")
                    if note.buttons.firstMatch.exists { note.buttons.firstMatch.tap() }
                }
            }
        }

        app.terminate()
        finish("D")
    }

    // MARK: - E: To-Do

    @MainActor
    func testE_toDo() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 60
        resetAppState()

        let app = launchSignedIn()
        openTabInTour(Self.tabLabel(.toDo), in: app)
        // L10N-04: was text("Missing & overdue", in: app) — the English section header, which
        // Spanish changes; any row is an equally good "the To-Do projection landed" signal.
        // Round 2: "todo.row" is now "todo.row.done"/"todo.row.notDone" (VoiceOver-safe way to
        // carry the done state — see ToDoScreen.swift); elementsWithPrefix finds every row either
        // way, same as the flat identifier did.
        _ = elementsWithPrefix("todo.row", in: app).firstMatch.waitForExistence(timeout: 15)
        snap(app, screen: "todo", state: "default", reachedVia: "To-Do tab")

        if go(app.buttons["todo.sort"], app, screen: "todo", state: "sortMenu", reachedVia: "sort toolbar menu") {
            snap(app, screen: "todo", state: "sortMenu", reachedVia: "tapped todo.sort")
            dismissOverlay(app)
        }

        let rows = elementsWithPrefix("todo.row", in: app)
        if rows.count > 1 {
            // ux-fp6: row 2 (`boundBy: 1`) sits under the floating tab bar at Pro Max AX5 (a single
            // AX5 row is tall enough to push it there), so the swipe landed on the tab bar instead
            // and the capture was missing. The first row whose frame clears the tab bar entirely is
            // used instead; one scroll-up-and-retry covers the case where every row now on screen is
            // still under it.
            func firstRowClearOfTabBar() -> XCUIElement? {
                let tabBarMinY = app.tabBars.firstMatch.frame.minY
                for index in 0..<rows.count {
                    let row = rows.element(boundBy: index)
                    if row.exists, row.frame.maxY < tabBarMinY { return row }
                }
                return nil
            }
            var target = firstRowClearOfTabBar()
            if target == nil {
                app.swipeUp(velocity: .slow)
                _ = waitUntilAtRest(app)
                target = firstRowClearOfTabBar()
            }
            if let target {
                target.swipeLeft()
                snap(app, screen: "todo", state: "swipeAction", reachedVia: "swiped a row left, fully revealed")
                // L10N-04: was app.buttons["Done"] — the English label, which Spanish changes.
                if element("todo.swipe.done", in: app).exists { element("todo.swipe.done", in: app).tap() }
            }
        }

        if go(app.buttons["todo.select"], app, screen: "todo", state: "selectMode", reachedVia: "Select toolbar button") {
            // L10N-04 round 2 (gate-2 verdict item 16 / round-1 report §8 item 3): was a match on
            // the English label "Marked done in Tally", which Spanish translates — the filter
            // silently stopped filtering instead of failing loudly. The row's own identifier
            // ("todo.row.notDone"/"todo.row.done", never spoken or localized) carries the state.
            let notDone = rows.matching(NSPredicate(format: "identifier == 'todo.row.notDone'"))
            for index in 0..<min(2, notDone.count) {
                let row = notDone.element(boundBy: index)
                if bringClearOfTheBottom(row, in: app) { row.tap() }
            }
            snap(app, screen: "todo", state: "batchSelect", reachedVia: "Select, then two rows tapped")
            if app.buttons["todo.markDone"].exists { app.buttons["todo.markDone"].tap() }
        }

        app.terminate()
        finish("E")
    }

    // MARK: - F: Insights

    @MainActor
    func testF_insights() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 75
        resetAppState()

        let app = launchSignedIn()
        openTabInTour(Self.tabLabel(.insights), in: app)
        _ = element("chart.trend", in: app).waitForExistence(timeout: 30)
        captureScreenfuls(app, screen: "insights", reachedVia: "Insights tab", maxScreens: 10)

        app.terminate()
        finish("F")
    }

    // MARK: - G: Settings, signed in

    @MainActor
    func testG_settingsSignedIn() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 90
        resetAppState()

        let app = launchSignedIn()
        openSettings(app)
        captureScreenfuls(app, screen: "settings", reachedVia: "Settings toolbar button", maxScreens: 20)

        scrollToTop(app)
        if goScrolling(app.buttons["settings.subscription"], app, screen: "settings-subscription", state: "page",
                       reachedVia: "Settings -> Subscription") {
            if element("subscription.status", in: app).waitForExistence(timeout: 10) {
                captureScreenfuls(app, screen: "settings-subscription", reachedVia: "Settings -> Subscription", maxScreens: 10)
            }
            goBack(app)
        }

        // Sign Out & Erase: fully presented, then cancel (never actually erase: the tour must not
        // end the account early for whichever other method runs in this process next).
        scrollToTop(app)
        if goScrolling(app.buttons["settings.signOut"], app, screen: "settings", state: "signOutButton", reachedVia: "Settings") {
            // L10N-04 round 2 (gate-2 verdict item 16): was a match on the English confirmation
            // message and the English "Cancel" button label, which Spanish translates — this
            // screen was missing from every es leg (std used `.alert`, AX5 the sheet; both show
            // the same message, so both failed the same way). `settings.signOutConfirm.cancel`
            // is set on the Cancel button in both presentations (`DestructiveConfirmation.swift`).
            let cancel = element("settings.signOutConfirm.cancel", in: app)
            if cancel.waitForExistence(timeout: 10) {
                snap(app, screen: "settings", state: "signOutConfirm", reachedVia: "Sign Out & Erase")
                cancel.tap()
            } else {
                let popover = app.otherElements["PopoverDismissRegion"].firstMatch
                if popover.waitForExistence(timeout: 3) { popover.tap() }
            }
        }

        // L10N-04: was app.buttons["Done"] — the English label, which Spanish changes.
        if element("settings.done", in: app).exists { element("settings.done", in: app).tap() }
        app.terminate()
        finish("G")
    }

    // MARK: - H: Welcome + school search

    @MainActor
    func testH_welcomeAndSchoolSearch() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 110
        resetAppState()

        let app = launchApp(arguments: Self.textSizeArguments)
        _ = element("account.findMySchool", in: app).waitForExistence(timeout: 30)
        snap(app, screen: "welcome", state: "default", reachedVia: "fresh launch")

        if go(element("account.findMySchool", in: app), app, screen: "schoolSearch", state: "idle", reachedVia: "Find My School") {
            _ = element("schoolSearch.idleHint", in: app).waitForExistence(timeout: 10)
            snap(app, screen: "schoolSearch", state: "idle", reachedVia: "Find My School")

            let searchField = schoolSearchField(app)
            if go(searchField, app, screen: "schoolSearch", state: "field", reachedVia: "search field", timeout: 5) {
                searchField.typeText("northfield")
                // No live search transport is wired in yet (SchoolSearchUITests' doc comment): every
                // query reaches `searchFailed`, the same state a real network failure would. A
                // "results" state is not reachable with the hooks this app ships today.
                if element("schoolSearch.searchFailed", in: app).waitForExistence(timeout: 5) {
                    snap(app, screen: "schoolSearch", state: "failure", reachedVia: "typed 'northfield'")
                } else {
                    snap(app, screen: "schoolSearch", state: "missing-failure", reachedVia: "typed 'northfield'")
                }
            }
        }

        app.terminate()
        finish("H")
    }

    // MARK: - I: Demo sign-in, first sync progress

    @MainActor
    func testI_demoSignInProgress() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 120
        resetAppState()

        let app = launchApp(arguments: TestHooks.demoSignIn + TestHooks.signOutButton + Self.textSizeArguments)
        _ = element("account.findMySchool", in: app).waitForExistence(timeout: 30)
        signInToDemoSchool(app)

        // First sync progress, once its content is stable — racing the root switch to Home, so this
        // is best-effort: a fast replay may already have switched by the time the check runs.
        let progress = element("onboarding.firstSync.settingUpTally", in: app)
        if progress.waitForExistence(timeout: 5) {
            snap(app, screen: "demoSignIn", state: "firstSyncProgress", reachedVia: "Continue to \(Self.demoHost)")
        } else {
            snap(app, screen: "demoSignIn", state: "missing-firstSyncProgress",
                 reachedVia: "first sync had already finished before it could be captured")
        }
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)

        app.terminate()
        finish("I")
    }

    // MARK: - J: First sync failure

    @MainActor
    func testJ_firstSyncFailure() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 130
        resetAppState()

        let app = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.demoSignIn + TestHooks.blockNetwork
            + Self.textSizeArguments)
        _ = element("account.findMySchool", in: app).waitForExistence(timeout: 30)
        signInToDemoSchool(app)

        if element("onboarding.retry", in: app).waitForExistence(timeout: 130) {
            snap(app, screen: "demoSignIn", state: "firstSyncFailed", reachedVia: "blocked network")
        } else {
            snap(app, screen: "demoSignIn", state: "missing-firstSyncFailed", reachedVia: "blocked network")
        }

        app.terminate()
        finish("J")
    }

    // MARK: - K: Paywall after the first sync

    @MainActor
    func testK_paywallAfterFirstSync() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 140
        resetAppState()

        let app = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.demoSignIn + Self.textSizeArguments)
        _ = element("account.findMySchool", in: app).waitForExistence(timeout: 30)
        signInToDemoSchool(app)
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)

        if element("paywall.root", in: app).waitForExistence(timeout: 15) {
            captureScreenfuls(app, screen: "paywall", reachedVia: "paywall after the first sync", maxScreens: 10)
            if app.buttons["paywall.close"].exists { app.buttons["paywall.close"].tap() }
        } else {
            snap(app, screen: "paywall", state: "missing-afterFirstSync", reachedVia: "first sync finished")
        }

        app.terminate()
        finish("K")
    }

    // MARK: - L: Locked tab card + paywall from it + school-seat Subscription

    @MainActor
    func testL_lockedTabAndSchoolSeatSubscription() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 155
        resetAppState()

        seedFlagshipAccount()
        let app = launchApp(arguments: TestHooks.entitlement("none") + TestHooks.replayAccounts + Self.textSizeArguments)
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)
        openTabInTour(Self.tabLabel(.courses), in: app)

        let seePlans = app.buttons["subscription.locked.seePlans"]
        if scrollUntilHittable(seePlans, in: app) {
            snap(app, screen: "lockedTab", state: "card", reachedVia: "Courses tab, no entitlement")
            if go(seePlans, app, screen: "paywall", state: "fromLockedTab", reachedVia: "locked card's See Plans") {
                captureScreenfuls(app, screen: "paywall-fromLockedTab", reachedVia: "locked card's See Plans", maxScreens: 10)
                if app.buttons["paywall.close"].exists { app.buttons["paywall.close"].tap() }
            }
        } else {
            snap(app, screen: "lockedTab", state: "missing-card", reachedVia: "Courses tab, no entitlement")
        }
        app.terminate()

        resetAppState()
        seedFlagshipAccount()
        let schoolSeatApp = launchApp(arguments: TestHooks.entitlement("schoolSeat") + TestHooks.replayAccounts + Self.textSizeArguments)
        _ = element("dashboard.hero.averageOfCourses", in: schoolSeatApp).waitForExistence(timeout: 30)
        openSettings(schoolSeatApp)
        if goScrolling(schoolSeatApp.buttons["settings.subscription"], schoolSeatApp, screen: "settings-subscription-schoolSeat",
                       state: "page", reachedVia: "Settings -> Subscription, school seat") {
            if element("subscription.status", in: schoolSeatApp).waitForExistence(timeout: 10) {
                snap(schoolSeatApp, screen: "settings-subscription-schoolSeat", state: "page",
                     reachedVia: "Settings -> Subscription, school seat")
            }
        }
        schoolSeatApp.terminate()

        finish("L")
    }

    // MARK: - M: App Lock screen + privacy cover

    @MainActor
    func testM_appLockAndPrivacyCover() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 170
        resetAppState()

        seedFlagshipAccount()
        let locked = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn + TestHooks.deviceAuth("cancel")
            + Self.textSizeArguments)
        // L10N-04: was locked.staticTexts["Tally is locked"] — the English text, which Spanish changes.
        if element("lock.title", in: locked).waitForExistence(timeout: 15) {
            snap(locked, screen: "appLock", state: "locked", reachedVia: "cold launch with App Lock on")
        } else {
            snap(locked, screen: "appLock", state: "missing-locked", reachedVia: "cold launch with App Lock on")
        }
        locked.terminate()

        resetAppState()
        seedFlagshipAccount()
        let unlocked = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn + TestHooks.deviceAuth("success")
            + Self.textSizeArguments)
        guard element("dashboard.hero.averageOfCourses", in: unlocked).waitForExistence(timeout: 20) else {
            snap(unlocked, screen: "appLock", state: "missing-privacyCover",
                 reachedVia: "could not unlock to reach the dashboard first")
            unlocked.terminate()
            finish("M")
            return
        }
        if let method = makeInactive(unlocked) {
            // The cover may render outside the app's own window while inactive, so this one capture
            // uses the device screen, not `app.screenshot()`, and skips the at-rest/layout pipeline
            // (the state is transient system UI, not something `app.snapshot()` can see into).
            stepNumber += 1
            let name = String(format: "%02d-appLock-privacyCover", stepNumber)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            manifestEntries.append(["name": name, "screen": "appLock", "state": "privacyCover", "reachedVia": "made inactive via \(method)"])
            unlocked.activate()
            _ = waitForScenePhase("active", in: unlocked, timeout: 10)
        } else {
            snap(unlocked, screen: "appLock", state: "missing-privacyCover",
                 reachedVia: "could not make the app inactive on this simulator (app switcher / Notification Center)")
        }
        unlocked.terminate()

        finish("M")
    }

    // MARK: - N: Sample data dashboard + parent mode

    @MainActor
    func testN_sampleDataAndParentMode() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 180
        resetAppState()

        let app = launchApp(arguments: Self.textSizeArguments)
        guard go(element("account.exploreWithSampleData", in: app), app, screen: "sampleData", state: "dashboard",
                 reachedVia: "Welcome -> Explore with Sample Data") else {
            finish("N")
            app.terminate()
            return
        }
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)
        snap(app, screen: "sampleData", state: "dashboard", reachedVia: "Explore with Sample Data (banner included)")

        openSettings(app)
        guard goScrolling(app.buttons["family.sample.viewAsParent"], app, screen: "family", state: "parentDashboard",
                          reachedVia: "Settings -> Explore Parent Mode", maxSwipes: 30) else {
            // L10N-04: was app.buttons["Done"] — the English label, which Spanish changes.
            if element("settings.done", in: app).exists { element("settings.done", in: app).tap() }
            finish("N")
            app.terminate()
            return
        }
        snap(app, screen: "family", state: "parentDashboard", reachedVia: "Settings -> Explore Parent Mode")

        let switchers = elements("family.switcher", in: app)
        let visibleSwitcher = (0..<switchers.count).map { switchers.element(boundBy: $0) }.first { $0.exists && $0.isHittable }
        if let visibleSwitcher {
            visibleSwitcher.tap()
            snap(app, screen: "family", state: "switcherOpen", reachedVia: "tapped the student switcher")
            if go(app.buttons["Skyler Sample"], app, screen: "family", state: "secondStudent", reachedVia: "switcher -> Skyler Sample") {
                snap(app, screen: "family", state: "secondStudent", reachedVia: "switcher -> Skyler Sample")
            }
        }

        if go(element("home.settingsButton", in: app), app, screen: "family", state: "linkedStudents", reachedVia: "toolbar Settings button") {
            snap(app, screen: "family", state: "linkedStudents", reachedVia: "Settings while in parent mode")

            let rowanRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Rowan Sample'")).firstMatch
            if goScrolling(rowanRow, app, screen: "family", state: "studentDetail", reachedVia: "Linked Students -> Rowan Sample") {
                let unlink = app.buttons["family.unlink"]
                if scrollUntilHittable(unlink, in: app) {
                    unlink.tap()
                    // L10N-04 round 2 (gate-2 verdict item 16): was a match on the English title
                    // and "Cancel" label, which Spanish translates.
                    let cancel = element("familyConfirm.unlink.cancel", in: app)
                    if cancel.waitForExistence(timeout: 10) {
                        snap(app, screen: "family", state: "unlinkConfirm", reachedVia: "Rowan Sample -> Unlink")
                        cancel.tap()
                    } else {
                        let popover = app.otherElements["PopoverDismissRegion"].firstMatch
                        if popover.waitForExistence(timeout: 3) { popover.tap() }
                    }
                }
                goBack(app)
            }
        }

        app.terminate()
        finish("N")
    }

    // MARK: - O: Parent empty state

    @MainActor
    func testO_parentEmptyState() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 200
        resetAppState()

        let app = launchApp(arguments: Self.textSizeArguments)
        guard go(element("account.exploreWithSampleData", in: app), app, screen: "family", state: "emptyRouteEntry",
                 reachedVia: "Welcome -> Explore with Sample Data") else {
            finish("O")
            app.terminate()
            return
        }
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)
        openSettings(app)
        guard goScrolling(app.buttons["family.sample.viewAsParent"], app, screen: "family", state: "emptyRouteParentMode",
                          reachedVia: "Settings -> Explore Parent Mode", maxSwipes: 30) else {
            finish("O")
            app.terminate()
            return
        }
        openSettings(app)

        for name in ["Rowan", "Skyler"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "\(name) Sample")).firstMatch
            guard goScrolling(row, app, screen: "family", state: "removeStudent-\(name)",
                              reachedVia: "Linked Students -> \(name) Sample") else { continue }
            // CI run 37639511433: `go` alone missed this at AX5 (below the fold on the student
            // detail screen); `goScrolling` is a safe strict improvement, same fallback on failure.
            guard goScrolling(app.buttons["family.removeFromTally"], app, screen: "family", state: "removeConfirm-\(name)",
                              reachedVia: "\(name) Sample -> Remove from Tally") else { continue }
            // L10N-04 round 2 (gate-2 verdict item 16): was a match on the English title and
            // "Remove from Tally" confirm-button label, which Spanish translates. Under es neither
            // ever matched, so the confirm button was never tapped, the sheet stayed open, and the
            // *next* loop iteration's row lookup failed too — its "missing-removeStudent-<name>"
            // screenshot was actually this student's still-open confirmation (the misfiled-name
            // bug the verdict found: "Rowan" filed under "Skyler").
            let confirm = element("familyConfirm.remove.destructive", in: app)
            if confirm.waitForExistence(timeout: 10) {
                snap(app, screen: "family", state: "removeConfirm-\(name)", reachedVia: "\(name) Sample -> Remove from Tally")
                confirm.tap()
            }
            // Back on Linked Students once the removal completes and the sheet dismisses: waits on
            // "Add a Student", not translated English text.
            _ = element("family.addStudent", in: app).waitForExistence(timeout: 10)
        }

        if element("family.parentEmpty", in: app).waitForExistence(timeout: 10) {
            snap(app, screen: "family", state: "parentEmpty", reachedVia: "both students removed")
        } else {
            snap(app, screen: "family", state: "missing-parentEmpty", reachedVia: "both students removed")
        }

        app.terminate()
        finish("O")
    }

    // MARK: - P: Slow-refresh breadcrumb

    @MainActor
    func testP_slowRefreshBreadcrumb() throws {
        continueAfterFailure = true
        executionTimeAllowance = 280
        XCUIDevice.shared.appearance = Self.appearance
        stepNumber = 215
        resetAppState()

        let app = launchApp(arguments: ["-TallyDebugSampleRefreshLatency", "20"] + Self.textSizeArguments)
        guard go(element("account.exploreWithSampleData", in: app), app, screen: "slowRefresh", state: "entry",
                 reachedVia: "Welcome -> Explore with Sample Data") else {
            finish("P")
            app.terminate()
            return
        }
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)

        let refresh = element("freshness.refresh", in: app)
        guard goScrolling(refresh, app, screen: "slowRefresh", state: "refreshButton", reachedVia: "Dashboard hero") else {
            finish("P")
            app.terminate()
            return
        }
        // L10N-04 round 2 (gate-2 verdict item 16 / round-1 report §8 item 3): was a match on the
        // English label prefix, which Spanish translates — a real breadcrumb was filed under
        // "missing-breadcrumb" on every es leg instead of "breadcrumb".
        let breadcrumb = element("freshness.breadcrumb", in: app)
        if breadcrumb.waitForExistence(timeout: 15) {
            snap(app, screen: "slowRefresh", state: "breadcrumb", reachedVia: "tapped Refresh, waited past the live budget")
        } else {
            snap(app, screen: "slowRefresh", state: "missing-breadcrumb", reachedVia: "tapped Refresh, waited past the live budget")
        }

        app.terminate()
        finish("P")
    }

    // MARK: - Shared signed-in launch

    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        let app = launchApp(arguments: TestHooks.seedFlagship + TestHooks.replayAccounts + TestHooks.deviceAuth("success")
            + ["-TallyTestHooks.notifications", "notDetermined:denied"] + Self.textSizeArguments)
        _ = element("dashboard.hero.averageOfCourses", in: app).waitForExistence(timeout: 30)
        return app
    }

    /// Welcome -> Find My School -> the demo school -> Continue: the first sync starts. Every step
    /// records "missing-<state>" and stops if it cannot go on (PaywallUITests' `signInToTheDemoSchool`,
    /// reused here through `go` instead of an assertion).
    @MainActor
    private func signInToDemoSchool(_ app: XCUIApplication) {
        guard go(element("account.findMySchool", in: app), app, screen: "demoSignIn", state: "schoolSearch", reachedVia: "Find My School")
        else { return }
        let searchField = schoolSearchField(app)
        guard go(searchField, app, screen: "demoSignIn", state: "searchField", reachedVia: "search field", timeout: 5)
        else { return }
        searchField.typeText(Self.demoHost)
        guard go(element("schoolSearch.useAddress", in: app), app, screen: "demoSignIn", state: "useSchool",
                 reachedVia: "typed \(Self.demoHost)") else { return }
        // CI run 37639511433: `go` alone missed this at AX5 on every leg (the confirmation screen's
        // button is below the fold at that text size) — `goScrolling` degrades to the same
        // "missing" recording if it still can't be found, so this can only help, never regress.
        _ = goScrolling(element("onboarding.signIn.continueTo", in: app), app, screen: "demoSignIn", state: "continue",
                        reachedVia: "Use \(Self.demoHost)")
    }

    /// School search's field, at every text size (ux-fp1 round 3). Below the accessibility sizes it
    /// is the system `.searchable` field: a search field, with no identifier of its own (what
    /// `SchoolSearchUITests` and this tour have always queried). From AX1 up, `SchoolSearchView`
    /// replaces it with its own `TextField(axis: .vertical)`, identifier `schoolSearch.field`, which
    /// `app.searchFields` never matches (a vertical-axis field need not even report as a text field,
    /// so any element type): Audit tour run 37768388853 recorded "missing-searchField" on every AX5
    /// leg, and so never reached demo sign-in, first sync or the paywall after it at AX5.
    @MainActor
    private func schoolSearchField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR elementType == %lu", "schoolSearch.field", XCUIElement.ElementType.searchField.rawValue
        )).firstMatch
    }

    // MARK: - Capture primitives

    /// Waits until `element` is hittable (never scrolling), taps it, and returns `true`; records a
    /// "missing-<state>" screenshot and returns `false` if it never becomes hittable. For controls
    /// already expected on screen: tab bar buttons, toolbar buttons, alert/dialog buttons, menu items.
    @MainActor
    @discardableResult
    private func go(_ element: XCUIElement, _ app: XCUIApplication, screen: String, state: String, reachedVia: String,
                    timeout: TimeInterval = 15) -> Bool {
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"),
                                                  object: element)
        guard XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed else {
            snap(app, screen: screen, state: "missing-\(state)", reachedVia: reachedVia)
            return false
        }
        element.tap()
        return true
    }

    /// Like `go`, but scrolls (`scrollUntilHittable`, swipes up only) before tapping — for a row or
    /// button that may be below the fold in a List/Form. Always call `scrollToTop` first if the
    /// screen was scrolled down by an earlier `captureScreenfuls` pass, since this only scrolls
    /// downward.
    @MainActor
    @discardableResult
    private func goScrolling(_ element: XCUIElement, _ app: XCUIApplication, screen: String, state: String, reachedVia: String,
                             maxSwipes: Int = 15) -> Bool {
        guard scrollUntilHittable(element, in: app, maxSwipes: maxSwipes) else {
            snap(app, screen: screen, state: "missing-\(state)", reachedVia: reachedVia)
            return false
        }
        element.tap()
        return true
    }

    /// Swipes down until the screenshot stops changing (the top, or nothing left to scroll), or
    /// `maxSwipes` is reached. **Found in CI (run 37627030732): every AX5 leg timed out in
    /// `testB`, not from a hang but from this method once unconditionally performing all 20
    /// swipes on every call — 4 calls in that one method, each ~40-50 s at AX5, consumed most of
    /// the 300 s cap before the real work even started.** Stopping as soon as the content settles
    /// turns a ~40-50 s call into a ~5-10 s one once already near the top.
    @MainActor
    private func scrollToTop(_ app: XCUIApplication, maxSwipes: Int = 20) {
        var previous = app.screenshot().pngRepresentation
        for _ in 0..<maxSwipes {
            app.swipeDown(velocity: .slow)
            let current = app.screenshot().pngRepresentation
            if current == previous { break }
            previous = current
        }
    }

    /// Taps a quiet corner of the screen, away from the status bar and any tab bar, to dismiss an
    /// open `Menu`'s popover or a borderless confirmation.
    @MainActor
    private func dismissOverlay(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.08)).tap()
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let backButton = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5), backButton.isHittable {
            backButton.tap()
        }
    }

    /// `openTab`, settled first. A tab tap made right after a transition (the previous screen's own
    /// capture, a sheet dismissal) can hit XCUITest's own "Failed to determine hittability of …:
    /// Activation point invalid" (run 37880767365, `testB` at Pro Max light AX5,
    /// `TallyUITestCase.swift:127`): the hit-test reads a stale frame while the app is still
    /// animating. `waitUntilAtRest` (already used before every capture in this file) settles that
    /// first, which is enough on its own in practice; a second attempt, settled again, covers
    /// whatever the first still misses.
    @MainActor
    private func openTabInTour(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.tabBars.buttons[name]
        for attempt in 0..<2 {
            _ = waitUntilAtRest(app)
            if attempt == 1 || !button.isSelected {
                openTab(name, in: app, file: file, line: line)
            }
            if button.waitForExistence(timeout: 2), button.isSelected { return }
        }
    }

    /// Top, then every scroll position down to the bottom: one capture per screenful. Stops as soon
    /// as a swipe produces an unchanged screenshot (the bottom), or after `maxScreens` swipes.
    @MainActor
    private func captureScreenfuls(_ app: XCUIApplication, screen: String, reachedVia: String, maxScreens: Int = 12) {
        snap(app, screen: screen, state: "top", reachedVia: reachedVia)
        guard maxScreens > 0 else { return }
        var previous = app.screenshot().pngRepresentation
        for index in 1...maxScreens {
            app.swipeUp(velocity: .slow)
            _ = waitUntilAtRest(app)
            let current = app.screenshot().pngRepresentation
            if current == previous { break }
            previous = current
            snap(app, screen: screen, state: "scroll\(index)", reachedVia: "swiped up \(index) screenful(s) from \(screen) top")
        }
    }

    /// Waits for `app`'s screenshot to stop changing (two 0.4 s-apart screenshots pixel-identical),
    /// up to `timeout`. `true` once settled.
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

    /// Waits at rest, attaches the screenshot as `NN-<screen>-<state>[-UNSETTLED]`, walks one
    /// `app.snapshot()` for the layout check (`<name>.layout.json`), and records a manifest entry.
    @MainActor
    private func snap(_ app: XCUIApplication, screen: String, state: String, reachedVia: String) {
        stepNumber += 1
        let settled = waitUntilAtRest(app)
        let name = String(format: "%02d-%@-%@", stepNumber, screen, state) + (settled ? "" : "-UNSETTLED")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)

        let (layout, counts) = analyzeLayout(app)
        attachJSON(layout, name: "\(name).layout.json")

        var screenCounts = summaryCounts[screen] ?? [:]
        for (check, count) in counts { screenCounts[check, default: 0] += count }
        summaryCounts[screen] = screenCounts

        manifestEntries.append(["name": name, "screen": screen, "state": state, "reachedVia": reachedVia])
    }

    @MainActor
    private func attachJSON(_ object: Any, name: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Layout check

    /// One `app.snapshot()` IPC call, walked once for every check this leg records. `isHittable` is
    /// not part of `XCUIElementSnapshot` (only a live `XCUIElement` query has it), so "hit target"
    /// below approximates hittability as enabled, on-screen and non-zero-area; that approximation is
    /// the price of the single-IPC-call rule, and is why these counts are a hint for the reviewer,
    /// not a verdict.
    @MainActor
    private func analyzeLayout(_ app: XCUIApplication) -> (layout: [String: Any], counts: [String: Int]) {
        guard let root = try? app.snapshot() else {
            return ([:], [:])
        }
        let windowFrame = root.frame

        struct Node {
            let snapshot: XCUIElementSnapshot
            let insideScrollView: Bool
        }
        var flat: [Node] = []
        func walk(_ node: XCUIElementSnapshot, insideScrollView: Bool) {
            flat.append(Node(snapshot: node, insideScrollView: insideScrollView))
            // Read the kind first: `||`'s autoclosure capturing the non-Sendable snapshot fails the
            // Release test build ("sending 'node' risks causing data races", ios-perf, run 37704108738).
            let kind = node.elementType
            let childInsideScrollView = insideScrollView || [.scrollView, .table, .collectionView].contains(kind)
            for child in node.children {
                walk(child, insideScrollView: childInsideScrollView)
            }
        }
        walk(root, insideScrollView: false)

        func describe(_ snapshot: XCUIElementSnapshot) -> String {
            let id = snapshot.identifier.isEmpty ? "" : " #\(snapshot.identifier)"
            let label = snapshot.label.isEmpty ? "" : " '\(snapshot.label)'"
            return "\(snapshot.elementType)\(id)\(label)"
        }
        func frameDict(_ frame: CGRect) -> [String: Any] {
            ["x": frame.origin.x, "y": frame.origin.y, "width": frame.size.width, "height": frame.size.height]
        }

        let visibleKinds: Set<XCUIElement.ElementType> = [.staticText, .button, .image]
        let visible = flat.filter { node in
            let frame = node.snapshot.frame
            return visibleKinds.contains(node.snapshot.elementType) && frame.width > 0 && frame.height > 0
                && frame.intersects(windowFrame)
        }

        var overlapPairs: [[String: Any]] = []
        if visible.count > 1 {
            for i in 0..<(visible.count - 1) {
                for j in (i + 1)..<visible.count {
                    let a = visible[i].snapshot.frame
                    let b = visible[j].snapshot.frame
                    let intersection = a.intersection(b)
                    guard !intersection.isNull, intersection.width > 2, intersection.height > 2 else { continue }
                    if a.contains(b) || b.contains(a) { continue }
                    overlapPairs.append([
                        "a": describe(visible[i].snapshot), "aFrame": frameDict(a),
                        "b": describe(visible[j].snapshot), "bFrame": frameDict(b),
                    ])
                }
            }
        }

        var offscreen: [[String: Any]] = []
        for node in visible {
            let frame = node.snapshot.frame
            let crossesSides = frame.minX < windowFrame.minX || frame.maxX > windowFrame.maxX
            let insideScrollView = node.insideScrollView
            let crossesBottom = frame.maxY > windowFrame.maxY && !insideScrollView
            if crossesSides || crossesBottom {
                offscreen.append([
                    "element": describe(node.snapshot), "frame": frameDict(frame),
                    "crossesSides": crossesSides, "crossesBottom": crossesBottom,
                ])
            }
        }

        var hitTargets: [[String: Any]] = []
        let targetKinds: Set<XCUIElement.ElementType> = [.button, .switch, .link]
        for node in flat where targetKinds.contains(node.snapshot.elementType) {
            let frame = node.snapshot.frame
            guard node.snapshot.isEnabled, frame.width > 0, frame.height > 0 else { continue }
            if frame.width < 44 || frame.height < 44 {
                hitTargets.append(["element": describe(node.snapshot), "frame": frameDict(frame)])
            }
        }

        var leadingInsets: Set<Int> = []
        for node in flat {
            let identifier = node.snapshot.identifier
            let isCell = node.snapshot.elementType == .cell
            let isCardOrSection = identifier.hasSuffix(".card") || identifier.hasSuffix(".section") || isCell
            guard isCardOrSection, node.snapshot.frame.width > 0 else { continue }
            leadingInsets.insert(Int(node.snapshot.frame.minX.rounded()))
        }

        var truncated: [[String: Any]] = []
        for node in flat where node.snapshot.elementType == .staticText {
            let label = node.snapshot.label
            let frame = node.snapshot.frame
            guard !label.isEmpty else { continue }
            if label.hasSuffix("…") || (frame.height > 0 && frame.height < 14) {
                truncated.append(["element": describe(node.snapshot), "label": label, "frame": frameDict(frame)])
            }
        }

        let layout: [String: Any] = [
            "overlap": overlapPairs,
            "offscreenOrClipped": offscreen,
            "hitTargetsUnder44pt": hitTargets,
            "truncationHint": truncated,
            "distinctLeadingInsets": leadingInsets.sorted(),
        ]
        let counts: [String: Int] = [
            "overlap": overlapPairs.count,
            "offscreenOrClipped": offscreen.count,
            "hitTargetsUnder44pt": hitTargets.count,
            "truncationHint": truncated.count,
            "distinctLeadingInsets": leadingInsets.count,
        ]
        return (layout, counts)
    }

    // MARK: - Making the app inactive (AppLockUITests' own helper, copied: test-only, no app changes)

    @MainActor
    private func makeInactive(_ app: XCUIApplication) -> String? {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let attempts: [(String, () -> Void)] = [
            ("app switcher", {
                let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
                let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                bottom.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1.5)
            }),
            ("Notification Center", {
                let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.001))
                let lower = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6))
                top.press(forDuration: 0.05, thenDragTo: lower)
            }),
        ]
        for (name, gesture) in attempts {
            gesture()
            if waitForScenePhase("inactive", in: app, timeout: 4) { return name }
            app.activate()
            _ = waitForScenePhase("active", in: app, timeout: 10)
        }
        return nil
    }

    @MainActor
    private func waitForScenePhase(_ phase: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let probe = app.staticTexts["testHook.scenePhase"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "scene: \(phase)"), object: probe)
        return XCTWaiter().wait(for: [expected], timeout: timeout) == .completed
    }
}
