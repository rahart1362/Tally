#if DEBUG
import Foundation
import Synchronization
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStrings
@testable import TallyFeatures

/// M3-E2 (FAM-09, FAM-10, FAM-14): parent mode's model and its sample-family data, hosted in the
/// app so the bundled `CanvasFixtures/family-manifest.json` is the one that ships. DEBUG only, like
/// the family test hook it exercises.
@Suite("Family: sample roster, switching, removal, adding (M3-E2)")
@MainActor
struct FamilyModelTests {
    // MARK: Fixtures

    /// A link service whose answers a test sets.
    final class ScriptedLinkService: FamilyLinkService {
        let added: ObservedUser?
        let failure: LinkManagementError?
        let unlinked = Mutex<[String]>([])

        init(added: ObservedUser? = nil, failure: LinkManagementError? = nil) {
            self.added = added
            self.failure = failure
        }

        func listObservers() async throws(LinkManagementError) -> [ObservedUser] { [] }
        func createInvite() async throws(LinkManagementError) -> PairingInvite {
            if let failure { throw failure }
            return PairingInvite(code: "AB12CD", expiresAt: .distantFuture)
        }
        func addStudent(pairingCode: String) async throws(LinkManagementError) -> ObservedUser {
            if let failure { throw failure }
            guard let added else { throw .invalidOrExpiredCode }
            return added
        }
        func unlink(observeeCanvasUserID: String) async throws(LinkManagementError) {
            if let failure { throw failure }
            unlinked.withLock { $0.append(observeeCanvasUserID) }
        }
    }

    static func student(_ id: String, _ name: String) -> FamilyStudent {
        FamilyStudent(subject: Subject(id: SubjectKey("test.\(id)"), kind: .observee(canvasUserID: id)), canvasUserID: id,
                      name: name, school: "Example School (fictional)")
    }

    static let maya = student("1", "Maya Example")
    static let leo = student("2", "Leo Example")

    /// A Home that is never started: these tests are about the roster, not the data.
    static func idleHome(_ student: FamilyStudent) -> HomeModel {
        HomeModel(source: SampleSession(clock: SystemDateProvider(), makeGateway: { throw CancellationError() }))
    }

    final class Announcements {
        var spoken: [String] = []
    }

    static func model(_ students: [FamilyStudent], link: any FamilyLinkService = ScriptedLinkService(),
                      announcements: Announcements = Announcements()) -> FamilyModel {
        FamilyModel(students: students, link: link, isSample: false,
                    makeStudent: { student($0.canvasUserID, $0.name) }, makeHome: idleHome,
                    announce: { announcements.spoken.append($0) })
    }

    // MARK: FAM-14: the bundled sample family

    @Test("The bundled sample family decodes through the production decoders: two fictional students, no names in their keys")
    func sampleRosterDecodes() async throws {
        let roster = try await SampleFamilyRoster.load()
        #expect(roster.students.map(\.name) == ["Rowan Sample", "Skyler Sample"])
        #expect(roster.students.allSatisfy { $0.school == "Riverbend Unified (fictional)" })
        for student in roster.students {
            #expect(!student.id.rawValue.contains(student.firstName), "a subject key carries a name: \(student.id)")
            let observee = try #require(roster.observees[student.canvasUserID])
            let snapshot = try await roster.replay.snapshot(of: observee, now: Date())
            #expect(snapshot.courses.count == 2, "\(student.name): \(snapshot.courses.map(\.courseCode))")
            #expect(snapshot.profile.name == student.name)
        }
    }

