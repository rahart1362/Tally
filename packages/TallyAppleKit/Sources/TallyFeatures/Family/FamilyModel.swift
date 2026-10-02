import Foundation
import Observation
import TallyCanvasAPI
import TallyDomain
import TallyStrings

/// Parent mode's state (family-linking.md §6.2, §7.1, §7.3; FAM-09/10): the linked students, the
/// active subject every tab shows, and one `HomeModel` per student, so each student keeps their own
/// projection and cache (per-subject keys, never mixed). App-wide: `AppModel.family` owns it and
/// the Home shell reads it on every tab root, so a switch on any tab holds on all five.
///
/// Today only sample mode builds one (FAM-14, `FamilyModel.sample`): a signed-in observer has no
/// per-subject snapshots yet (FAM-04/05 are not built; M3-E2 report, open items).
@MainActor
@Observable
public final class FamilyModel {
    /// Explicit and nonisolated, as every class in this module (`AppModel`'s note: CI's `nm` gate
    /// keeps isolated deinits out of shipping binaries).
    nonisolated deinit {}

    /// In Canvas's order. Empty: the parent empty state (§7.6) replaces the tabs.
    public private(set) var students: [FamilyStudent]
    /// The student every tab shows; `nil` only with no students.
    public private(set) var activeSubject: SubjectKey?
    /// The parent's notification settings per student (§7.3 "Notifications for Maya"), F7(a) defaults.
    public private(set) var notificationSettings: [SubjectKey: FamilySubjectNotificationSettings] = [:]
    /// §7.6 "Link removed": the student whose Canvas link disappeared, until the parent closes the alert.
    public var removedNotice: FamilyStudent?
    /// Whether this is sample data (FAM-14): Settings offers the way back to the student sample.
    public let isSample: Bool

    @ObservationIgnored private var homes: [SubjectKey: HomeModel]
    @ObservationIgnored private let link: any FamilyLinkService
    @ObservationIgnored private let makeStudent: @MainActor (ObservedUser) -> FamilyStudent
    @ObservationIgnored private let makeHome: @MainActor (FamilyStudent) -> HomeModel
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - students: the linked students; a repeated subject is kept once (the first).
    ///   - makeStudent: a student Canvas added (W2), with the subject key the storage layer derives.
    ///   - makeHome: each student's Home model (pure construction; the shell starts it on first view).
    ///   - announce: VoiceOver's announcement after a switch (`AccessibilityAnnouncer` in the app).
    init(students: [FamilyStudent], link: any FamilyLinkService, isSample: Bool,
         makeStudent: @escaping @MainActor (ObservedUser) -> FamilyStudent,
         makeHome: @escaping @MainActor (FamilyStudent) -> HomeModel,
         announce: @escaping @MainActor (String) -> Void = { AccessibilityAnnouncer.announce($0) }) {
        var seen: Set<SubjectKey> = []
        let unique = students; _ = seen
        self.students = unique
        self.link = link
        self.isSample = isSample
        self.makeStudent = makeStudent
        self.makeHome = makeHome
        self.announce = announce
        homes = Dictionary(unique.map { ($0.id, makeHome($0)) }, uniquingKeysWith: { first, _ in first })
        notificationSettings = Dictionary(unique.map { ($0.id, FamilySubjectNotificationSettings()) },
                                          uniquingKeysWith: { first, _ in first })
        activeSubject = ActiveSubjectPolicy.resolve(persisted: nil, subjects: unique.map(\.subject))
    }

    /// The student every tab shows.
    public var activeStudent: FamilyStudent? {
        students.first { $0.id == activeSubject }
    }

    /// The active student's Home model.
    public var activeHome: HomeModel? {
        activeSubject.flatMap { homes[$0] }
    }

    /// One student: the switcher is a label, not a menu (UX-12, no dead controls).
    public var hasMenu: Bool { students.count > 0 }

    /// The avatar colour of `student`: its place in the roster.
    func colorIndex(of student: FamilyStudent) -> Int {
        students.firstIndex { $0.id == student.id } ?? 0
    }

    /// The service FAM-10's add and unlink flows use.
    var linkService: any FamilyLinkService { link }

    // MARK: - Switching (FAM-09)

    /// Shows `subject` on every tab and says so to VoiceOver ("Now viewing Maya"). An unknown or the
    /// current subject changes nothing.
    public func select(_ subject: SubjectKey) {
        guard let student = students.first(where: { $0.id == subject }) else { return }
        activeSubject = subject
        announce(String(localized: L10n.FamilyUI.nowViewing(student.firstName)))
    }

