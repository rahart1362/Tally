import CoreImage.CIFilterBuiltins
import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem
import TallyDomain
import TallyStrings
import UIKit

// FAM-10 (M3-E2): Settings' family sections (family-linking.md §7.2-§7.7). Every action goes
// through FAM-06's use cases behind `FamilyLinkService`; every failure shows its §7.6 copy.

// MARK: - Parent: Linked students (§7.3)

/// Parent mode's first Settings section: one row per student (initials, name, school, a checkmark on
/// the one shown), each opening that student's page; "Add a Student"; and in sample mode the way
/// back to the student sample. With no students, the §7.6 parent empty state.
struct LinkedStudentsSection: View {
    let family: FamilyModel
    @Binding var presentsAddStudent: Bool
    /// Sample mode only: back to the fictional student's own view (FAM-14).
    let onExploreStudentMode: (() -> Void)?

    var body: some View {
        Section {
            if family.students.isEmpty {
                Text(L10n.FamilyUI.parentNoStudents())
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityIdentifier("family.parentEmpty")
            }
            ForEach(family.students) { student in
                NavigationLink {
                    StudentDetailView(family: family, student: student)
                } label: {
                    LinkedStudentRow(student: student, colorIndex: family.colorIndex(of: student),
                                     isViewed: student.id == family.activeSubject)
                }
                .accessibilityIdentifier("family.student")
            }
            Button(String(localized: L10n.FamilyUI.addStudent())) { presentsAddStudent = true }
                .accessibilityIdentifier("family.addStudent")
            if !family.students.isEmpty {
                Toggle(String(localized: L10n.FamilyUI.hideStudentNames()),
                       isOn: Binding(get: { family.hidesStudentNames }, set: { family.setHidesStudentNames($0) }))
                    .accessibilityIdentifier("family.hideNames")
            }
            if let onExploreStudentMode {
                Button(String(localized: L10n.FamilyUI.sampleViewAsStudent()), action: onExploreStudentMode)
                    .accessibilityIdentifier("family.sample.viewAsStudent")
            }
        } header: {
            Text(L10n.FamilyUI.linkedStudentsHeader())
        } footer: {
            Text(L10n.FamilyUI.linkedStudentsFooter())
        }
    }
}

/// One linked student: initials, name, school; a checkmark (and the Selected trait) on the one shown.
struct LinkedStudentRow: View {
    let student: FamilyStudent
    let colorIndex: Int
    let isViewed: Bool

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            StudentAvatar(initials: student.initials, colorIndex: colorIndex)
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(verbatim: student.name)
                    .font(TallyTypography.body)
                Text(verbatim: student.school)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
            Spacer(minLength: 0)
            if isViewed {
                Image(systemName: "checkmark")
                    .foregroundStyle(TallyColor.accent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isViewed ? .isSelected : [])
    }
}

/// One student's page (§7.3): the parent's notifications for them (§6.5 kinds; never grades),
/// "Remove from Tally", then "Unlink in Canvas" at the bottom, each behind §7.7's confirmation.
struct StudentDetailView: View {
    let family: FamilyModel
    let student: FamilyStudent
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemove = false
    @State private var confirmsUnlink = false
    @State private var problem: FamilyLinkProblem?
    @State private var isUnlinking = false

    var body: some View {
        Form {
            Section {
                notificationToggle(L10n.FamilyUI.notifyWeekAhead, \.weekAheadEnabled, id: "family.notify.weekAhead")
                notificationToggle(L10n.FamilyUI.notifyMissingStillOpen, \.missingStillOpenEnabled, id: "family.notify.missing")
                notificationToggle(L10n.FamilyUI.notifyGradePosted, \.gradePostedEnabled, id: "family.notify.gradePosted")
                notificationToggle(L10n.FamilyUI.notifyDueReminders, \.dueRemindersEnabled, id: "family.notify.due")
            } header: {
                Text(L10n.FamilyUI.notificationsFor(student.firstName))
            } footer: {
                Text(L10n.FamilyUI.linkedStudentsFooter())
            }
            Section {
                Button(String(localized: L10n.FamilyUI.removeFromTally())) { confirmsRemove = true }
                    .accessibilityIdentifier("family.removeFromTally")
            }
            Section {
                Button(String(localized: L10n.FamilyUI.unlinkInCanvas()), role: .destructive) { confirmsUnlink = true }
                    .disabled(isUnlinking)
                    .accessibilityIdentifier("family.unlink")
                if let problem {
                    FamilyProblemText(problem: problem, school: student.school)
                }
            }
        }
        .navigationTitle(Text(verbatim: student.name))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(String(localized: L10n.FamilyUI.removeTitle(student.firstName)), isPresented: $confirmsRemove,
                            titleVisibility: .visible) {
            Button(String(localized: L10n.FamilyUI.removeFromTally())) { remove() }
            Button(String(localized: L10n.Settings.cancel()), role: .cancel) {}
        } message: {
            Text(L10n.FamilyUI.removeMessage(student.firstName))
        }
        .confirmationDialog(String(localized: L10n.FamilyUI.unlinkTitle(student.firstName)), isPresented: $confirmsUnlink,
                            titleVisibility: .visible) {
            Button(String(localized: L10n.FamilyUI.unlinkConfirm()), role: .destructive) { unlink() }
            Button(String(localized: L10n.Settings.cancel()), role: .cancel) {}
        } message: {
            Text(L10n.FamilyUI.unlinkMessage(student.firstName))
        }
    }

