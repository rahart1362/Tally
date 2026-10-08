import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// UX-WP-16: the what-if sheet (ux-ui.md §3.7.3), `.medium` to `.large`. A sticky summary says
/// "Simulation — not your real grade" with the `flask` symbol; rows are the course's ungraded work
/// by category, each with a numeric field, a ±1-point stepper that VoiceOver adjusts, and quick-fill
/// chips; goal mode answers "what do I need on X for Y%?". All grade math is `WhatIfModel`'s,
/// through `GradeWork`.
///
/// Plan 08 XG-06: for a course whose grades are kept outside Canvas (`setup.estimate`), the sheet
/// opens with the owner's approved disclaimer, then the category weights the student may set; the
/// category sections name the category only (its weight is in the weights section).
struct WhatIfSheet: View {
    let model: WhatIfModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let estimate = model.setup.estimate {
                    Section {
                        Text(L10n.WhatIfEstimate.disclaimer())
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("whatif.disclaimer")
                    }
                    // D31 round 2: applied to the Section, which reaches every row inside it.
                    .tallyRow()
                    WhatIfWeightsSection(estimate: estimate, model: model)
                }
                ForEach(model.setup.groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            WhatIfItemRow(item: item, model: model)
                        }
                    } header: {
                        if model.setup.estimate != nil {
                            Text(verbatim: group.name)
                        } else {
                            Text(L10n.CourseDetail.whatIfGroupHeader(group.name, group.weightText))
                        }
                    }
                    .tallyRow()
                }
                WhatIfGoalSection(model: model)
            }
            .listStyle(.insetGrouped)
            // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
            .tallyList()
            // D01: content scrolled past the top stayed visible, blurred, under the inline title,
            // the toolbar buttons and the status bar, even at rest.
            .tallyScreenChrome()
            .safeAreaInset(edge: .top, spacing: 0) {
                WhatIfSummary(model: model)
            }
            .navigationTitle(String(localized: L10n.CourseDetail.whatIfHeader()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: L10n.Account.done())) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(String(localized: L10n.CourseDetail.whatIfResetButton())) { model.reset() }
                        .disabled(!model.canReset)
                        .accessibilityIdentifier("whatif.reset")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await model.start() }
    }
}

/// The sticky summary: the simulation label, then the projected grade and its change.
private struct WhatIfSummary: View {
    let model: WhatIfModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            // One element with the words as its label: an identifier on a bare `Label` can land on
            // its icon (run 36454544581 read the flask's label, not the words).
            Label(WhatIfCopy.simulationLabel, systemImage: "flask")
                .font(TallyTypography.footnote.weight(.semibold))
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WhatIfCopy.simulationLabel)
                .accessibilityIdentifier("whatif.simulationLabel")
            HStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                Text(L10n.CourseDetail.whatIfSummaryLabel())
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
                Text(verbatim: model.hasNoGrade ? WhatIfCopy.noGradeDash : WhatIfCopy.percent(model.projected, locale: locale))
                    .font(.system(.title, design: .serif).bold())
                    .foregroundStyle(TallyColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let change = WhatIfCopy.change(model.delta) {
                    Text(change)
                        .font(TallyTypography.subheadline)
                        .foregroundStyle(TallyColor.textSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.hasNoGrade ? WhatIfCopy.noGradeSpoken
                                : WhatIfCopy.spoken(projected: model.projected, baseline: model.baseline, locale: locale))
            .accessibilityIdentifier("whatif.projected")
        }
        .padding(.horizontal, TallySpacing.screenMargin)
        .padding(.vertical, TallySpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        // D31 (dark): with the list rows now `bgCard` (`tallyList()`), the sticky band's old
        // `bgCanvas` read as a black hole cut into it.
        .background(TallyColor.bgCard)
    }
}

