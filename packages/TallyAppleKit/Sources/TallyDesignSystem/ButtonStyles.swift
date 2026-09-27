import SwiftUI

/// The welcome screen's primary CTA (ux-ui.md §3.2 stage 2): Liquid Glass
/// where available, falling back to a solid tinted style otherwise so the
/// button still reads correctly on older SDKs.
public struct TallyPrimaryButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(configuration)
                    .buttonStyle(.glassProminent)
                    .tint(TallyColor.accent)
            } else {
                Button(configuration)
                    .buttonStyle(.borderedProminent)
                    .tint(TallyColor.accent)
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
