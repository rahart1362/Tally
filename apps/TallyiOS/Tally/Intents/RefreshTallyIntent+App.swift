import AppIntents
import Foundation
import TallyDomain
import TallyGlance
import TallyIntents
import TallySync

extension RefreshTallyIntent {
    /// The app's half of `TallyWidgets/Shared/TallyControlIntents.swift`: one run through the
    /// signed-in account's one coordinator (`RefreshIntentBridge`, which `AppModel.attach` sets and
    /// `detach`/sign-out clear), then an honest answer from where it ended (`RefreshAnswer`). With no
    /// coordinator (signed out, sample data, or the app was launched only to run this before its
    /// account attached) nothing is fetched and the answer is "Open Tally to refresh".
    func refreshInThisProcess() async -> LocalizedStringResource {
        let state = await RefreshIntentBridge.coordinator?.run(trigger: .intent)
        return RefreshAnswer(state: state).dialog(now: Date(), calendar: .autoupdatingCurrent)
    }
}
