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
        Group {
            if #available(iOS 26.0, *) {
                Button(configuration)
                    .buttonStyle(.glassProminent)
                    .tint(TallyColor.accentFill)
            } else {
                Button(configuration)
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
        Button(configuration)
            .buttonStyle(.bordered)
            .tint(TallyColor.accent)
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
