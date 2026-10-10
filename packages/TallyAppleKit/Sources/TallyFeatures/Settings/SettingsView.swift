import StoreKit
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings
import UIKit

/// The copy Settings shows (ux-ui.md §3.7.7; app-store-compliance.md R10 for the disclaimer).
/// Plan 08 L10N-03a: every value now comes from the `TallyStrings` catalog through `L10n`; this
/// enum stays only so the call sites below read the same way they did before the sweep.
nonisolated enum SettingsCopy {
    static var signOutTitle: LocalizedStringResource { L10n.Settings.signOutTitle() }
    /// ux-ui.md §3.7.7, SEC §3, ASC R9.
    static var signOutConfirmation: LocalizedStringResource { L10n.Settings.signOutConfirmation() }
    /// PAY-11 (M3-B2): the confirmation's message, then that erasing does not cancel the subscription.
    /// M3-B3: a school-assigned seat has nothing to cancel on this Apple Account, so the note is left
    /// off for one.
    static func signOutMessage(isSchoolSeat: Bool) -> String {
        let base = String(localized: signOutConfirmation)
        guard !isSchoolSeat else { return base }
        return base + "\n\n" + String(localized: L10n.Subscription.eraseKeepsSubscription())
    }
    static var disclaimer: LocalizedStringResource { L10n.Account.disclaimer() }
    static var thresholdFooter: LocalizedStringResource { L10n.Settings.thresholdFooter() }
    /// M2-C2 OI5: the Standing widget's copy points here ("if you choose to show grades in widgets").
    static var widgetGradesTitle: LocalizedStringResource { L10n.Settings.widgetGradesTitle() }
    static var widgetGradesFooter: LocalizedStringResource { L10n.Settings.widgetGradesFooter() }
}

/// UX-WP-20: Settings as a `Form` (ux-ui.md §3.7.7), presented as one sheet from the tab roots.
///
/// - No dead rows: a row either navigates (and shows a chevron), acts, or states a fact (no
///   chevron). Microsoft 365 and Google are absent (SEC-D6, ASC-D6).
/// - "Sign Out & Erase" asks first, with the spec's copy, then calls `AppModel.signOut()`. Sample
///   mode has nothing to sign out of: it offers "Exit Sample Data" instead.
/// - "What changed": "All" or points, globally and per course, written to `UserState.digestThresholds`
///   (owner decision DG-1) through `HomeModel.userState`.
/// - Signed in only: App Lock over `AppModel.lock` (`AppLockSettingsModel`), and "Show Grades in
///   Widgets" (`UserState.showGradesInGlance`, M2-C2 OI5). Sample mode has no lock and no widgets.
///
/// The `AppModel` comes from the environment, where the composition root puts it; without one there
/// is nothing to sign out of here, so the account actions are left out rather than shown dead.
struct SettingsView: View {
    @Environment(HomeModel.self) private var home
    @Environment(AppModel.self) private var app: AppModel?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var settings: SettingsModel?
    @State private var lockSettings: AppLockSettingsModel?
    @State private var confirmsSignOut = false
    /// PAY-11: the confirmation's Manage Subscription (Apple's sheet).
    @State private var presentsManageSubscriptions = false
    @State private var showsSampleFeedNote = false
    @State private var backgroundRefresh = BackgroundRefreshState.unknown
    /// FAM-10 (M3-E2): opened from the switcher's "Add a student…", Settings shows its add-student
    /// sheet at once (parent mode only).
    private let opensAddStudent: Bool
    @State private var presentsAddStudent = false
    @State private var presentsInvite = false
    @State private var hasOpenedAddStudent = false
    /// FAM-10: a student's Family & Sharing, while one has a link service (sample mode today).
    @State private var familySharing: FamilySharingModel?

    init(opensAddStudent: Bool = false) {
        self.opensAddStudent = opensAddStudent
    }