    private func notificationToggle(_ title: () -> LocalizedStringResource,
                                    _ setting: WritableKeyPath<FamilySubjectNotificationSettings, Bool> & Sendable,
                                    id: String) -> some View {
        Toggle(String(localized: title()), isOn: Binding(
            get: { family.settings(for: student.id)[keyPath: setting] },
            set: { isOn in
                var settings = family.settings(for: student.id)
                settings[keyPath: setting] = isOn
                family.setSettings(settings, for: student.id)
            }))
            .accessibilityIdentifier(id)
    }

    /// The page closes first, then the student leaves the roster (the row this page came from goes).
    private func remove() {
        let subject = student.id
        dismiss()
        Task { await family.removeFromTally(subject) }
    }

    /// W3 first; only once Canvas agreed does the page close and the student's data go.
    private func unlink() {
        let subject = student.id
        isUnlinking = true
        problem = nil
        Task {
            do {
                try await family.unlinkInCanvas(subject)
                dismiss()
                await family.removeFromTally(subject)
            } catch {
                problem = FamilyLinkProblem(failure: error)
                isUnlinking = false
            }
        }
    }
}

/// "Add a Student" (§7.5 step 4): the code field (no auto-capitalisation: codes are case-sensitive)
/// and Add, which runs W2. A refused code shows §7.6's "Code rejected" with Try Again.
struct AddStudentSheet: View {
    let family: FamilyModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var problem: FamilyLinkProblem?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: L10n.FamilyUI.codeField()), text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(TallyTypography.body.monospaced())
                        .submitLabel(.done)
                        .onSubmit { add() }
                        .accessibilityIdentifier("family.codeField")
                } footer: {
                    Text(L10n.FamilyUI.codeFieldFooter())
                }
                if let problem {
                    Section {
                        FamilyProblemText(problem: problem, school: family.students.first?.school)
                        Button(String(localized: L10n.FamilyUI.tryAgain())) {
                            self.problem = nil
                            code = ""
                        }
                        .accessibilityIdentifier("family.tryAgain")
                    }
                }
            }
            .navigationTitle(Text(L10n.FamilyUI.addStudentTitle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: L10n.Settings.cancel())) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.FamilyUI.add())) { add() }
                        .disabled(isAdding || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("family.add")
                }
            }
        }
    }

    private func add() {
        let entered = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty, !isAdding else { return }
        isAdding = true
        problem = nil
        Task {
            do {
                try await family.addStudent(pairingCode: entered)
                dismiss()
            } catch {
                problem = FamilyLinkProblem(failure: error)
            }
            isAdding = false
        }
    }
}

// MARK: - Student: Family & Sharing (§7.2)

/// A student's Family & Sharing: what observers can see, "Invite a Parent", who is linked in Canvas
/// (each opening "How to Remove"), the codes this iPhone created and, in sample mode, the way into
/// the sample parent view (FAM-14).
struct FamilySharingSection: View {
    let model: FamilySharingModel
    /// Sample mode only: the fictional parent's view.
    let onExploreParentMode: (() -> Void)?
    @State private var presentsInvite = false

