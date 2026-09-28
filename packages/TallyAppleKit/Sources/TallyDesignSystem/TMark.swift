import SwiftUI

/// The Tally brand mark: a serif "T" with a rising gold arc, drawn as vector
/// `Shape`s rather than a raster asset (ux-ui.md §3.8 spec; UX-06/UX-07 flag
/// the old raster emblem and wordmark as illegible below 60 pt and broken in
/// light mode). A code-drawn vector scales losslessly at any size, needs no
/// image-editing tool to author or update, and is exactly the same art used
/// wherever the mark appears (welcome screen, widget, lock screen).
public struct TMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 96) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            GoldArc()
                .stroke(
                    TallyColor.brandGold,
                    style: StrokeStyle(lineWidth: max(size * 0.055, 2), lineCap: .round)
                )
            SerifT()
                .fill(TallyColor.brandCream)
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        // Decorative; the views that place a TMark supply their own label
        // (e.g. "Tally" as a heading), so VoiceOver doesn't read this twice.
        .accessibilityHidden(true)
    }
}

/// A partial rising arc, matching the icon's "gold rising arc with
/// arrowhead" motif (ux-ui.md §3.8).
private struct GoldArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(150),
            endAngle: .degrees(-40),
            clockwise: true
        )
        return path
    }
}

/// A simple serif "T" glyph: a crossbar plus a stem, each capped with small
/// serif feet, built from straight line segments only.
private struct SerifT: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let stemWidth = w * 0.18
        let barHeight = h * 0.16
        let serif = w * 0.10

        var path = Path()

        // Crossbar, with serif feet at both ends.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + barHeight))
        path.addLine(to: CGPoint(x: rect.maxX - serif, y: rect.minY + barHeight))
        path.addLine(to: CGPoint(x: rect.midX + stemWidth / 2, y: rect.minY + barHeight))
        path.addLine(to: CGPoint(x: rect.midX + stemWidth / 2, y: rect.maxY - serif))
        path.addLine(to: CGPoint(x: rect.maxX - serif / 2, y: rect.maxY - serif))
        path.addLine(to: CGPoint(x: rect.maxX - serif / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + serif / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + serif / 2, y: rect.maxY - serif))
        path.addLine(to: CGPoint(x: rect.midX - stemWidth / 2, y: rect.maxY - serif))
        path.addLine(to: CGPoint(x: rect.midX - stemWidth / 2, y: rect.minY + barHeight))
        path.addLine(to: CGPoint(x: rect.minX + serif, y: rect.minY + barHeight))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + barHeight))
        path.closeSubpath()
        return path
    }
}

#Preview {
    TMark(size: 120)
        .padding(40)
        .background(TallyColor.bgBrand)
}
