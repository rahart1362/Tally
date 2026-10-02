import AppIntents
import Foundation
import TallyGlance

extension RefreshTallyIntent {
    /// The widget extension's half of `Shared/TallyControlIntents.swift`. It does not run: the
    /// system performs a `LiveActivityIntent` in the app's process. If it ever ran here, this
    /// process could not refresh anyway (it holds no credential and reads the glance only), so it
    /// says to open Tally.
    func refreshInThisProcess() async -> LocalizedStringResource {
        RefreshAnswer.openTallyDialog()
    }
}
