import CoreGraphics
import UIKit
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
        // MVP-2b: the first audit signs in to the demo school; when its first sync finishes before
        // the app is terminated, the next launch opens signed in, not on Welcome (run 38357314250:
        // "account.findMySchool never appeared"). Back to Welcome first, as `tearDown` does.
        resetAppState()
        auditScreen("firstSyncSkeleton", reach: { self.a11yReachFirstSyncSkeleton(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    /// MVP-2b gate-2 round 3 (verdict item 6): the long screens' AX5 audit pages to the end of the
    /// list, auditing each page (`a11yPageToEnd`). MVP-2c: that AX5 audit and its pages are a method
    /// of their own (`test<Screen>AX5`), so each gets the whole per-test ceiling: in scope=a11y run
    /// 38660677136 the default-size audit, the AX5 audit and the pages shared one method, and four of
    /// them (Dashboard, Courses, Course Detail, Parent Mode) ran past 300 s.
    @MainActor
    func testDashboard() throws {
        auditScreen("dashboard", reach: { self.a11yReachDashboard(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testDashboardAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("dashboard", reach: { self.a11yReachDashboard(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    @MainActor
    func testCourses() throws {
        auditScreen("courses", reach: { self.a11yReachCourses(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testCoursesAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("courses", reach: { self.a11yReachCourses(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    @MainActor
    func testCourseDetail() throws {
        auditScreen("courseDetail", reach: { self.a11yReachCourseDetail(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testCourseDetailAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("courseDetail", reach: { self.a11yReachCourseDetail(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    /// MVP-2b gate-2 round 2 (item 12): the medium height is the state every user opens the sheet
    /// in, and was never audited (verdict section 3, "not even for contrast or hit regions"). It
    /// gets the types whose misfire was only ever seen pulled up, at 0.96 scale (run 38350587735:
    /// 4 `textClipped` and 4 `elementDetection` at the medium height, none on the same rows pulled
    /// up) — `contrast`, `hitRegion`, `sufficientElementDescription` and `trait`. The large height
    /// (pulled up) keeps only the two types that genuinely need the sheet fully presented.
    @MainActor
    func testWhatIf() throws {
        auditScreen("whatIf", reach: { self.a11yReachWhatIfMedium(extra: $0) }, variant: "medium-std",
                    types: [.contrast, .hitRegion, .sufficientElementDescription, .trait])
        auditScreen("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }, variant: "light-std",
                    types: [.textClipped, .elementDetection])
        auditScreen("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testCourseOptions() throws {
        auditScreen("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }, variant: "light-std")
        auditScreen("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
    }

    /// MVP-2b gate-2 round 3 (verdict item 2): the agenda opened on today, kept as the primary
    /// variant now that item 1 fixes it; the first-day tap state stays as a second variant (the
    /// suite's own original coverage, round 1 onward).
    @MainActor
    func testCalendar() throws {
        executionTimeAllowance = 300
        auditScreen("calendar", reach: { self.a11yReachCalendarToday(extra: $0) }, variant: "light-std")
        auditScreen("calendar", reach: { self.a11yReachCalendarToday(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped])
        auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, variant: "light-std-firstDay")
        auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5-firstDay", types: [.dynamicType, .textClipped])
    }

    @MainActor
    func testToDo() throws {
        auditScreen("toDo", reach: { self.a11yReachToDo(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testToDoAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("toDo", reach: { self.a11yReachToDo(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    @MainActor
    func testInsights() throws {
        auditScreen("insights", reach: { self.a11yReachInsights(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testInsightsAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("insights", reach: { self.a11yReachInsights(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    @MainActor
    func testSettings() throws {
        auditScreen("settings", reach: { self.a11yReachSettings(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testSettingsAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("settings", reach: { self.a11yReachSettings(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    @MainActor
    func testPaywall() throws {
        auditScreen("paywall", reach: { self.a11yReachPaywall(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testPaywallAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("paywall", reach: { self.a11yReachPaywall(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
    }

    @MainActor
    func testParentMode() throws {
        auditScreen("parentMode", reach: { self.a11yReachParentMode(extra: $0) }, variant: "light-std")
    }

    @MainActor
    func testParentModeAX5() throws {
        executionTimeAllowance = Self.a11yPagedAllowance
        auditScreen("parentMode", reach: { self.a11yReachParentMode(extra: $0) }, extra: Self.a11yAccessibilityXXXL,
                    variant: "light-ax5", types: [.dynamicType, .textClipped], pageToEnd: true)
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
    // MVP-2b gate-2 round 2 (item 12): the same medium/large split as the Light class's testWhatIf.
    func testWhatIf() throws {
        auditScreen("whatIf", reach: { self.a11yReachWhatIfMedium(extra: $0) }, variant: "medium-dark",
                    types: [.contrast, .hitRegion, .sufficientElementDescription, .trait])
        auditScreen("whatIf", reach: { self.a11yReachWhatIf(extra: $0) }, variant: "dark-std",
                    types: [.textClipped, .elementDetection])
    }
    @MainActor
    func testCourseOptions() throws { auditScreen("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }, variant: "dark-std") }
    /// MVP-2b gate-2 round 3 (verdict item 2): the agenda opened on today, plus the first-day tap
    /// state as a second variant (this class's own original coverage).
    @MainActor
    func testCalendar() throws {
        auditScreen("calendar", reach: { self.a11yReachCalendarToday(extra: $0) }, variant: "dark-std")
        auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, variant: "dark-std-firstDay")
    }
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
    // MVP-2b gate-2 round 2 (item 12): contrast now belongs to the medium height, not pulled up.
    func testWhatIf() throws {
        auditScreen("whatIf", reach: { self.a11yReachWhatIfMedium(extra: $0) }, extra: Self.a11yIncreaseContrast,
                    variant: "medium-contrast", types: [.contrast])
    }
    @MainActor
    func testCourseOptions() throws { auditContrast("courseOptions", reach: { self.a11yReachCourseOptions(extra: $0) }) }
    /// MVP-2b gate-2 round 3 (verdict item 2): the agenda opened on today, plus the first-day tap
    /// state as a second variant (this class's own original coverage). `auditContrast` always
    /// names its variant "contrast"; the second call names its own so both are kept.
    @MainActor
    func testCalendar() throws {
        auditContrast("calendar", reach: { self.a11yReachCalendarToday(extra: $0) })
        auditScreen("calendar", reach: { self.a11yReachCalendar(extra: $0) }, extra: Self.a11yIncreaseContrast,
                    variant: "contrast-firstDay", types: [.contrast])
    }
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
        // Measured false positive: #1D4E9E on #CCD6E8 is 5.44:1 (Light) and #123C80 on #CAD3E2 7.02:1
        // (Increase Contrast) on the audit's own screenshot, against 3:1 for 17 pt semibold text.
        Key(elementIdentifier: "account.exploreWithSampleData", auditType: "contrast"),
        // Measured false positives, Increase Contrast: Calendar's day letter ("S", 9.41:1 and 9.52:1,
        // in the toolbar buttons' glass shadow) and Settings' "Account" header (8.80:1).
        Key(elementIdentifier: "calendar.weekStrip.weekday", auditType: "contrast"),
        Key(elementIdentifier: "settings.accountHeader", auditType: "contrast"),
        // Run 38350587735. Measured false positives: Paywall's Restore Purchases link (7.24:1 Light,
        // 9.61:1 Increase Contrast) and the hand-off's "Choose a Different School" (`.tallySecondary`,
        // the same style and the same pixels as Welcome's Explore: 5.44:1 / 7.02:1). And the price:
        // VoiceOver reads it as words ("$9.99 per year", PAY-05), not the "$9.99/year" on screen,
        // which the Audit tour shows whole on one line at AX5 on the smallest iPhone.
        Key(elementIdentifier: "paywall.restore", auditType: "contrast"),
        Key(elementIdentifier: "onboarding.signIn.chooseDifferentSchool", auditType: "contrast"),
        Key(elementIdentifier: "paywall.price", auditType: "textClipped"),
        // Run 38357314250, What-If pulled up at AX5: measured as scaling with Dynamic Type on the
        // audit's own screenshots (the score field's placeholder 12.0 pt tall at the default size,
        // 38.7 pt at AX5; the group header 40 pt, one line, then 145 pt, two lines).
        Key(elementIdentifier: "whatif.field", auditType: "dynamicType"),
        Key(elementIdentifier: "whatif.groupHeader", auditType: "dynamicType"),
        // Same run's evidence for the hand-off address tag: at AX5 it shows "canvas." /
        // "northfield." / "example", each whole (run 38350587735's screenshot).
        Key(elementIdentifier: "onboarding.signIn.schoolText", auditType: "textClipped"),
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

    /// `types` split into the passes `runA11yAudit` runs: everything that measures the screen as
    /// it is first, then `.textClipped`, then `.dynamicType` (both grow the text to predict larger
    /// sizes; `runA11yAudit`'s doc comment has the two runs that showed why).
    static func a11yPasses(_ types: XCUIAccessibilityAuditType) -> [XCUIAccessibilityAuditType] {
        let growing: [XCUIAccessibilityAuditType] = [.textClipped, .dynamicType]
        var passes: [XCUIAccessibilityAuditType] = []
        let still = types.subtracting(.textClipped).subtracting(.dynamicType)
        if !still.isEmpty { passes.append(still) }
        for type in growing where types.contains(type) { passes.append(type) }
        return passes
    }

    /// Reaches a screen with `reach`, audits it, attaches the issue list, and terminates the app.
    /// One call per screen × variant, so a failure's message names both.
    ///
    /// MVP-2b gate-2 round 3 (verdict item 6, replacing round 2's one-extra-swipe `page`):
    /// `pageToEnd`, when `true`, scrolls the reached screen one screenful at a time to the end of
    /// the list, auditing each page (`a11yPageToEnd`, below) — round 2's single second pass
    /// (`<variant>-paged`) covered only one more screenful, so Settings' lower rows (16 tour
    /// screenfuls at AX5 on the smallest iPhone, `docs/pmo/a11y-waivers.md`) were still never
    /// reached. Paging after the first pass, rather than scrolling before it, keeps the first
    /// pass's own at-rest reading of the screen as it opens.
    @MainActor
    func auditScreen(_ screen: String, reach: ([String]) -> XCUIApplication, extra: [String] = [], variant: String,
                     types: XCUIAccessibilityAuditType = TallyUITestCase.a11yDefaultSizeTypes,
                     pageToEnd: Bool = false,
                     file: StaticString = #filePath, line: UInt = #line) {
        let app = reach(extra)
        runA11yAudit(app, for: types, screen: screen, variant: variant, file: file, line: line)
        if pageToEnd {
            a11yPageToEnd(app, file: file, line: line) { pageIndex in
                runA11yAudit(app, for: types, screen: screen, variant: "\(variant)-paged-\(pageIndex)", file: file, line: line)
            }
        }
        app.terminate()
    }

    /// MVP-2c: a paged AX5 method's own ceiling, the command line's maximum (`IOS_TEST_FLAGS`'s
    /// `-maximum-test-execution-time-allowance 300`, the release gate's `TEST_FLAGS` alike).
    static let a11yPagedAllowance: TimeInterval = 300
    /// MVP-2c: one page is a drag from this height of the screen (just above the tab bar, 751 of 874
    /// pt; no paged screen pins anything there, run 38660677136's elements) ...
    static let a11yPageDragFrom: CGFloat = 0.86
    /// ... to this one (192 pt, below the navigation bar's 170): 559 pt, less than the 621 pt of
    /// list between To-Do's bars, so consecutive pages overlap and no row is skipped.
    static let a11yPageDragTo: CGFloat = 0.22
    /// MVP-2c: more pages than any screen needs at AX5; reaching it fails the test (see below).
    static let a11yMaxPages = 30

    /// MVP-2b gate-2 round 3 (verdict item 6): one screenful at a time to the end of the list,
    /// auditing each page, so Settings' lower rows (Exit Sample Data, Language, English, Show every
    /// grade change, At least 0.5 points) each land on an audited page. `onPage` runs after each
    /// step that moved the list, with that page's 1-based index.
    ///
    /// MVP-2c, two fixes (scope=a11y run 38660677136's own pages):
    /// - **A step is a held drag of under one screen**, not `app.swipeUp()`. The swipe's fling moved
    ///   To-Do about 1,100 pt per page, almost two screens, so rows between pages were never in
    ///   view. A press, a slow drag and a hold before release leave no momentum.
    /// - **The end is a list that did not move**: the middle band of two settled screenshots,
    ///   between the drag's two points, is compared. The old rule compared whole screenshots taken
    ///   right after the swipe, which a bounce, a scroll indicator or the clock always changed:
    ///   Settings reached its end by page 6 and was audited 7 more times at the same rows, To-Do from
    ///   page 8 on, and Insights until the 20-page cap.
    /// Reaching `maxPages` without the end fails: a silent stop would leave rows unaudited.
    @MainActor
    func a11yPageToEnd(_ app: XCUIApplication, maxPages: Int = TallyUITestCase.a11yMaxPages,
                       file: StaticString = #filePath, line: UInt = #line, onPage: (Int) -> Void) {
        var previous = a11yListBand(app)
        for index in 1...maxPages {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: Self.a11yPageDragFrom))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: Self.a11yPageDragTo))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            a11yWaitUntilSettled(app)
            let current = a11yListBand(app)
            if current == previous { return }
            previous = current
            onPage(index)
        }
        XCTFail("paging reached \(maxPages) pages before the end of the list", file: file, line: line)
    }

    /// The band of a screenshot between `a11yPageDragTo` and `a11yPageDragFrom` (list content only:
    /// no status bar clock, title or tab bar), as PNG data for `a11yPageToEnd`'s comparison.
    @MainActor
    private func a11yListBand(_ app: XCUIApplication) -> Data? {
        guard let image = app.screenshot().image.cgImage else { return nil }
        let height = CGFloat(image.height)
        let band = CGRect(x: 0, y: (height * Self.a11yPageDragTo).rounded(), width: CGFloat(image.width),
                          height: (height * (Self.a11yPageDragFrom - Self.a11yPageDragTo)).rounded())
        guard let cropped = image.cropping(to: band) else { return nil }
        return UIImage(cgImage: cropped).pngData()
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
    /// - The checks that grow the text (`.textClipped`, `.dynamicType`) run after the others, each
    ///   in a pass of its own (`a11yPasses`). Run 38338079168: in one `.all` audit, every contrast
    ///   and clipping issue on a `List` screen came back with no element at all, because the list
    ///   had rebuilt its rows at the larger size by the time the issues were handed over. Run
    ///   38350587735: with `.textClipped` still in the first pass, Calendar's agenda (opened
    ///   scrolled to today) moved while contrast was being measured — issues at y = 36, 150 and
    ///   818 pt for rows the pre-audit snapshot had at 391, 458 and 483 pt.
    /// - `continueAfterFailure` stays `true` through this method's own assertion, so a failing
    ///   default-size audit no longer ends the test before its AX5 audit runs (run 38313859274
    ///   audited AX5 on only the three screens whose default-size audit passed).
    /// - An issue the audit-position rule holds (`A11yScene.heldReason`) is recorded with its
    ///   reason and does not fail the test; `docs/pmo/a11y-waivers.md` has the rule and every
    ///   issue it held, with its measurement.
    /// - MVP-2b gate-2 round 3 (verdict item 5): a "no element" hold (`heldReason`'s own doc
    ///   comment) is now allowed only in a `-paged` variant, only with an empty element identifier,
    ///   capped at 3 per pass, and only confirmed by one retry of the same pass, after the list
    ///   settles, that shows no elementless issue of the same type — otherwise it is a real,
    ///   recurring problem, not the audit's own list-rebuild instability, and fails like any other
    ///   issue.
    @MainActor
    func runA11yAudit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all, screen: String, variant: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        let scene = a11yAttachScreen(app, name: "\(screen)-\(variant)-audit")
        var issues: [[String: Any]] = []
        var unwaived: [String] = []
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        // The two checks that grow the text run last, each in a pass of its own (`a11yPasses`).
        for pass in Self.a11yPasses(types) {
            struct PendingIssue {
                var record: [String: Any]
                let elementID: String
                let elementLabel: String
                let typeName: String
                let waived: Bool
                let isNoElementHold: Bool
            }
            var pending: [PendingIssue] = []
            var noElementCount = 0
            var noElementTypesSeen: Set<String> = []
            do {
                try app.performAccessibilityAudit(for: pass) { issue in
                    let typeName = Self.a11yAuditTypeName(issue.auditType)
                    let elementID = issue.element?.identifier ?? ""
                    // CI run 38306768609: most issues land on a plain `Text` with no identifier;
                    // `element?.label` gives the actual words to search the source for. Never part
                    // of the waiver key: several unidentified elements share the empty identifier.
                    let elementLabel = issue.element?.label ?? ""
                    let waived = !elementID.isEmpty && A11yWaivers.isWaived(elementIdentifier: elementID, auditType: typeName)
                    var held = waived ? nil : scene.heldReason(auditType: typeName, label: elementLabel,
                                                              elementIdentifier: elementID,
                                                              frame: issue.element?.frame ?? .zero, variant: variant)
                    let isNoElementHold = held?.hasPrefix("no element") == true
                    if isNoElementHold {
                        noElementCount += 1
                        noElementTypesSeen.insert(typeName)
                        // Item 5: capped at 3 per pass.
                        if noElementCount > 3 { held = nil }
                    }
                    var record = Self.a11yIssueRecord(issue, typeName: typeName, waived: waived)
                    record["held"] = held ?? ""
                    pending.append(PendingIssue(record: record, elementID: elementID, elementLabel: elementLabel,
                                                typeName: typeName, waived: waived, isNoElementHold: isNoElementHold))
                    // A no-element hold's real verdict waits on the retry below — XCTest's own
                    // immediate per-issue failure (this file's top doc comment on
                    // `continueAfterFailure`) must not fire before that retry runs, so it is
                    // always deferred to this method's final `unwaived` check.
                    return waived || held != nil || isNoElementHold
                }
            } catch {
                if pending.isEmpty {
                    unwaived.append("performAccessibilityAudit itself threw with no issue captured: \(error)")
                }
            }
            // Item 5: one retry, after the list settles, decides which "no element" types are
            // confirmed transient (none of that type on the retry) versus still elementless (not
            // held — a real, recurring issue). The retry's own issues are never recorded or waived;
            // it exists only to answer that one question.
            var stillElementless: Set<String> = []
            if !noElementTypesSeen.isEmpty {
                a11yWaitUntilSettled(app, timeout: 2)
                _ = try? app.performAccessibilityAudit(for: pass) { retryIssue in
                    let retryType = Self.a11yAuditTypeName(retryIssue.auditType)
                    let retryFrame = A11yScene.finite(retryIssue.element?.frame ?? .zero)
                    let retryID = retryIssue.element?.identifier ?? ""
                    let retryLabel = retryIssue.element?.label ?? ""
                    if retryFrame.width <= 0, retryFrame.height <= 0, retryID.isEmpty, retryLabel.isEmpty {
                        stillElementless.insert(retryType)
                    }
                    return true
                }
            }
            for item in pending {
                var record = item.record
                var held = (record["held"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if item.isNoElementHold, held != nil, stillElementless.contains(item.typeName) {
                    held = nil
                    record["held"] = ""
                }
                issues.append(record)
                if !item.waived && held == nil {
                    let target = item.elementID.isEmpty
                        ? (item.elementLabel.isEmpty ? "(no identifier or label)" : "label '\(item.elementLabel)'")
                        : "'\(item.elementID)'"
                    let description = record["description"] as? String ?? ""
                    unwaived.append("\(item.typeName) on \(target): \(description)")
                }
            }
        }
        attachA11yJSON(issues, name: "\(screen)-\(variant)-audit")
        XCTAssertTrue(unwaived.isEmpty,
                     "\(screen) (\(variant)): \(unwaived.count) unwaived accessibility issue(s): " + unwaived.joined(separator: " | "),
                     file: file, line: line)
        continueAfterFailure = previousContinueAfterFailure
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
            // The issue's own description: when the element no longer resolves (a `List` rebuilt
            // at a larger size), this is the only other place that may still name it.
            "issue": String(describing: issue),
            "waived": waived ? "true" : "false",
        ]
    }

    /// Waits until two screenshots `interval` apart are pixel-identical, or `timeout` elapses
    /// (`AuditTourUITests.waitUntilAtRest`'s own rule). MVP-2b gate-2 round 3 (verdict item 5):
    /// also used, with a short `timeout`, before `runA11yAudit`'s one retry of a pass that found a
    /// "no element" issue — the same settling this screen's own first measurement already waits
    /// for, reused rather than a bare `Thread.sleep`.
    @MainActor
    private func a11yWaitUntilSettled(_ app: XCUIApplication, timeout: TimeInterval = 6, interval: TimeInterval = 0.4) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = app.screenshot().pngRepresentation
        while Date() < deadline {
            Thread.sleep(forTimeInterval: interval)
            let next = app.screenshot().pngRepresentation
            if next == previous { return }
            previous = next
        }
    }

    /// Waits for the screen to settle (`a11yWaitUntilSettled`'s default: two screenshots 0.4 s
    /// apart pixel-identical, at most 6 s), attaches it as `<prefix>-screen` (PNG), and, from one
    /// `app.snapshot()`, `<prefix>-window` and `<prefix>-elements` (JSON). Returns that snapshot's
    /// `A11yScene` for the audit-position rule.
    @MainActor
    private func a11yAttachScreen(_ app: XCUIApplication, name prefix: String) -> A11yScene {
        a11yWaitUntilSettled(app)
        // MVP-2b gate-2 round 2 (item 3): the same screenshot, reused for `A11yScene`'s in-test
        // fade-band pixel measurement, so what is measured is exactly what was attached.
        let finalScreenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: finalScreenshot)
        shot.name = "\(prefix)-screen"
        shot.lifetime = .keepAlways
        add(shot)
        let scene = A11yScene(app, screenshot: finalScreenshot.image)
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

    /// Opens What-If and waits for it to finish presenting, at whichever height the system gives
    /// it first (the medium detent: `.presentationDetents([.medium, .large])`'s first member).
    @MainActor
    private func a11yReachWhatIfPresented(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachCourseDetail(extra: extra)
        let whatIf = element("courseDetail.whatIf", in: app)
        XCTAssertTrue(scrollUntilHittable(whatIf, in: app), "Hierarchy: \(app.debugDescription)")
        whatIf.tap()
        XCTAssertTrue(element("whatif.simulationLabel", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        let sheetBar = app.navigationBars["What-If"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        _ = eventually(timeout: 3, {
            let before = sheetBar.frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            return before == sheetBar.frame
        })
        return app
    }

    /// MVP-2b gate-2 round 2 (item 12): the medium height, the state every user opens the sheet
    /// in — no pull-up gesture, so the sheet stays at its initial detent.
    @MainActor
    func a11yReachWhatIfMedium(extra: [String] = []) -> XCUIApplication {
        a11yReachWhatIfPresented(extra: extra)
    }

    @MainActor
    func a11yReachWhatIf(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachWhatIfPresented(extra: extra)
        // MVP-2b: audited at its large height, fully presented (the Audit tour captures it the same
        // way). At the medium height the system draws the sheet at 0.96 scale (`ScoreStepper.
        // buttonSide`'s note; run 38350587735 read Reset as 64.65 x 34.57 pt there, 67.33 x 36 pt
        // pulled up), and the audit's text checks misfire on the scaled text: 4 textClipped and
        // 4 elementDetection at the medium height, light and dark alike, and none on the same
        // rows, chips and summary pulled up (`whatIf-light-std-large`, same run, every type).
        let sheetBar = app.navigationBars["What-If"]
        // Pulled up means the bar sits in the top quarter of the screen. Run 38357314250: a swipe
        // on the bar left the Dark sheet at its medium height; release gate 38381878113: at AX5 a
        // swipe on the bar and a slow drag from it both did. The Audit tour's own gesture,
        // `app.swipeUp()`, pulled the sheet up on all 8 of its AX5 captures (runs 38339844918 and
        // 38372167047), so it goes first, once the sheet has finished presenting; the other two
        // are fallbacks.
        let pulledUp = { sheetBar.frame.minY < app.frame.height / 4 }
        let gestures: [@MainActor () -> Void] = [
            { app.swipeUp() },
            { sheetBar.swipeUp() },
            {
                sheetBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
            },
        ]
        for gesture in gestures where !pulledUp() {
            gesture()
            _ = eventually(timeout: 3, { pulledUp() })
        }
        XCTAssertTrue(pulledUp(), "What-If did not reach its large height: \(sheetBar.frame)")
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

    /// MVP-2b gate-2 round 3 (verdict item 2, still pending from round-1 item 8): the agenda exactly
    /// as a student opens it, before any tap — the only state the Audit tour has ever captured here
    /// (10 of 10 legs, round-2 verdict section 3), never this suite's own scope=a11y audit, which
    /// always tapped the first day first (`a11yReachCalendar`, below, kept as a second variant).
    @MainActor
    func a11yReachCalendarToday(extra: [String] = []) -> XCUIApplication {
        let app = launchSample(arguments: extra)
        openTab("Calendar", in: app)
        XCTAssertTrue(elements("calendar.day", in: app).firstMatch.waitForExistence(timeout: 15),
                      "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(elements("calendar.item", in: app).firstMatch.waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)")
        return app
    }

    @MainActor
    func a11yReachCalendar(extra: [String] = []) -> XCUIApplication {
        let app = a11yReachCalendarToday(extra: extra)
        let firstDay = elements("calendar.day", in: app).firstMatch
        // MVP-2b: audited at the agenda's first day too, as a student gets it by tapping the week's
        // first day in the strip. Calendar opens scrolled to today, the one list that does: the
        // agenda rows above today then sit hidden behind the SAMPLE DATA banner, the navigation bar
        // and the week strip (scope=a11y run 38370696712's snapshot: "Mon, Oct 12" at y = 87–127 and
        // "Nothing scheduled" at 128–180 pt; at AX5 "Nothing scheduled" at 23–170 and "Today · Tue,
        // Oct 13" at 187–332, under the strip). Here the audit's clipping check returned a "may be
        // clipped" it could not attach to any element: one to four per variant in all five scope=a11y
        // runs, and the only finding left in the last. Gate-2 round 3 (item 1): tapping the first day
        // used to leave its own heading under the strip too, a real defect, not this audit-position
        // artifact; MVP-2c fixed it (the strip is a safe-area bar and the heading a row,
        // `CalendarScreen.swift`), and `docs/pmo/a11y-waivers.md` tracks the current state. From AX1
        // up the strip scrolls, centred on today, so it is swiped back until the first day can be
        // tapped.
        let header = element("calendar.pinnedHeader", in: app)
        var swipes = 0
        while !firstDay.isHittable, swipes < 6 {
            header.swipeRight()
            swipes += 1
        }
        tapWhenHittable(firstDay, in: app)
        XCTAssertTrue(eventually(timeout: 5, { firstDay.isSelected }), "The first day was not selected: \(firstDay.debugDescription)")
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
/// **Narrowed, gate-2 round 2 (verdict items 1–7).** The PMO's gate-2 review measured 104 held
/// contrast issues on gate2's own screenshots and found the rule too broad in four ways, each
/// fixed below:
/// 1. The scroll-edge dimming image is translucent, not opaque chrome: it was treated as a bar
///    over its *whole* frame (60 pt of plain, at-rest content above the tab bar), so 43 of 104
///    held issues sat in clear view. It is no longer `chrome`; a `contrast` issue it only
///    intersects is held only when an in-test pixel measurement of its own frame, on the audit
///    screenshot, passes the threshold (`measureFadeBandContrast`) — the ratio is recorded in the
///    held reason.
/// 2. "Under system chrome" needed only `intersects`, with no minimum overlap (three issues held
///    for a 2.3 pt overlap). It now needs the frame's own height overlapped by at least a third.
/// 3. The pinned-bar case held the pinned bar's *own* content too (since 52c5876 the week strip's
///    day letters sit in a horizontal `ScrollView`, so they are "scrolling" by the same test this
///    rule uses) — contradicting the waivers doc's "a pinned element is never held". An element
///    structurally inside a `pinnedBars` subtree (`insidePinned`, set while walking the tree, not
///    by frame intersection) is never held by any reason.
/// 4. "Partly outside" checked all four edges, so a vertical list's real left/right clipping would
///    have been held as if it were the normal bottom-of-scroll case. It now checks only the
///    container's own scroll axis (`ScrollAxis`, inferred from the container's element kind and
///    aspect ratio: `.table`/`.collectionView` are vertical; a `.scrollView` wider than it is tall
///    is horizontal, matching the week strip, the only horizontal scroller in this app).
/// 5. `textClipped` could be held "under system chrome" or "under the screen's pinned bar", which
///    makes no sense for a clipping *prediction* (nothing was measured there); it is now held only
///    in the partly-outside case, the same one `contrast` and `textClipped` share.
/// 6. Top chrome (the navigation bar) no longer counts toward "under system chrome": an element
///    sitting under the navigation bar or the pinned header at the screen's resting position is
///    not a mid-scroll artifact, it is a real defect at rest (item 8's Calendar fix).
///
/// So the rule holds only what it must: a `contrast` or `textClipped` issue, on an element that
/// scrolls (it sits in a scroll view, table or collection view, and is not itself inside a pinned
/// subtree), which at the audit moment is not wholly in view along its own scroll axis; and, for
/// `contrast` only, one under a tab bar or toolbar by at least a third of its own height, under one
/// of the app's own opaque pinned bars, or in the translucent fade band with a passing in-test
/// measurement. Every other issue still fails, and so does anything wholly in view, inside a
/// pinned subtree, or under the navigation bar. A held issue is still attached, with its reason.
/// The rule's two other cases: an issue on the system keyboard's own elements, and a growing-type
/// issue (`dynamicType`/`textClipped`) with no element and no frame at all — the audit's own
/// list-rebuild artifact (paging, item 11, makes this common enough to need a rule, not a
/// scroll-position workaround); neither can be measured, reproduced or waived by identifier
/// (`heldReason`).
struct A11yScene {
    /// A scroll container's axis, inferred in `walk` from its element kind and aspect (this app's
    /// only horizontal scroller is Calendar's week strip; everything else is a vertical `List`,
    /// which XCUITest reports as `.table` or `.collectionView`).
    enum ScrollAxis {
        case vertical, horizontal
    }

    /// One piece of system chrome `walk` recorded, with the bar kind (item 6: the navigation bar
    /// never counts toward "under system chrome").
    enum ChromeKind: Equatable {
        case tabBar, navigationBar, toolbar
        var canHoldContrast: Bool { self != .navigationBar }
    }

    /// The image iOS 26 adds over content beside a bar (the scroll-edge dimming) — translucent,
    /// never counted as opaque chrome (item 1); see `measureFadeBandContrast`.
    static let dimmingOverlay = "AdditionalDimmingOverlay"
    /// The system keyboard's own container, as the snapshot names it.
    static let keyboardInputView = "inputView"
    /// The app's own pinned bars that scrolling content passes under (opaque, so text there is
    /// hidden by design): Calendar's week strip with its breadcrumb (`CalendarScreen.swift`).
    static let pinnedBars: Set<String> = ["calendar.pinnedHeader"]
    /// Calendar's own day heading (item 1, `CalendarScreen.swift`'s `calendar.dayHeading`). Item 3
    /// needs it to tell content genuinely scrolled past and under the strip from the selected
    /// day's own heading, or its rows, which must never be held that way.
    static let dayHeadingIdentifier = "calendar.dayHeading"
    /// The week strip's day buttons (`CalendarScreen.swift`), one of them selected.
    static let dayButtonIdentifier = "calendar.day"

    /// The app's window, in points.
    var window: CGRect = .zero
    /// For `<prefix>-elements`: every text, button, image, field, switch, cell, bar and identified
    /// container, with its frame, and the frame of the scroll view it scrolls in, if any.
    var elements: [[String: Any]] = []
    /// Opaque system chrome over the scrolling content: tab bars, navigation bars and toolbars
    /// (never the translucent scroll-edge dimming — item 1; `dimming` below).
    var chrome: [(frame: CGRect, kind: ChromeKind)] = []
    /// The scroll-edge dimming image's frame(s) (item 1): a `contrast` issue only intersecting one
    /// of these is held only on a passing in-test measurement (`measureFadeBandContrast`).
    var dimming: [CGRect] = []
    /// Every element inside a scroll view, table or collection view, with that container's frame
    /// and axis, and whether the element itself sits inside a pinned bar's own subtree (item 3).
    var scrolling: [(label: String, frame: CGRect, container: CGRect, axis: ScrollAxis, insidePinned: Bool)] = []
    /// The frames of `pinnedBars` on this screen.
    var pinned: [CGRect] = []
    /// The frames and labels of `dayHeadingIdentifier` on this screen (item 3).
    var dayHeadings: [(frame: CGRect, label: String)] = []
    /// MVP-2c: the day of the month of the strip's selected day, if the strip is on screen. The
    /// selected day's heading is the one with this day (`dayNumber(in:)`), never simply the topmost:
    /// the day before it stays in the hierarchy under the bars (run 38623450627).
    var selectedDayNumber: Int?
    /// The system keyboard, when it is up (Find School opens with its search field focused).
    var keyboards: [CGRect] = []

    /// A pixel buffer of the audit screenshot (RGBA8, one draw at init), for
    /// `measureFadeBandContrast`'s in-test measurement (item 3). Empty when no screenshot was
    /// given (`init()`, used only by tests of this type itself) or it could not be decoded.
    private var pixels: [UInt8] = []
    private var pixelWidth = 0
    private var pixelHeight = 0
    private var pixelScale: CGFloat = 1

    init() {}

    @MainActor
    init(_ app: XCUIApplication, screenshot: UIImage? = nil) {
        guard let root = try? app.snapshot() else { return }
        window = root.frame
        walk(root, container: nil, insidePinned: false)
        guard let screenshot, let cgImage = screenshot.cgImage, window.width > 0 else { return }
        pixelWidth = cgImage.width
        pixelHeight = cgImage.height
        pixelScale = CGFloat(pixelWidth) / window.width
        // CoreGraphics allocates and owns this buffer (`data: nil`); `context.data` stays valid for
        // the context's own lifetime, so it is copied out rather than handed a pointer that would
        // outlive the scope that produced it.
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        pixels = Array(UnsafeRawBufferPointer(start: data, count: pixelWidth * pixelHeight * 4))
    }

    @MainActor
    private mutating func walk(_ node: XCUIElementSnapshot, container: (frame: CGRect, axis: ScrollAxis)?, insidePinned: Bool) {
        // Fields into locals first: `&&`/`||` autoclosures capturing the non-Sendable snapshot fail
        // the Release test build (`AuditTourUITests.analyzeLayout`'s own note, run 37704108738).
        let kind = node.elementType
        let frame = Self.finite(node.frame)
        let identifier = node.identifier
        let label = node.label
        let isSelected = node.isSelected
        let isOverlay = kind == .image && identifier == Self.dimmingOverlay
        if isOverlay {
            dimming.append(frame)
        } else if kind == .tabBar {
            chrome.append((frame: frame, kind: .tabBar))
        } else if kind == .navigationBar {
            chrome.append((frame: frame, kind: .navigationBar))
        } else if kind == .toolbar {
            chrome.append((frame: frame, kind: .toolbar))
        }
        // Item 3 (gate-2 round 2): true for this node and every descendant once a `pinnedBars`
        // identifier is seen, not only when a frame happens to intersect it — the pinned bar's own
        // content (the week strip's day letters, in a `ScrollView` since 52c5876) is never held.
        let nowInsidePinned = insidePinned || Self.pinnedBars.contains(identifier)
        if Self.pinnedBars.contains(identifier) {
            pinned.append(frame)
        }
        if identifier == Self.dayHeadingIdentifier {
            dayHeadings.append((frame: frame, label: label))
        }
        if identifier == Self.dayButtonIdentifier, isSelected {
            selectedDayNumber = Self.dayNumber(in: label)
        }
        // Run 38363059477: the snapshot showed the keyboard as an "Other" element, `inputView` (402 x
        // 335 pt, holding the predictive bar and the keys), not as a keyboard element.
        if kind == .keyboard || identifier == Self.keyboardInputView {
            keyboards.append(frame)
        }
        if let container {
            scrolling.append((label: label, frame: frame, container: container.frame, axis: container.axis,
                             insidePinned: nowInsidePinned))
        }
        let recorded: Set<XCUIElement.ElementType> = [.staticText, .button, .image, .tabBar, .navigationBar, .toolbar,
                                                      .link, .textField, .switch, .cell, .other]
        let visible = frame.width > 0 && frame.height > 0
        if visible && recorded.contains(kind) && (kind != .other || !identifier.isEmpty) {
            elements.append(["elementType": Int(kind.rawValue), "identifier": identifier, "label": label,
                             "frame": Self.json(frame), "inScrollView": container != nil,
                             "scrollView": Self.json(container?.frame ?? .zero)])
        }
        let next: (frame: CGRect, axis: ScrollAxis)?
        switch kind {
        case .table, .collectionView:
            next = (frame: frame, axis: .vertical)
        case .scrollView:
            // Item 4 (gate-2 round 2): this app's one horizontal scroller, the week strip, is wide
            // and short; every other scroller (a `List`'s own backing, where it reports as
            // `.scrollView` rather than `.table`) is the usual tall, narrow shape.
            next = (frame: frame, axis: frame.width > frame.height ? .horizontal : .vertical)
        default:
            next = container
        }
        for child in node.children {
            walk(child, container: next, insidePinned: nowInsidePinned)
        }
    }

    /// The audit-position rule (this type's doc comment): the reason an issue is held, or `nil`.
    ///
    /// One more case, of any audit type: an element wholly inside the system keyboard is the
    /// keyboard's own (run 38357314250: Find School, Dark, three empty `TUIPredictionViewCell`s of
    /// the predictive bar, "missing useful accessibility information"), not the app's.
    func heldReason(auditType: String, label: String, elementIdentifier: String, frame rawFrame: CGRect,
                    variant: String) -> String? {
        let frame = Self.finite(rawFrame)
        guard frame.width > 0, frame.height > 0 else {
            // Item 11 (gate-2 round 2): paging to audit rows below the fold scrolls a `List`
            // right before `dynamicType`/`textClipped` grow its text to predict larger sizes
            // (`a11yPasses`); this file's own doc comments already record the same list-rebuild
            // artifact at rest (run 38338079168's `.all` audit, run 38350587735's Calendar).
            // With no element and no frame there is nothing to measure, reproduce or waive by
            // identifier — the audit's own instability, not a finding about the app.
            //
            // Item 5 (gate-2 round 3): narrowed. Allowed only in a `-paged` variant (`auditScreen`'s
            // own paging, item 6 — a plain first-pass audit never rebuilds mid-measurement the way
            // paging does), and only with an empty element identifier too (not only an empty
            // label — `heldReason`'s caller, `runA11yAudit`, caps this at 3 per pass and confirms
            // it with one retry after the list settles; this function only recognises the shape).
            if elementIdentifier.isEmpty, label.isEmpty, variant.contains("-paged"),
               auditType == "dynamicType" || auditType == "textClipped" {
                return "no element (the audit's own list-rebuild artifact, -paged only)"
            }
            return nil
        }
        if keyboards.contains(where: { $0.insetBy(dx: -0.5, dy: -0.5).contains(frame) }) {
            return "on the system keyboard"
        }
        guard auditType == "contrast" || auditType == "textClipped" else { return nil }
        guard let node = scrolling.first(where: { $0.label == label && Self.same($0.frame, frame) }) else { return nil }
        // Item 3: never hold anything structurally inside a pinned bar's own subtree.
        if node.insidePinned { return nil }
        let inView = node.container.intersection(window).insetBy(dx: -0.5, dy: -0.5)
        if Self.isPartlyOutside(frame, inView, axis: node.axis) {
            return "partly outside its scroll view or the window"
        }
        // Item 5: textClipped is held only in the partly-outside case above, never for chrome or a
        // pinned bar (occlusion does not explain a clipping prediction).
        guard auditType == "contrast" else { return nil }
        if chrome.contains(where: { $0.kind.canHoldContrast && Self.overlapsByAtLeastAThird($0.frame, frame) }) {
            return "under system chrome"
        }
        // Item 3 (gate-2 round 3): narrowed to >= 1/3 overlap (like the chrome case above), and
        // only for an element that ENDS ABOVE the selected day's own heading — content genuinely
        // scrolled past and now under the strip. The heading itself, and its own rows (which start
        // at or after the heading, never above it), can never satisfy `frame.maxY <= heading.minY`,
        // so they can never be held this way again (gate-2 round 2 verdict section 2.3: the rule's
        // only 2 holds were the selected day's own heading, a real at-rest defect). MVP-2c: the
        // selected day's heading by its day number, not the topmost heading (that is the day before,
        // under the bars); with no selected day or no such heading on screen, nothing is held here.
        if pinned.contains(where: { Self.overlapsByAtLeastAThird($0, frame) }),
           let selected = selectedDayNumber,
           let heading = dayHeadings.first(where: { Self.dayNumber(in: $0.label) == selected })?.frame,
           frame.maxY <= heading.minY + 0.5 {
            return "under the screen's pinned bar"
        }
        if dimming.contains(where: { $0.intersects(frame) }), let measured = measureFadeBandContrast(frame: frame) {
            // Item 4: 4.5:1 always — the frame-height large-text exception is dropped (a two-line
            // caption is not 18 pt bold; `isLargeText` is gone).
            if measured >= 4.5 {
                return "in the fade band, measured \(String(format: "%.2f", measured)):1 on the audit screenshot (row median)"
            }
        }
        return nil
    }

    /// Item 2: at least a third of the issue's own frame height overlapped by the bar.
    static func overlapsByAtLeastAThird(_ bar: CGRect, _ frame: CGRect) -> Bool {
        let overlap = bar.intersection(frame)
        guard !overlap.isNull, frame.height > 0 else { return false }
        return overlap.height / frame.height >= 1.0 / 3.0
    }

    /// Item 4: outside the visible area along the container's own scroll axis only (a vertical
    /// list's left/right edges, or a horizontal strip's top/bottom edges, are never scroll clipping).
    static func isPartlyOutside(_ frame: CGRect, _ inView: CGRect, axis: ScrollAxis) -> Bool {
        switch axis {
        case .vertical: return frame.minY < inView.minY || frame.maxY > inView.maxY
        case .horizontal: return frame.minX < inView.minX || frame.maxX > inView.maxX
        }
    }

    /// Item 4 (gate-2 round 3, replacing the frame-height large-text exception — a two-line
    /// caption is not 18 pt bold, so `isLargeText` is gone): measures each pixel ROW of `frame`
    /// against that row's own modal (most common) colour, rather than one blob for the whole
    /// frame. The gate-2 round 2 false pass (HIST 210, `calendar-light-std`) came from exactly
    /// that whole-frame blob: a 15.7 pt crop straddling the tab bar's edge has no one dominant
    /// colour (a gradient has no mode), yet the old code still picked one and passed on it — its
    /// own modal colour covered only 16% of the frame. This rewrite:
    /// - Excludes any row inside an opaque `chrome` bar (the fade band is the translucent strip
    ///   above the bar, not the bar's own opaque rows).
    /// - Skips a ROW whose own modal colour covers under half of it — not reliable enough to
    ///   measure — rather than rejecting the whole frame: the scroll-edge dimming is itself a
    ///   vertical gradient by design, so a multi-row crop's rows legitimately differ from each
    ///   other (an earlier version of this gate compared the WHOLE crop's dominant colour, which
    ///   rejected exactly that normal row-to-row gradient variation and regressed 7 previously
    ///   held Dashboard rows, `FamilyUITests.testSwitcherPassesTheAccessibilityAudit`, CI run
    ///   38608671835). Row-by-row, each row's OWN pixels are still near-uniform even inside a
    ///   gradient; only a genuinely unreliable row (little majority colour at all, as HIST 210's
    ///   chrome-straddling frame had before the chrome-row exclusion above) is skipped.
    /// - Otherwise measures every remaining row (background = that row's modal colour; glyph core
    ///   = the most common colour among that row's pixels at least half as far, in contrast, from
    ///   the background as the row's farthest pixel — the same two-step `a11ylib.measure`
    ///   algorithm the evidence script uses, `pmo-audit/.build-audit/mvp2b/a11ylib.py`, applied
    ///   once per row instead of once for the frame) and returns the MEDIAN row ratio, which
    ///   `heldReason` now always compares against 4.5:1.
    ///
    /// WCAG 2.x relative luminance throughout. `nil` when there is no screenshot, the frame is off
    /// the image, or no row yields a measurable core (every row falls inside chrome, or every
    /// row's own colour is too mixed to trust).
    func measureFadeBandContrast(frame: CGRect) -> Double? {
        guard !pixels.isEmpty else { return nil }
        let x0 = max(0, Int((frame.minX * pixelScale).rounded()))
        let y0 = max(0, Int((frame.minY * pixelScale).rounded()))
        let x1 = min(pixelWidth, Int(((frame.minX + frame.width) * pixelScale).rounded()))
        let y1 = min(pixelHeight, Int(((frame.minY + frame.height) * pixelScale).rounded()))
        guard x1 > x0, y1 > y0 else { return nil }
        // Rows inside an opaque chrome bar (e.g. the false pass's frame straddling the tab bar's
        // top edge) are excluded from the per-row measurement below.
        let chromeRows: Set<Int> = Set(chrome.flatMap { bar -> [Int] in
            let barX0 = Int((bar.frame.minX * pixelScale).rounded())
            let barX1 = Int(((bar.frame.minX + bar.frame.width) * pixelScale).rounded())
            guard barX1 > x0, barX0 < x1 else { return [] }
            let barY0 = max(0, Int((bar.frame.minY * pixelScale).rounded()))
            let barY1 = min(pixelHeight, Int(((bar.frame.minY + bar.frame.height) * pixelScale).rounded()))
            return barY0 < barY1 ? Array(barY0..<barY1) : []
        })
        func luminance(_ key: UInt32) -> Double {
            func channel(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let r = channel(Double((key >> 16) & 0xFF) / 255)
            let g = channel(Double((key >> 8) & 0xFF) / 255)
            let b = channel(Double(key & 0xFF) / 255)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
            let la = luminance(a), lb = luminance(b)
            let hi = max(la, lb), lo = min(la, lb)
            return (hi + 0.05) / (lo + 0.05)
        }
        // MVP-2c: a colour's "share" of a row counts the pixels within `colourTolerance` of it on
        // every channel, not only its exact value. The scroll-edge fade is blurred, so one row's
        // background is a spread of near-identical values (#FBFCFC, #FCFCFD, #FCFDFD under "BIO 101",
        // run 38660677136) and no exact value reached half the row: the measurement skipped 25 of
        // that text's 29 rows and its median came from four, one an anti-aliased edge (3.56:1;
        // 5.40:1 on 29 rows, 5.52:1 by the round-2 reviewer's darkest-pixel method). Re-measuring
        // every fade-band issue of runs 38550012702 and 38660677136 this way changed one decision,
        // that "BIO 101"; HIST 210 Light (the round-2 false pass) still fails, at 4.18:1
        // (`pmo-audit/.build-audit/mvp2c/fadeband/`). Only a row's eight most common values are
        // tried as its centre, which gives the same decisions in a fraction of the time.
        func share(of key: UInt32, among counts: [UInt32: Int]) -> Int {
            counts.reduce(0) { sum, entry in Self.isNear(entry.key, key) ? sum + entry.value : sum }
        }
        func densest(_ counts: [UInt32: Int]) -> (key: UInt32, share: Int)? {
            let candidates = counts.sorted { $0.value > $1.value }.prefix(Self.centreCandidates)
            var best: (key: UInt32, share: Int, count: Int)?
            for candidate in candidates {
                let candidateShare = share(of: candidate.key, among: counts)
                if let current = best, (current.share, current.count) >= (candidateShare, candidate.value) { continue }
                best = (key: candidate.key, share: candidateShare, count: candidate.value)
            }
            return best.map { (key: $0.key, share: $0.share) }
        }
        var rowRatios: [Double] = []
        pixels.withUnsafeBufferPointer { buffer in
            for y in y0..<y1 where !chromeRows.contains(y) {
                var rowCounts: [UInt32: Int] = [:]
                let rowStart = y * pixelWidth * 4
                for x in x0..<x1 {
                    let offset = rowStart + x * 4
                    let key = UInt32(buffer[offset]) << 16 | UInt32(buffer[offset + 1]) << 8 | UInt32(buffer[offset + 2])
                    rowCounts[key, default: 0] += 1
                }
                let total = rowCounts.values.reduce(0, +)
                guard total > 0, let bg = densest(rowCounts) else { continue }
                // Item 4's row-level gate: skip a row with no reliable single background.
                guard Double(bg.share) / Double(total) >= 0.5 else { continue }
                let bgKey = bg.key
                let extreme = rowCounts.keys.map { contrastRatio($0, bgKey) }.max() ?? 1.0
                guard extreme >= 1.05 else { continue }
                let cut = 1 + (extreme - 1) * 0.5
                var core: [UInt32: Int] = [:]
                for (key, count) in rowCounts where contrastRatio(key, bgKey) >= cut { core[key] = count }
                guard let fg = densest(core)?.key else { continue }
                rowRatios.append(contrastRatio(fg, bgKey))
            }
        }
        guard !rowRatios.isEmpty else { return nil }
        rowRatios.sort()
        let mid = rowRatios.count / 2
        return rowRatios.count % 2 == 0 ? (rowRatios[mid - 1] + rowRatios[mid]) / 2 : rowRatios[mid]
    }

    /// MVP-2c: two colours (0xRRGGBB) within `colourTolerance` of each other on every channel, the
    /// scroll-edge blur's own spread (`measureFadeBandContrast`). 3 of 255 is far below any visible
    /// difference: it moves a contrast ratio by about 1%.
    static let colourTolerance: UInt32 = 3
    /// MVP-2c: how many of a row's most common values `measureFadeBandContrast` tries as its centre.
    static let centreCandidates = 8

    static func isNear(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
        for shift in [UInt32(16), 8, 0] {
            let a = (lhs >> shift) & 0xFF
            let b = (rhs >> shift) & 0xFF
            if (a > b ? a - b : b - a) > colourTolerance { return false }
        }
        return true
    }

    /// MVP-2c: the day of the month in a Calendar label, the first whole number from 1 to 31: the
    /// week strip's "Sunday, October 11, 3 items" and the agenda's "Sun, Oct 11" or "Today · Wed,
    /// Oct 14" all give 11 or 14. Seven consecutive days never share one, so it pairs the strip's
    /// selected day with that day's own heading. English labels (the UI tests' locale).
    static func dayNumber(in label: String) -> Int? {
        label.split(whereSeparator: { !$0.isNumber }).lazy.compactMap { Int($0) }.first { (1...31).contains($0) }
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
