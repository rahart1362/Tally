import AppIntents
import SwiftUI
import TallyGlance
import WidgetKit

/// The WidgetKit extension (plan 06 step 11; perf-app-runtime.md §2.4 W1-W3; M3-D UX-WP-29): four
/// Home widgets, three Lock Screen accessories and two Control Center controls. Every widget reads
/// the glance only, through `TallyGlance`: `SnapshotStore(root: <App Group>, sealer: VaultSealer(…,
/// mayCreateKeys: false), isOwner: false).loadGlance()`, with the widget-audience key alone. They
/// never decode the snapshot, write, use the network, build a `RefreshCoordinator` or read a
/// credential, and this target links no `TallyFeatures` (CI: scripts/ci/check_widget_isolation.py).
/// Without a Team ID (GO-LIVE GL-02) the App Group Keychain group is unavailable (-34018 on the CI
/// simulator) and every widget shows its message text.
///
/// The controls' actions are app intents in `Shared/`, compiled into the app too: "Refresh Tally"
/// is a `LiveActivityIntent` and "Next Up" an `OpenIntent`, so the system performs both in the
/// app's process, never this one (Apple, "Adding interactivity to widgets and Live Activities").
///
/// Files: `Widget`, `WidgetBundle`, `WidgetConfiguration` and `ControlWidget` are SwiftUI types, so
/// every file of this target that names them imports SwiftUI. (M2 kept this target to one file
/// after runs 36328840843 and 36329218945 failed with "cannot find type 'Widget' in scope"; that
/// file imported only WidgetKit, which no longer declares those types.)
@main
struct TallyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TallyNextUpWidget()
        TallyDueSoonWidget()
        TallyWeekAheadWidget()
        TallyStandingWidget()
        TallyDueTodayWidget()
        TallyRefreshControl()
        TallyNextUpControl()
    }
}

/// The widgets' one configuration (FAM-11). No parameters today, so a widget needs no setup. M3-E2
/// adds an optional `StudentEntity` parameter here ("Last viewed" when unset) and maps it in
/// `glanceScope`: the kinds stay, and a placed widget's stored configuration decodes with the new
/// parameter unset, so nothing a student placed breaks.
struct GlanceWidgetIntent: WidgetConfigurationIntent, GlanceScoped {
    static let title = LocalizedStringResource("intent.widget.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.widget.description", table: "AppIntents"))

    init() {}

    var glanceScope: GlanceScope { .signedInStudent }
}

typealias GlanceProvider = GlanceIntentTimelineProvider<GlanceWidgetIntent>

/// "Next up" (insights-at-a-glance.md §1.5): Home small (StandBy too), and the Lock Screen's "Next
/// item" (rectangular) and "Next due line" (inline). No grades.
struct TallyNextUpWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceWidgetKind.nextUp, intent: GlanceWidgetIntent.self, provider: GlanceProvider()) { entry in
            NextUpFamilyView(entry: entry)
        }
        .configurationDisplayName(WidgetGalleryText.nextUpName)
        .description(WidgetGalleryText.nextUpDescription)
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

/// "Due soon": Home medium, the next three items. No grades. M3-D2: each row's trailing "Mark
/// Done" button is `MarkDoneButton` (`Shared/`), built here so `TallyGlance` never names
/// `MarkDoneIntent` itself (see `DueSoonWidgetView`'s doc).
struct TallyDueSoonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceWidgetKind.dueSoon, intent: GlanceWidgetIntent.self, provider: GlanceProvider()) { entry in
            DueSoonWidgetView(entry: entry) { itemID, accessibilityLabel in
                AnyView(MarkDoneButton(itemID: itemID, accessibilityLabel: accessibilityLabel))
            }
        }
        .configurationDisplayName(WidgetGalleryText.dueSoonName)
        .description(WidgetGalleryText.dueSoonDescription)
        .supportedFamilies([.systemMedium])
    }
}

/// "Week ahead": Home large, the seven-day strip and the next five items. No grades.
struct TallyWeekAheadWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceWidgetKind.weekAhead, intent: GlanceWidgetIntent.self, provider: GlanceProvider()) { entry in
            WeekAheadWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetGalleryText.weekAheadName)
        .description(WidgetGalleryText.weekAheadDescription)
        .supportedFamilies([.systemLarge])
    }
}

/// "Standing": the overall grade band (medium: per course too), only if the user chose to show
/// grades in widgets, and hidden while the iPhone is locked (PMO R10). Home only: no grade ever
/// reaches the Lock Screen.
struct TallyStandingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceWidgetKind.standing, intent: GlanceWidgetIntent.self, provider: GlanceProvider()) { entry in
            StandingFamilyView(entry: entry)
        }
        .configurationDisplayName(WidgetGalleryText.standingName)
        .description(WidgetGalleryText.standingDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// "Due today": the Lock Screen's circular gauge. No grades.
struct TallyDueTodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: GlanceWidgetKind.dueToday, intent: GlanceWidgetIntent.self, provider: GlanceProvider()) { entry in
            DueTodayAccessoryView(entry: entry)
        }
        .configurationDisplayName(WidgetGalleryText.dueTodayName)
        .description(WidgetGalleryText.dueTodayDescription)
        .supportedFamilies([.accessoryCircular])
    }
}

