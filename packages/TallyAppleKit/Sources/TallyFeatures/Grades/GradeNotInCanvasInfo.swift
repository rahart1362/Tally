import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

// Plan 08 §4.5 (XG-03): grades kept outside Canvas. A dash plus a caption plus an ⓘ button
// (`info.circle`); the button opens a bubble with a title, a body and Tell My School, which shares
// a pre-written message exactly as onboarding's "Ask My School" does (`SchoolNotEnabledView`). The
// bubble is a popover, and a sheet at the accessibility text sizes (A11Y-02). Nothing is shown
// unprompted. The copy is the owner's G-4 text (2026-09-30), in `TallyStrings`.

/// How the bubble is presented, and the ⓘ button's size: pure, so hosted tests pin them.
nonisolated enum GradeInfoPresentation {
    /// A11Y-04: the ⓘ button's tap target is at least 44 × 44 pt.
    static let minimumTapTarget: CGFloat = 44
    /// The popover's width; its height follows the text.
    static let popoverWidth: CGFloat = 300

    /// A11Y-02: at the accessibility text sizes the bubble is a `.medium`/`.large` sheet, so its
    /// text never clips; below them, a popover (`.presentationCompactAdaptation(.popover)`).
    static func usesSheet(at size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}

/// The bubble's words.
nonisolated enum GradeInfoText {
    /// The course-level body, or the school-level one when no course's grades appear to be in
    /// Canvas (plan 08 §4.2 "Per course versus per school").
    static func body(_ scope: GradeInfoScope) -> LocalizedStringResource {
        switch scope {
        case .course: L10n.Grades.infoBodyCourse()
        case .school: L10n.Grades.infoBodySchool()
        }
    }

    /// Tell My School's message, in the student's voice (G-4: no link, and no price claim). The
    /// school's name is the signed-in account's (`AccountRecord.displayLabel`, from the institution
    /// directory at sign-in); without one (sample data), the message says "your school".
    static func shareText(school: String?) -> String {
        let name = school?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? String(localized: L10n.Grades.shareTextNoSchool())
            : String(localized: L10n.Grades.shareText(school: name))
    }
}

/// Why a course is left out of the Dashboard's average (plan 08 G-5), from its Home course row
/// (§4.4 row 17): the same rule as `CourseGradeStatus`, so the bubble lists exactly the courses
/// the hero's "N courses not included" counts.
nonisolated enum HeroExclusion {
    static func status(of row: HomeProjection.CourseRow) -> CourseGradeStatus {
        switch row.gradeAvailability {
        case .available: row.percent != nil ? .averaged : .noPercentage
        case .lettersOnly: .lettersOnly
        case .hiddenByInstructor: .hiddenByInstructor
        case .notYetPosted: .notYetPosted
        case .notGradedInCanvas: .notGradedInCanvas
        case .keptOutsideCanvas: .keptOutsideCanvas
        }
    }

    /// The reason's words, or `nil` for an averaged course.
    static func reason(_ status: CourseGradeStatus) -> LocalizedStringResource? {
        switch status {
        case .averaged: nil
        case .noPercentage: L10n.Dashboard.reasonNoPercentage()
        case .lettersOnly: L10n.Dashboard.reasonLettersOnly()
        case .hiddenByInstructor: L10n.Dashboard.reasonHiddenByInstructor()
        case .notYetPosted: L10n.Grades.noGradeYet()
        case .notGradedInCanvas: L10n.Grades.notGradedCaption()
        case .keptOutsideCanvas: L10n.Grades.notInCanvasCaption()
        }
    }
}

/// The ⓘ button (SF Symbol `info.circle`): labelled for VoiceOver, at least 44 pt, presenting
/// `content` as a popover, or as a sheet at the accessibility text sizes.
struct GradeInfoButton<Content: View>: View {
    let label: Text
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let asSheet = GradeInfoPresentation.usesSheet(at: typeSize)
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(TallyTypography.body)
                .frame(minWidth: GradeInfoPresentation.minimumTapTarget, minHeight: GradeInfoPresentation.minimumTapTarget)
                .contentShape(Rectangle())
        }
        // Its own tap target inside a list row or a navigation link's label.
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier("grades.info")
        .popover(isPresented: Binding(get: { isPresented && !asSheet }, set: { isPresented = $0 })) {
            content()
                .padding(TallySpacing.lg)
                .frame(width: GradeInfoPresentation.popoverWidth, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
        .sheet(isPresented: Binding(get: { isPresented && asSheet }, set: { isPresented = $0 })) {
            ScrollView {
                content()
                    .padding(TallySpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// The bubble's content, and Course Detail's inline card: the title (a header, A11Y-09), the
/// body, anything `extra` adds (the hero's list of courses), and Tell My School when it applies.
struct GradeInfoBubble<Extra: View>: View {
    let title: LocalizedStringResource
    var message: LocalizedStringResource?
    var offersTellMySchool = true
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            Text(title)
                .font(TallyTypography.sectionHeader)
                .foregroundStyle(TallyColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            extra()
            if offersTellMySchool {
                TellMySchoolLink()
            }
        }
    }
}

extension GradeInfoBubble where Extra == EmptyView {
    /// A course's bubble (Courses card, Course Detail): G-4's title and the body for `scope`.
    init(scope: GradeInfoScope) {
        self.init(title: L10n.Grades.infoTitle(), message: GradeInfoText.body(scope), offersTellMySchool: true) {
            EmptyView()
        }
    }
}

/// Tell My School: a `ShareLink` with the student's message, exactly as `SchoolNotEnabledView`'s
/// "Ask My School". The student chooses where it goes; Tally sends nothing itself.
struct TellMySchoolLink: View {
    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        ShareLink(item: GradeInfoText.shareText(school: app?.activeAccount?.displayLabel)) {
            Label {
                Text(L10n.Grades.tellMySchool())
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tallyPrimary)
        .accessibilityIdentifier("grades.tellMySchool")
    }
}

/// A course card's grade when it is not in Canvas (plan 08 §4.4 row 3): "—" over its caption, one
/// VoiceOver element that reads "Grade not in Canvas" (never "dash"), and the ⓘ button for a
/// course whose grades are kept outside Canvas.
struct GradeNotInCanvasValue: View {
    let notInCanvas: GradeNotInCanvas
    let infoButtonLabel: String?
    @Binding var isInfoPresented: Bool
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: alignment, spacing: TallySpacing.xs) {
                Text(verbatim: GradeNotInCanvas.dash)
                    .font(.system(.title2).bold())
                    .foregroundStyle(TallyColor.textPrimary)
                Text(verbatim: notInCanvas.caption)
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: notInCanvas.spoken))
            if let infoButtonLabel, case .keptOutside(let scope) = notInCanvas {
                GradeInfoButton(label: Text(verbatim: infoButtonLabel), isPresented: $isInfoPresented) {
                    GradeInfoBubble(scope: scope)
                }
            }
        }
    }
}
