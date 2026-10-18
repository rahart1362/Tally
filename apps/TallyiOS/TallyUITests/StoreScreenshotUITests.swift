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

    /// Report-only since the PMO ruling of 2026-10-18 (the comment at the end of this function has
    /// the measured reason): it attaches its findings beside each capture and never fails a test.
    ///
    /// MVP-3b (branch audit's clean plan, F1 — rewrites 2acdbee's own version, which failed every
    /// scene: `AccessibilityAuditUITests.swift`'s `A11yScene` tab-label-text filter missed every
    /// row genuinely hidden by the bar's hard scroll edge, since a scrolled row's accessibility
    /// frame reaching into the tab bar's Y-range does not by itself mean it is visible there — the
    /// bar's own now-opaque chrome can cover it at rest. Runs on the SAME `XCUIScreenshot` attached
    /// as the store image (measure exactly what was captured), building an `A11yScene` from it for
    /// structural exclusion (`chromeOwnContent`: the bar's own descendants, never a label-text
    /// guess) and the pixel proof (`measureBottomChromeCoverage`, `measureHardEdgeBandTop` —
    /// `AccessibilityAuditUITests.swift`'s own type, the same one `scope=a11y` already proves the
    /// top chrome with).
    ///
    /// The union is the tab bar's own frame plus `TallyScreenChrome`'s hard bottom scroll-edge's
    /// own measured gradient band directly above it. A `staticText` with a positive but partial
    /// overlap (under two thirds of its own on-screen height) inside that union fails outright — a
    /// real straddle, half shown and half cut off, which the pixel proof below is not meant to
    /// excuse. One at least two thirds inside still needs that proof on each part it reaches: at
    /// least 95% of its own pixels within 1.2:1 of that part's own colour, and no pixel row above
    /// 1.5:1 — genuinely invisible, not merely "mostly" under the bar.
    ///
    /// Skips entirely while a sheet with no tab bar of its own is on screen (What-If, the only
    /// sheet this suite ever captures): the tab bar's own element can still report `exists` from
    /// underneath a presented sheet (it never leaves the hierarchy, only the screen), so rows
    /// behind the sheet must never be judged against it. Detected structurally, by the sheet's own
    /// "Done" identifier, not by counting bars or guessing at presentation state.
    @MainActor
    private func recordWhatIsUnderTheTabBar(_ app: XCUIApplication, screenshot: XCUIScreenshot, scene: String) {
        guard !element("whatif.done", in: app).exists else { return }
        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists else { return }
        let tabBarFrame = tabBar.frame
        let a11yScene = A11yScene(app, screenshot: screenshot.image)
        let band = a11yScene.measureHardEdgeBandTop(aboveBar: tabBarFrame).map { bandTop in
            CGRect(x: tabBarFrame.minX, y: bandTop, width: tabBarFrame.width, height: tabBarFrame.minY - bandTop)
        }
        let union = band.map { tabBarFrame.union($0) } ?? tabBarFrame
        var straddling: [String] = []
        var hidden: [String] = []
        for text in app.staticTexts.allElementsBoundByIndex {
            guard text.exists else { continue }
            let rawFrame = text.frame
            // Structural exclusion (not label text): the bar's own descendants (its tab labels),
            // recorded by true tree ancestry during the same snapshot `a11yScene` was built from.
            guard !a11yScene.chromeOwnContent.contains(where: { A11yScene.same($0, rawFrame) }) else { continue }
            let frame = rawFrame.intersection(a11yScene.window)
            guard frame.height > 0, frame.width > 0 else { continue }
            let overlap = union.intersection(frame)
            let overlapHeight = overlap.isNull ? 0 : overlap.height
            guard overlapHeight > 0 else { continue }
            let fraction = overlapHeight / frame.height
            guard fraction >= 2.0 / 3.0 else {
                straddling.append("'\(text.label)' \(frame), \(String(format: "%.0f", fraction * 100))% inside the union")
                continue
            }
            let measured = a11yScene.measureBottomChromeCoverage(tabBar: tabBarFrame, band: band, regionFrame: frame,
                                                                   excluding: a11yScene.chromeOwnContent)
            let passes = measured.map { $0.coverage >= A11yScene.navBarCoverageThreshold
                && $0.maxGlyphContrast <= A11yScene.navBarGlyphContrastThreshold } ?? false
            guard passes else {
                let detail = measured.map { "coverage \(String(format: "%.1f", $0.coverage * 100))%, max glyph contrast " +
                    "\(String(format: "%.2f", $0.maxGlyphContrast)):1" } ?? "a part failed the per-part proof (measureBottomChromeCoverage returns nil for that)"
                hidden.append("'\(text.label)' \(frame), \(String(format: "%.0f", fraction * 100))% inside the union, \(detail)")
                continue
            }
        }
        // PMO ruling 2026-10-18 (release gate 39137674623): report-only. Measured on the tour's own
        // Pro Max captures (run 39130267292), the hard edge cuts content off at the tab bar's top and
        // nothing shows through the glass below it, yet the per-part proof failed every tab-rooted
        // scene in all four legs: the floating capsule's own rim and highlight measure 1.5-1.9:1
        // against the bar's modal colour (above the 1.2:1 limit), and the band scan ran to its full
        // 80 pt window on Calendar and parent mode, counting visible content above the bar as
        // "under" it. A measurement check never gates (owner, 2026-09-28); these findings are
        // attached beside each capture, and the gate-2 visual review at 200% decides "no text
        // through or under the tab bar".
        let findings = "\(scene): tab bar/hard-edge band union \(union)\n" +
            "Straddling (positive overlap, under two thirds inside): \(straddling)\n" +
            "Not proven hidden (two thirds or more inside, but the pixel proof failed): \(hidden)\n"
        let attachment = XCTAttachment(string: findings)
        attachment.name = "\(scene)-bottom-chrome"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits at rest (`AuditTourUITests.waitUntilAtRest`'s own rule: two screenshots 0.4 s apart,
    /// pixel-identical, up to 6 s — pmo-ux-common.md's "captures only at rest"), then checks
    /// nothing sits under the tab bar/hard-edge band union (I1) on the SAME screenshot before
    /// attaching it as `NN-<scene>`.
    @MainActor
    private func capture(_ app: XCUIApplication, number: Int, scene: String) {
        let settled = waitUntilAtRest(app)
        XCTAssertTrue(settled, "\(scene) never settled before capture. Hierarchy: \(app.debugDescription)")
        let screenshot = app.screenshot()
        recordWhatIsUnderTheTabBar(app, screenshot: screenshot, scene: scene)
        let name = String(format: "%02d-%@", number, scene)
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// MVP-3b (owner decision 2026-10-18, "nudge 3, keep Dashboard"): the hard bottom edge cuts
    /// content off at the tab bar's top, and in release gate 39146374513 that line ran through a
    /// text row on Course Detail ("Lab Report 6"), Calendar ("Due 8:00 AM") and To-Do (Journal 5's
    /// "Not submitted" chip). From the scene's own resting layout, this finds the smallest upward
    /// scroll, at most `maxNudge` (which keeps the screen's own top where it is), after which every
    /// text either ends `room` above the cut (room for a status chip's own capsule) or starts no
    /// more than `leading` above it (a line box's empty top, never glyphs), then scrolls that far
    /// with held drags, measured on a text whose label is unique. It is measured on every run,
    /// never a fixed offset, since the es legs wrap differently from en. A combined row (a text
    /// whose frame holds other texts) is judged by its own lines, not as one block, and the tab
    /// bar's own labels never count. If there is no such scroll, or the drags miss it, the scene
    /// is left as it is and the reason is attached for the gate-2 visual review.
    @MainActor
    private func nudgeTheCutLineIntoAGap(_ app: XCUIApplication, scene: String) {
        let room: CGFloat = 5, leading: CGFloat = 2, maxNudge: CGFloat = 24, minimumGap: CGFloat = 1
        _ = waitUntilAtRest(app)
        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists else { return }
        let cut = tabBar.frame.minY
        let chrome = tabBar.descendants(matching: .staticText).allElementsBoundByIndex.map { $0.frame }
        func isChrome(_ frame: CGRect) -> Bool {
            chrome.contains { abs($0.minX - frame.minX) < 0.5 && abs($0.minY - frame.minY) < 0.5
                && abs($0.width - frame.width) < 0.5 && abs($0.height - frame.height) < 0.5 }
        }
        var texts: [(label: String, frame: CGRect)] = []
        for text in app.staticTexts.allElementsBoundByIndex where text.exists {
            let label = text.label
            let frame = text.frame
            guard frame.height > 0, frame.width > 0, !label.isEmpty, !isChrome(frame) else { continue }
            texts.append((label, frame))
        }
        let lines = texts.filter { outer in
            !texts.contains { inner in inner.frame != outer.frame && outer.frame.contains(inner.frame) }
        }
        // The offsets at which a line is cut: past the point of hiding it, short of showing all of it.
        let blocked = lines.compactMap { line -> (from: CGFloat, to: CGFloat)? in
            let from = max(0, line.frame.minY - (cut - leading))
            let to = line.frame.maxY - (cut - room)
            return to > from ? (from, to) : nil
        }.sorted { $0.from < $1.from }
        // Nothing is cut at rest (no line starts more than `leading` above the cut and runs past it).
        guard blocked.contains(where: { $0.from == 0 }) else { return }
        var gapStart: CGFloat = 0
        var target: CGFloat?
        for interval in blocked {
            if interval.from - gapStart >= minimumGap { break }
            gapStart = max(gapStart, interval.to)
        }
        let gapEnd = blocked.first { $0.from >= gapStart }?.from ?? .greatestFiniteMagnitude
        if gapStart == 0 { return }
        if gapStart <= maxNudge, gapEnd - gapStart >= minimumGap {
            target = min(gapStart + min(3, (gapEnd - gapStart) / 2), maxNudge)
        }
        let counts = Dictionary(lines.map { ($0.label, 1) }, uniquingKeysWith: +)
        let anchorLine = lines.first { counts[$0.label] == 1 && $0.frame.minY > 300 && $0.frame.maxY < cut - 40 }
        guard let target, let anchorLine else {
            note("\(scene): no nudge. Cut at y \(cut); gap from \(gapStart) pt; anchor found: \(anchorLine != nil)")
            return
        }
        let anchor = app.staticTexts.matching(NSPredicate(format: "label == %@", anchorLine.label)).firstMatch
        let startY = anchorLine.frame.minY
        let centre = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var slop: CGFloat = 10
        for _ in 0..<5 {
            guard anchor.exists else { break }
            let before = anchor.frame.minY
            let error = target - (startY - before)
            if abs(error) <= 0.5 { return }
            let distance = abs(error) + slop
            let end = centre.withOffset(CGVector(dx: 0, dy: error > 0 ? -distance : distance))
            centre.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            _ = waitUntilAtRest(app)
            let actual = abs(before - anchor.frame.minY)
            slop = actual > 0 ? max(0, distance - actual) : slop + 8
        }
        let moved = anchor.exists ? startY - anchor.frame.minY : -1
        note("\(scene): the nudge to \(target) pt ended at \(moved) pt (cut at y \(cut))")
    }

    /// Attaches `text` beside the scene's capture, for the gate-2 visual review.
    @MainActor
    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "cut-line-note"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        nudgeTheCutLineIntoAGap(app, scene: "course-detail")
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

        // MVP-3b (branch audit's clean plan, F3): the scene must show the feature exercised, not
        // the empty initial state. The gate-2 fix (`2acdbee`) matched the baseline against an
        // English phrase ("the same as your current grade"), which every es leg failed (gates
        // 39093421442, 39104275778, 39111609633): compares `whatif.projected`'s own label against
        // itself, before and after, which is locale-free by construction -- whatever the sentence
        // says, in any language, it changes once the projection actually moves. Two quick-fill
        // presets (not the text field) move it without ever bringing up the keyboard: the branch
        // audit's own finding was that the decimal pad has no dismiss key and stays up through the
        // capture (`evidence/E4`), which this avoids rather than works around.
        let baselineLabel = projected.label
        XCTAssertFalse(baselineLabel.isEmpty, "the What-If baseline never landed. Hierarchy: \(app.debugDescription)")
        let firstPreset = elements("whatif.quickFill.90", in: app).element(boundBy: 0)
        XCTAssertTrue(firstPreset.waitForExistence(timeout: 10), "no first item's 90% preset. Hierarchy: \(app.debugDescription)")
        firstPreset.tap()
        let secondPreset = elements("whatif.quickFill.90", in: app).element(boundBy: 1)
        XCTAssertTrue(secondPreset.waitForExistence(timeout: 5), "no second item's 90% preset. Hierarchy: \(app.debugDescription)")
        secondPreset.tap()
        XCTAssertTrue(eventually(timeout: 15) { projected.label != baselineLabel },
                     "the projection did not move after two quick-fill presets: '\(projected.label)'")
        XCTAssertEqual(app.keyboards.count, 0, "the keyboard must not be up for the capture. Hierarchy: \(app.debugDescription)")
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
        nudgeTheCutLineIntoAGap(app, scene: "todo")
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
        nudgeTheCutLineIntoAGap(app, scene: "calendar")
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
