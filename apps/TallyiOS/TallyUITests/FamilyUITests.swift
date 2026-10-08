import XCTest

/// M3-E2: family linking's screens over the bundled sample family (FAM-14's two fictional students
/// observed by one fictional parent). No mock server: the family-linking states come from sample
/// mode's own link service, steered by `-TallyTestHooks.familyOutcome` (DEBUG only).
///
/// - FAM-14: "Explore with Sample Data" reaches parent mode, the switcher and Linked students.
/// - FAM-09: a switch on any tab holds on all five; one student is a label, not a menu; the
///   switcher passes the accessibility audit at the default size and at AX5 (initials only there).
/// - FAM-10: one test per state family-linking.md §7.6 lists that sample mode can reach, and the
///   §7.7 confirmations.
final class FamilyUITests: TallyUITestCase {
    private static let outcomeHook = "-TallyTestHooks.familyOutcome"
    /// Wider than the initials circle and the chevron, narrower than any label with a name.
    private static let initialsOnlyMaxWidth: CGFloat = 80

    // MARK: FAM-14 + FAM-09

    @MainActor
    func testSampleReachesParentModeAndTheSwitcherHoldsAcrossAllFiveTabs() throws {
        let app = launchSample()
        enterParentMode(app)

        // Linked students: both fictional students, from Settings (FAM-14's App Review path).
        openSettings(app)
        XCTAssertTrue(text("Linked Students", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(app.buttons.matching(identifier: "family.student").count, 2, "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Skyler Sample'")).firstMatch.exists)
        tapWhenHittable(app.buttons["Done"], in: app)

        // Switch on the Calendar tab, then every tab shows Skyler, and Skyler's courses.
        openTab("Calendar", in: app)
        switchStudent(to: "Skyler Sample", in: app)
        assertViewing("Skyler", in: app)
        for tab in ["Courses", "To-Do", "Insights", "Dashboard", "Calendar"] {
            openTab(tab, in: app)
            assertViewing("Skyler", in: app, on: tab)
        }
        openTab("Courses", in: app)
        XCTAssertTrue(anyElement(containing: "World History", in: app).waitForExistence(timeout: 15),
                      "Skyler's course is missing. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(anyElement(containing: "Biology I", in: app).exists, "Rowan's course shows under Skyler")

        // Back to Rowan from Insights; the Dashboard follows.
        openTab("Insights", in: app)
        switchStudent(to: "Rowan Sample", in: app)
        openTab("Dashboard", in: app)
        assertViewing("Rowan", in: app, on: "Dashboard")
        // Every button has a label, except the toolbar Menu's own wrapper inside the switcher, which
        // SwiftUI builds and leaves unlabelled under the labelled switcher (CI runs 37065562136,
        // 37074800313); the switcher itself reads "Viewing Rowan".
        let unlabelled = app.buttons.matching(NSPredicate(format: "label == ''")).count
        let inSwitcher = visibleSwitcher(in: app).buttons.matching(NSPredicate(format: "label == ''")).count
        XCTAssertEqual(unlabelled - inSwitcher, 0, "Parent mode: unlabelled buttons. Hierarchy: \(app.debugDescription)")

        // FAM-14's way back: Explore Student Mode, then the flagship student's own Home.
        openSettings(app)
        let back = app.buttons["family.sample.viewAsStudent"]
        XCTAssertTrue(scrollUntilHittable(back, in: app), "Hierarchy: \(app.debugDescription)")
        back.tap()
        XCTAssertTrue(app.staticTexts["Average of 5 courses"].waitForExistence(timeout: 20), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(element("family.switcher", in: app).exists)
    }

    /// §7.8: the switcher passes Xcode's accessibility audit; only issues on the family's own
    /// elements count (the screens behind it have their own suites).
    @MainActor
    func testSwitcherPassesTheAccessibilityAudit() throws {
        let app = launchSample()
        enterParentMode(app)
        try app.performAccessibilityAudit { issue in
            !Self.isFamilyElement(issue.element)
        }
    }

    /// §7.1, §7.8: from AX1 up the label shows the initials only; the audit passes at AX5 too.
    @MainActor
    func testSwitcherAtAX5ShowsInitialsAndPassesTheAudit() throws {
        let app = launchApp(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tapWhenHittable(app.buttons["Explore with Sample Data"], in: app, timeout: 30)
        XCTAssertTrue(app.staticTexts["SAMPLE DATA"].waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        enterParentMode(app)
        let switcher = visibleSwitcher(in: app)
        XCTAssertEqual(switcher.label, "Viewing Rowan")
        // Initials (a 28-point circle) and the chevron only; with the first name it was 104 points
        // wide at the default size (CI run 37065562136).
        XCTAssertLessThan(switcher.frame.width, Self.initialsOnlyMaxWidth, "the first name shows at AX5: \(switcher.frame)")
        try app.performAccessibilityAudit { issue in
            !Self.isFamilyElement(issue.element)
        }
    }

    /// D17 (ux-fp1, AX5 regression): the switcher's `Menu` drew "Manage linked students…" over the
    /// Dashboard hero at AX5, because a `Menu` never reflows for Dynamic Type. At AX5 the switcher
    /// now opens a sheet instead: tapping it must show "Student" (the sheet's own nav title, never
    /// true of the `Menu`), both students as separate reachable rows, and the two actions, with no
    /// element drawn outside the sheet (CI run 37716470762 caught this failing to switch to the
    /// sheet at all: `StudentSwitcher`'s own `@Environment(\.dynamicTypeSize)` read the toolbar's
    /// clamped size, never true AX5 — fixed by passing the shell's own unclamped size in instead).
    @MainActor
    func testSwitcherAtAX5OpensASheetNotAMenu() throws {
        let app = launchApp(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tapWhenHittable(app.buttons["Explore with Sample Data"], in: app, timeout: 30)
        XCTAssertTrue(app.staticTexts["SAMPLE DATA"].waitForExistence(timeout: 15), "Hierarchy: \(app.debugDescription)")
        enterParentMode(app)
        let switcher = visibleSwitcher(in: app)
        // A plain tap + wait flaked on a loaded CI simulator (run 37734195394: the tap did not
        // take, "Student" never appeared within 10 s, retried-and-passed on CI's own retry). `tap(
        // _:expecting:)` re-taps once while the switcher is still hittable, the established fix for
        // exactly this (app-core report O9; `TallyUITestCase.swift`'s own doc comment).
        tap(switcher, expecting: app.navigationBars["Student"], in: app, timeout: 15)
        XCTAssertTrue(app.buttons["Rowan Sample"].waitForExistence(timeout: 5), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(scrollUntilHittable(app.buttons["Skyler Sample"], in: app), "Hierarchy: \(app.debugDescription)")
        let manage = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Manage linked'")).firstMatch
        XCTAssertTrue(scrollUntilHittable(manage, in: app), "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["Done"], in: app)
        XCTAssertTrue(eventually { !app.navigationBars["Student"].exists })
    }

    // MARK: FAM-10: §7.6 states

    /// §7.6 "Link removed", and FAM-09's one student: a label, not a menu.
    @MainActor
    func testLinkRemovedTellsTheParentAndOneStudentHasNoMenu() throws {
        let app = launchSample(arguments: [Self.outcomeHook, "linkRemoved"])
        openSettings(app)
        tapExploreParentMode(app)
        let alert = app.alerts["Link Removed"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label == %@", "You're no longer linked to Skyler in Canvas. Tally removed Skyler's saved data from this iPhone.")).firstMatch.exists,
                      "Hierarchy: \(app.debugDescription)")
        alert.buttons["OK"].tap()
        let switcher = visibleSwitcher(in: app)
        XCTAssertEqual(switcher.label, "Viewing Rowan")
        XCTAssertNotEqual(switcher.elementType, .button, "one student still offers a menu")
    }

    /// §7.6 "Parent, no students", reached the honest way: removing both students (with §7.7's
    /// Remove from Tally confirmation).
    @MainActor
    func testRemovingEveryStudentShowsTheParentEmptyState() throws {
        let app = launchSample()
        enterParentMode(app)
        openSettings(app)
        for name in ["Rowan", "Skyler"] {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "\(name) Sample")).firstMatch
            tapWhenHittable(row, in: app)
            tapWhenHittable(app.buttons["family.removeFromTally"], in: app)
            let title = "Remove \(name) from Tally?"
            XCTAssertTrue(staticText(title, in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
            XCTAssertTrue(staticText("\(name) stays linked to your Canvas account. Tally will delete \(name)'s saved data from this iPhone. You can add \(name) back from Linked students.", in: app).exists,
                          "Hierarchy: \(app.debugDescription)")
            tapConfirmation("Remove from Tally", in: app)
            XCTAssertTrue(text("Linked Students", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        }
        XCTAssertTrue(element("family.parentEmpty", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["family.addStudent"].exists)
        tapWhenHittable(app.buttons["Done"], in: app)
        XCTAssertTrue(app.buttons["family.emptyAdd"].waitForExistence(timeout: 10), "the tabs did not give way. Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(element("family.switcher", in: app).exists)
    }

    /// §7.7 "Unlink in Canvas": the confirmation's words; Cancel keeps the student.
    @MainActor
    func testUnlinkAsksWithTheSpecCopy() throws {
        let app = launchSample()
        enterParentMode(app)
        openSettings(app)
        tapWhenHittable(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Rowan Sample'")).firstMatch, in: app)
        let unlink = app.buttons["family.unlink"]
        XCTAssertTrue(scrollUntilHittable(unlink, in: app), "Hierarchy: \(app.debugDescription)")
        unlink.tap()
        XCTAssertTrue(staticText("Unlink Rowan?", in: app).waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(staticText("You'll stop seeing Rowan's courses and grades in Tally, the Canvas Parent app and Canvas on the web. To link again, Rowan will need to send you a new code. Tally will delete Rowan's saved data from this iPhone.", in: app).exists,
                      "Hierarchy: \(app.debugDescription)")
        // ux-fp1 D03/D22: this used to be a `.confirmationDialog`, shown as a popover with no Cancel
        // button on some layouts (tapping outside cancelled it instead) and an arrow that pointed at
        // the wrong button. It is now an `.alert`, always centred with its own Cancel button.
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' AND NOT (identifier BEGINSWITH 'family.')")).firstMatch
        tapWhenHittable(cancel, in: app)
        XCTAssertTrue(eventually { !self.staticText("Unlink Rowan?", in: app).exists }, "the dialog stayed. Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(unlink.waitForExistence(timeout: 10))
    }

    /// §7.6 "Code rejected": sample mode checks no code with a school, so every code is refused.
    @MainActor
    func testRejectedCodeOffersTryAgain() throws {
        let app = launchSample()
        enterParentMode(app)
        openSettings(app)
        tapWhenHittable(app.buttons["family.addStudent"], in: app)
        let field = app.textFields["family.codeField"]
        tapWhenHittable(field, in: app)
        field.typeText("x7Q2kp")
        tapWhenHittable(app.buttons["family.add"], in: app)
        XCTAssertTrue(anyElement(containing: "That code didn't work.", in: app).waitForExistence(timeout: 10),
                      "Hierarchy: \(app.debugDescription)")
        tapWhenHittable(app.buttons["family.tryAgain"], in: app)
        XCTAssertFalse(anyElement(containing: "That code didn't work.", in: app).exists)
    }

    /// §7.6 "Student, no observers".
    @MainActor
    func testStudentWithNoObservers() throws {
        let app = launchSample(arguments: [Self.outcomeHook, "noObservers"])
        openSettings(app)
        let empty = element("family.noObservers", in: app)
        XCTAssertTrue(scrollUntilHittable(empty, in: app), "Hierarchy: \(app.debugDescription)")
        XCTAssertEqual(empty.label, "No one is linked to your Canvas account.")
        XCTAssertTrue(app.buttons["family.invite"].exists)
    }

    /// §7.4: a student's invite shows the code, spelled for VoiceOver, with its warning; the
    /// persona's observer is listed (S1), and How to Remove explains the school path (§7.7).
    @MainActor
    func testStudentInviteShowsTheCode() throws {
        let app = launchSample()
        openSettings(app)
        let observer = app.buttons["family.observer"]
        XCTAssertTrue(scrollUntilHittable(observer, in: app), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(observer.label.contains("Dana Sample"))
        observer.tap()
        tapWhenHittable(app.buttons["family.howToRemove"], in: app)
        XCTAssertTrue(staticText("Only your school can remove an observer.", in: app).waitForExistence(timeout: 10))
        tapWhenHittable(app.buttons["family.howToRemoveDone"], in: app)
        tapWhenHittable(app.navigationBars["Dana Sample"].buttons.element(boundBy: 0), in: app)

        let invite = app.buttons["family.invite"]
        XCTAssertTrue(scrollUntilHittable(invite, in: app), "Hierarchy: \(app.debugDescription)")
        invite.tap()
        let create = app.buttons["family.createCode"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(scrollUntilHittable(create, in: app), "Hierarchy: \(app.debugDescription)")
        create.tap()
        let code = element("family.inviteCode", in: app)
        XCTAssertTrue(code.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertTrue(code.label.hasPrefix("Code: "), code.label)
        XCTAssertEqual(code.label.components(separatedBy: ", ").count, 6, code.label)
        // The warning is the section's footer, below the half-height sheet's fold.
        XCTAssertTrue(scrollUntilHittable(anyElement(containing: "Anyone who enters this code first will be linked to you.", in: app), in: app),
                      "Hierarchy: \(app.debugDescription)")
    }

    /// §7.6 "Invite refused": the school has no parent self-registration.
    @MainActor
    func testInviteRefused() throws {
        let app = launchSample(arguments: [Self.outcomeHook, "inviteRefused"])
        createInvite(app)
        XCTAssertTrue(anyElement(containing: "Your school hasn't turned on parent accounts in Canvas, so Tally can't create an invite.", in: app)
            .waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(element("family.inviteCode", in: app).exists)
    }

    /// §7.6 "Scope missing on Tally's key".
    @MainActor
    func testScopeMissing() throws {
        let app = launchSample(arguments: [Self.outcomeHook, "scopeMissing"])
        createInvite(app)
        XCTAssertTrue(anyElement(containing: "Your school's Tally setup doesn't include parent invites yet.", in: app)
            .waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)")
        XCTAssertFalse(element("family.inviteCode", in: app).exists)
    }

    // MARK: Steps

    @MainActor
    private func enterParentMode(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openSettings(app, file: file, line: line)
        tapExploreParentMode(app, file: file, line: line)
        assertViewing("Rowan", in: app, file: file, line: line)
    }

    @MainActor
    private func tapExploreParentMode(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let explore = app.buttons["family.sample.viewAsParent"]
        XCTAssertTrue(scrollUntilHittable(explore, in: app, maxSwipes: 30), "Hierarchy: \(app.debugDescription)", file: file, line: line)
        explore.tap()
    }

    @MainActor
    private func createInvite(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openSettings(app, file: file, line: line)
        let invite = app.buttons["family.invite"]
        XCTAssertTrue(scrollUntilHittable(invite, in: app), "Hierarchy: \(app.debugDescription)", file: file, line: line)
        invite.tap()
        let create = app.buttons["family.createCode"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Hierarchy: \(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(scrollUntilHittable(create, in: app), "Hierarchy: \(app.debugDescription)", file: file, line: line)
        create.tap()
    }

    /// The switcher in the visible navigation bar (a built tab that is not selected keeps its own).
    @MainActor
    private func visibleSwitcher(in app: XCUIApplication, timeout: TimeInterval = 20) -> XCUIElement {
        let all = elements("family.switcher", in: app)
        var found: XCUIElement?
        _ = eventually(timeout: timeout) {
            found = (0..<all.count).map { all.element(boundBy: $0) }.first { $0.exists && $0.isHittable }
            return found != nil
        }
        return found ?? all.firstMatch
    }

    @MainActor
    private func assertViewing(_ firstName: String, in app: XCUIApplication, on tab: String = "", file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertTrue(eventually(timeout: 20) { self.visibleSwitcher(in: app, timeout: 1).label == "Viewing \(firstName)" },
                      "\(tab): the switcher reads '\(visibleSwitcher(in: app, timeout: 1).label)'. Hierarchy: \(app.debugDescription)",
                      file: file, line: line)
    }

    @MainActor
    private func switchStudent(to name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        visibleSwitcher(in: app).tap()
        tapWhenHittable(app.buttons[name], in: app, file: file, line: line)
    }

    /// A confirmation dialog's button, however the system presents the dialog: the button with that
    /// label that is not one of the page's own (`family.*`), which may carry the same words.
    @MainActor
    private func tapConfirmation(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'family.')", label)).firstMatch
        tapWhenHittable(button, in: app, file: file, line: line)
    }

    /// A static text by its exact words (a subscript query is capped at 128 characters).
    @MainActor
    private func staticText(_ words: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", words)).firstMatch
    }

    @MainActor
    private func anyElement(containing words: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    @MainActor
    private static func isFamilyElement(_ element: XCUIElement?) -> Bool {
        guard let identifier = element?.identifier else { return false }
        return identifier.hasPrefix("family.")
    }
}