/// "Refresh Tally" in Control Center, on the Lock Screen and on the Action button (integrations.md
/// §2.5): fixed text and a symbol, never a title or a grade.
struct TallyRefreshControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: GlanceControlKind.refresh) {
            ControlWidgetButton(action: RefreshTallyIntent()) {
                Label {
                    Text(WidgetGalleryText.refreshControlName)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .displayName(WidgetGalleryText.refreshControlName)
        .description(WidgetGalleryText.refreshControlDescription)
    }
}

/// "Next Up": opens Tally (integrations.md §2.5).
struct TallyNextUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: GlanceControlKind.nextUp) {
            ControlWidgetButton(action: OpenTallyIntent(target: .nextUp)) {
                Label {
                    Text(WidgetGalleryText.nextUpControlName)
                } icon: {
                    Image(systemName: "checklist")
                }
            }
        }
        .displayName(WidgetGalleryText.nextUpControlName)
        .description(WidgetGalleryText.nextUpControlDescription)
    }
}

/// The widget and control galleries' names and descriptions (plan 08 §3.1, L10N-01): keys in this
/// extension's own `Localizable.xcstrings` (the galleries read them from the extension bundle,
/// `.main` here), with the English text as the fallback. Computed, so each resource takes the
/// locale current when it is read.
enum WidgetGalleryText {
    static var nextUpName: LocalizedStringResource {
        LocalizedStringResource(
            "widget.nextUp.displayName", defaultValue: "Next Up",
            comment: "Widget gallery: the name of the widget that shows the next assignment due."
        )
    }
    static var nextUpDescription: LocalizedStringResource {
        LocalizedStringResource(
            "widget.nextUp.description", defaultValue: "The next thing due in your courses.",
            comment: "Widget gallery: the description of the Next Up widget."
        )
    }
    static var dueSoonName: LocalizedStringResource {
        LocalizedStringResource(
            "widget.dueSoon.displayName", defaultValue: "Due Soon",
            comment: "Widget gallery: the name of the widget that lists the next three assignments due."
        )
    }
    static var dueSoonDescription: LocalizedStringResource {
        LocalizedStringResource(
            "widget.dueSoon.description", defaultValue: "Your next three assignments.",
            comment: "Widget gallery: the description of the Due Soon widget."
        )
    }
    static var weekAheadName: LocalizedStringResource {
        LocalizedStringResource(
            "widget.weekAhead.displayName", defaultValue: "Week Ahead",
            comment: "Widget gallery: the name of the widget that shows the next seven days."
        )
    }
    static var weekAheadDescription: LocalizedStringResource {
        LocalizedStringResource(
            "widget.weekAhead.description", defaultValue: "What's due each day this week, and what's next.",
            comment: "Widget gallery: the description of the Week Ahead widget."
        )
    }
    static var standingName: LocalizedStringResource {
        LocalizedStringResource(
            "widget.standing.displayName", defaultValue: "Standing",
            comment: "Widget gallery: the name of the widget that shows the student's average grade band."
        )
    }
    static var standingDescription: LocalizedStringResource {
        LocalizedStringResource(
            "widget.standing.description",
            defaultValue: "Your average grade band, if you choose to show grades in widgets. Hidden while your iPhone is locked.",
            comment: "Widget gallery: the description of the Standing widget. It shows a grade band only if the student turned that on in Tally's settings."
        )
    }
    static var dueTodayName: LocalizedStringResource {
        LocalizedStringResource(
            "widget.dueToday.displayName", defaultValue: "Due Today",
            comment: "Widget gallery: the name of the Lock Screen widget that counts the assignments due today."
        )
    }
    static var dueTodayDescription: LocalizedStringResource {
        LocalizedStringResource(
            "widget.dueToday.description", defaultValue: "How many assignments are still due today.",
            comment: "Widget gallery: the description of the Due Today Lock Screen widget."
        )
    }
    static var refreshControlName: LocalizedStringResource {
        LocalizedStringResource(
            "control.refresh.displayName", defaultValue: "Refresh Tally",
            comment: "Controls gallery and the control's label: refreshes Tally's saved Canvas data. Keep the brand name Tally."
        )
    }
    static var refreshControlDescription: LocalizedStringResource {
        LocalizedStringResource(
            "control.refresh.description", defaultValue: "Refreshes Tally's saved Canvas data.",
            comment: "Controls gallery: the description of the Refresh Tally control."
        )
    }
    static var nextUpControlName: LocalizedStringResource {
        LocalizedStringResource(
            "control.nextUp.displayName", defaultValue: "Next Up",
            comment: "Controls gallery and the control's label: opens Tally to what is due next."
        )
    }
    static var nextUpControlDescription: LocalizedStringResource {
        LocalizedStringResource(
            "control.nextUp.description", defaultValue: "Opens Tally to what's due next.",
            comment: "Controls gallery: the description of the Next Up control."
        )
    }
}
