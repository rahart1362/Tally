import AppIntents
import Foundation

/// "Mark Done" (M3-D2, m3d-report.md §6 option A): the "Due soon" row's trailing button. Conforms
/// to `LiveActivityIntent`, so the system always performs it in the app's process (§3 fact 1),
/// never the widget's: the widget's `Button(intent:)` carries only the opaque glance item ID
/// (`GlanceDueItem.id`, e.g. "assignment:123") and never writes a file or holds the vault key
/// (encryption.md §3.3; the hygiene widget-isolation check stays green). The app's half
/// (`MarkDoneIntent+App.swift`) parses that ID back to a `CanvasID<Assignment>` and writes the
/// mark; the widget's half (`MarkDoneIntent+Widget.swift`) never runs, as a safety net.
///
/// Buttons are inactive on a locked device (Apple's own behaviour — Tally does not work around
/// it). An unknown or stale ID (the glance is older than the latest commit, or the item was
/// already removed) is a no-op, never a crash. Not discoverable in Siri or Shortcuts: there is
/// nothing to say about one opaque ID, so `isDiscoverable` is `false`.
struct MarkDoneIntent: LiveActivityIntent {
    static let title = LocalizedStringResource("intent.markDone.title", table: "AppIntents")
    static let description = IntentDescription(LocalizedStringResource("intent.markDone.description", table: "AppIntents"))
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("intent.markDone.itemID", table: "AppIntents"))
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        await markDoneInThisProcess(itemID: itemID)
        return .result()
    }
}
