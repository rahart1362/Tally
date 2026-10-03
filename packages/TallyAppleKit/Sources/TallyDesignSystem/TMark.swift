import SwiftUI

/// The Tally brand mark: the owner's original emblem (the serif "T" under a mortarboard, with the
/// calendar, the grade card and the rising gold arc) on a white rounded tile, the same art as the
/// app icon (owner decision, 2026-10-03). It appears wherever the mark does: the welcome screen,
/// the lock screen, the sign-in hand-off, the paywall, the launch placeholder and the widget header.
///
/// The tile keeps the emblem's dark outlines legible on every background (light, dark and the navy
/// brand panel), as the emblem was drawn for a light ground. The art is a raster asset
/// (`brand.emblem`, 620 × 640 px), sharp at the largest size used here (96 pt at 3x).
public struct TMark: View {
    /// The tile's corner radius as a fraction of its side, close to the iOS app icon's mask.
    static let cornerRatio: CGFloat = 0.2237
    /// The emblem's inset on each side as a fraction of the tile's side: the emblem fills 86% of the
    /// tile, as on the app icon.
    static let insetRatio: CGFloat = 0.07

    private let size: CGFloat

    public init(size: CGFloat = 96) {
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
            .fill(Color.white)
            .overlay {
                Image("brand.emblem", bundle: .module)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * Self.insetRatio)
            }
            .frame(width: size, height: size)
            // Decorative; the views that place a TMark supply their own label
            // (e.g. "Tally" as a heading), so VoiceOver doesn't read this twice.
            .accessibilityHidden(true)
    }
}
