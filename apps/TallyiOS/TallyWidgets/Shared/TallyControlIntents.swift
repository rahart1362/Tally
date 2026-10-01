import AppIntents
import Foundation

// The intents behind the Control Center controls (integrations.md §2.5). This directory is
// compiled into the app and into the widget extension, because a control's action must be in both
// ("Creating controls to perform actions across the system": "The system requires the Target
// Membership of the app intent to be set to both the app and the widget extension"). The system
// performs both intents in the app's process, never the widget's: "Refresh Tally" is a
// `LiveActivityIntent` and "Next Up" an `OpenIntent` ("Adding interactivity to widgets and Live
// Activities"). Each target supplies `refreshInThisProcess()`: the app's refreshes, the widget's
// only answers "Open Tally to refresh" (it never runs there, and the widget cannot refresh).
//
// Titles, descriptions and parameter names are build-time constants (App Intents metadata) in the
// `AppIntents` strings table next to this file, which both bundles carry.

/// "Refresh Tally": a Siri phrase, a Shortcuts action and the Control Center button.
struct RefreshTallyIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("intent.refresh.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.refresh.description", table: "AppIntents"))

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(await refreshInThisProcess()))
    }
}

/// Where the "Next Up" control opens Tally.
enum TallyDestination: String, AppEnum {
    case nextUp

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent.destination.type", table: "AppIntents"), numericFormat: nil)
    static let caseDisplayRepresentations: [TallyDestination: DisplayRepresentation] = [
        .nextUp: DisplayRepresentation(title: LocalizedStringResource("intent.destination.nextUp", table: "AppIntents"),
                                       subtitle: nil, image: nil),
    ]
}

/// "Next Up": opens Tally. The app has no in-app route for intents yet, so it opens where the student
/// left it (a cold launch shows the Dashboard, whose second module is Next up); a route to the
/// To-Do list sorted by priority is an open item for the app shell.
struct OpenTallyIntent: OpenIntent {
    static let title = LocalizedStringResource("intent.open.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.open.description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("intent.open.target", table: "AppIntents"))
    var target: TallyDestination

    init() {}

    init(target: TallyDestination) {
        self.target = target
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
