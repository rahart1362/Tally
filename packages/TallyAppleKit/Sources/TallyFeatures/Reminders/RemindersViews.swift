import SwiftUI
import TallyDesignSystem
import UIKit

/// The reminders copy (ux-ui.md §3.2 stage 6, §3.7.7; insights-at-a-glance.md §3.3, §3.6). It
/// promises only what the Balanced preset does: there is no rules editor yet, so no "you choose the
/// rules".
nonisolated enum RemindersViewCopy {
    static let tipTitle = "Get reminded before work is due"
    static let tipBody = "Tally can remind you a day and an hour before each deadline."
    static let turnOn = "Turn On Reminders"
    static let notNow = "Not Now"
    static let sectionTitle = "Reminders"
    static let denied = "Notifications are off for Tally"
    static let openSettings = "Open Settings"
    static let sampleData = "Reminders aren't scheduled for sample data. Sign in with your school's Canvas to be "
        + "reminded before work is due."
    static let hideCourseNames = "Hide Course Names"
    static let footer = "A day and an hour before each due date, and an evening and a Sunday summary when work is due. "
        + "Nothing arrives between 11 PM and 7 AM: a reminder comes earlier instead. Reminders use the Canvas data "
        + "Tally last refreshed, and Tally tells you if it hasn't refreshed for a day."
    static let hideCourseNamesFooter = "With Hide Course Names on, notifications say \u{201C}a course\u{201D} and "
        + "\u{201C}An assignment\u{201D} instead of names. Grades are never shown in notifications."
}

/// UX-WP-12: the Dashboard's reminders tip, under "Needs attention", once there is work due. It
/// renders nothing unless `RemindersModel.showsTip` says so (never for sample data, never once the
/// permission was answered, not while dismissed). It reads the app model from the environment
/// (`RootView` puts it there); without one it renders nothing.
struct RemindersTip: View {
    let hasUpcomingDueItem: Bool
    let isSampleData: Bool
    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        if let reminders = app?.reminders,
           reminders.showsTip(isSampleData: isSampleData, hasUpcomingDueItem: hasUpcomingDueItem) {
            RemindersTipCard(reminders: reminders)
        }
    }
}

private struct RemindersTipCard: View {
    let reminders: RemindersModel

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            HStack(alignment: .top, spacing: TallySpacing.md) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(TallyColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: TallySpacing.xs) {
                    Text(RemindersViewCopy.tipTitle)
                        .font(TallyTypography.cardTitle)
                        .foregroundStyle(TallyColor.textPrimary)
                    Text(RemindersViewCopy.tipBody)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                }
                Spacer(minLength: 0)
                // A 44 × 44 pt target (HIG minimum), labelled for VoiceOver.
                Button {
                    reminders.dismissTip()
                } label: {
                    Image(systemName: "xmark")
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(RemindersViewCopy.notNow)
                .accessibilityIdentifier("tip.dismissReminders")
            }
            Button(RemindersViewCopy.turnOn) {}
            .buttonStyle(.borderedProminent)
            .tint(TallyColor.accent)
            .disabled(reminders.isRequesting)
            .accessibilityIdentifier("tip.enableReminders")
        }
        .padding(TallySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
        // A container, not one combined element: both buttons stay their own elements.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tip.reminders")
    }
}

/// UX-WP-12 / ux-ui.md §3.7.7: Settings' Reminders section. The permission is the switch: "Turn On
/// Reminders" while never asked; "Notifications are off for Tally" with Open Settings (the app's
/// notification settings) when denied; "On" when allowed. Sample data explains that nothing is
/// scheduled for it and never asks. A signed-in account also has "Hide Course Names" (PMO R10).
/// The permission is read again whenever the app becomes active: the student may have changed it
/// in iOS Settings.
struct RemindersSettingsSection: View {
    let reminders: RemindersModel?
    let isSampleData: Bool
    /// The signed-in account's settings, for "Hide Course Names"; `nil` in sample mode.
    let settings: SettingsModel?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let reminders {
            Section {
                switch reminders.status(isSampleData: isSampleData) {
                case .sampleData:
                    Text(RemindersViewCopy.sampleData)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                        .accessibilityIdentifier("settings.reminders.sample")
                case .checking:
                    LabeledContent(RemindersViewCopy.sectionTitle, value: "Checking\u{2026}")
                case .off:
                    LabeledContent(RemindersViewCopy.sectionTitle, value: "Off")
                        .accessibilityIdentifier("settings.reminders.status")
                    Button(RemindersViewCopy.turnOn) { reminders.requestPermission() }
                        .disabled(reminders.isRequesting)
                        .accessibilityIdentifier("settings.reminders.turnOn")
                case .deniedInSettings:
                    Text(RemindersViewCopy.denied)
                        .accessibilityIdentifier("settings.reminders.denied")
                    Button(RemindersViewCopy.openSettings) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .accessibilityIdentifier("settings.reminders.openSettings")
                case .on:
                    LabeledContent(RemindersViewCopy.sectionTitle, value: "On")
                        .accessibilityIdentifier("settings.reminders.status")
                }
                if let settings, settings.hasLoaded {
                    Toggle(RemindersViewCopy.hideCourseNames, isOn: Binding(
                        get: { settings.hideCourseNamesInNotifications },
                        set: { settings.setHideCourseNamesInNotifications($0) }))
                        .accessibilityIdentifier("settings.reminders.hideNames")
                    if settings.hideCourseNamesSaveFailed {
                        Label("This setting couldn't be saved.", systemImage: "exclamationmark.triangle")
                            .font(TallyTypography.footnote)
                    }
                }
            } header: {
                Text(RemindersViewCopy.sectionTitle)
            } footer: {
                if !isSampleData {
                    Text(RemindersViewCopy.footer + "\n\n" + RemindersViewCopy.hideCourseNamesFooter)
                }
            }
            .task(id: scenePhase) {
                if scenePhase == .active, !isSampleData { await reminders.refreshPermission() }
            }
        }
    }
}