    var body: some View {
        Group {
            Section {
                Text(L10n.FamilyUI.sharingExplainer())
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                Button(String(localized: L10n.FamilyUI.invite())) { presentsInvite = true }
                    .accessibilityIdentifier("family.invite")
            } header: {
                Text(L10n.FamilyUI.sharingHeader())
            }
            Section {
                switch model.phase {
                case .loading:
                    ProgressView()
                case .failed(let problem):
                    FamilyProblemText(problem: problem, school: model.school)
                case .loaded:
                    if model.observers.isEmpty {
                        Text(L10n.FamilyUI.studentNoObservers())
                            .accessibilityIdentifier("family.noObservers")
                    }
                    ForEach(Array(model.observers.enumerated()), id: \.element.id) { index, observer in
                        NavigationLink {
                            ObserverDetailView(observer: observer)
                        } label: {
                            HStack(spacing: TallySpacing.md) {
                                StudentAvatar(initials: StudentNameText.initials(of: observer.name), colorIndex: index)
                                Text(verbatim: observer.name)
                            }
                        }
                        .accessibilityIdentifier("family.observer")
                    }
                }
            } header: {
                Text(L10n.FamilyUI.linkedInCanvasHeader())
            } footer: {
                Text(L10n.FamilyUI.linkedInCanvasFooter())
            }
            if !model.invites.isEmpty {
                Section {
                    ForEach(model.invites) { sent in
                        SentInviteRow(sent: sent, school: model.school)
                    }
                } header: {
                    Text(L10n.FamilyUI.invitesHeader())
                } footer: {
                    Text(L10n.FamilyUI.invitesFooter())
                }
            }
            if let onExploreParentMode {
                Section {
                    Button(String(localized: L10n.FamilyUI.sampleViewAsParent()), action: onExploreParentMode)
                        .accessibilityIdentifier("family.sample.viewAsParent")
                } footer: {
                    Text(L10n.FamilyUI.sampleViewAsParentFooter())
                }
            }
        }
        .sheet(isPresented: $presentsInvite) {
            InviteSheet(model: model)
        }
    }
}

/// One code from this iPhone: the student's label (or "Code"), when it expires, and Share Again.
struct SentInviteRow: View {
    let sent: FamilySharingModel.SentInvite
    let school: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(verbatim: sent.label.isEmpty ? L10n.string(L10n.FamilyUI.inviteFallbackLabel) : sent.label)
                Text(verbatim: L10n.string(L10n.FamilyUI.expires, PairingInviteText.expiry(sent.invite.expiresAt)))
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
            Spacer(minLength: 0)
            ShareLink(item: PairingInviteText.shareMessage(sent.invite, school: school)) {
                Text(verbatim: L10n.string(L10n.FamilyUI.shareAgain))
            }
        }
    }
}

/// An observer's page: they are linked to the student's Canvas account, and How to Remove.
struct ObserverDetailView: View {
    let observer: ObservedUser
    @State private var showsHowToRemove = false

    var body: some View {
        Form {
            Section {
                Text(L10n.FamilyUI.linkedToYourAccount())
                Button(String(localized: L10n.FamilyUI.howToRemove())) { showsHowToRemove = true }
                    .accessibilityIdentifier("family.howToRemove")
            }
        }
        .navigationTitle(Text(verbatim: observer.name))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsHowToRemove) {
            HowToRemoveSheet(observerName: observer.name)
        }
    }
}

