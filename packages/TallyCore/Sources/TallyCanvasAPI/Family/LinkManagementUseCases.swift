import Foundation
import TallyDomain

/// Errors the family-linking screens show (family-linking.md §7.6's table). Deliberately
/// not `RefreshFailure` itself: these use cases need distinctions `RefreshFailure` doesn't
/// carry (an invalid code vs. a missing scope vs. self-registration being off), so
/// transport/auth/server trouble is wrapped in `.network(_:)` instead of losing that.
public enum LinkManagementError: Error, Sendable, Equatable {
    /// The registry says this institution's Tally key lacks the family/observer scopes
    /// (`ClientRegistration.familyCapable == false`) — checked locally, Canvas is never
    /// called (family-linking.md §4.4 "Scope missing on Tally's key").
    case scopeMissing
    /// A write's scope was present per the registry, but Canvas still 401'd: on Canvas's
    /// own account-policy 401s (§2.2 "unless… the root account has self-registration on"),
    /// that can only mean self-registration is off, since a scope-missing 401 would already
    /// have been caught above (family-linking.md §4.4 "Invite refused").
    case selfRegistrationOff
    /// W2's pairing code was wrong, already used, or expired (family-linking.md §7.6 "Code
    /// rejected"). The exact status Canvas returns for this is UNVERIFIED pending FAM-01;
    /// see `AddStudentByCodeUseCase`'s doc comment.
    case invalidOrExpiredCode
    /// The client-side write-amplification throttle refused the request locally
    /// (family-linking.md §6.7; `TallyConfig.maxInvitesPerDay`) — Canvas is never called.
    case throttled(nextAllowedAt: Date)
    /// Transport, auth or server trouble bubbled up from `CanvasClient` unchanged.
    case network(RefreshFailure)
}

/// S1 ("Who can see my Canvas", family-linking.md §4.2, §7.2) and O1 ("Linked students",
/// §4.3, §7.3). Both are plain reads of the same "User" shape — no scope gate here, since
/// misconfiguration surfaces as an ordinary read failure (`.network(.unknown)`), not one of
/// the three distinguishable write errors above.
public struct LinkedUsersUseCase: Sendable {
    private let client: CanvasClient

    public init(client: CanvasClient) { self.client = client }

    /// S1.
    public func listObservers() async throws(LinkManagementError) -> [ObservedUser] {
        try await fetch(path: FamilyEndpoints.observersPath)
    }

    /// O1.
    public func listObservees() async throws(LinkManagementError) -> [ObservedUser] {
        try await fetch(path: FamilyEndpoints.observeesPath)
    }

    private func fetch(path: String) async throws(LinkManagementError) -> [ObservedUser] {
        let data: Data
        do { data = try await client.fetchOne(path: path, query: FamilyEndpoints.observedUsersQuery, budget: FamilyEndpoints.requestBudget) }
        catch { throw .network(error) }
        do { return try ObservedUserMapper.map(data) } catch { throw .network(.contract) }
    }
}

/// W1: "Invite a parent" (family-linking.md §4.2, §7.4).
public struct CreateInviteUseCase: Sendable {
    private let client: CanvasClient
    private let familyCapable: Bool
    private let clock: any DateProviding

    public init(client: CanvasClient, familyCapable: Bool, clock: any DateProviding) {
        self.client = client; self.familyCapable = familyCapable; self.clock = clock
    }

