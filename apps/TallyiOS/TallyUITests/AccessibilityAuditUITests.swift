import XCTest

/// MVP-2 (UX-WP-22, ux-ui.md §3.9, A11Y-01/02/04/09): `performAccessibilityAudit()` over screen set
/// S plus the main sheets (Settings, Paywall, What-If, Course Options) and parent mode, through
/// Sample Data (no account, no network) except the lock screen, which Sample Data has no path to —
/// `AppLockUITests`' own precedent is a seeded, signed-in *replay* account, itself fully offline.
///
/// **Three classes, one file** (precedent: `SettingsUITests.swift`'s `SettingsUITests` +
/// `SettingsSignedInUITests` — check a class name against this file before naming it in
/// `-only-testing`; pmo-common-rules-v2.md's CI budget note names exactly this mistake):
/// - `AccessibilityAuditUITests`: Light appearance, default size (every audit type) and AX5
///   (`.dynamicType`, `.textClipped`).
/// - `AccessibilityAuditDarkUITests`: Dark appearance, default size, every audit type.
/// - `AccessibilityAuditContrastUITests`: Increase Contrast, default size, `.contrast` only.
///
/// **Why three classes, not one with a loop.** `XCUIDevice.shared.appearance` alone does not
/// reliably repaint the simulator (Audit tour's own finding, run 37649050231, `AuditTourUITests.swift`'s
/// doc comment): Light and Dark need the simulator's own appearance set with
/// `xcrun simctl ui <udid> appearance light|dark` *before* `xcodebuild test` runs, which the release
/// gate does as a job step between invocations (release-gate.yml), never in-process — so a Light
/// screen and a Dark screen cannot share one `xcodebuild test` run. Increase Contrast is split out
/// the same way, for the same reason (ux-ui.md §3.9 "Harness": `simctl ui`'s content-size and
/// Increase Contrast options are UNVERIFIED on the CI simulator).
///
/// **Increase Contrast, belt and suspenders.** The release gate sets `xcrun simctl ui <udid>
/// increase_contrast enabled` before `AccessibilityAuditContrastUITests` runs (ux-ui.md §3.9's
/// primary mechanism); every launch in that class also passes `TallyUITestCase.a11yIncreaseContrast`
/// (`-UIAccessibilityDarkerSystemColorsEnabled YES`, the brief's documented fallback launch
/// argument). Passing both is harmless if one is a no-op. **UNVERIFIED** until the first CI run's
/// `.contrast` audit (or a deliberately low-contrast canary) confirms one of the two actually
/// changed `colorSchemeContrast` — `ScreenComponents.swift`, `ScreenCharts.swift` and
/// `DestructiveConfirmation.swift` all read that environment value today, so a no-op here would
/// silently audit the *unincreased* colours and under-report.
///
/// **Waivers.** `A11yWaivers` (below) matches one element identifier plus one audit type exactly —
/// never a whole type or screen; `docs/pmo/a11y-waivers.md` has the justification for every row.
/// Every issue an audit call finds — waived or not — is attached as `<screen>-<variant>-audit`
/// (type, element, description), so a reviewer sees what was waived, not only what failed.
///
/// **Coverage.** `docs/pmo/reviews/mvp2-report.md` has the A11Y-01…12 requirement → test → result
/// map. This suite is A11Y-01/02/04/09's own evidence; A11Y-03/05/06/07/08/10/11 are proven by the
/// screen suites named there (`ScreenUITestSupport.assertEveryButtonHasALabel`, `SlowRefreshUITests`,
/// `ToDoUITests`, `InsightsUITests`, `WelcomeCTAUITests`, `RemindersUITests`); A11Y-12 has a unit
/// test (`SignInHandoffViewModelTests`) but no UI test yet — an open item, not claimed here.
final class AccessibilityAuditUITests: TallyUITestCase {
    private var runs = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipUnlessA11yAuditScopeIsSet()
        runs = true
    }

    override func tearDownWithError() throws {
        guard runs else { return }
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testWelcome() throws {
        auditScreen("welcome", reach: { self.a11yReachWelcome(extra: $0) }, variant: "light-std")
        auditScreen("welcome", reach: { self.a11yReachWelcome(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    /// The idle state only (ScreenSearchUITests and PaywallUITests already reach "searchFailed" and
    /// "not enabled" through the same screen's code; this suite does not re-audit every sub-state —
    /// an open item, not a gap in the underlying screen's own coverage).
    @MainActor
    func testFindSchool() throws {
        auditScreen("findSchool", reach: { self.a11yReachFindSchoolIdle(extra: $0) }, variant: "light-std")
        auditScreen("findSchool", reach: { self.a11yReachFindSchoolIdle(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testHandoff() throws {
        auditScreen("handoff", reach: { self.a11yReachHandoff(extra: $0) }, variant: "light-std")
        auditScreen("handoff", reach: { self.a11yReachHandoff(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testFirstSyncSkeleton() throws {
        auditScreen("firstSyncSkeleton", reach: { self.a11yReachFirstSyncSkeleton(extra: $0) }, variant: "light-std")
        auditScreen("firstSyncSkeleton", reach: { self.a11yReachFirstSyncSkeleton(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testDashboard() throws {
        auditScreen("dashboard", reach: { self.a11yReachDashboard(extra: $0) }, variant: "light-std")
        auditScreen("dashboard", reach: { self.a11yReachDashboard(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testCourses() throws {
        auditScreen("courses", reach: { self.a11yReachCourses(extra: $0) }, variant: "light-std")
        auditScreen("courses", reach: { self.a11yReachCourses(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testCourseDetail() throws {
        auditScreen("courseDetail", reach: { self.a11yReachCourseDetail(extra: $0) }, variant: "light-std")
        auditScreen("courseDetail", reach: { self.a11yReachCourseDetail(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testWhatIf() throws {
        auditScreen("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }, variant: "light-std")
        auditScreen("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    /// MVP-2b: What-If opens at its medium height, where the system draws the sheet at about 0.96
    /// scale (`ScoreStepper.buttonSide`'s note). Its large height is audited too, as a state of its
    /// own (a student who pulls the sheet up sees it), in a method of its own so neither method
    /// nears the 240 s allowance (`testWhatIf` took 140 s with two audits in run 38338079168).
    @MainActor
    func testWhatIfLargeDetent() throws {
        auditScreen("whatIf", reach: { self.a11yReachWhatIfLarge(extra: $0) }, variant: "light-std-large")
    }

    @MainActor
    func testCourseOptions() throws {
        auditScreen("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }, variant: "light-std")
        auditScreen("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testCalendar() throws {
        auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, variant: "light-std")
        auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testToDo() throws {
        auditScreen("toDo", reach: { self.a11yReachToDo(extra: $0) }, variant: "light-std")
        auditScreen("toDo", reach: { self.a11yReachToDo(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testInsights() throws {
        auditScreen("insights", reach: { self.a11yReachInsights(extra: $0) }, variant: "light-std")
        auditScreen("insights", reach: { self.a11yReachInsights(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testSettings() throws {
        auditScreen("settings", reach: { self.a11yReachSettings(extra: $0) }, variant: "light-std")
        auditScreen("settings", reach: { self.a11yReachSettings(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testPaywall() throws {
        auditScreen("paywall", reach: { self.a11yReachPaywall(extra: $0) }, variant: "light-std")
        auditScreen("paywall", reach: { self.a11yReachPaywall(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testParentMode() throws {
        auditScreen("parentMode", reach: { self.a11yReachParentMode(extra: $0) }, variant: "light-std")
        auditScreen("parentMode", reach: { self.a11yReachParentMode(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testLockView() throws {
        auditScreen("lockView", reach: { self.a11yReachLockView(extra: $0) }, variant: "light-std")
        auditScreen("lockView", reach: { self.a11yReachLockView(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }
}

/// Dark appearance, default size, every audit type. release-gate.yml sets the simulator to Dark
/// with `xcrun simctl ui <udid> appearance dark` before this class's `xcodebuild test` invocation,
/// and back to Light afterward (the class above's own doc comment explains why this cannot share a
/// run with it).
final class AccessibilityAuditDarkUITests: TallyUITestCase {
    private var runs = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipUnlessA11yAuditScopeIsSet()
        runs = true
    }

    override func tearDownWithError() throws {
        guard runs else { return }
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testWelcome() throws { auditScreen("welcome", reach: { self.a11yReachWelcome(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testFindSchool() throws { auditScreen("findSchool", reach: { self.a11yReachFindSchoolIdle(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testHandoff() throws { auditScreen("handoff", reach: { self.a11yReachHandoff(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testFirstSyncSkeleton() throws { auditScreen("firstSyncSkeleton", reach: { self.a11yReachFirstSyncSkeleton(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testDashboard() throws { auditScreen("dashboard", reach: { self.a11yReachDashboard(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testCourses() throws { auditScreen("courses", reach: { self.a11yReachCourses(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testCourseDetail() throws { auditScreen("courseDetail", reach: { self.a11yReachCourseDetail(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testWhatIf() throws { auditScreen("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testCourseOptions() throws { auditScreen("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testCalendar() throws { auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testToDo() throws { auditScreen("toDo", reach: { self.a11yReachToDo(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testInsights() throws { auditScreen("insights", reach: { self.a11yReachInsights(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testSettings() throws { auditScreen("settings", reach: { self.a11yReachSettings(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testPaywall() throws { auditScreen("paywall", reach: { self.a11yReachPaywall(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testParentMode() throws { auditScreen("parentMode", reach: { self.a11yReachParentMode(extra: $0) }, variant: "dark-std") }
    @MainActor
    func testLockView() throws { auditScreen("lockView", reach: { self.a11yReachLockView(extra: $0) }, variant: "dark-std") }
}

/// Increase Contrast, default size, `.contrast` only (this class's own doc comment above has the
/// two-mechanism rationale).
final class AccessibilityAuditContrastUITests: TallyUITestCase {
    private var runs = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipUnlessA11yAuditScopeIsSet()
        runs = true
    }

    override func tearDownWithError() throws {
        guard runs else { return }
        MainActor.assumeIsolated { LifecycleUITest.resetAppState() }
    }

    @MainActor
    func testWelcome() throws { auditContrast("welcome", reach: { self.a11yReachWelcome(extra: $0) }) }
    @MainActor
    func testFindSchool() throws { auditContrast("findSchool", reach: { self.a11yReachFindSchoolIdle(extra: $0) }) }
    @MainActor
    func testHandoff() throws { auditContrast("handoff", reach: { self.a11yReachHandoff(extra: $0) }) }
    @MainActor
    func testFirstSyncSkeleton() throws { auditContrast("firstSyncSkeleton", reach: { self.a11yReachFirstSyncSkeleton(extra: $0) }) }
    @MainActor
    func testDashboard() throws { auditContrast("dashboard", reach: { self.a11yReachDashboard(extra: $0) }) }
    @MainActor
    func testCourses() throws { auditContrast("courses", reach: { self.a11yReachCourses(extra: $0) }) }
    @MainActor
    func testCourseDetail() throws { auditContrast("courseDetail", reach: { self.a11yReachCourseDetail(extra: $0) }) }
    @MainActor
    func testWhatIf() throws { auditContrast("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }) }
    @MainActor
    func testCourseOptions() throws { auditContrast("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }) }
    @MainActor
    func testCalendar() throws { auditContrast("calendar", reach: { self.a11yReachCalendar(extra: $0) }) }
    @MainActor
    func testToDo() throws { auditContrast("toDo", reach: { self.a11yReachToDo(extra: $0) }) }
    @MainActor
    func testInsights() throws { auditContrast("insights", reach: { self.a11yReachInsights(extra: $0) }) }
    @MainActor
    func testSettings() throws { auditContrast("settings", reach: { self.a11yReachSettings(extra: $0) }) }
    @MainActor
    func testPaywall() throws { auditContrast("paywall", reach: { self.a11yReachPaywall(extra: $0) }) }
    @MainActor
    func testParentMode() throws { auditContrast("parentMode", reach: { self.a11yReachParentMode(extra: $0) }) }
    @MainActor
    func testLockView() throws { auditContrast("lockView", reach: { self.a11yReachLockView(extra: $0) }) }
}

// MARK: - Waiver registry

/// MVP-2 waiver registry: `docs/pmo/a11y-waivers.md` has the justification for every row. A waiver
/// matches one element identifier plus one audit type exactly — never a whole type or screen.
/// Empty until a CI run finds a real, justified false positive; nothing here is speculative.
enum A11yWaivers {
    struct Key: Hashable {
        let elementIdentifier: String
        let auditType: String
    }

    /// One entry per row of `docs/pmo/a11y-waivers.md`. Keep the two in sync.
    ///
    /// **Format matters, not just style:** release-gate.yml counts waivers for `REL.a11y.audit`'s
    /// report by counting lines matching `^\s*Key\(elementIdentifier:` in this file, rather than
    /// reading `.count` out of a running process — so every entry must be `Key(elementIdentifier:`
    /// at the start of its own line (leading whitespace only), one entry per line, exactly like the
    /// array literal's own syntax already reads.
    ///
    /// CI run 38313859274's evidence (`pmo-audit/.build-audit/mvp2/issue-inventory.md`): every
    /// entry below is a `ToolbarItem` button — system-rendered navigation-bar chrome whose text
    /// scaling, truncation and exact colour the app does not control beyond its `Button`'s own
    /// label string, the same category `defects.md`'s "Layout-check triage" already accepted for
    /// toolbar items ("the system extends their hit region"). `docs/pmo/a11y-waivers.md` has the
    /// full justification and the source line for each.
    static let waived: Set<Key> = [
        Key(elementIdentifier: "courses.edit", auditType: "dynamicType"),
        Key(elementIdentifier: "paywall.close", auditType: "dynamicType"),
        Key(elementIdentifier: "settings.done", auditType: "dynamicType"),
        Key(elementIdentifier: "todo.select", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.done", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.reset", auditType: "contrast"),
        Key(elementIdentifier: "whatif.reset", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.reset", auditType: "textClipped"),
        // MVP-2b (scope=a11y run 38338079168). Pinned chrome capped at AX2 by design (ux-fp2 D04/D05,
        // FP-3's banner rule; ASC-14 needs the banner on every screen, perf-app-runtime.md §7 step 3
        // needs Welcome's two actions on screen at every size): Dynamic Type stops at AX2 there, so the
        // audit reads "partially unsupported". Each offers the Large Content Viewer instead (HIG).
        Key(elementIdentifier: "sampleData.banner.label", auditType: "dynamicType"),
        Key(elementIdentifier: "sampleData.banner.exit", auditType: "dynamicType"),
        Key(elementIdentifier: "account.findMySchool", auditType: "dynamicType"),
        Key(elementIdentifier: "account.exploreWithSampleData", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.summary.simulationText", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.summary.projectedLabel", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.summary.projectedValue", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.summary.change", auditType: "dynamicType"),
        // Measured false positive: #1D4E9E on #CCD6E8 is 5.44:1 (Light) and #123C80 on #CAD3E2 7.02:1
        // (Increase Contrast) on the audit's own screenshot, against 3:1 for 17 pt semibold text.
        Key(elementIdentifier: "account.exploreWithSampleData", auditType: "contrast"),
    ]

    static func isWaived(elementIdentifier: String, auditType: String) -> Bool {
        waived.contains(Key(elementIdentifier: elementIdentifier, auditType: auditType))
    }
}

// MARK: - Shared audit primitive and navigation (both classes above)

extension TallyUITestCase {
    static let a11yAccessibilityXXXL = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    /// This file's own top doc comment has the two-mechanism rationale.
    static let a11yIncreaseContrast = ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
    static let a11yDemoHost = "canvas.northfield.example"

    /// Shared by all three classes above: `XCTSkipUnless` on `TALLY_A11Y_AUDIT`, read from
    /// `ProcessInfo` the same way `AuditTourUITests` reads `AUDIT_APPEARANCE` (the
    /// `TEST_RUNNER_` prefix is `xcodebuild`'s own mechanism for reaching the UI test runner
    /// process, so CI sets it as `TEST_RUNNER_TALLY_A11Y_AUDIT`). PMO direction after run
    /// 38280762497: a plain `scope=quick` dispatch bundled these classes with the rest of
    /// `TallyUITests` and hit CI's own 110-minute job cap (16:55→18:48, cancelled) — they now run
    /// only from `ci.yml`'s dedicated `scope=a11y` dispatch and from the release gate's
    /// accessibility-audit step, both of which set this variable; a plain push, PR, or any other
    /// dispatch scope skips every method in all three classes.
    func skipUnlessA11yAuditScopeIsSet() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TALLY_A11Y_AUDIT"] != nil,
                          "The accessibility audit classes run only from scope=a11y or the release gate (they set TALLY_A11Y_AUDIT)")
    }

    /// CI run 38277982949 (`iOS build + test`, Xcode 26.6): `XCUIAccessibilityAuditType` has no
    /// `.action` or `.parentChild` member on this SDK — ux-ui.md §3.9's own list of nine names was
    /// wrong about those two (trusted the code over the doc, rule 8: the compiler is the ground
    /// truth here, not a review document). The seven below are the ones that actually exist.
    private static let a11yAuditTypeNames: [(XCUIAccessibilityAuditType, String)] = [
        (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
        (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
        (.textClipped, "textClipped"), (.trait, "trait"),
    ]

    /// `issue.auditType` is an `OptionSet` with no guaranteed string form; this names it from the
    /// nine known cases (ux-ui.md §3.9) instead of interpolating the raw value.
    static func a11yAuditTypeName(_ type: XCUIAccessibilityAuditType) -> String {
        let names = a11yAuditTypeNames.filter { type.contains($0.0) }.map { $0.1 }
        return names.isEmpty ? "unknown" : names.joined(separator: "+")
    }

    /// MVP-2b: what a default-size audit checks — every type but `.dynamicType`, which each screen's
    /// AX5 audit checks (`light-ax5`; Dynamic Type does not depend on the appearance). Run
    /// 38338079168: every default-size Dynamic Type finding on text with no cap (Settings' seven
    /// lower rows, light and dark) was absent from the same screen's AX5 audit, while every capped
    /// element (the SAMPLE DATA banner, Welcome's two actions, What-If's summary, the toolbar
    /// buttons) was flagged at both sizes. The audit grows the text and measures it again; a row
    /// that growth pushes below the fold cannot be measured again, and is reported as "partially
    /// unsupported" although it scales. AX5 keeps every real finding and none of that artifact.
    static let a11yDefaultSizeTypes = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)

    /// Reaches a screen with `reach`, audits it, attaches the issue list, and terminates the app.
    /// One call per screen × variant, so a failure's message names both.
    @MainActor
    func auditScreen(_ screen: String, reach: ([String]) -> XCUIApplication, extra: [String] = [], variant: String,
                     types: XCUIAccessibilityAuditType = TallyUITestCase.a11yDefaultSizeTypes,
                     file: StaticString = #filePath, line: UInt = #line) {
        let app = reach(extra)
        runA11yAudit(app, for: types, screen: screen, variant: variant, file: file, line: line)
        app.terminate()
    }

    /// `AccessibilityAuditContrastUITests`: Increase Contrast's two mechanisms (this file's top doc
    /// comment), `.contrast` only.
    @MainActor
    func auditContrast(_ screen: String, reach: ([String]) -> XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        auditScreen(screen, reach: reach, extra: Self.a11yIncreaseContrast, variant: "contrast", types: [.contrast],
                   file: file, line: line)
    }

    /// Audits `app` for `types`, attaches every issue it finds — waived or not — as
    /// `<screen>-<variant>-audit` (type, element, frame, description), and fails with the screen's
    /// own name in the message if any issue was neither waived nor held.
    ///
    /// CI run 38280762497: `TallyUITestCase.setUpWithError` sets `continueAfterFailure = false`
    /// (every suite inherits it), and when the issue handler returns `false`, the audit records
    /// that issue as a failure *immediately*, through a mechanism this method's own `do`/`catch`
    /// cannot intercept. With it false, the *first* unwaived issue ended the test method on the
    /// spot. Toggling it `true` for the span of the call lets the handler run for every issue the
    /// audit finds, so `issues`/`unwaived` end up complete before anything decides pass or fail.
    ///
    /// MVP-2b, so that every issue can be measured from CI alone:
    /// - Before the audit the screen waits at rest (the Audit tour's two-identical-screenshots
    ///   rule) and three attachments record it: `<screen>-<variant>-audit-screen` (PNG), and
    ///   `<screen>-<variant>-audit-window` / `-audit-elements` (JSON: the window frame in points,
    ///   and every element with its frame). Run 38338079168 lost the last two: a name with a dot
    ///   in it came out of `xcresulttool` without its `.json`.
    /// - Each issue records its element's frame, type and detailed description.
    /// - `.dynamicType` runs in a pass of its own, after the others. Run 38338079168: in one
    ///   `.all` audit, every contrast and clipping issue on a `List` screen came back with no
    ///   element at all, because the Dynamic Type pass had grown the text and the list had
    ///   rebuilt its rows by the time the issues were handed over.
    /// - `continueAfterFailure` stays `true` through this method's own assertion, so a failing
    ///   default-size audit no longer ends the test before its AX5 audit runs (run 38313859274
    ///   audited AX5 on only the three screens whose default-size audit passed).
    /// - An issue the audit-position rule holds (`A11yScene.heldReason`) is recorded with its
    ///   reason and does not fail the test; `docs/pmo/a11y-waivers.md` has the rule and every
    ///   issue it held, with its measurement.
    @MainActor
    func runA11yAudit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all, screen: String, variant: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        let scene = a11yAttachScreen(app, name: "\(screen)-\(variant)-audit")
        var issues: [[String: Any]] = []
        var unwaived: [String] = []
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        let passes: [XCUIAccessibilityAuditType] = types.contains(.dynamicType) && types != .dynamicType
            ? [types.subtracting(.dynamicType), .dynamicType]
            : [types]
        for pass in passes {
            do {
                try app.performAccessibilityAudit(for: pass) { issue in
                    let typeName = Self.a11yAuditTypeName(issue.auditType)
                    let elementID = issue.element?.identifier ?? ""
                    // CI run 38306768609: most issues land on a plain `Text` with no identifier;
                    // `element?.label` gives the actual words to search the source for. Never part
                    // of the waiver key: several unidentified elements share the empty identifier.
                    let elementLabel = issue.element?.label ?? ""
                    let waived = !elementID.isEmpty && A11yWaivers.isWaived(elementIdentifier: elementID, auditType: typeName)
                    let held = waived ? nil : scene.heldReason(auditType: typeName, label: elementLabel,
                                                              frame: issue.element?.frame ?? .zero)
                    var record = Self.a11yIssueRecord(issue, typeName: typeName, waived: waived)
                    record["held"] = held ?? ""
                    issues.append(record)
                    if !waived && held == nil {
                        let target = elementID.isEmpty
                            ? (elementLabel.isEmpty ? "(no identifier or label)" : "label '\(elementLabel)'")
                            : "'\(elementID)'"
                        unwaived.append("\(typeName) on \(target): \(issue.compactDescription)")
                    }
                    return waived || held != nil
                }
            } catch {
                if unwaived.isEmpty {
                    unwaived.append("performAccessibilityAudit itself threw with no issue captured: \(error)")
                }
            }
        }
        attachA11yJSON(issues, name: "\(screen)-\(variant)-audit")
        XCTAssertTrue(unwaived.isEmpty,
                     "\(screen) (\(variant)): \(unwaived.count) unwaived accessibility issue(s): " + unwaived.joined(separator: " | "),
                     file: file, line: line)
        continueAfterFailure = previousContinueAfterFailure
    }

    /// MVP-2b: `FamilyUITests`' switcher audits keep their scope filter's exact behaviour (an issue
    /// `shouldIgnore` accepts is ignored, any other fails the test), and attach every issue the
    /// filter ignored as `<name>-ignored-audit`, so `docs/pmo/a11y-waivers.md` can say what the
    /// filter actually suppresses instead of guessing.
    @MainActor
    func a11yAuditRecordingIgnored(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all, name: String,
                                   ignoring shouldIgnore: @escaping (XCUIAccessibilityAuditIssue) -> Bool) throws {
        let scene = a11yAttachScreen(app, name: "\(name)-audit")
        var ignored: [[String: Any]] = []
        var thrown: Error?
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let ignore = shouldIgnore(issue)
                if ignore {
                    // What the shared rules (an exact waiver, or the audit-position rule) would make
                    // of it, recorded beside it: the evidence for replacing the prefix filter.
                    let typeName = Self.a11yAuditTypeName(issue.auditType)
                    let elementID = issue.element?.identifier ?? ""
                    let waived = !elementID.isEmpty && A11yWaivers.isWaived(elementIdentifier: elementID, auditType: typeName)
                    var record = Self.a11yIssueRecord(issue, typeName: typeName, waived: waived)
                    record["held"] = scene.heldReason(auditType: typeName, label: issue.element?.label ?? "",
                                                      frame: issue.element?.frame ?? .zero) ?? ""
                    ignored.append(record)
                }
                return ignore
            }
        } catch {
            thrown = error
        }
        continueAfterFailure = previousContinueAfterFailure
        attachA11yJSON(ignored, name: "\(name)-ignored-audit")
        if let thrown { throw thrown }
    }

    /// One issue as the JSON evidence records it. The frame is the element's own, in points; a
    /// missing or non-finite frame is recorded as zero (JSONSerialization rejects infinity, and
    /// one bad number would drop the whole attachment).
    @MainActor
    static func a11yIssueRecord(_ issue: XCUIAccessibilityAuditIssue, typeName: String, waived: Bool) -> [String: Any] {
        let element = issue.element
        let frame = A11yScene.finite(element?.frame ?? .zero)
        return [
            "type": typeName,
            "element": element?.identifier ?? "",
            "elementLabel": element?.label ?? "",
            "elementType": Int(element?.elementType.rawValue ?? 0),
            "frame": A11yScene.json(frame),
            "description": issue.compactDescription,
            "detailedDescription": issue.detailedDescription,
            "waived": waived ? "true" : "false",
        ]
    }

    /// Waits for the screen to settle (two screenshots 0.4 s apart pixel-identical, at most 6 s:
    /// `AuditTourUITests.waitUntilAtRest`'s rule), attaches it as `<prefix>-screen` (PNG), and,
    /// from one `app.snapshot()`, `<prefix>-window` and `<prefix>-elements` (JSON). Returns that
    /// snapshot's `A11yScene` for the audit-position rule.
    @MainActor
    private func a11yAttachScreen(_ app: XCUIApplication, name prefix: String) -> A11yScene {
        let deadline = Date().addingTimeInterval(6)
        var previous = app.screenshot().pngRepresentation
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.4)
            let next = app.screenshot().pngRepresentation
            if next == previous { break }
            previous = next
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(prefix)-screen"
        shot.lifetime = .keepAlways
        add(shot)
        let scene = A11yScene(app)
        attachA11yJSON(A11yScene.json(scene.window), name: "\(prefix)-window")
        attachA11yJSON(scene.elements, name: "\(prefix)-elements")
        return scene
    }

    @MainActor
    private func attachA11yJSON(_ object: Any, name: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Navigation to every screen in S (ux-ui.md §3.9), the main sheets and parent mode

    @MainActor
    func a11yReachWelcome(extra: [String] = []) -> XCUIApplication {
        let app = launchApp(arguments: extra)
        XCTAssertTrue(element("account.findMySchool", in: app).waitForExistence(timeout: 30),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachFindSchoolIdle(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachWelcome(extra: extra)
        tapWhenHittable(element("account.findMySchool", in: app), in: app, timeout: 30)
        XCTAssertTrue(element("schoolSearch.idleHint", in: app).waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    /// School search's field, at every text size (ux-fp1 round 3's own doc comment on
    /// `AuditTourUITests.schoolSearchField`, copied here for the same reason: below AX1 it is the
    /// system `.searchable` field, with no identifier; from AX1 up it is `schoolSearch.field`).
    @MainActor
    private func a11ySchoolSearchField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR elementType == %lu", "schoolSearch.field", XCUIElement.ElementType.searchField.rawValue
        )).firstMatch
    }

    @MainActor
    func a11yReachHandoff(extra: [String] = []) -> XCUIApplication {
        let app = launchApp(arguments: TestHooks.demoSignIn + extra)
        tapWhenHittable(element("account.findMySchool", in: app), in: app, timeout: 30)
        let field = a11ySchoolSearchField(app)
        tapWhenHittable(field, in: app, timeout: 10)
        field.typeText(Self.a11yDemoHost)
        tapWhenHittable(element("schoolSearch.useAddress", in: app), in: app, timeout: 10)
        XCTAssertTrue(element("onboarding.signIn.continueTo", in: app).waitForExistence(timeout: 15),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachFirstSyncSkeleton(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachHandoff(extra: extra)
        element("onboarding.signIn.continueTo", in: app).tap()
        // Best-effort, like `AuditTourUITests.testI`'s own doc comment: a fast replay may already
        // have switched to the Dashboard by the time this is checked. When it has, the audit below
        // runs the Dashboard instead — already covered by its own screen group, never a false pass.
        _ = element("onboarding.firstSync.settingUpTally", in: app).waitForExistence(timeout: 5)
        return app
    }

    @MainActor
    func a11yReachDashboard(extra: [String] = []) -> XCUIApplication {
        launchSample(arguments: extra)
    }

    @MainActor
    func a11yReachCourses(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openTab("Courses", in: app)
        XCTAssertTrue(elements("course.card", in: app).firstMatch.waitForExistence(timeout: 15),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachCourseDetail(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachCourses(extra: extra)
        let cards = elements("course.card", in: app)
        let first = cards.element(boundBy: 0)
        XCTAssertTrue(scrollUntilHittable(first, in: app, maxSwipes: 15), "Hierarchy: \(app.debugDescription)")
        first.tap()
        XCTAssertTrue(element("courseDetail.hero", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachWhatIf(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachCourseDetail(extra: extra)
        let whatIf = element("courseDetail.whatIf", in: app)
        XCTAssertTrue(scrollUntilHittable(whatIf, in: app), "Hierarchy: \(app.debugDescription)")
        whatIf.tap()
        XCTAssertTrue(element("whatif.simulationLabel", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        return app
    }

    /// What-If pulled up to its large height (`CourseDetailUITests`' own gesture: a swipe up on
    /// the sheet's navigation bar).
    @MainActor
    func a11yReachWhatIfLarge(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachWhatIf(extra: extra)
        let sheetBar = app.navigationBars["What-If"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        sheetBar.swipeUp()
        return app
    }

    @MainActor
    func a11yReachCourseOptions(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachCourseDetail(extra: extra)
        let menu = element("courseDetail.menu", in: app)
        XCTAssertTrue(scrollUntilHittable(menu, in: app), "Hierarchy: \(app.debugDescription)")
        menu.tap()
        XCTAssertTrue(element("courseDetail.gradesOutsideCanvas", in: app).waitForExistence(timeout: 5),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachCalendar(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openTab("Calendar", in: app)
        XCTAssertTrue(elements("calendar.day", in: app).firstMatch.waitForExistence(timeout: 15),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachToDo(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openTab("To-Do", in: app)
        XCTAssertTrue(elementsWithPrefix("todo.row", in: app).firstMatch.waitForExistence(timeout: 15),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachInsights(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openTab("Insights", in: app)
        XCTAssertTrue(element("chart.trend", in: app).waitForExistence(timeout: 30), "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachSettings(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openSettings(app)
        return app
    }

    /// Settings → Subscription → See Plans → the interstitial → Continue, the same Sample Data
    /// path `PaywallUITests.testSampleModeSettingsInterstitialPaywallAndPurchase` proves end to
    /// end; its two steps (`openSubscriptionSettings`, `openPaywallThroughTheInterstitial`) are a
    /// `TallyUITestCase` extension in `PaywallUITests.swift`, reused here rather than duplicated.
    @MainActor
    func a11yReachPaywall(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: TestHooks.entitlement("none") + extra)
        openSubscriptionSettings(app)
        openPaywallThroughTheInterstitial(app)
        return app
    }

    @MainActor
    func a11yReachParentMode(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openSettings(app)
        let explore = app.buttons["family.sample.viewAsParent"]
        XCTAssertTrue(scrollUntilHittable(explore, in: app, maxSwipes: 30), "Hierarchy: \(app.debugDescription)")
        explore.tap()
        XCTAssertTrue(element("family.switcher", in: app).waitForExistence(timeout: 20), "Hierarchy: \(app.debugDescription)")
        return app
    }

    /// Sample Data has no path to the lock screen (it is a signed-in-account feature); this is the
    /// one screen in S this suite reaches through a seeded, signed-in *replay* account instead —
    /// `AppLockUITests`' own precedent, itself fully offline, no network, no real Canvas account.
    @MainActor
    func a11yReachLockView(extra: [String] = []) -> XCUIApplication {
        seedFlagshipAccount()
        let app = launchApp(arguments: TestHooks.replayAccounts + TestHooks.appLockOn + TestHooks.deviceAuth("cancel") + extra)
        XCTAssertTrue(app.buttons["lock.unlock"].waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        return app
    }
}

// MARK: - The screen at the audit moment, and the audit-position rule

/// MVP-2b: the screen the audit sees, from one `app.snapshot()` taken just before it (one IPC
/// call), and the audit-position rule, `heldReason`.
///
/// **Why a rule, and why this one.** Run 38338079168 measured every contrast issue on the
/// audit-moment screenshot's own pixels (`docs/pmo/reviews/mvp2b-report.md` has the table). The
/// colour tokens never failed: every pixel failure was text that scrolls and, at that moment, sat
/// under the floating tab bar, under the navigation bar or a pinned header, or under iOS 26's
/// scroll-edge dimming (`AdditionalDimmingOverlay`, an image the system lays over the content next
/// to a bar). Which rows sit there depends on the scroll position and on the sample data's dates
/// (relative to today), so no exact (identifier, type) waiver can name them, and an identifier on
/// every row would waive those rows everywhere, in view or not. The design audit already ruled
/// this pattern out as a defect (`defects.md`, layout-check triage 1991: mid-scroll rows under
/// the translucent bar; the last row clears it at the bottom of the scroll).
///
/// So the rule holds only what it must: a `contrast` or `textClipped` issue, on an element that
/// scrolls (it sits in a scroll view, table or collection view), which at the audit moment is not
/// wholly in view — part of it lies outside its scroll view or the window, or under system chrome.
/// Every other issue still fails, and so do these two types on anything wholly in view or pinned
/// (a pinned button or banner is never held). A held issue is still attached, with its reason.
struct A11yScene {
    /// The image iOS 26 adds over content beside a bar (the scroll-edge dimming).
    static let dimmingOverlay = "AdditionalDimmingOverlay"

    /// The app's window, in points.
    var window: CGRect = .zero
    /// For `<prefix>-elements`: every text, button, image, field, switch, cell, bar and identified
    /// container, with its frame, and the frame of the scroll view it scrolls in, if any.
    var elements: [[String: Any]] = []
    /// System chrome over the scrolling content: tab bars, navigation bars, toolbars, and the
    /// scroll-edge dimming.
    var chrome: [CGRect] = []
    /// Every element inside a scroll view, table or collection view, with that container's frame.
    var scrolling: [(label: String, frame: CGRect, container: CGRect)] = []

    init() {}

    @MainActor
    init(_ app: XCUIApplication) {
        guard let root = try? app.snapshot() else { return }
        window = root.frame
        walk(root, container: nil)
    }

    @MainActor
    private mutating func walk(_ node: XCUIElementSnapshot, container: CGRect?) {
        // Fields into locals first: `&&`/`||` autoclosures capturing the non-Sendable snapshot fail
        // the Release test build (`AuditTourUITests.analyzeLayout`'s own note, run 37704108738).
        let kind = node.elementType
        let frame = Self.finite(node.frame)
        let identifier = node.identifier
        let label = node.label
        let isOverlay = kind == .image && identifier == Self.dimmingOverlay
        if kind == .tabBar || kind == .navigationBar || kind == .toolbar || isOverlay {
            chrome.append(frame)
        }
        if let container {
            scrolling.append((label: label, frame: frame, container: container))
        }
        let recorded: Set<XCUIElement.ElementType> = [.staticText, .button, .image, .tabBar, .navigationBar, .toolbar,
                                                      .link, .textField, .switch, .cell, .other]
        let visible = frame.width > 0 && frame.height > 0
        if visible && recorded.contains(kind) && (kind != .other || !identifier.isEmpty) {
            elements.append(["elementType": Int(kind.rawValue), "identifier": identifier, "label": label,
                             "frame": Self.json(frame), "inScrollView": container != nil,
                             "scrollView": Self.json(container ?? .zero)])
        }
        let isScroller = kind == .scrollView || kind == .table || kind == .collectionView
        let next = isScroller ? frame : container
        for child in node.children {
            walk(child, container: next)
        }
    }

    /// The audit-position rule (this type's doc comment): the reason an issue is held, or `nil`.
    func heldReason(auditType: String, label: String, frame rawFrame: CGRect) -> String? {
        guard auditType == "contrast" || auditType == "textClipped" else { return nil }
        let frame = Self.finite(rawFrame)
        guard frame.width > 0, frame.height > 0 else { return nil }
        guard let node = scrolling.first(where: { $0.label == label && Self.same($0.frame, frame) }) else { return nil }
        let inView = node.container.intersection(window).insetBy(dx: -0.5, dy: -0.5)
        if !inView.contains(frame) { return "partly outside its scroll view or the window" }
        if chrome.contains(where: { $0.intersects(frame) }) { return "under system chrome" }
        return nil
    }

    static func same(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1
            && abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
    }

    /// `.zero` for a null, infinite or non-finite frame (JSONSerialization rejects infinity).
    static func finite(_ frame: CGRect) -> CGRect {
        let parts = [frame.minX, frame.minY, frame.width, frame.height]
        return !frame.isNull && !frame.isInfinite && parts.allSatisfy { $0.isFinite } ? frame : .zero
    }

    static func json(_ frame: CGRect) -> [String: Double] {
        ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)]
    }
}
