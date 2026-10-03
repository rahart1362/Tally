import AppIntents
import Foundation

extension MarkDoneIntent {
    /// The widget extension's half of `Shared/MarkDoneIntent.swift` (M3-D2). It does not run: the
    /// system performs a `LiveActivityIntent` in the app's process. If it ever ran here regardless,
    /// this process holds no account, no `UserState` and no vault key (encryption.md §3.3; the
    /// hygiene widget-isolation check), so there would be nothing safe to do — a no-op, exactly as
    /// `RefreshTallyIntent`'s widget half answers "Open Tally to refresh" instead of refreshing.
    func markDoneInThisProcess(itemID: String) async {}
}
