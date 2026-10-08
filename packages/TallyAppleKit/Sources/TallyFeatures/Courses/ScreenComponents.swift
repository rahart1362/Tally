import SwiftUI
import TallyDesignSystem

/// The categorical course palette and the status colours (ux-ui.md §3.5), with the review's
/// measured light, dark and Increase Contrast values. Colour is only ever a second signal: a course
/// colour sits next to the course code, a status colour next to an icon and words (§3.1 rule 4).
///
/// Defined here, not in `TallyDesignSystem`'s asset catalog, because that target is outside this
/// stream's lane (the M3-A report's deviations); it resolves from the environment's colour scheme
/// and contrast, so it needs no UIKit trait provider.
nonisolated enum ScreenPalette {
    nonisolated struct Swatch: Sendable {
        let light: UInt32
        let dark: UInt32
        let highLight: UInt32
        let highDark: UInt32
    }

    /// blue, teal, violet, orange, pink, green, amber, slate: each at least 3:1 on the card.
    static let courses: [Swatch] = [
        Swatch(light: 0x2563EB, dark: 0x6EA0FF, highLight: 0x1D4ED8, highDark: 0x9DC0FF),
        Swatch(light: 0x0F766E, dark: 0x2DD4BF, highLight: 0x0B5E58, highDark: 0x5EEAD4),
        Swatch(light: 0x7C3AED, dark: 0xB79CFF, highLight: 0x6D28D9, highDark: 0xCDB8FF),
        Swatch(light: 0xC2410C, dark: 0xFB9A5B, highLight: 0x9A3412, highDark: 0xFDBA8C),
        Swatch(light: 0xBE185D, dark: 0xF48FC0, highLight: 0x9D174D, highDark: 0xF9B4D6),
        Swatch(light: 0x15803D, dark: 0x5EDB8A, highLight: 0x166534, highDark: 0x86EFAC),
        Swatch(light: 0xA16207, dark: 0xF5C451, highLight: 0x854D0E, highDark: 0xFCD677),
        Swatch(light: 0x475569, dark: 0xA3B1C6, highLight: 0x334155, highDark: 0xCBD5E1),
    ]

    static let positive = Swatch(light: 0x0A7A4B, dark: 0x4ADE9A, highLight: 0x05603A, highDark: 0x7EEBB4)
    static let warning = Swatch(light: 0x9A5B00, dark: 0xFBBF4D, highLight: 0x7A4700, highDark: 0xFFD37A)
    static let danger = Swatch(light: 0xC4271E, dark: 0xFF8A80, highLight: 0xA01B14, highDark: 0xFFB0A8)
    static let neutral = Swatch(light: 0x475467, dark: 0xAEB8C8, highLight: 0x344054, highDark: 0xD3DAE5)

    static func course(_ index: Int) -> Swatch {
        courses[((index % courses.count) + courses.count) % courses.count]
    }

    static func color(_ swatch: Swatch, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        let high = contrast == .increased
        let value = scheme == .dark ? (high ? swatch.highDark : swatch.dark) : (high ? swatch.highLight : swatch.light)
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// A course's colour as a 4 pt bar or a 10 pt dot (ux-ui.md §3.5: colour only for the bar, the dot
/// and chart series, never for text). Decorative: VoiceOver reads the course code beside it.
struct CourseColorMark: View {
    enum Style { case bar, dot }

    let paletteIndex: Int
    var style: Style = .dot
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let color = ScreenPalette.color(ScreenPalette.course(paletteIndex), scheme: scheme, contrast: contrast)
        Group {
            switch style {
            case .bar:
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 4)
            case .dot:
                Circle().fill(color).frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An icon plus words on a tinted capsule (ux-ui.md §3.6 StatusChip): the icon's shape and the words
/// carry the meaning; the tint only reinforces it. The words are primary-text colour, so the chip
/// reads at full contrast whatever its tint.
///
/// Plan 08 §3.1/§5 (L10N-03a): this component takes `LocalizedStringResource` where it takes text.
/// The `String` initializer stays, additively, for callers not yet swept to `L10n.*` (Courses,
/// CourseDetail, Insights, ToDo: L10N-03b, later) — none of them pass a string literal, so there is
/// no literal at a call site that could be ambiguous between the two initializers.
struct StatusChip: View {
    enum Tone { case positive, warning, danger, neutral }

    let symbol: String
    private let label: Text
    var tone: Tone = .neutral
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(symbol: String, text: LocalizedStringResource, tone: Tone = .neutral) {
        self.symbol = symbol
        self.label = Text(text)
        self.tone = tone
    }

    /// Not yet localized at the call site (plan 08 L10N-03b sweeps `Courses/*`, `CourseDetail/*`,
    /// `Insights/*`, `ToDo/*`): kept so this shared component stays additive for that stream.
    init(symbol: String, text: String, tone: Tone = .neutral) {
        self.symbol = symbol
        self.label = Text(text)
        self.tone = tone
    }

    var body: some View {
        let tint = ScreenPalette.color(swatch, scheme: scheme, contrast: contrast)
        Label {
            label.foregroundStyle(TallyColor.textPrimary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        // ux-fp2 D11: in a `List` row a plain `Label` took the list's icon column (an 18 pt gap
        // before the words); the chip's words never wrap or truncate: on one line, shrunk only if
        // even a line of their own is too narrow (D02's value rule, `TallyReflow`).
        .labelStyle(.tallyCompact)
        .lineLimit(1)
        .minimumScaleFactor(TallyReflow.valueMinimumScale)
        .font(TallyTypography.caption.weight(.semibold))
        .padding(.horizontal, TallySpacing.sm)
        .padding(.vertical, TallySpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var swatch: ScreenPalette.Swatch {
        switch tone {
        case .positive: ScreenPalette.positive
        case .warning: ScreenPalette.warning
        case .danger: ScreenPalette.danger
        case .neutral: ScreenPalette.neutral
        }
    }
}

/// ux-fp2 D11: a row of status chips that wraps instead of squeezing them. Side by side while they
/// fit on one line at their full size; otherwise one under the other (the smallest iPhone in To-Do's
/// select mode read "Not sub…" next to "High pri…", and AX5 split them mid-word).
struct StatusChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TallySpacing.xs) { content() }
            VStack(alignment: .leading, spacing: TallySpacing.xs) { content() }
        }
    }
}

extension CourseHealth {
    var tone: StatusChip.Tone {
        switch self {
        case .onTrack: .positive
        case .needsAttention: .warning
        case .atRisk: .danger
        case .noGradeYet, .gradeNotInCanvas: .neutral
        }
    }
}

extension WorkStatus {
    var tone: StatusChip.Tone {
        switch self {
        case .missing: .danger
        case .late: .warning
        case .submitted, .graded: .positive
        case .notSubmitted, .excused: .neutral
        }
    }
}

/// A section title on a scrolling (non-`List`) screen, with the header trait (A11Y-09).
///
/// Plan 08 §5 (L10N-03b): takes `LocalizedStringResource`, not `String` (L10N-03a's `StatusChip`
/// precedent did not apply here — unlike `StatusChip`, every one of this component's six call sites,
/// all in `Insights/InsightsScreen.swift`, passed a string literal, including one
/// (`Insights/InsightsProjection.swift:18`'s `StreakInsight.definition`) as a non-literal `String`
/// constant; L10N-03a left this blocked rather than risk a literal-argument overload ambiguity with
/// no local Xcode to check it. Converting both at once, in the same stream, removes the ambiguity
/// instead of creating it.
struct ScreenSectionHeader: View {
    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            Text(title)
                .font(TallyTypography.sectionHeader)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
    }
}

/// A card surface for the scrolling screens (Insights, Course Detail's hero): solid tokens, no
/// material in the content layer (ux-ui.md §3.4).
struct ScreenCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            content
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
    }
}