/// One ungraded item: the score field, the ±1 stepper, the slider and the quick-fill chips.
private struct WhatIfItemRow: View {
    let item: WhatIfItem
    let model: WhatIfModel
    @State private var text = ""
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            Text(item.title)
                .font(TallyTypography.cardTitle)
                .foregroundStyle(TallyColor.textPrimary)
            if let due = item.dueText {
                Text(due)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
            // From the accessibility sizes up, the field and the stepper stack instead of sharing a line.
            let controls = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallySpacing.sm))
                : AnyLayout(HStackLayout(spacing: TallySpacing.sm))
            controls {
                HStack(spacing: TallySpacing.sm) {
                    TextField(String(localized: L10n.CourseDetail.whatIfScoreFieldPrompt()), text: $text)
                        .keyboardType(.decimalPad)
                        // D31 round 2: `.roundedBorder` still rendered as pure black against the
                        // `bgCard` rows (round 1's separator overlay alone did not fix the fill
                        // itself) — `.plain` with an explicit `bgCanvas` fill and the same
                        // separator stroke keeps the sheet at two dark tones (bgCanvas, bgCard).
                        .textFieldStyle(.plain)
                        .padding(.horizontal, TallySpacing.sm)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 120, minHeight: 44)
                        .background(TallyColor.bgCanvas, in: RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous)
                            .stroke(TallyColor.separator))
                        .accessibilityLabel(String(localized: L10n.CourseDetail.whatIfScoreFieldAccessibility(item.title, item.outOfText)))
                        .accessibilityIdentifier("whatif.field")
                    Text(item.outOfText)
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textSecondary)
                        .accessibilityHidden(true)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: TallySpacing.sm) }
                ScoreStepper(item: item, model: model)
            }
            // The adjustable control: VoiceOver swipes up or down on it, and every other assistive
            // technology treats it as the standard slider it is.
            Slider(value: Binding(get: { model.scores[item.id] ?? 0 }, set: { model.setScore($0, for: item.id) }),
                   in: 0...max(item.pointsPossible, 1), step: WhatIfModel.stepPoints) {
                Text(L10n.CourseDetail.whatIfSliderAccessibility(item.title))
            }
            .tint(TallyColor.accent)
            .accessibilityIdentifier("whatif.slider")
            let chips = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallySpacing.sm))
                : AnyLayout(HStackLayout(spacing: TallySpacing.sm))
            chips {
                ForEach(WhatIfModel.quickFillPercents, id: \.self) { percent in
                    // §3.3 "Percent": the sign's position and spacing follow the locale.
                    Button(percent.formatted(.percent.scale(1).precision(.fractionLength(0)).locale(locale))) {
                        model.fill(item.id, percent: percent)
                    }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityLabel(String(localized: L10n.CourseDetail.whatIfQuickFillAccessibility(item.title, Int(percent))))
                }
            }
            .sensoryFeedback(.selection, trigger: model.scores[item.id])
        }
        .padding(.vertical, TallySpacing.xs)
        .onChange(of: text) { _, typed in
            let parsed = Self.parse(typed, locale: locale)
            if parsed != model.scores[item.id] { model.setScore(parsed, for: item.id) }
        }
        .onChange(of: model.scores[item.id]) { _, score in
            // A step, a chip, a reset or a clamp: show the model's value unless the field already says it.
            guard Self.parse(text, locale: locale) != score else { return }
            text = score.map { $0.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) } ?? ""
        }
    }

    static func parse(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return try? Double(trimmed, format: .number.locale(locale))
    }
}