    var body: some View {
        NavigationStack {
            Form {
                // FAM-10 (M3-E2): parent mode's Linked students, first (§7.3).
                if let family = app?.family {
                    LinkedStudentsSection(family: family, presentsAddStudent: $presentsAddStudent,
                                          onExploreStudentMode: studentModeAction)
                }
                accountSection
                // M3-C (UX-WP-12): the reminders permission and "Hide Course Names".
                RemindersSettingsSection(reminders: app?.reminders, isSampleData: home.isSampleData,
                                         settings: isSignedIn ? settings : nil)
                thresholdSection
                dataSection
                calendarSection
                privacySection
                // FAM-10 (M3-E2): a student's Family & Sharing (§7.2), additive; FAM-14's way in.
                if app?.family == nil, let familySharing {
                    FamilySharingSection(model: familySharing, presentsInvite: $presentsInvite,
                                         onExploreParentMode: parentModeAction)
                }
                aboutSection
            }
            // D01: content scrolled past the top stayed visible, blurred, under the inline title
            // and the status bar, even at rest.
            .tallyFormScreenChrome()
            // D07: every `LabeledContent` row value in this Form (plus the embedded Linked
            // students, Reminders and Family & Sharing sections) in `TallyColor.textSecondary`
            // instead of the system secondary grey.
            .labeledContentStyle(.tallySecondaryValue)
            .navigationTitle(Text(L10n.Settings.navigationTitle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Account.done())) { dismiss() }
                }
            }
            // D03 (AX5) round 2: a `.confirmationDialog` was an anchored popover that cut the
            // warning text and button labels mid-sentence at AX5; `.alert` fixed D22's wrong-button
            // arrow but Gate 2 found it still cut the message and pushed Cancel off-screen at rest
            // on the smallest iPhone at AX5 (its own internal scroll sizes to a fixed fraction of
            // the screen, not to the content). `tallyDestructiveConfirmation` keeps `.alert` below
            // the accessibility sizes and swaps to a full-screen sheet (Cancel pinned, always
            // visible at rest) at AX1 and up, from the same title/message/actions.
            .tallyDestructiveConfirmation(
                String(localized: SettingsCopy.signOutTitle), isPresented: $confirmsSignOut,
                message: SettingsCopy.signOutMessage(isSchoolSeat: isSchoolSeat), actions: signOutActions)
            .manageSubscriptionsSheet(isPresented: $presentsManageSubscriptions)
            .alert(String(localized: L10n.Calendar.subscribeAlertTitle()), isPresented: $showsSampleFeedNote) {
                Button(String(localized: L10n.Calendar.subscribeAlertOK()), role: .cancel) {}
            } message: {
                Text(L10n.Settings.calendarSampleNote())
            }
            .sheet(isPresented: $presentsAddStudent) {
                if let family = app?.family {
                    AddStudentSheet(family: family)
                }
            }
            .sheet(isPresented: $presentsInvite) {
                if let familySharing {
                    InviteSheet(model: familySharing)
                }
            }
        }
        .task {
            backgroundRefresh = BackgroundRefreshState(UIApplication.shared.backgroundRefreshStatus)
            if settings == nil {
                // M3-C: once "Hide Course Names" is saved, the pending reminders are rewritten.
                let reminders = app?.reminders
                let model = SettingsModel(userState: home.userState,
                                          notificationSettingsSaved: { reminders?.reconcileNow() })
                settings = model
                await model.load()
            }
            if lockSettings == nil, let app, case .signedIn = app.route {
                let lock = AppLockSettingsModel(lock: app.lock)
                lockSettings = lock
                await lock.load()
            }
            // FAM-10: the switcher's "Add a student…" (once per presentation).
            if opensAddStudent, !hasOpenedAddStudent, app?.family != nil {
                hasOpenedAddStudent = true
                presentsAddStudent = true
            }
            // FAM-10: only sample mode has a link service today (M3-E2 report, open items).
            if familySharing == nil, app?.family == nil, app?.route == .sample {
                let sharing = FamilySharingModel(link: SampleFamilyLinkService(), school: nil, host: nil)
                familySharing = sharing
                await sharing.load()
            }
        }
    }

    /// FAM-14: "Explore Parent Mode", in sample mode only.
    private var parentModeAction: (() -> Void)? {
        guard app?.route == .sample else { return nil }
        return { exploreParentMode() }
    }

    /// FAM-14: "Explore Student Mode", in the sample parent view only.
    private var studentModeAction: (() -> Void)? {
        guard app?.family?.isSample == true else { return nil }
        return { exploreStudentMode() }
    }

    /// FAM-14: sample mode's parent view, with the sample family (Settings closes first).
    private func exploreParentMode() {
        guard let app else { return }
        dismiss()
        Task { await app.enterSampleFamily() }
    }

    /// FAM-14: back from the sample parent view to the fictional student's own.
    private func exploreStudentMode() {
        dismiss()
        app?.exitSampleFamily()
    }

    /// A signed-in account's Settings (not sample mode, not a preview without an `AppModel`).
    private var isSignedIn: Bool {
        guard let app, case .signedIn = app.route else { return false }
        return true
    }

    /// M3-B3: `false` (today's purchase UI) without an `AppModel`, or before StoreKit has answered
    /// this launch.
    private var isSchoolSeat: Bool {
        app?.subscription.isSchoolSeat == true
    }

    /// D03 round 2: the Sign Out & Erase confirmation's buttons, shared between `.alert` (below
    /// the accessibility sizes) and the AX1+ sheet (`tallyDestructiveConfirmation`).
    private var signOutActions: [TallyConfirmationAction] {
        var actions = [
            TallyConfirmationAction(String(localized: L10n.Account.signOutAndErase()), role: .destructive) {
                dismiss()
                app?.signOut()
            },
        ]
        // PAY-11 (PRD §11.4): erasing does not cancel the subscription; cancelling is one tap away.
        // M3-B3: omitted for a school-assigned seat, which this Apple Account has nothing to cancel.
        if !isSchoolSeat {
            actions.append(TallyConfirmationAction(String(localized: L10n.Subscription.manage())) {
                presentsManageSubscriptions = true
            })
        }
        actions.append(TallyConfirmationAction(String(localized: L10n.Settings.cancel()), role: .cancel) {})
        return actions
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if home.isSampleData {
                LabeledContent(String(localized: L10n.Settings.sampleModeLabel()), value: String(localized: L10n.Settings.sampleModeValue()))
                Text(L10n.Settings.sampleModeCaption())
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                subscriptionRow
                if let app, app.route == .sample {
                    Button(String(localized: L10n.Settings.exitSampleData())) {
                        dismiss()
                        app.exitSample()
                    }
                    .accessibilityIdentifier("settings.exitSample")
                }
            } else {
                if !home.account.host.isEmpty {
                    LabeledContent(String(localized: L10n.Settings.schoolLabel()), value: home.account.host)
                }
                if let name = home.account.displayName {
                    LabeledContent(String(localized: L10n.Settings.signedInAsLabel()), value: name)
                }
                subscriptionRow
                if let app, case .signedIn = app.route {
                    Button(String(localized: L10n.Account.signOutAndErase()), role: .destructive) {
                        confirmsSignOut = true
                    }
                    .accessibilityIdentifier("settings.signOut")
                }
            }
        } header: {
            Text(L10n.Settings.accountHeader())
                .tallySectionText()
        }
    }

    /// PAY-08, PAY-09 (M3-B2): Settings → Subscription, in sample mode too (App Review buys there).
    @ViewBuilder
    private var subscriptionRow: some View {
        if let app {
            NavigationLink {
                SubscriptionSettingsView(appModel: app, school: home.dashboard.hero.school, onCheckMySchool: {
                    dismiss()
                    app.exitSample()
                })
            } label: {
                // M3-B3: holding, so a school seat reads "Provided by your school…" here too, not
                // just on the pushed Subscription page.
                LabeledContent(String(localized: L10n.Subscription.settingsTitle()),
                               value: SubscriptionStatusText.status(app.subscription.accountState, holding: app.subscription.holding,
                                                                    isPurchasePending: app.subscription.isPurchasePending))
            }
            .accessibilityIdentifier("settings.subscription")
        }
    }

    // MARK: - What changed (DG-1)

    @ViewBuilder
    private var thresholdSection: some View {
        if let settings {
            Section {
                Toggle(String(localized: L10n.Settings.showEveryGradeChange()), isOn: Binding(
                    get: { settings.thresholds.global == .all },
                    set: { settings.setEveryChange($0) }))
                    .accessibilityIdentifier("settings.everyChange")
                if let points = SettingsModel.points(of: settings.thresholds.global) {
                    Stepper(value: Binding(get: { points }, set: { settings.setGlobalPoints($0) }),
                            in: SettingsModel.pointRange, step: SettingsModel.pointStep) {
                        Text(L10n.Settings.atLeastPoints(ThresholdText.points(points)))
                    }
                    .accessibilityIdentifier("settings.points")
                }
                NavigationLink {
                    PerCourseThresholdsView(settings: settings, courses: home.courseCards)
                } label: {
                    LabeledContent(String(localized: L10n.Settings.perCourseLabel()),
                                   value: ThresholdText.overrides(settings.thresholds.perCourse.count))
                }
                .accessibilityIdentifier("settings.perCourse")
                if settings.saveFailed {
                    Label(String(localized: L10n.Settings.settingSaveFailed()), systemImage: "exclamationmark.triangle")
                        .font(TallyTypography.footnote)
                }
            } header: {
                Text(L10n.Settings.whatChangedHeader())
                    .tallySectionText()
            } footer: {
                Text(SettingsCopy.thresholdFooter)
                    .tallySectionText()
            }
        }
    }

    // MARK: - Data & Refresh

    private var dataSection: some View {
        Section {
            TimelineView(.everyMinute) { context in
                LabeledContent(String(localized: L10n.Settings.lastRefreshedLabel()),
                               value: FreshnessPresenter.present(home.freshness, now: context.date).shortText)
            }
            Button(String(localized: L10n.Settings.refreshNow())) { home.requestRefresh() }
                .accessibilityIdentifier("settings.refresh")
            LabeledContent(String(localized: L10n.Settings.backgroundAppRefreshLabel()),
                           value: home.isSampleData ? String(localized: L10n.Settings.notUsedForSampleData()) : backgroundRefresh.text)
        } header: {
            Text(L10n.Settings.dataAndRefreshHeader())
                .tallySectionText()
        }
    }

    // MARK: - Calendar (R6)

    @ViewBuilder
    private var calendarSection: some View {
        if home.account.subscribeURL != nil {
            Section {
                Button(String(localized: L10n.Settings.subscribeButton())) {
                    guard !home.isSampleData, let url = home.account.subscribeURL else {
                        showsSampleFeedNote = true
                        return
                    }
                    openURL(url)
                }
                .accessibilityIdentifier("settings.subscribe")
            } header: {
                Text(L10n.Calendar.tabTitle())
                    .tallySectionText()
            } footer: {
                Text(L10n.Settings.calendarFooter())
                    .tallySectionText()
            }
        }
    }

    // MARK: - Privacy & Security, About

    @ViewBuilder
    private var privacySection: some View {
        Section {
            if let lockSettings, lockSettings.hasLoaded {
                AppLockRows(model: lockSettings)
            }
            NavigationLink(String(localized: L10n.Settings.whatTallyStoresLabel())) {
                WhatTallyStoresView()
            }
            .accessibilityIdentifier("settings.whatTallyStores")
        } header: {
            Text(L10n.Settings.privacySecurityHeader())
                .tallySectionText()
        } footer: {
            if let lockSettings, lockSettings.hasLoaded {
                Text(lockSettings.footer)
                    .tallySectionText()
            }
        }
        if isSignedIn, let settings {
            Section {
                Toggle(String(localized: SettingsCopy.widgetGradesTitle), isOn: Binding(
                    get: { settings.showGradesInWidgets },
                    set: { settings.setShowGradesInWidgets($0) }))
                    .accessibilityIdentifier("settings.widgetGrades")
                if settings.widgetSaveFailed {
                    Label(String(localized: L10n.Settings.settingSaveFailed()), systemImage: "exclamationmark.triangle")
                        .font(TallyTypography.footnote)
                }
            } footer: {
                Text(SettingsCopy.widgetGradesFooter)
                    .tallySectionText()
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(String(localized: L10n.Settings.versionLabel()), value: AppVersion.text)
                .accessibilityIdentifier("settings.version")
        } header: {
            Text(L10n.Settings.aboutHeader())
                .tallySectionText()
        } footer: {
            Text(SettingsCopy.disclaimer)
                .tallySectionText()
        }
    }
}

