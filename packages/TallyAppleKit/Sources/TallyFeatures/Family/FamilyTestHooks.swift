#if DEBUG || TALLY_TEST_HOOKS
import Foundation

/// UI-test hook for the family screens (M3-E2, FAM-10): `-TallyTestHooks.familyOutcome <outcome>`
/// makes sample mode's link service answer one of family-linking.md §7.6's states
/// (`SampleFamilyOutcome`: `noObservers`, `inviteRefused`, `scopeMissing`, `linkRemoved`), so each
/// state has a UI test without a mock server.
///
/// Never in a shipping build: like `LaunchTestHooks`, this compiles only under `DEBUG` or
/// `TALLY_TEST_HOOKS`, and CI's Release gate fails if any shipping binary contains the
/// `TallyTestHooks.` argument prefix.
nonisolated enum FamilyTestHooks {
    static let key = "TallyTestHooks.familyOutcome"

    /// The outcome `arguments` ask for, or `nil` when they do not use the hook.
    static func outcome(arguments: [String] = ProcessInfo.processInfo.arguments) -> SampleFamilyOutcome? {
        guard let index = arguments.firstIndex(of: "-\(key)"), arguments.index(after: index) < arguments.endIndex else {
            return nil
        }
        return SampleFamilyOutcome(rawValue: arguments[arguments.index(after: index)])
    }
}
#endif

#if DEBUG || TALLY_TEST_HOOKS
extension FamilyModel {
    /// `linkRemoved`: the last sample student's link disappears as parent mode opens (§7.6).
    func applyScriptedOutcome(_ outcome: SampleFamilyOutcome? = FamilyTestHooks.outcome()) async {
        guard outcome == .linkRemoved, let last = students.last else { return }
        await linkDisappeared(last.id)
    }
}
#endif
