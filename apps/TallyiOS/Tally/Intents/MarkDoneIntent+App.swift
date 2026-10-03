import AppIntents
import Foundation
import TallyIntents
import TallyStore

extension MarkDoneIntent {
    /// The app's half of `TallyWidgets/Shared/MarkDoneIntent.swift` (M3-D2): parses the glance's
    /// opaque planner ID ("assignment:123") back to a `CanvasID<Assignment>`
    /// (`GlancePlannerID.assignmentID`) and hands it to `MarkDoneIntentBridge`, registered at launch
    /// in the composition root (`TallyApp.swift`). An ID this build does not recognise — not an
    /// assignment, malformed, or the bridge not yet set (a preview or a test host) — is silently
    /// ignored, never a crash (m3d-report.md §6: "unknown or stale item IDs are ignored").
    func markDoneInThisProcess(itemID: String) async {
        guard let assignmentID = GlancePlannerID.assignmentID(itemID) else { return }
        _ = await MarkDoneIntentBridge.handler?(assignmentID, true)
    }
}