    @Test("Sample mode reaches parent mode: two students, each with their own Home that loads their own courses")
    func sampleReachesParentMode() async throws {
        let app = AppModel()
        app.bootstrap()
        await app.enterSampleFamily()
        #expect(app.family == nil, "parent mode opened outside sample mode")
        app.enterSample()
        await app.enterSampleFamily()
        let family = try #require(app.family)
        #expect(family.isSample)
        #expect(family.students.count == 2)
        #expect(family.hasMenu)

        var codes: [[String]] = []
        for student in family.students {
            family.select(student.id)
            let home = try #require(family.activeHome)
            #expect(home !== app.home, "a student's Home is the student sample's")
            await home.start()
            #expect(try await HomeTestSupport.waitUntil { home.phase == .loaded }, "\(student.name)'s Home never loaded")
            codes.append(home.courseCards.map(\.code).sorted())
        }
        #expect(codes.count == 2 && Set(codes[0]).isDisjoint(with: codes[1]), "the students' courses mixed: \(codes)")

        app.exitSampleFamily()
        #expect(app.family == nil)
        await app.enterSampleFamily()
        #expect(app.family != nil)
        app.exitSample()
        #expect(app.family == nil, "leaving sample mode left parent mode behind")
        await app.awaitTeardown()
    }

    // MARK: FAM-09: switching

    @Test("Switching shows the student everywhere and says so once; an unknown or current student changes nothing")
    func switching() {
        let announcements = Announcements()
        let family = Self.model([Self.maya, Self.leo], announcements: announcements)
        #expect(family.activeSubject == Self.maya.id)
        let mayaHome = family.activeHome

        family.select(Self.leo.id)
        #expect(family.activeSubject == Self.leo.id)
        #expect(family.activeHome !== mayaHome)
        #expect(announcements.spoken == ["Now viewing Leo"])

        family.select(Self.leo.id)
        family.select(SubjectKey("test.unknown"))
        #expect(family.activeSubject == Self.leo.id)
        #expect(announcements.spoken.count == 1)
    }

    @Test("A student listed twice is kept once; one student is a label, not a menu")
    func repeatedAndSingle() {
        let family = Self.model([Self.maya, Self.maya])
        #expect(family.students.count == 1)
        #expect(!family.hasMenu)
        #expect(family.colorIndex(of: Self.maya) == 0)
    }

    // MARK: FAM-10: remove, unlink, link removed, add

    @Test("Remove from Tally: the student goes, the active student moves on, and with none left there is no Home")
    func removeFromTally() async {
        let family = Self.model([Self.maya, Self.leo])
        await family.removeFromTally(Self.maya.id)
        #expect(family.students == [Self.leo])
        #expect(family.activeSubject == Self.leo.id)
        #expect(!family.hasMenu)
        await family.removeFromTally(Self.leo.id)
        #expect(family.students.isEmpty)
        #expect(family.activeSubject == nil)
        #expect(family.activeHome == nil)
    }

    @Test("Unlink in Canvas: W3 first; when Canvas refuses, the student stays")
    func unlink() async throws {
        let refusing = Self.model([Self.maya, Self.leo], link: ScriptedLinkService(failure: .scopeMissing))
        await #expect(throws: LinkManagementError.scopeMissing) { try await refusing.unlink(Self.leo.id) }
        #expect(refusing.students.count == 2)

        let link = ScriptedLinkService()
        let family = Self.model([Self.maya, Self.leo], link: link)
        try await family.unlink(Self.leo.id)
        #expect(link.unlinked.withLock { $0 } == ["2"])
        #expect(family.students == [Self.maya])
    }

    @Test("Link removed: the student's data goes and the parent is told once (§7.6), including through the test hook")
    func linkRemoved() async {
        let family = Self.model([Self.maya, Self.leo])
        await family.linkDisappeared(Self.leo.id)
        #expect(family.removedNotice == Self.leo)
        #expect(family.students == [Self.maya])

        let hooked = Self.model([Self.maya, Self.leo])
        await hooked.applyScriptedOutcome(.linkRemoved)
        #expect(hooked.removedNotice == Self.leo)
        await hooked.applyScriptedOutcome(nil)
        #expect(hooked.students == [Self.maya])
    }

