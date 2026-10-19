import SwiftUI

/// The welcome screen's primary CTA (ux-ui.md §3.2 stage 2): Liquid Glass
/// where available, falling back to a solid tinted style otherwise so the
/// button still reads correctly on older SDKs.
///
/// ux-fp6 D28: `.glassProminent`/`.borderedProminent` draw a white label by default, and `accent`
/// flips to a light blue (#8DB4FF) in dark — white-on-light-blue measured 2.08–2.15:1 across every
/// screen that uses this style (Welcome, Paywall, App Lock, first-sync Retry, the sign-in
/// hand-off, SchoolNotEnabled, SchoolRevoked, GradeNotInCanvas). `accentFill` stays dark enough in
/// both appearances for the system's white label to clear 4.5:1 without touching the label itself.
public struct TallyPrimaryButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // UX1-01: call sites applied `.frame(maxWidth: .infinity)` to the already-styled button
        // from *outside* `Button(configuration)`, which only widens an invisible container
        // around the control — the system capsule still sizes to its label, so the primary and
        // secondary pills hugged their text at different widths (the same pattern D10 found on
        // "See Plans"). Giving the LABEL the flexible frame here, once, makes every call site's
        // pill fill its available width without each one repeating the fix.
        let flexibleLabel = configuration.label.frame(maxWidth: .infinity)
        Group {
            if #available(iOS 26.0, *) {
                Button(role: configuration.role, action: configuration.trigger) { flexibleLabel }
                    .buttonStyle(.glassProminent)
                    .buttonSizing(.flexible)
                    .tint(TallyColor.accentFill)
            } else {
                Button(role: configuration.role, action: configuration.trigger) { flexibleLabel }
                    .buttonStyle(.borderedProminent)
                    .tint(TallyColor.accentFill)
            }
        }
        .font(TallyTypography.cardTitle.weight(.semibold))
        .controlSize(.large)
    }
}

/// The welcome screen's secondary action.
public struct TallySecondaryButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // UX1-01: same flexible-label fix as `TallyPrimaryButtonStyle`, so the secondary pill
        // matches the primary pill's width at every call site (Welcome, hand-off, App Lock,
        // paywall, SchoolNotEnabled) instead of wrapping at the AX2 cap.
        let flexibleLabel = configuration.label.frame(maxWidth: .infinity)
        Group {
            if #available(iOS 26.0, *) {
                Button(role: configuration.role, action: configuration.trigger) { flexibleLabel }
                    .buttonStyle(.bordered)
                    .buttonSizing(.flexible)
                    .tint(TallyColor.accent)
            } else {
                Button(role: configuration.role, action: configuration.trigger) { flexibleLabel }
                    .buttonStyle(.bordered)
                    .tint(TallyColor.accent)
            }
        }
        .font(TallyTypography.cardTitle)
        .controlSize(.large)
    }
}

extension PrimitiveButtonStyle where Self == TallyPrimaryButtonStyle {
    public static var tallyPrimary: TallyPrimaryButtonStyle { TallyPrimaryButtonStyle() }
}

extension PrimitiveButtonStyle where Self == TallySecondaryButtonStyle {
    public static var tallySecondary: TallySecondaryButtonStyle { TallySecondaryButtonStyle() }
}