/// Plan 08 XG-06: each category's weight, its total, and why an entry is not used. Every field is
/// a control of at least 44 pt on screen (`WhatIfWeightInput.minimumHeight`) with its own label.
private struct WhatIfWeightsSection: View {
    let estimate: WhatIfEstimateSetup
    let model: WhatIfModel
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            ForEach(estimate.categories) { category in
                WhatIfWeightField(category: category, model: model)
            }
            Text(L10n.WhatIfEstimate.total(WhatIfCopy.weightTotal(model.weightTotal, locale: locale)))
                .font(TallyTypography.subheadline.weight(.semibold))
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityIdentifier("whatif.weights.total")
            if model.weightsOutcome == .allZero {
                WhatIfWeightNote(text: L10n.WhatIfEstimate.allZero(), identifier: "whatif.weights.allZero")
            } else if model.weightTotalIsOverHundred {
                WhatIfWeightNote(text: L10n.WhatIfEstimate.overHundred(), identifier: "whatif.weights.overHundred")
            }
        } header: {
            Text(L10n.WhatIfEstimate.weightsHeader())
        } footer: {
            Text(L10n.WhatIfEstimate.weightsFooter())
        }
        // D31 round 2: applied to the Section, which reaches every row inside it.
        .tallyRow()
    }
}

/// One category's weight: its name, then a number field whose placeholder is the weight it keeps
/// when left blank. An entry that cannot be used says so beneath it, in words and with a symbol.
private struct WhatIfWeightField: View {
    let category: WhatIfWeightCategory
    let model: WhatIfModel
    @State private var text = ""
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            Text(verbatim: category.name)
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityHidden(true)
            WhatIfWeightInput(text: $text, category: category)
            if model.invalidWeights.contains(category.id) {
                WhatIfWeightNote(text: L10n.WhatIfEstimate.invalidWeight(), identifier: "whatif.weight.invalid")
            }
        }
        .padding(.vertical, TallySpacing.xs)
        .onChange(of: text) { _, typed in
            model.setWeight(WhatIfModel.weightEntry(typed, locale: locale), for: category.id)
        }
        .onChange(of: model.resetCount) { _, _ in
            text = ""
        }
    }
}

/// The weight's number field and its tap target: the whole box, at least `minimumHeight` tall,
/// puts the cursor in the field (A11Y-04). Its label names the category for VoiceOver and Voice
/// Control.
struct WhatIfWeightInput: View {
    /// Drawn at 46 pt so it still measures at least 44 pt when the system shows the sheet scaled
    /// by 0.960 at the medium height (`ScoreStepper.buttonSide`, PR #6).
    static let minimumHeight: CGFloat = 46

    @Binding var text: String
    let category: WhatIfWeightCategory
    @FocusState private var isFocused: Bool

    init(text: Binding<String>, category: WhatIfWeightCategory) {
        _text = text
        self.category = category
    }

    var body: some View {
        TextField(text: $text, prompt: Text(verbatim: category.defaultText)) {
            Text(L10n.WhatIfEstimate.weightLabel(category.name))
        }
        .keyboardType(.decimalPad)
        // D31 round 2: `.roundedBorder` still rendered as pure black against the `bgCard` rows
        // (round 1's separator overlay alone did not fix the fill itself) — `.plain` with an
        // explicit `bgCanvas` fill and the same separator stroke keeps the sheet at two dark
        // tones (bgCanvas, bgCard), the same treatment as the score field above.
        .textFieldStyle(.plain)
        .padding(.horizontal, TallySpacing.sm)
        .background(TallyColor.bgCanvas, in: RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TallyRadius.iconTile, style: .continuous)
            .stroke(TallyColor.separator))
        .focused($isFocused)
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .accessibilityLabel(Text(L10n.WhatIfEstimate.weightLabel(category.name)))
        .accessibilityIdentifier("whatif.weight")
    }
}

