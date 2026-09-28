import SwiftUI
import TallyDesignSystem

/// The Welcome stack's first-sync page (perf-app-runtime.md §2.4 S4): the skeleton over the model
/// `AppModel` owns for the sign-in in progress. On `.finished` it asks for the root switch (S8);
/// Retry gets a fresh model over the same, already provisioned coordinator; "Choose a Different
/// School" abandons the sign-in (the half-made account is purged) and returns to Welcome.
struct FirstSyncPage: View {
    let appModel: AppModel
    let onChooseDifferentSchool: () -> Void

    var body: some View {
        if let viewModel = appModel.firstSync {
            FirstSyncSkeletonView(
                viewModel: viewModel,
                onRetry: { appModel.retryFirstSync() },
                onFinished: { appModel.finishFirstSync() },
                onChooseDifferentSchool: {
                    appModel.abandonSignIn()
                    onChooseDifferentSchool()
                }
            )
        } else {
            // Only reachable for a frame while the root switch removes this stack.
            TallyColor.bgCanvas.ignoresSafeArea()
        }
    }
}
