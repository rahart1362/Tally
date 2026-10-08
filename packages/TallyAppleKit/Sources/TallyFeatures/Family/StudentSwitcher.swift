import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// FAM-09: the header student-switcher (family-linking.md §7.1), the principal toolbar item of every
/// tab root in parent mode. An initials circle, the first name (cut at 15 characters) and a chevron;
/// a `Menu` whose inline `Picker` checks the student shown, then "Manage linked students…" and "Add a
/// student…". With one student it is a label, not a menu (UX-12: no dead controls). From the first
/// accessibility size up, the label shows the initials only; the names are in the menu.
///
/// A switch changes `FamilyModel.activeSubject`, which every tab reads, so it holds on all five
/// tabs; the shell cross-fades to that student's Home, and VoiceOver hears "Now viewing Maya"
/// (`FamilyModel.select`).
struct StudentSwitcher: View {
    let family: FamilyModel
    /// From AX1 up (the shell's own size: toolbar content gets a clamped one, CI run 37065562136).
    let showsInitialsOnly: Bool
    /// D17: at AX5 the `Menu`'s last item ("Manage linked students…") draws over the hero text at
    /// the menu's edge. A `Menu` never reflows for Dynamic Type, so accessibility sizes get a sheet
    /// instead, which scrolls like any other screen. Passed in from `HomeShellView`, not read via
    /// `@Environment(\.dynamicTypeSize)` here: this view IS the toolbar's principal item content,
    /// where the environment's Dynamic Type size is the toolbar's own clamped one, never AX5 — the
    /// same reason `showsInitialsOnly` above is computed at the shell, not in this view (CI run
    /// 37065562136's finding, restated by run 37716470762: with an internal `@Environment` read
    /// here, this branch never took at AX5, and the AX5 "after" audit capture of the switcher open
    /// was byte-identical to "before").
    let isAccessibilitySize: Bool
    let onManage: () -> Void
    let onAdd: () -> Void
    @State private var showsAccessibleSwitcher = false

    var body: some View {
        if let student = family.activeStudent {
            if family.hasMenu {
                if isAccessibilitySize {
                    Button {
                        showsAccessibleSwitcher = true
                    } label: {
                        StudentSwitcherLabel(student: student, colorIndex: family.colorIndex(of: student), showsChevron: true,
                                             showsInitialsOnly: showsInitialsOnly)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(L10n.FamilyUI.viewing(student.firstName)))
                    }
                    .accessibilityLabel(Text(L10n.FamilyUI.viewing(student.firstName)))
                    .accessibilityHint(Text(L10n.FamilyUI.switchHint()))
                    .accessibilityIdentifier("family.switcher")
                    .sensoryFeedback(.selection, trigger: family.activeSubject)
                    .sheet(isPresented: $showsAccessibleSwitcher) {
                        StudentSwitcherSheet(family: family, onManage: onManage, onAdd: onAdd)
                    }
                } else {
                    Menu {
                        Picker(selection: Binding(get: { family.activeSubject ?? student.id }, set: { family.select($0) })) {
                            ForEach(family.students) { option in
                                Text(verbatim: option.name).tag(option.id)
                            }
                        } label: {
                            Text(L10n.FamilyUI.pickerLabel())
                        }
                        .pickerStyle(.inline)
                        Divider()
                        Button(String(localized: L10n.FamilyUI.manageLinkedStudents()), action: onManage)
                        Button(String(localized: L10n.FamilyUI.addStudentEllipsis()), action: onAdd)
                    } label: {
                        // The menu's label is a button of its own inside the bar item: it gets the same label.
                        StudentSwitcherLabel(student: student, colorIndex: family.colorIndex(of: student), showsChevron: true,
                                             showsInitialsOnly: showsInitialsOnly)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(L10n.FamilyUI.viewing(student.firstName)))
                    }
                    .accessibilityLabel(Text(L10n.FamilyUI.viewing(student.firstName)))
                    .accessibilityHint(Text(L10n.FamilyUI.switchHint()))
                    .accessibilityIdentifier("family.switcher")
                    .sensoryFeedback(.selection, trigger: family.activeSubject)
                }
            } else {
                StudentSwitcherLabel(student: student, colorIndex: family.colorIndex(of: student), showsChevron: false,
                                     showsInitialsOnly: showsInitialsOnly)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(L10n.FamilyUI.viewing(student.firstName)))
                    .accessibilityIdentifier("family.switcher")
            }
        }
    }
}

