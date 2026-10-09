import SwiftUI
import TallyDesignSystem
import TallyStrings
import UIKit

/// The reminders copy (ux-ui.md §3.2 stage 6, §3.7.7; insights-at-a-glance.md §3.3, §3.6). It
/// promises only what the Balanced preset does: there is no rules editor yet, so no "you choose the
/// rules". Plan 08 L10N-03a: every value comes from the `TallyStrings` catalog through `L10n`.
nonisolated enum RemindersViewCopy {
    static var tipTitle: LocalizedStringResource { L10n.Reminders.tipTitle() }
    static var tipBody: LocalizedStringResource { L10n.Reminders.tipBody() }
    static var turnOn: LocalizedStringResource { L10n.Reminders.turnOn() }
    static var notNow: LocalizedStringResource { L10n.Reminders.notNow() }
    static var sectionTitle: LocalizedStringResource { L10n.Reminders.sectionTitle() }
    static var denied: LocalizedStringResource { L10n.Reminders.denied() }
    static var openSettings: LocalizedStringResource { L10n.Reminders.openSettings() }
    static var sampleData: LocalizedStringResource { L10n.Reminders.sampleData() }
    static var hideCourseNames: LocalizedStringResource { L10n.Reminders.hideCourseNames() }
    static var footer: LocalizedStringResource { L10n.Reminders.footer() }
    static var hideCourseNamesFooter: LocalizedStringResource { L10n.Reminders.hideCourseNamesFooter() }
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
                .accessibilityLabel(String(localized: RemindersViewCopy.notNow))
                .accessibilityIdentifier("tip.dismissReminders")
            }
            Button(String(localized: RemindersViewCopy.turnOn)) {
                reminders.requestPermission()
            }
            .buttonStyle(.borderedProminent)
            // ux-fp6 D28: the system's white label on `accent` measured 2.08–2.15:1 in dark.
            .tint(TallyColor.accentFill)
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
                    LabeledContent(String(localized: RemindersViewCopy.sectionTitle), value: String(localized: L10n.Reminders.checking()))
                case .off:
                    LabeledContent(String(localized: RemindersViewCopy.sectionTitle), value: String(localized: L10n.Reminders.statusOff()))
                        .accessibilityIdentifier("settings.reminders.status")
                    Button(String(localized: RemindersViewCopy.turnOn)) { reminders.requestPermission() }
                        .disabled(reminders.isRequesting)
                        .accessibilityIdentifier("settings.reminders.turnOn")
                case .deniedInSettings:
                    Text(RemindersViewCopy.denied)
                        .accessibilityIdentifier("settings.reminders.denied")
                    Button(String(localized: RemindersViewCopy.openSettings)) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                    .accessibilityIdentifier("settings.reminders.openSettings")
                case .on:
                    LabeledContent(String(localized: RemindersViewCopy.sectionTitle), value: String(localized: L10n.Reminders.statusOn()))
                        .accessibilityIdentifier("settings.reminders.status")
                }
                if let settings, settings.hasLoaded {
                    Toggle(String(localized: RemindersViewCopy.hideCourseNames), isOn: Binding(
                        get: { settings.hideCourseNamesInNotifications },
                        set: { settings.setHideCourseNamesInNotifications($0) }))
                        .accessibilityIdentifier("settings.reminders.hideNames")
                    if settings.hideCourseNamesSaveFailed {
                        Label(String(localized: L10n.Settings.settingSaveFailed()), systemImage: "exclamationmark.triangle")
                            .font(TallyTypography.footnote)
                    }
                }
            } header: {
                Text(RemindersViewCopy.sectionTitle)
                    .tallySectionText()
            } footer: {
                if !isSampleData {
                    // Built outside the Text(...) call (not literal-concatenated inside it): the
                    // separator is two plain newlines, not user-facing words.
                    let combined = String(localized: RemindersViewCopy.footer) + "\n\n" + String(localized: RemindersViewCopy.hideCourseNamesFooter)
                    Text(combined)
                        .tallySectionText()
                }
            }
            .task(id: scenePhase) {
                if scenePhase == .active, !isSampleData { await reminders.refreshPermission() }
            }
        }
    }
}
