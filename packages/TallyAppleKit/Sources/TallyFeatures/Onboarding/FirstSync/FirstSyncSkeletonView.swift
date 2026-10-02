import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// UX-WP-10: the first-sync skeleton (ux-ui.md §3.2 stage 5 / prototype
/// `heroSkeleton`). The real Dashboard hero card (with its ring, sparkline
/// and course rows) is a later work package — this view is the progressive
/// placeholder shell that precedes it, driven entirely by
/// `FirstSyncViewModel`.
///
/// Plan 06 step 9: a plain page pushed in the Welcome stack (never a `TabView`). It does not own
/// its model: `AppModel` does (`FirstSyncPage`), so a Retry can hand it a fresh one, and the root
/// switch on `.finished` releases it. The page's `.task` starts it.
struct FirstSyncSkeletonView: View {
    let viewModel: FirstSyncViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onRetry: () -> Void
    let onFinished: () -> Void
    /// perf-app-runtime.md §2.4: after a failure, "Choose a different school" ends and purges the
    /// half-made account.
    let onChooseDifferentSchool: () -> Void

    init(viewModel: FirstSyncViewModel, onRetry: @escaping () -> Void, onFinished: @escaping () -> Void,
         onChooseDifferentSchool: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onRetry = onRetry
        self.onFinished = onFinished
        self.onChooseDifferentSchool = onChooseDifferentSchool
    }

    var body: some View {
        VStack(spacing: TallySpacing.xl) {
            if let failure = viewModel.failure {
                failureState(failure)
            } else {
                heroPlaceholder
                progressSection
                if viewModel.showsSlowLoadNotice {
                    // "Large course loads can take a minute — you can keep exploring"
                    // (ux-ui.md §3.2 stage 5), not the stale breadcrumb: nothing is saved yet.
                    Text(L10n.Onboarding.FirstSync.slowLoadNotice())
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
            }
        }
        .padding(TallySpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TallyColor.bgCanvas)
        .animation(reduceMotion ? nil : .snappy, value: viewModel.showsSlowLoadNotice)
        .navigationBarBackButtonHidden(true)
        .task(id: ObjectIdentifier(viewModel)) { viewModel.start() }
        .onChange(of: viewModel.isFinished, initial: true) { _, isFinished in
            if isFinished { onFinished() }
        }
    }

    private var heroPlaceholder: some View {
        VStack(spacing: TallySpacing.lg) {
            Text(L10n.Onboarding.FirstSync.settingUpTally())
                .font(TallyTypography.sectionHeader)
                .foregroundStyle(TallyColor.textSecondary)

            HStack(spacing: TallySpacing.lg) {
                Circle()
                    .fill(TallyColor.separator)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: TallySpacing.sm) {
                    RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous)
                        .fill(TallyColor.separator)
                        .frame(height: 16)
                    RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous)
                        .fill(TallyColor.separator)
                        .frame(width: 120, height: 12)
                }
            }
            .redacted(reason: .placeholder)
            // "the hero is accessibilityElement(children: .combine) while it is busy"
            // (ux-ui.md §3.2 stage 5).
            .accessibilityElement(children: .combine)
            .accessibilityLabel(viewModel.statusText)
        }
    }

    private var progressSection: some View {
        VStack(spacing: TallySpacing.sm) {
            Text(viewModel.statusText)
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textSecondary)
                .accessibilityHidden(true) // already carried by the hero's combined label above

            ProgressView(value: viewModel.progress)
                .tint(TallyColor.brandGold)
                .accessibilityLabel(String(localized: L10n.Onboarding.FirstSync.settingUpTally()))
                .accessibilityValue(String(localized: L10n.Onboarding.FirstSync.progressPercent(Int(viewModel.progress * 100))))
        }
    }

    private func failureState(_ failure: RefreshFailure) -> some View {
        ContentUnavailableView {
            Label(String(localized: L10n.Onboarding.FirstSync.failedTitle()), systemImage: "exclamationmark.triangle")
        } description: {
            Text(Self.message(for: failure))
        } actions: {
            Button(String(localized: L10n.Onboarding.retry()), action: onRetry)
                .buttonStyle(.tallyPrimary)
            Button(String(localized: L10n.Onboarding.chooseDifferentSchool()), action: onChooseDifferentSchool)
                .buttonStyle(.tallySecondary)
        }
    }

    private static func message(for failure: RefreshFailure) -> LocalizedStringResource {
        switch failure {
        case .offline:
            L10n.Onboarding.FirstSync.failureOffline()
        case .authExpired:
            L10n.Onboarding.FirstSync.failureAuthExpired()
        case .rateLimited, .server:
            L10n.Onboarding.FirstSync.failureServerSlow()
        // PAY-10's `.schoolDisabled` comes from a token refresh, which a first sync (a token issued
        // moments before) does not reach: the generic message covers it.
        case .contract, .unknown, .schoolDisabled:
            L10n.Onboarding.FirstSync.failureUnknown()
        }
    }
}