/// §7.7, student side: only the school can remove an observer; a ready-written request to copy.
struct HowToRemoveSheet: View {
    let observerName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.FamilyUI.howToRemoveHeading())
                        .font(TallyTypography.cardTitle)
                    Text(L10n.FamilyUI.howToRemoveBody(observerName))
                    Button(String(localized: L10n.FamilyUI.copyRequest())) {
                        UIPasteboard.general.string = String(localized: L10n.FamilyUI.removalRequest(observerName))
                    }
                    .accessibilityIdentifier("family.copyRequest")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Account.done())) { dismiss() }
                        .accessibilityIdentifier("family.howToRemoveDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Invite flow (§7.4)

/// "Let a parent see your Canvas": what a parent sees and can't do, an optional private label, then
/// Create Code (W1). The code shows large and spelled out for VoiceOver, with its expiry, a QR code,
/// Share… and Copy, and the warning that whoever enters it first is linked. A refused invite shows
/// its §7.6 copy.
struct InviteSheet: View {
    let model: FamilySharingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var label = ""
    @State private var created: FamilySharingModel.SentInvite?
    @State private var problem: FamilyLinkProblem?
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    PairingCodeSection(sent: created, school: model.school)
                } else {
                    Section {
                        Text(L10n.FamilyUI.inviteWillSee())
                        Text(L10n.FamilyUI.inviteCannot())
                        Text(L10n.FamilyUI.inviteOwnAccount())
                    }
                    Section {
                        TextField(String(localized: L10n.FamilyUI.inviteLabelField()), text: $label)
                            .accessibilityIdentifier("family.inviteLabel")
                        Button(String(localized: L10n.FamilyUI.createCode())) { create() }
                            .disabled(isCreating)
                            .accessibilityIdentifier("family.createCode")
                    } footer: {
                        if model.warnsOldestCode {
                            Text(L10n.FamilyUI.oldestCodeWarning())
                        }
                    }
                    if let problem {
                        Section {
                            FamilyProblemText(problem: problem, school: model.school)
                            if problem == .scopeMissing, let url = model.canvasSettingsURL {
                                Button(String(localized: L10n.FamilyUI.getCodeInCanvas())) { openURL(url) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(L10n.FamilyUI.inviteTitle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Account.done())) { dismiss() }
                        .accessibilityIdentifier("family.inviteDone")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        problem = nil
        let label = label
        Task {
            do {
                created = try await model.createInvite(label: label)
            } catch {
                problem = FamilyLinkProblem(failure: error)
            }
            isCreating = false
        }
    }
}

/// A new pairing code (§7.4 step 3-4).
struct PairingCodeSection: View {
    let sent: FamilySharingModel.SentInvite
    let school: String?
    @State private var qrCode: UIImage?

    var body: some View {
        Section {
            Text(verbatim: sent.invite.code)
                .font(TallyTypography.screenTitle.monospaced())
                .tracking(TallySpacing.xs)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(L10n.FamilyUI.codeAccessibility(StudentNameText.spelled(sent.invite.code))))
                .accessibilityIdentifier("family.inviteCode")
            Text(L10n.FamilyUI.worksOnce(PairingInviteText.expiry(sent.invite.expiresAt)))
                .font(TallyTypography.footnote)
                .frame(maxWidth: .infinity)
            if let qrCode {
                Image(uiImage: qrCode)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: PairingInviteText.qrSide)
                    .accessibilityHidden(true)
            }
            ShareLink(item: PairingInviteText.shareMessage(sent.invite, school: school)) {
                Text(L10n.FamilyUI.share())
            }
            .accessibilityIdentifier("family.share")
            Button(String(localized: L10n.FamilyUI.copy())) { UIPasteboard.general.string = sent.invite.code }
                .accessibilityIdentifier("family.copyCode")
        } footer: {
            Text(L10n.FamilyUI.codeWarning())
        }
        .task(id: sent.invite.code) { qrCode = PairingInviteText.qrCode(for: sent.invite.code) }
    }
}

/// A pairing code's words and picture. The code is only ever the code: never inside a URL (§6.7).
enum PairingInviteText {
    /// The QR code's side, in points.
    static let qrSide: CGFloat = 180
    /// How much the QR generator's 1-point modules are scaled before display.
    static let qrScale: CGFloat = 8

    /// "Fri, Oct 2", in the app's formatting locale.
    static func expiry(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(TallyLocale.effective))
    }

    /// The share sheet's text (§7.4 step 5): no grades, and the code is not part of any link.
    static func shareMessage(_ invite: PairingInvite, school: String?) -> String {
        let expiry = expiry(invite.expiresAt)
        guard let school else { return String(localized: L10n.FamilyUI.shareMessageNoSchool(invite.code, expiry)) }
        return String(localized: L10n.FamilyUI.shareMessage(school, invite.code, expiry))
    }

    /// The code as a QR image (the code text alone), for a parent beside the student.
    static func qrCode(for code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: qrScale, y: qrScale)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - States (§7.6)

/// A failed link request's §7.6 copy, with a warning symbol.
struct FamilyProblemText: View {
    let problem: FamilyLinkProblem
    /// The school's name, when Tally knows it ("Your school" otherwise).
    let school: String?

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .font(TallyTypography.footnote)
        .accessibilityIdentifier("family.problem")
    }

    private var message: LocalizedStringResource {
        switch problem {
        case .codeRejected: L10n.FamilyUI.codeRejected()
        case .inviteRefused: L10n.FamilyUI.inviteRefused(school ?? String(localized: L10n.FamilyUI.yourSchool()))
        case .scopeMissing: L10n.FamilyUI.scopeMissing()
        case .throttled: L10n.FamilyUI.throttled()
        case .network: L10n.FamilyUI.networkProblem()
        }
    }
}