/// App Lock (ux-ui.md §3.7.7; SEC-07): the toggle, which snaps back when the lock did not change
/// (`AppLockSettingsModel`), and, while it is on, how long Tally may stay in the background.
struct AppLockRows: View {
    let model: AppLockSettingsModel

    var body: some View {
        Toggle(model.title, isOn: Binding(get: { model.isOn }, set: { model.requestEnabled($0) }))
            .disabled(!model.isToggleEnabled)
            .accessibilityIdentifier("settings.appLock")
        if model.isOn {
            Picker(String(localized: L10n.Settings.requireUnlock()), selection: Binding(get: { model.gracePeriod }, set: { model.requestGracePeriod($0) })) {
                ForEach(AppLockPolicy.GracePeriod.allCases, id: \.self) { period in
                    Text(AppLockSettingsModel.label(for: period)).tag(period)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isChanging)
            .accessibilityIdentifier("settings.appLockGrace")
        }
    }
}

/// Per-course "What changed" thresholds: each course follows the global setting, or has its own.
/// A menu picker per course: a row that acts, so no chevron.
struct PerCourseThresholdsView: View {
    let settings: SettingsModel
    let courses: [CourseCard]

    var body: some View {
        Form {
            Section {
                ForEach(courses) { course in
                    Picker(selection: Binding(
                        get: { settings.thresholds.perCourse[course.id] },
                        set: { settings.setThreshold($0, for: course.id) })) {
                        Text(L10n.Settings.defaultThreshold(ThresholdText.describe(settings.thresholds.global)))
                            .tag(ScoreChangeThreshold?.none)
                        Text(L10n.Settings.everyChangeOption()).tag(ScoreChangeThreshold?.some(.all))
                        ForEach(SettingsModel.pointChoices, id: \.self) { points in
                            Text(L10n.Settings.atLeastPoints(ThresholdText.points(points))).tag(ScoreChangeThreshold?.some(.points(points)))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(course.code)
                            Text(course.name)
                                .font(TallyTypography.footnote)
                                .foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("settings.courseThreshold")
                }
            } footer: {
                Text(SettingsCopy.thresholdFooter)
                    .tallySectionText()
            }
        }
        // D01: content scrolled past the top stayed visible, blurred, under the inline title and
        // the status bar, even at rest.
        .tallyFormScreenChrome()
        .navigationTitle(Text(L10n.Settings.perCourseNavTitle()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "What Tally stores", in plain language (ux-ui.md §3.7.7). It states what the code does and makes
/// no claim beyond it.
struct WhatTallyStoresView: View {
    var body: some View {
        Form {
            Section {
                Text(L10n.Settings.storesNoAccount())
                Text(L10n.Settings.storesCanvasData())
                Text(L10n.Settings.storesKeychain())
                Text(L10n.Settings.storesLocalOnly())
                Text(L10n.Settings.storesSampleNeverSaved())
                Text(L10n.Settings.storesSignOutErase())
            }
            .font(TallyTypography.body)
        }
        // D01: content scrolled past the top stayed visible, blurred, under the inline title and
        // the status bar, even at rest.
        .tallyFormScreenChrome()
        .navigationTitle(Text(L10n.Settings.whatTallyStoresLabel()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Words for a threshold.
nonisolated enum ThresholdText {
    static func points(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return value == 1 ? String(localized: L10n.Settings.pointsOne()) : String(localized: L10n.Settings.pointsOther(number))
    }

    static func describe(_ threshold: ScoreChangeThreshold) -> String {
        switch threshold {
        case .all: String(localized: L10n.Settings.describeEveryChange())
        case .points(let value): String(localized: L10n.Settings.describeAtLeast(points(value)))
        }
    }

    static func overrides(_ count: Int) -> String {
        switch count {
        case 0: String(localized: L10n.Settings.overridesNone())
        default: String(localized: L10n.Settings.overridesCount(count))
        }
    }
}

/// "1.0 (1)", from the bundle.
nonisolated enum AppVersion {
    static var text: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// `UIApplication.backgroundRefreshStatus` in words.
enum BackgroundRefreshState {
    case unknown, available, denied, restricted

    init(_ status: UIBackgroundRefreshStatus) {
        switch status {
        case .available: self = .available
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unknown
        }
    }

    var text: String {
        switch self {
        case .unknown: String(localized: L10n.Settings.backgroundRefreshUnknown())
        case .available: String(localized: L10n.Settings.backgroundRefreshOn())
        case .denied: String(localized: L10n.Settings.backgroundRefreshOff())
        case .restricted: String(localized: L10n.Settings.backgroundRefreshRestricted())
        }
    }
}
