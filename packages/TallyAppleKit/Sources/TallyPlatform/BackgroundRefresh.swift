import Foundation
import TallyDomain

/// The identifier the composition root registers with
/// `.backgroundTask(.appRefresh(_:))` (architecture.md §3.1). It must equal
/// the single entry XcodeGen writes into `BGTaskSchedulerPermittedIdentifiers`
/// (`project.yml`: `$(PRODUCT_BUNDLE_IDENTIFIER).refresh`), computed here at
/// runtime from the same bundle identifier so the two can never drift apart.
public enum BackgroundRefresh {
    public static var taskIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") + ".refresh"
    }
}

/// Re-exported so platform adapters share TallyCore's one source of truth
/// for tunables (implementation brief: "TallyConfig for every constant")
/// instead of re-declaring their own budgets.
public enum TallyPlatformConfig {
    public static let backgroundBudget = TallyConfig.backgroundBudget
    public static let warmStartBudget = TallyConfig.warmStartBudget
}
