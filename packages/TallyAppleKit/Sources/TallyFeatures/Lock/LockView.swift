import SwiftUI
import TallyDesignSystem

/// SEC-07 / UX-WP-21 (ux-ui.md §3.7.8): the lock view. Opaque (`bg.canvas`, the launch colour), so
/// nothing of the Home shows through, and `RootView` does not build the Home under it at all.
///
/// - The T-mark (64 pt), "Tally is locked", and **Unlock with Face ID** (or Touch ID, Optic ID, or
///   the passcode), which auto-prompts once per lock. `.deviceOwnerAuthentication` falls back to
///   the device passcode by itself.
/// - A cancel leaves the student here with the button. **No error alert.**
/// - With no device passcode (`LAError.passcodeNotSet`) the lock can never open, so the view says
///   so and offers only **Sign Out & Erase** (security.md §3.3).
struct LockView: View {
    let lock: AppLockModel
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: TallySpacing.xl) {
            Spacer()
            TMark(size: 64)
            Text("Tally is locked")
                .font(TallyTypography.screenTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if lock.lastFailure == .passcodeNotSet {
                Text("Set a device passcode in Settings to unlock Tally, or sign out and erase Tally's data from this iPhone.")
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Sign Out & Erase", role: .destructive, action: onSignOut)
                    .buttonStyle(.tallySecondary)
                    .accessibilityIdentifier("lock.signOut")
            } else {
                Button(action: lock.requestUnlock) {
                    HStack(spacing: TallySpacing.sm) {
                        Image(systemName: symbol)
                        Text(title)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tallyPrimary)
                .disabled(lock.isAuthenticating)
                .accessibilityIdentifier("lock.unlock")
            }
            Spacer()
        }
        .padding(TallySpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TallyColor.bgCanvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lock.view")
        // Once per lock (the episode goes up each time the app locks).
        .task(id: lock.lockEpisode) { await lock.autoPromptIfNeeded() }
    }

    private var title: String {
        switch lock.availability {
        case .available(.faceID): "Unlock with Face ID"
        case .available(.touchID): "Unlock with Touch ID"
        case .available(.opticID): "Unlock with Optic ID"
        case .available(.noBiometry): "Unlock with Passcode"
        case .passcodeNotSet, .unavailable: "Unlock"
        }
    }

    private var symbol: String {
        switch lock.availability {
        case .available(.faceID): "faceid"
        case .available(.touchID): "touchid"
        case .available(.opticID): "opticid"
        case .available(.noBiometry), .passcodeNotSet, .unavailable: "lock.fill"
        }
    }
}