    // MARK: - Settings (FAM-10)

    public func settings(for subject: SubjectKey) -> FamilySubjectNotificationSettings {
        notificationSettings[subject] ?? FamilySubjectNotificationSettings()
    }

    public func setSettings(_ settings: FamilySubjectNotificationSettings, for subject: SubjectKey) {
        guard students.contains(where: { $0.id == subject }) else { return }
        notificationSettings[subject] = settings
    }

    /// "Hide Student Names" (§6.5): one switch for every student's notifications.
    public var hidesStudentNames: Bool {
        !students.isEmpty && students.allSatisfy { settings(for: $0.id).hideStudentNames }
    }

    public func setHidesStudentNames(_ hides: Bool) {
        for student in students {
            var settings = settings(for: student.id)
            settings.hideStudentNames = hides
            notificationSettings[student.id] = settings
        }
    }

    /// "Remove from Tally" (§7.7): this iPhone forgets the student; the Canvas link stays. Their Home
    /// model ends (its snapshot is released); the active subject moves on if it was this one.
    public func removeFromTally(_ subject: SubjectKey) async {
        guard let home = drop(subject) else { return }
        await home.end()
    }

    /// "Unlink in Canvas" (§7.7): W3, then the same local removal. On failure nothing is removed.
    public func unlink(_ subject: SubjectKey) async throws(LinkManagementError) {
        await removeFromTally(subject)
        try await unlinkInCanvas(subject)
    }

    /// W3 alone, so a page about the student can close before the student leaves the roster.
    public func unlinkInCanvas(_ subject: SubjectKey) async throws(LinkManagementError) {
        guard let student = students.first(where: { $0.id == subject }) else { return }
        try await link.unlink(observeeCanvasUserID: student.canvasUserID)
    }

    /// "Add a student" (§7.5 step 4): W2 with the code; the new student joins the roster and is
    /// shown. A student already linked here is shown, not added twice.
    public func addStudent(pairingCode: String) async throws(LinkManagementError) {
        let user = try await link.addStudent(pairingCode: pairingCode)
        if let existing = students.first(where: { $0.canvasUserID == user.canvasUserID }) {
            select(existing.id)
            return
        }
        let student = makeStudent(user)
        guard !students.contains(where: { $0.id == student.id }) else { return }
        students.append(student)
        homes[student.id] = makeHome(student)
        notificationSettings[student.id] = FamilySubjectNotificationSettings()
        select(student.id)
    }

    /// §7.6 "Link removed": a refresh found the student's link gone (FAM-05 decides when; sample
    /// mode's test hook simulates it). The data goes, and the parent is told once.
    public func linkDisappeared(_ subject: SubjectKey) async {
        guard let student = students.first(where: { $0.id == subject }), let home = drop(subject) else { return }
        removedNotice = student
        await home.end()
    }

    /// Ends every student's Home model (sample exit, or leaving parent mode).
    public func end() async {
        let ending = Array(homes.values)
        homes.removeAll()
        for home in ending { await home.end() }
    }

    /// Removes `subject` from the roster and returns its Home model to end.
    private func drop(_ subject: SubjectKey) -> HomeModel? {
        guard let index = students.firstIndex(where: { $0.id == subject }) else { return nil }
        students.remove(at: index)
        notificationSettings[subject] = nil
        let home = homes.removeValue(forKey: subject)
        if activeSubject == subject {
            activeSubject = ActiveSubjectPolicy.resolve(persisted: nil, subjects: students.map(\.subject))
        }
        return home
    }
}

extension FamilyModel {
    /// FAM-14: parent mode over the sample family, each student's Home over their own sample session
    /// (the replay, never the network). Pure construction: the roster was loaded off the main actor.
    static func sample(_ roster: SampleFamilyRoster, clock: any DateProviding = SystemDateProvider()) -> FamilyModel {
        let replay = roster.replay
        let model = FamilyModel(
            students: roster.students, link: SampleFamilyLinkService(replay: replay), isSample: true,
            makeStudent: { user in
                FamilyStudent(subject: SampleFamilyReplay.subject(of: user), canvasUserID: user.canvasUserID, name: user.name,
                              school: replay.school)
            },
            makeHome: { student in
                let observee = roster.observees[student.canvasUserID]
                    ?? ObservedUser(canvasUserID: student.canvasUserID, name: student.name, avatarURL: nil)
                return HomeModel(source: SampleSession(clock: clock, makeGateway: {
                    SampleFamilyStudentGateway(replay: replay, student: observee)
                }))
            })
        return model
    }
}
