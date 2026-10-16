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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// MVP-2f gate-2 (fix list item 3): set by an ancestor `StatusChipRow` (via `.environment`,
    /// never a direct parameter — `StatusChipRow`'s own `content` closure is generic, so it cannot
    /// reach into its children to set a property on each chip individually). Giving a WRAPPING
    /// `VStack` its own `.frame(maxWidth: .infinity)` does not, by itself, make each child inside
    /// it any wider than that child's own natural "pill" size wants to be — a `VStack` positions
    /// children by `alignment` within its bounds, it does not stretch them; this file's own
    /// `body` doc comment below has the fix this flag drives.
    @Environment(\.statusChipFullWidth) private var fullWidth
    /// A value chip (a score) keeps D02's value rule: one line, shrunk at the accessibility sizes.
    private var isValue = false

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
        // before the words). Words stay full size and, when they no longer fit on one line, wrap
        // between words onto a second: shrinking them (gate 2, R1) drew the same chip at different
        // sizes side by side. Only a value chip (`valueStyle()`) keeps one line, shrunk at AX
        // sizes, so a score never breaks (D02's value rule, `TallyReflow`).
        //
        // MVP-2b: two lines at every size, not only from AX1 up. Between the default size and AX1
        // (xLarge–xxxLarge) a word chip was held to one line, so a long one in a narrow column
        // ("Needs attention" beside a course's grade) could only truncate there. Where a chip fits
        // on one line, as at the default size, nothing changes. (Courses and Calendar each kept one
        // "may be clipped at larger Dynamic Type sizes" the audit could not attach to an element,
        // scope=a11y run 38357314250; both show word chips. Whether this was that is in MVP-2b's
        // report, not assumed here.)
        .labelStyle(.tallyCompact)
        .lineLimit(isValue ? 1 : 2)
        .minimumScaleFactor(isValue ? TallyReflow.minimumScale(at: typeSize) : 1)
        // MVP-2f gate-2 (fix list item 3): the gate-2 final review's own evidence (verdict §3) was
        // still "Not subm…"/"High priori…" truncated at AX5 even once `StatusChipRow` stopped using
        // `ViewThatFits` there (a prior attempt that wrapped only the ROW in `.frame(maxWidth:
        // .infinity)`, which this doc comment's own earlier wording wrongly assumed would reach
        // each chip — dispatched for real, Audit tour run 38828098145, it did not: the chip is
        // still its own "ideal"-sized pill). Two things were missing, both on the chip itself:
        // - `.fixedSize(horizontal: false, vertical: true)`: without it, nothing guarantees this
        //   `Label` is actually GIVEN the height its own wrapped second line needs inside a `List`
        //   row's own (separate) height-measurement pass — always on, value chips included, since a
        //   value chip's own single line already equals its ideal height (this costs it nothing).
        // - `.frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)`: only when
        //   `fullWidth` (`StatusChipRow`'s own flag, this type's own doc comment) — stretches the
        //   chip itself to the row's width, handing its `Text` a definite width to wrap against,
        //   instead of the chip's own natural, compact pill width (too narrow for "High priority"
        //   on one line, and with nothing wider offered, two lines either). `nil` elsewhere (every
        //   other call site: Courses, CourseDetail, Calendar) keeps the plain pill unchanged.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .font(TallyTypography.caption.weight(.semibold))
        .padding(.horizontal, TallySpacing.sm)
        .padding(.vertical, TallySpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
    }

    /// D02: this chip shows a value (a score): one line, shrunk at the accessibility sizes.
    func valueStyle() -> StatusChip {
        var chip = self
        chip.isValue = true
        return chip
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
///
/// MVP-2f gate-2 (fix list item 3): `ViewThatFits` picks between the two stacks above by each one's
/// own IDEAL size (every chip at its natural single-line width, `lineLimit` or not — "ideal" means
/// unconstrained). At accessibility sizes a chip's natural single-line width can exceed the row's
/// own width on its own, so neither alternative's ideal size ever fits and `ViewThatFits` falls back
/// to its last alternative, squeezed into the row's width with no definite width handed to the
/// `Text` inside to wrap against — the gate-2 final review's own evidence (verdict §3): "Not
/// subm…" on the smallest iPhone at AX5 outside select mode, "Not submi…" and "High priori…" on Pro
/// Max in select mode. FP-2's rule is that a VALUE never breaks mid-token; these are word chips
/// (never `.valueStyle()`), so wrapping between words is the correct fix, not shrinking them.
///
/// **A first attempt (skip `ViewThatFits` at accessibility sizes, give this row's own `VStack` a
/// `.frame(maxWidth: .infinity)`) did not actually fix it** — dispatched for real (Audit tour run
/// 38828098145), Pro Max select mode still read "High priori…". A `VStack` stacks and aligns its
/// children within its own bounds; stretching the STACK's own frame does not, by itself, stretch
/// EACH CHILD inside it any wider than that child's own natural "pill" size wants — each `StatusChip`
/// was still proposed (and fit itself to) its own ideal compact width, the same as before. The real
/// fix is on `StatusChip` itself (its own doc comment): this row only sets `statusChipFullWidth`
/// (via `.environment`, since `content` is a generic closure this type cannot reach inside of) —
/// every chip inside reads that flag and stretches ITSELF.
///
/// The Courses xxxLarge precedent (`CourseCardView.usesFullWidthColumn`) is reused for WHEN this
/// applies: at accessibility sizes and `xxxLarge` (the standard size closest to them), skip
/// `ViewThatFits` entirely and lay the chips out in a plain, full-width `VStack`.
struct StatusChipRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Same threshold as `CourseCardView.usesFullWidthColumn`, for the same reason (this type's own
    /// doc comment): a standalone copy, not a shared property, since the two types are otherwise
    /// unrelated and neither owns the other.
    private var usesFullRowWidth: Bool { typeSize.isAccessibilitySize || typeSize == .xxxLarge }

    var body: some View {
        if usesFullRowWidth {
            VStack(alignment: .leading, spacing: TallySpacing.xs) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.statusChipFullWidth, true)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TallySpacing.xs) { content() }
                VStack(alignment: .leading, spacing: TallySpacing.xs) { content() }
            }
        }
    }
}

/// MVP-2f gate-2 (fix list item 3): `StatusChipRow`'s own "lay chips out full width, not as
/// compact pills" decision, read by every `StatusChip` in its subtree (`StatusChip`'s own doc
/// comment on `fullWidth` has why this is an environment value, not a parameter). `fileprivate`:
/// only `StatusChipRow` sets it and only `StatusChip` reads it, both in this file.
fileprivate struct StatusChipFullWidthKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var statusChipFullWidth: Bool {
        get { self[StatusChipFullWidthKey.self] }
        set { self[StatusChipFullWidthKey.self] = newValue }
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
