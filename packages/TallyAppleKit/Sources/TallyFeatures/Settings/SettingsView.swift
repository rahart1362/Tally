import SwiftUI
import TallyDesignSystem
import TallyDomain
import UIKit

/// The copy Settings shows (ux-ui.md §3.7.7; app-store-compliance.md R10 for the disclaimer).
nonisolated enum SettingsCopy {
    static let signOutTitle = "Sign out and erase?"
    /// ux-ui.md §3.7.7, SEC §3, ASC R9.
    static let signOutConfirmation =
        "Tally will delete your saved courses and grades from this iPhone. Canvas in Safari may stay signed in."
    static let disclaimer = "Tally is an independent app and is not affiliated with, endorsed by, "
        + "or sponsored by Instructure, Inc. Canvas is a trademark of Instructure, Inc."
    static let thresholdFooter = "A course's grade shows in \u{201C}What changed\u{201D} only when it moves at least "
        + "this much. Assignment grades always show."
    /// M2-C2 OI5: the Standing widget's copy points here ("if you choose to show grades in widgets").
    static let widgetGradesTitle = "Show Grades in Widgets"
    static let widgetGradesFooter = "The Standing widget shows your average grade band. It is hidden while your "
        + "iPhone is locked. A change reaches the widget the next time Tally starts and refreshes."
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
    @State private var showsSampleFeedNote = false
    @State private var backgroundRefresh = BackgroundRefreshState.unknown

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                thresholdSection
                dataSection
                calendarSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(SettingsCopy.signOutTitle, isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out & Erase", role: .destructive) {
                    dismiss()
                    app?.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SettingsCopy.signOutConfirmation)
            }
            .alert("Subscribing needs your school's Canvas", isPresented: $showsSampleFeedNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Sample data has no real calendar feed. Once you sign in, this adds your own Canvas calendar to the Calendar app.")
            }
        }
        .task {
            backgroundRefresh = BackgroundRefreshState(UIApplication.shared.backgroundRefreshStatus)
            if settings == nil {
                let model = SettingsModel(userState: home.userState)
                settings = model
                await model.load()
            }
            if lockSettings == nil, let app, case .signedIn = app.route {
                let lock = AppLockSettingsModel(lock: app.lock)
                lockSettings = lock
                await lock.load()
            }
        }
    }

    /// A signed-in account's Settings (not sample mode, not a preview without an `AppModel`).
    private var isSignedIn: Bool {
        guard let app, case .signedIn = app.route else { return false }
        return true
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if home.isSampleData {
                LabeledContent("Mode", value: "Sample data")
                Text("Everything here is fictional sample data. Nothing is saved on this iPhone.")
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                if let app, app.route == .sample {
                    Button("Exit Sample Data") {
                        dismiss()
                        app.exitSample()
                    }
                    .accessibilityIdentifier("settings.exitSample")
                }
            } else {
                if !home.account.host.isEmpty {
                    LabeledContent("School", value: home.account.host)
                }
                if let name = home.account.displayName {
                    LabeledContent("Signed in as", value: name)
                }
                if let app, case .signedIn = app.route {
                    Button("Sign Out & Erase", role: .destructive) {
                        confirmsSignOut = true
                    }
                    .accessibilityIdentifier("settings.signOut")
                }
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - What changed (DG-1)

    @ViewBuilder
    private var thresholdSection: some View {
        if let settings {
            Section {
                Toggle("Show every grade change", isOn: Binding(
                    get: { settings.thresholds.global == .all },
                    set: { settings.setEveryChange($0) }))
                    .accessibilityIdentifier("settings.everyChange")
                if let points = SettingsModel.points(of: settings.thresholds.global) {
                    Stepper(value: Binding(get: { points }, set: { settings.setGlobalPoints($0) }),
                            in: SettingsModel.pointRange, step: SettingsModel.pointStep) {
                        Text("At least \(ThresholdText.points(points))")
                    }
                    .accessibilityIdentifier("settings.points")
                }
                NavigationLink {
                    PerCourseThresholdsView(settings: settings, courses: home.courseCards)
                } label: {
                    LabeledContent("Per course", value: ThresholdText.overrides(settings.thresholds.perCourse.count))
                }
                .accessibilityIdentifier("settings.perCourse")
                if settings.saveFailed {
                    Label("This setting couldn't be saved.", systemImage: "exclamationmark.triangle")
                        .font(TallyTypography.footnote)
                }
            } header: {
                Text("What changed")
            } footer: {
                Text(SettingsCopy.thresholdFooter)
            }
        }
    }

    // MARK: - Data & Refresh

    private var dataSection: some View {
        Section {
            TimelineView(.everyMinute) { context in
                LabeledContent("Last refreshed",
                               value: FreshnessPresenter.present(home.freshness, now: context.date).shortText)
            }
            Button("Refresh Now") { home.requestRefresh() }
                .accessibilityIdentifier("settings.refresh")
            LabeledContent("Background App Refresh",
                           value: home.isSampleData ? "Not used for sample data" : backgroundRefresh.text)
        } header: {
            Text("Data & Refresh")
        }
    }

    // MARK: - Calendar (R6)

    @ViewBuilder
    private var calendarSection: some View {
        if home.account.subscribeURL != nil {
            Section {
                Button("Subscribe to Canvas Calendar") {
                    guard !home.isSampleData, let url = home.account.subscribeURL else {
                        showsSampleFeedNote = true
                        return
                    }
                    openURL(url)
                }
                .accessibilityIdentifier("settings.subscribe")
            } header: {
                Text("Calendar")
            } footer: {
                Text("Adds your own Canvas calendar to the Calendar app, where it stays up to date. "
                     + "To add one item, use Add to Calendar on it. Tally never asks for access to your calendars.")
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
            NavigationLink("What Tally Stores") {
                WhatTallyStoresView()
            }
            .accessibilityIdentifier("settings.whatTallyStores")
        } header: {
            Text("Privacy & Security")
        } footer: {
            if let lockSettings, lockSettings.hasLoaded {
                Text(lockSettings.footer)
            }
        }
        if isSignedIn, let settings {
            Section {
                Toggle(SettingsCopy.widgetGradesTitle, isOn: Binding(
                    get: { settings.showGradesInWidgets },
                    set: { settings.setShowGradesInWidgets($0) }))
                    .accessibilityIdentifier("settings.widgetGrades")
                if settings.widgetSaveFailed {
                    Label("This setting couldn't be saved.", systemImage: "exclamationmark.triangle")
                        .font(TallyTypography.footnote)
                }
            } footer: {
                Text(SettingsCopy.widgetGradesFooter)
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Microsoft 365", value: "Off")
            LabeledContent("Version", value: AppVersion.text)
                .accessibilityIdentifier("settings.version")
        } header: {
            Text("About")
        } footer: {
            Text(SettingsCopy.disclaimer)
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
            Picker("Require Unlock", selection: Binding(get: { model.gracePeriod }, set: { model.requestGracePeriod($0) })) {
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
                        Text("Default (\(ThresholdText.describe(settings.thresholds.global)))")
                            .tag(ScoreChangeThreshold?.none)
                        Text("Every change").tag(ScoreChangeThreshold?.some(.all))
                        ForEach(SettingsModel.pointChoices, id: \.self) { points in
                            Text("At least \(ThresholdText.points(points))").tag(ScoreChangeThreshold?.some(.points(points)))
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
            }
        }
        .navigationTitle("Per Course")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "What Tally stores", in plain language (ux-ui.md §3.7.7). It states what the code does and makes
/// no claim beyond it.
struct WhatTallyStoresView: View {
    var body: some View {
        Form {
            Section {
                Text("There is no Tally account and no Tally server. Tally talks only to your school's Canvas.")
                Text("After you sign in, Tally keeps your latest Canvas courses, grades, assignments and calendar on "
                     + "this iPhone, sealed with a key that stays on this iPhone. Each refresh replaces the copy before it.")
                Text("Your Canvas sign-in is kept in the iPhone's Keychain.")
                Text("Your settings, course order and To-Do marks stay on this iPhone and are not included in backups.")
                Text("Sample data is never saved.")
                Text("Sign Out & Erase deletes all of it from this iPhone.")
            }
            .font(TallyTypography.body)
        }
        .navigationTitle("What Tally Stores")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Words for a threshold.
nonisolated enum ThresholdText {
    static func points(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        return value == 1 ? "1 point" : "\(number) points"
    }

    static func describe(_ threshold: ScoreChangeThreshold) -> String {
        switch threshold {
        case .all: "every change"
        case .points(let value): "at least \(points(value))"
        }
    }

    static func overrides(_ count: Int) -> String {
        switch count {
        case 0: "None"
        case 1: "1 course"
        default: "\(count) courses"
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
        case .unknown: "Unknown"
        case .available: "On"
        case .denied: "Off"
        case .restricted: "Restricted"
        }
    }
}
