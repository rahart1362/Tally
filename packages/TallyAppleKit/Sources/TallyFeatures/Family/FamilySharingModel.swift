import Foundation
import Observation
import TallyCanvasAPI
import TallyDomain

/// A student's Settings → Family & Sharing (family-linking.md §7.2, §7.4; FAM-10): who is linked in
/// Canvas (S1), and the pairing codes this iPhone created (W1). Codes live only in memory here: the
/// Keychain store the design asks for (§6.3, `WhenUnlockedThisDeviceOnly`, deleted at `expires_at`)
/// is not built (M3-E2 report, open items), and sample mode keeps nothing anyway (ASC-14).
@MainActor
@Observable
final class FamilySharingModel {
    nonisolated deinit {}

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(FamilyLinkProblem)
    }

    /// One code this iPhone created, with the student's private label ("Mom").
    struct SentInvite: Identifiable, Equatable {
        let id: UUID
        let label: String
        let invite: PairingInvite
    }

    private(set) var phase: Phase = .loading
    private(set) var observers: [ObservedUser] = []
    /// Newest first.
    private(set) var invites: [SentInvite] = []
    /// The school's name, when Tally knows it (a signed-in account's registry label); `nil` in sample mode.
    let school: String?
    /// The school's Canvas host, for "Get a Code in Canvas" (§7.6); `nil` in sample mode, whose
    /// school is fictional.
    let host: String?

    @ObservationIgnored private let link: any FamilyLinkService
    @ObservationIgnored private let clock: any DateProviding

    init(link: any FamilyLinkService, school: String?, host: String?, clock: any DateProviding = SystemDateProvider()) {
        self.link = link
        self.school = school
        self.host = host
        self.clock = clock
    }

    /// S1. A repeated observer is listed once (the first).
    func load() async {
        do {
            let listed = try await link.listObservers()
            var seen: Set<String> = []
            observers = listed.filter { seen.insert($0.canvasUserID).inserted }
            phase = .loaded
        } catch {
            phase = .failed(FamilyLinkProblem(failure: error))
        }
    }

    /// W1. The new code is kept for "Invites from This iPhone".
    func createInvite(label: String) async throws(LinkManagementError) -> SentInvite {
        let invite = try await link.createInvite()
        let sent = SentInvite(id: UUID(), label: label.trimmingCharacters(in: .whitespacesAndNewlines), invite: invite)
        invites.insert(sent, at: 0)
        return sent
    }

    /// §7.4 step 6: with this many codes still pending, Canvas turns the oldest unused one off.
    var warnsOldestCode: Bool {
        let now = clock.now()
        return invites.count { $0.invite.expiresAt > now } >= FamilyUIConfig.pendingInvitesBeforeWarning
    }

    /// The school's Canvas settings, where a student can also create a pairing code
    /// ("Pair with Observer"), for the scope-missing state.
    var canvasSettingsURL: URL? {
        host.flatMap { URL(string: "https://\($0)/profile/settings") }
    }
}
