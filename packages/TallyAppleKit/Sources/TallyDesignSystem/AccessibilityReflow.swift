import SwiftUI

/// ux-fp2: the shared layout rules for the accessibility text sizes (AX1–AX5), one place for every
/// screen (audit run 37649050231, `review/defects.md`).
///
/// - **Rows reflow (D02, S1).** Two-column rows kept their trailing column at AX5, so the values in
///   it broke mid-token: "93.2/100" read "9 / 3.2/10 / 0", "MATH 122" read "MAT / H 122", "11:00 PM"
///   read "11:00 P / M", and the titles beside them hyphenated ("Project- / ed"). Below the
///   accessibility sizes a row is the `HStack` it always was; from AX1 up it is a leading-aligned
///   `VStack` (title, then meta, then value): `TallyReflowStack`, with `TallyReflowSpacer` and
///   `TallyReflowValueColumn` for the parts that only make sense side by side.
/// - **Values never break (D02).** A score, a course code or a time stays on one line
///   (`tallyReflowValue()`), shrinking (never below `valueMinimumScale`) only when even a whole line
///   is too narrow for it, and taking its full width before the text beside it.
/// - **Pinned chrome is capped (D04, D05).** A bar that stays on screen while the content scrolls
///   (the lapsed-subscription banner, Welcome's two entry actions, What-If's summary) is drawn at most
///   at `pinnedChromeMaximumSize`, so at AX5 it can no longer fill the screen and hide the content
///   it sits on: the same thing the system does for its own bars. The content itself keeps scaling.
/// - **Tall empty and error states scroll (D20).** `tallyCenteredScrolling()`.
public enum TallyReflow {
    /// The spacing between a reflowed row's parts at the accessibility sizes.
    public static let stackedSpacing: CGFloat = TallySpacing.xs

    /// How far a one-line value may shrink to stay on one line: 0.6 of an AX5 caption (43 pt) is
    /// still 26 pt, twice the default size.
    public static let valueMinimumScale: CGFloat = 0.6

    /// The largest Dynamic Type size pinned chrome is drawn at. At AX2 the lapsed-subscription banner
    /// takes about a quarter of the smallest iPhone's screen and Welcome's two actions under a third,
    /// against all of it and half of it at AX5 (D04, D05); its text is still twice the default size.
    public static let pinnedChromeMaximumSize: DynamicTypeSize = .accessibility2

    /// The fade above a bar pinned at the bottom of the screen (`TallyBottomBarFade`), in points at
    /// the default text size: about one line of `body`. Scale it with `@ScaledMetric(relativeTo:
    /// .body)`, so it stays about one line at every size (about 75 pt at AX5).
    public static let bottomBarFadeHeight: CGFloat = 24
}

/// D02: a row's two sides. Below the accessibility sizes, an `HStack` with the given alignment and
/// spacing; from AX1 up, a leading-aligned `VStack`, so the title takes the full width and the value
/// sits under it instead of being squeezed beside it.
public struct TallyReflowStack<Content: View>: View {
    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallyReflow.stackedSpacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}

/// D02: the `Spacer` between a row's sides, which only exists while they are side by side (in the
/// stacked layout it would add an empty gap under the title).
public struct TallyReflowSpacer: View {
    private let minLength: CGFloat?
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    public var body: some View {
        if !typeSize.isAccessibilitySize {
            Spacer(minLength: minLength)
        }
    }
}

/// D02: a row's trailing column (a chip over a score, say): trailing-aligned beside the title,
/// leading-aligned under it from AX1 up, so every line of the stacked row starts at the same edge.
public struct TallyReflowValueColumn<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: spacing) {
            content
        }
    }
}

extension View {
    /// D02: a value that must never break across lines (a score, a course code, a time): one line,
    /// shrunk to fit only when even a whole line is too narrow, and laid out before the text beside
    /// it, which wraps instead. Apply it to the value, or to the group (dot and code) that holds it.
    public func tallyReflowValue() -> some View {
        lineLimit(1)
            .minimumScaleFactor(TallyReflow.valueMinimumScale)
            .layoutPriority(1)
    }

    /// D04/D05: caps pinned chrome at `TallyReflow.pinnedChromeMaximumSize`. Apply it to the bar
    /// itself, never to the content that scrolls under it.
    public func tallyPinnedChromeTextSize() -> some View {
        dynamicTypeSize(...TallyReflow.pinnedChromeMaximumSize)
    }

    /// D20: content that is centred in the screen when it fits and scrolls when it does not (at AX5
    /// the first-sync failure page cut its second action off the bottom and its icon and title off
    /// the top). The content sits in a `ScrollView`, over a clear view as tall as the scroll view's
    /// visible area: the pair is as tall as the taller of the two, with the content centred in it.
    public func tallyCenteredScrolling() -> some View {
        ScrollView {
            ZStack {
                Color.clear
                    .containerRelativeFrame(.vertical)
                    .accessibilityHidden(true)
                self
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// D11 (S2): an icon and its words side by side, `TallySpacing.xs` apart. Inside a `List` row a
/// plain `Label` takes the list's icon column, which left an 18 pt gap between a status chip's icon
/// and its words (and between the Course Detail hero's "Needs attention" and its icon).
public struct TallyCompactLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TallySpacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == TallyCompactLabelStyle {
    /// D11: an icon and its words, `TallySpacing.xs` apart, wherever the label sits.
    public static var tallyCompact: TallyCompactLabelStyle { TallyCompactLabelStyle() }
}

/// D05: the soft edge between scrolling content and a bar pinned at the bottom of the screen. It is
/// drawn above the bar's top edge, over the content, so the last visible line fades into the canvas
/// instead of being sliced by the bar (the pattern ux-fp1's D03 confirmation sheet uses).
public struct TallyBottomBarFade: View {
    private let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    public var body: some View {
        LinearGradient(colors: [TallyColor.bgCanvas.opacity(0), TallyColor.bgCanvas], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .offset(y: -height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