    /// - Parameter recentInviteTimestamps: this account's own record of when it created a
    ///   pairing code, at any retention the caller likes — only entries inside the last
    ///   `TallyConfig.invitesPerDayWindow` count. The caller owns persisting this list; kept
    ///   pure and clock-injected here so the throttle boundary is exactly testable.
    public func createInvite(recentInviteTimestamps: [Date]) async throws(LinkManagementError) -> PairingInvite {
        guard familyCapable else { throw .scopeMissing }
        let now = clock.now()
        let withinWindow = recentInviteTimestamps.filter { now.timeIntervalSince($0) < TallyConfig.invitesPerDayWindow.timeInterval }
        if withinWindow.count >= TallyConfig.maxInvitesPerDay {
            let oldest = withinWindow.min() ?? now
            throw .throttled(nextAllowedAt: oldest.addingTimeInterval(TallyConfig.invitesPerDayWindow.timeInterval))
        }

        let response: HTTPResponse
        do { response = try await client.perform(method: .post, path: FamilyEndpoints.pairingCodesPath, budget: FamilyEndpoints.requestBudget) }
        catch { throw .network(error) }

        guard (200..<300).contains(response.status) else {
            if response.status == 401 { throw .selfRegistrationOff }
            throw .network(.unknown)
        }
        do { return try PairingCodeMapper.map(response.body) } catch { throw .network(.contract) }
    }
}

/// W2: "Add a student" (family-linking.md §4.3, §7.5 step 4).
public struct AddStudentByCodeUseCase: Sendable {
    private let client: CanvasClient
    private let familyCapable: Bool

    public init(client: CanvasClient, familyCapable: Bool) {
        self.client = client; self.familyCapable = familyCapable
    }

    /// `pairing_code` goes in the form body, never the query string (family-linking.md
    /// §4.3: keeps a live bearer secret out of URL logs; Instructure's own app puts it in
    /// the query, per §6.1's W2 row — Tally deliberately does not copy that).
    ///
    /// The rejection status for an invalid/expired/already-used code is UNVERIFIED against
    /// hosted Canvas pending FAM-01; family-linking.md §7.6 cites 422, so both 422 and the
    /// more generic 400 are treated as `.invalidOrExpiredCode` here rather than falling
    /// through to an unhelpful `.network(.unknown)`.
    public func addStudent(pairingCode: String) async throws(LinkManagementError) -> ObservedUser {
        guard familyCapable else { throw .scopeMissing }
        let body = FormBody.encode([("pairing_code", pairingCode)])

        let response: HTTPResponse
        do {
            response = try await client.perform(method: .post, path: FamilyEndpoints.observeesPath,
                                                body: body, contentType: FormBody.contentType, budget: FamilyEndpoints.requestBudget)
        } catch { throw .network(error) }

        guard (200..<300).contains(response.status) else {
            if response.status == 422 || response.status == 400 { throw .invalidOrExpiredCode }
            if response.status == 401 { throw .scopeMissing } // defensive: shouldn't reach here given the gate above
            throw .network(.unknown)
        }
        do { return try ObservedUserMapper.mapOne(response.body) } catch { throw .network(.contract) }
    }
}

/// W3: "Unlink in Canvas" (family-linking.md §4.3, §7.7) — distinct from "Remove from
/// Tally", which is purely local (purging a subject's sealed storage) and calls Canvas not
/// at all; that purge is `TallyStore`'s job (FAM-05), outside this work package.
public struct UnlinkStudentUseCase: Sendable {
    private let client: CanvasClient
    private let familyCapable: Bool

    public init(client: CanvasClient, familyCapable: Bool) {
        self.client = client; self.familyCapable = familyCapable
    }

    /// A 404 (already unlinked — by the school, or a race with another device) is treated
    /// as success: the end state Tally wants is "not linked", which already holds. UNVERIFIED
    /// against hosted Canvas pending FAM-01, but a safe, disclosed assumption either way.
    public func unlink(observeeCanvasUserID: String) async throws(LinkManagementError) {
        guard familyCapable else { throw .scopeMissing }
        let response: HTTPResponse
        do {
            response = try await client.perform(method: .delete, path: FamilyEndpoints.observeePath(observeeCanvasUserID),
                                                budget: FamilyEndpoints.requestBudget)
        } catch { throw .network(error) }
        guard (200..<300).contains(response.status) || response.status == 404 else {
            if response.status == 401 { throw .scopeMissing }
            throw .network(.unknown)
        }
    }
}