/// A note under the weights: words and a symbol, never colour alone (A11Y-06).
private struct WhatIfWeightNote: View {
    let text: LocalizedStringResource
    let identifier: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(TallyTypography.footnote)
        .foregroundStyle(TallyColor.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// ±1 point, two buttons of at least 44 × 44 pt on screen (A11Y-04), each with its own label so
/// Voice Control can name it; `whatif.stepper` is their container.
private struct ScoreStepper: View {
    /// Drawn at 46 pt so they still measure at least 44 pt when the system shows the sheet scaled
    /// by 0.960: CI measured the 44 pt buttons at 42.25 pt on iOS 26.5 and on iOS 27 (PR #6 run
    /// 36524838684; m3-screens-report O14).
    static let buttonSide: CGFloat = 46

    let item: WhatIfItem
    let model: WhatIfModel

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.step(item.id, up: false)
            } label: {
                Image(systemName: "minus").frame(width: Self.buttonSide, height: Self.buttonSide)
            }
            .accessibilityLabel(String(localized: L10n.CourseDetail.whatIfLowerByOnePoint(item.title)))
            .accessibilityIdentifier("whatif.decrement")
            Divider().frame(height: 24)
            Button {
                model.step(item.id, up: true)
            } label: {
                Image(systemName: "plus").frame(width: Self.buttonSide, height: Self.buttonSide)
            }
            .accessibilityLabel(String(localized: L10n.CourseDetail.whatIfRaiseByOnePoint(item.title)))
            .accessibilityIdentifier("whatif.increment")
        }
        .buttonStyle(.borderless)
        // D31 (dark): with the list rows now `bgCard` (`tallyList()`), the stepper's old
        // `bgCanvas` read as a black hole cut into it.
        .background(TallyColor.bgCard, in: Capsule())
        // D31 round 2: the capsule's `bgCard` fill had no edge of its own against the `bgCard`
        // rows around it; a separator stroke gives it a visible boundary, as the fix list asks.
        .overlay(Capsule().stroke(TallyColor.separator))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatif.stepper")
    }
}

/// Goal mode (ux-ui.md §3.7.3): the lowest score on one item that reaches a target percentage,
/// from `GoalSeek` through `GradeWork`.
private struct WhatIfGoalSection: View {
    let model: WhatIfModel
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            Picker(String(localized: L10n.CourseDetail.whatIfGoalAssignmentPicker()), selection: Binding(
                get: { model.goalAssignmentID },
                set: { if let id = $0 { model.setGoal(assignment: id) } })) {
                ForEach(model.setup.groups) { group in
                    ForEach(group.items) { item in
                        Text(item.title).tag(Optional(item.id))
                    }
                }
            }
            Stepper(value: Binding(get: { model.goalPercent }, set: { model.setGoal(percent: $0) }),
                    in: 50...100, step: 1) {
                Text(L10n.CourseDetail.whatIfGoalTarget(goalPercentText))
            }
            Text(answer)
                .font(TallyTypography.cardTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityIdentifier("whatif.goal")
        } header: {
            Text(L10n.CourseDetail.whatIfGoalHeader())
        } footer: {
            Text(L10n.CourseDetail.whatIfGoalFooter())
        }
        // D31 round 2: applied to the Section, which reaches every row inside it.
        .tallyRow()
    }

    /// "90%" (§3.3 "Percent"): `model.goalPercent` is already a whole number (the stepper's step is 1).
    private var goalPercentText: String {
        model.goalPercent.formatted(.percent.scale(1).precision(.fractionLength(0)).locale(locale))
    }

    private var answer: String {
        guard let id = model.goalAssignmentID, let outcome = model.goalOutcome else {
            return String(localized: L10n.CourseDetail.whatIfGoalWorkingItOut())
        }
        let possible = model.pointsPossible(for: id) ?? 0
        let outOf = possible.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        switch outcome {
        case .reachable(let minimum) where minimum <= 0:
            return String(localized: L10n.CourseDetail.whatIfGoalAnyScoreReaches(goalPercentText))
        case .reachable(let minimum):
            let minimumText = minimum.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            return String(localized: L10n.CourseDetail.whatIfGoalMinimumOrMore(minimumText, outOf))
        case .impossible(.unreachableEvenAtMaxScore):
            return String(localized: L10n.CourseDetail.whatIfGoalUnreachableEvenAtMax(outOf))
        case .impossible:
            return String(localized: L10n.CourseDetail.whatIfGoalCannotChangeGrade())
        }
    }
}