    @Test("Add a student: Canvas's student joins and is shown; one already here is shown, not added twice; a bad code throws")
    func addStudent() async throws {
        let newcomer = ObservedUser(canvasUserID: "3", name: "Ana Example", avatarURL: nil)
        let family = Self.model([Self.maya], link: ScriptedLinkService(added: newcomer))
        try await family.addStudent(pairingCode: "AB12CD")
        #expect(family.students.map(\.name) == ["Maya Example", "Ana Example"])
        #expect(family.activeStudent?.name == "Ana Example")
        #expect(family.activeHome != nil)

        let again = Self.model([Self.maya, Self.leo],
                               link: ScriptedLinkService(added: ObservedUser(canvasUserID: "2", name: "Leo Example", avatarURL: nil)))
        try await again.addStudent(pairingCode: "AB12CD")
        #expect(again.students.count == 2)
        #expect(again.activeSubject == Self.leo.id)

        let rejecting = Self.model([Self.maya])
        await #expect(throws: LinkManagementError.invalidOrExpiredCode) { try await rejecting.addStudent(pairingCode: "nope") }
        #expect(rejecting.students.count == 1)
    }

    @Test("Notification settings start at F7(a)'s defaults per student; Hide Student Names covers every student")
    func notificationSettings() {
        let family = Self.model([Self.maya, Self.leo])
        #expect(family.settings(for: Self.maya.id) == FamilySubjectNotificationSettings())
        var leo = family.settings(for: Self.leo.id)
        leo.dueRemindersEnabled = true
        family.setSettings(leo, for: Self.leo.id)
        #expect(family.settings(for: Self.leo.id).dueRemindersEnabled)
        #expect(!family.settings(for: Self.maya.id).dueRemindersEnabled)
        #expect(!family.hidesStudentNames)
        family.setHidesStudentNames(true)
        #expect(family.hidesStudentNames)
        #expect(family.students.allSatisfy { family.settings(for: $0.id).hideStudentNames })
    }

    // MARK: The student side (§7.2, §7.4) and the sample service

    @Test("Sample link service: the persona's observer, a 6-character code for 7 days, every code rejected, the hook's states")
    func sampleLinkService() async throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let sample = SampleFamilyLinkService(outcome: nil, clock: clock)
        #expect(try await sample.listObservers().map(\.name) == ["Dana Sample"])
        let invite = try await sample.createInvite()
        #expect(invite.code.count == 6)
        #expect(invite.expiresAt == clock.now().addingTimeInterval(7 * 24 * 60 * 60))
        await #expect(throws: LinkManagementError.invalidOrExpiredCode) { _ = try await sample.addStudent(pairingCode: "AB12CD") }

        #expect(try await SampleFamilyLinkService(outcome: .noObservers).listObservers().isEmpty)
        await #expect(throws: LinkManagementError.selfRegistrationOff) { _ = try await SampleFamilyLinkService(outcome: .inviteRefused).createInvite() }
        await #expect(throws: LinkManagementError.scopeMissing) { _ = try await SampleFamilyLinkService(outcome: .scopeMissing).createInvite() }
        #expect(FamilyTestHooks.outcome(arguments: ["-TallyTestHooks.familyOutcome", "inviteRefused"]) == .inviteRefused)
        #expect(FamilyTestHooks.outcome(arguments: ["-TallyTestHooks.familyOutcome"]) == nil)
    }

    @Test("Family & Sharing: S1 listed once each, codes kept newest first, the oldest-code warning from the fifth pending code")
    func sharingModel() async throws {
        let sharing = FamilySharingModel(link: SampleFamilyLinkService(outcome: nil), school: nil, host: nil)
        await sharing.load()
        #expect(sharing.phase == .loaded)
        #expect(sharing.observers.map(\.name) == ["Dana Sample"])
        #expect(sharing.canvasSettingsURL == nil)
        for index in 1...FamilyUIConfig.pendingInvitesBeforeWarning {
            #expect(!sharing.warnsOldestCode)
            _ = try await sharing.createInvite(label: " Code \(index) ")
        }
        #expect(sharing.warnsOldestCode)
        #expect(sharing.invites.first?.label == "Code 5")

        let refused = FamilySharingModel(link: SampleFamilyLinkService(outcome: .scopeMissing), school: "Example", host: "canvas.example.edu")
        await #expect(throws: LinkManagementError.scopeMissing) { _ = try await refused.createInvite(label: "") }
        #expect(refused.invites.isEmpty)
        #expect(refused.canvasSettingsURL?.absoluteString == "https://canvas.example.edu/profile/settings")
    }
}
#endif
