import SwiftUI
import TallyDesignSystem
import TallyDomain

/// UX-WP-16: the what-if sheet (ux-ui.md §3.7.3), `.medium` to `.large`. A sticky summary says
/// "Simulation — not your real grade" with the `flask` symbol; rows are the course's ungraded work
/// by category, each with a numeric field, a ±1-point stepper that VoiceOver adjusts, and quick-fill
/// chips; goal mode answers "what do I need on X for Y%?". All grade math is `WhatIfModel`'s,
/// through `GradeWork`.
struct WhatIfSheet: View {
    let model: WhatIfModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.setup.groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            WhatIfItemRow(item: item, model: model)
                        }
                    } header: {
                        Text("\(group.name) · \(group.weightText)")
                    }
                }
                WhatIfGoalSection(model: model)
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top, spacing: 0) {
                WhatIfSummary(model: model)
            }
            .navigationTitle("What-If")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { model.reset() }
                        .disabled(model.scores.isEmpty)
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

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            Label("Simulation — not your real grade", systemImage: "flask")
                .font(TallyTypography.footnote.weight(.semibold))
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityIdentifier("whatif.simulationLabel")
            HStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                Text("Projected")
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
                Text(Self.percent(model.projected))
                    .font(.system(.title, design: .serif).bold())
                    .foregroundStyle(TallyColor.textPrimary)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let change = Self.change(model.delta) {
                    Text(change)
                        .font(TallyTypography.subheadline)
                        .foregroundStyle(TallyColor.textSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(projected: model.projected, baseline: model.baseline))
            .accessibilityIdentifier("whatif.projected")
        }
        .padding(.horizontal, TallySpacing.screenMargin)
        .padding(.vertical, TallySpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgCanvas)
    }

    static func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "…"
    }

    /// "▲ 1.3" / "▼ 0.4"; nothing when the change rounds to zero.
    static func change(_ delta: Double?) -> String? {
        guard let delta, abs(delta) >= 0.05 else { return nil }
        return (delta > 0 ? "▲ " : "▼ ") + abs(delta).formatted(.number.precision(.fractionLength(1)))
    }

    static func spoken(projected: Double?, baseline: Double?) -> String {
        guard let projected else { return "Projected grade: working it out" }
        let value = projected.formatted(.number.precision(.fractionLength(1)))
        guard let baseline else { return "Projected \(value) percent" }
        let delta = projected - baseline
        guard abs(delta) >= 0.05 else { return "Projected \(value) percent, the same as your current grade" }
        let points = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return "Projected \(value) percent, \(delta > 0 ? "up" : "down") \(points) points from your current "
            + "\(baseline.formatted(.number.precision(.fractionLength(1)))) percent"
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
                    TextField("Score", text: $text)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                        .accessibilityLabel("Score for \(item.title), \(item.outOfText)")
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
                Text("Score for \(item.title)")
            }
            .tint(TallyColor.accent)
            .accessibilityIdentifier("whatif.slider")
            let chips = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallySpacing.sm))
                : AnyLayout(HStackLayout(spacing: TallySpacing.sm))
            chips {
                ForEach(WhatIfModel.quickFillPercents, id: \.self) { percent in
                    Button("\(Int(percent))%") { model.fill(item.id, percent: percent) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Set \(item.title) to \(Int(percent)) percent")
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

/// ±1 point, two 44 × 44 pt buttons (A11Y-04), each with its own label so Voice Control can name
/// it; `whatif.stepper` is their container.
private struct ScoreStepper: View {
    let item: WhatIfItem
    let model: WhatIfModel

    var body: some View {
        HStack(spacing: 0) {
            Button {
                model.step(item.id, up: false)
            } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Lower \(item.title) by 1 point")
            .accessibilityIdentifier("whatif.decrement")
            Divider().frame(height: 24)
            Button {
                model.step(item.id, up: true)
            } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Raise \(item.title) by 1 point")
            .accessibilityIdentifier("whatif.increment")
        }
        .buttonStyle(.borderless)
        .background(TallyColor.bgCanvas, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatif.stepper")
    }
}

/// Goal mode (ux-ui.md §3.7.3): the lowest score on one item that reaches a target percentage,
/// from `GoalSeek` through `GradeWork`.
private struct WhatIfGoalSection: View {
    let model: WhatIfModel

    var body: some View {
        Section {
            Picker("Assignment", selection: Binding(
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
                Text("Target: \(Int(model.goalPercent))%")
            }
            Text(answer)
                .font(TallyTypography.cardTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityIdentifier("whatif.goal")
        } header: {
            Text("Goal")
        } footer: {
            Text("Other assignments keep the scores you entered above.")
        }
    }

    private var answer: String {
        guard let id = model.goalAssignmentID, let outcome = model.goalOutcome else { return "Working it out…" }
        let possible = model.pointsPossible(for: id) ?? 0
        let outOf = possible.formatted(.number.precision(.fractionLength(0...2)))
        switch outcome {
        case .reachable(let minimum) where minimum <= 0:
            return "Any score reaches \(Int(model.goalPercent))%."
        case .reachable(let minimum):
            return "\(minimum.formatted(.number.precision(.fractionLength(0...2))))/\(outOf) or more"
        case .impossible(.unreachableEvenAtMaxScore):
            return "Not reachable, even with \(outOf)/\(outOf)."
        case .impossible:
            return "This assignment can't change your grade."
        }
    }
}
