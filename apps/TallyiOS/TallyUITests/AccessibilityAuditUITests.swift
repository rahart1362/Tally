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

    /// Reaches a screen with `reach`, audits it, attaches the issue list, and terminates the app.
    /// One call per screen × variant, so a failure's message names both.
    @MainActor
    func auditScreen(_ screen: String, reach: ([String]) -> XCUIApplication, extra: [String] = [], variant: String,
                     types: XCUIAccessibilityAuditType = .all, file: StaticString = #filePath, line: UInt = #line) {
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

    /// Runs one `performAccessibilityAudit`, attaches every issue it finds — waived or not — as
    /// `<screen>-<variant>-audit` (type, element, description), and fails with the screen's own
    /// name in the message if any issue was not waived.
    ///
    /// CI run 38280762497: `TallyUITestCase.setUpWithError` sets `continueAfterFailure = false`
    /// (every suite inherits it), and when the issue handler returns `false`, the audit records
    /// that issue as a failure *immediately*, through a mechanism this method's own `do`/`catch`
    /// cannot intercept (not a thrown Swift error a `catch` clause can see — `continueAfterFailure
    /// = false`'s abort unwinds past normal `try`/`catch` the same way an assertion failure does).
    /// With it false, the *first* unwaived issue ended the test method on the spot: no later issue
    /// in the same audit was ever found, no JSON got attached, and the only message on screen was
    /// Apple's own terse one-liner ("Contrast failed") rather than this method's own. Toggling it
    /// `true` for the span of the call — restored immediately after, before this method's own
    /// assertion — lets the handler run for every issue the audit finds, so `issues`/`unwaived`
    /// end up complete before anything decides pass or fail.
    ///
    /// Collects into `unwaived` from inside the issue handler itself, rather than reading the
    /// thrown error's text: the handler already sees every issue with its element and type, the
    /// authoritative detail this suite's JSON attachment and failure message both need (the whole
    /// point of "one test method per screen" is a failure that names its screen precisely, not
    /// "performAccessibilityAudit threw").
    @MainActor
    func runA11yAudit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all, screen: String, variant: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        var issues: [[String: String]] = []
        var unwaived: [String] = []
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                let typeName = Self.a11yAuditTypeName(issue.auditType)
                let elementID = issue.element?.identifier ?? ""
                // CI run 38306768609: most `contrast` and several `dynamicType`/`elementDetection`
                // issues land on a plain `Text` with no `.accessibilityIdentifier` — `element:
                // ''` alone names nothing a fix can target. `element?.label` (always real text on
                // screen, never used for the waiver key below: several different unidentified
                // elements can share the same empty identifier, so waiving by identifier alone
                // when it is empty would silently become a blanket waiver by accident) gives the
                // actual words to search the source for.
                let elementLabel = issue.element?.label ?? ""
                let waived = A11yWaivers.isWaived(elementIdentifier: elementID, auditType: typeName)
                issues.append(["type": typeName, "element": elementID, "elementLabel": elementLabel,
                               "description": issue.compactDescription, "waived": waived ? "true" : "false"])
                if !waived {
                    let target = elementID.isEmpty
                        ? (elementLabel.isEmpty ? "(no identifier or label)" : "label '\(elementLabel)'")
                        : "'\(elementID)'"
                    unwaived.append("\(typeName) on \(target): \(issue.compactDescription)")
                }
                return waived
            }
        } catch {
            if unwaived.isEmpty {
                unwaived.append("performAccessibilityAudit itself threw with no issue captured: \(error)")
            }
        }
        continueAfterFailure = previousContinueAfterFailure
        attachA11yJSON(issues, name: "\(screen)-\(variant)-audit")
        XCTAssertTrue(unwaived.isEmpty,
                     "\(screen) (\(variant)): \(unwaived.count) unwaived accessibility issue(s): " + unwaived.joined(separator: " | "),
                     file: file, line: line)
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