/// D17 (AX5): the student switcher as a sheet, so "Manage linked students…" never draws over the
/// Dashboard hero the way the `Menu`'s last row did at accessibility sizes.
private struct StudentSwitcherSheet: View {
    let family: FamilyModel
    let onManage: () -> Void
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(family.students) { option in
                        Button {
                            family.select(option.id)
                            dismiss()
                        } label: {
                            HStack(spacing: TallySpacing.md) {
                                StudentAvatar(initials: option.initials, colorIndex: family.colorIndex(of: option))
                                Text(verbatim: option.name)
                                    .font(TallyTypography.body)
                                    .foregroundStyle(TallyColor.textPrimary)
                                Spacer(minLength: TallySpacing.sm)
                                if option.id == family.activeSubject {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(TallyColor.accent)
                                }
                            }
                        }
                        .accessibilityAddTraits(option.id == family.activeSubject ? .isSelected : [])
                    }
                }
                // D31 round 2: applied to the Section, which reaches every row inside it.
                .tallyRow()
                Section {
                    Button(String(localized: L10n.FamilyUI.manageLinkedStudents())) {
                        dismiss()
                        onManage()
                    }
                    Button(String(localized: L10n.FamilyUI.addStudentEllipsis())) {
                        dismiss()
                        onAdd()
                    }
                }
                .tallyRow()
            }
            // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
            .tallyList()
            // D01: content scrolled past the top stayed visible, blurred, under the inline title
            // and the status bar, even at rest.
            .tallyScreenChrome()
            .navigationTitle(Text(L10n.FamilyUI.pickerLabel()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Account.done())) { dismiss() }
                }
            }
        }
    }
}

/// The switcher's label: initials circle, first name, chevron when it is a menu.
struct StudentSwitcherLabel: View {
    let student: FamilyStudent
    let colorIndex: Int
    let showsChevron: Bool
    let showsInitialsOnly: Bool

    var body: some View {
        HStack(spacing: TallySpacing.xs) {
            StudentAvatar(initials: student.initials, colorIndex: colorIndex)
            if !showsInitialsOnly {
                Text(verbatim: StudentNameText.truncated(student.firstName))
                    .font(TallyTypography.body.weight(.semibold))
                    .foregroundStyle(TallyColor.textPrimary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
        // The whole label is the target, at least the HIG's 44 points tall.
        .frame(minHeight: CGFloat(FamilyUIConfig.minimumHitTarget))
        .contentShape(Rectangle())
    }
}

/// A student's (or an observer's) initials on their palette colour. Decorative: every place that
/// shows one also names the person in text, so it is hidden from VoiceOver.
struct StudentAvatar: View {
    let initials: String
    let colorIndex: Int
    /// R3 (ux-fp1 round 2): at AX5 the fixed 28 pt circle let the initials' Dynamic-Type-scaled
    /// `.caption` text fill it edge to edge. Scales the circle with Dynamic Type like the text
    /// inside it, so it grows instead of clipping — but capped at `avatarDiameterMax`, so it never
    /// outgrows the switcher's own 44 pt minimum tap height (`FamilyUIConfig.minimumHitTarget`).
    @ScaledMetric(relativeTo: .caption) private var scaledDiameter: CGFloat = CGFloat(FamilyUIConfig.avatarDiameter)

    private var diameter: CGFloat { min(scaledDiameter, CGFloat(FamilyUIConfig.avatarDiameterMax)) }

    var body: some View {
        Text(verbatim: initials)
            .font(TallyTypography.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Color.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(FamilyAvatarPalette.swiftUIColor(at: colorIndex)))
            .accessibilityHidden(true)
    }
}

extension FamilyAvatarPalette {
    static func swiftUIColor(at index: Int) -> Color {
        let rgb = color(at: index)
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}
