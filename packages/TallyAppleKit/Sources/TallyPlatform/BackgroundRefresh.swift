import BackgroundTasks
import Foundation
import TallyDomain
import TallyFeatures

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

/// PAY-07 (M3-B1; perf-app-runtime.md §2.4 B6): the background-refresh request, through
/// `BGTaskScheduler`. The subscription engine asks for it while the gate allows background refresh
/// (at launch, when the scene enters the background, after each background run) and withdraws it
/// on a lapse. Only one refresh request can be pending, and submitting replaces it (Apple,
/// VERIFIED in perf-app-runtime.md §8). The simulator does not run background tasks: `submit`
/// fails there, and nothing is scheduled.
public final class BackgroundRefreshScheduler: BackgroundRefreshScheduling, Sendable {
    private let identifier: String

    public init(identifier: String = BackgroundRefresh.taskIdentifier) {
        self.identifier = identifier
    }

    @concurrent
    public func schedule(earliestBegin: Date) async {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBegin
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Unavailable (the simulator, Background App Refresh off) or too many pending: iOS
            // decides; the next launch or background entry asks again.
        }
    }

    @concurrent
    public func cancel() async {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    @concurrent
    public func isScheduled() async -> Bool {
        await BGTaskScheduler.shared.pendingTaskRequests().contains { $0.identifier == identifier }
    }
}

/// Re-exported so platform adapters share TallyCore's one source of truth
/// for tunables (implementation brief: "TallyConfig for every constant")
/// instead of re-declaring their own budgets.
public enum TallyPlatformConfig {
    public static let backgroundBudget = TallyConfig.backgroundBudget
    public static let warmStartBudget = TallyConfig.warmStartBudget
}
