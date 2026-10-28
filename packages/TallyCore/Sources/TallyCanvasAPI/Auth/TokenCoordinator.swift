import Foundation
import TallyDomain

/// Keychain-backed in the app (`AfterFirstUnlockThisDeviceOnly`); in-memory in tests.
public protocol CredentialStore: Sendable {
    func load() async -> CanvasCredential?
    func save(_ credential: CanvasCredential) async throws
    func delete() async
}

/// Performs one refresh-token grant (TokenEndpoint + transport in production).
public protocol TokenRefreshing: Sendable {
    func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential
}

public enum AuthError: Error, Sendable, Equatable {
    /// Sign-in must be repeated: tokens dropped, saved Canvas data kept (security.md §3.2).
    case reauthRequired
    /// Network trouble during refresh: tokens kept, caller backs off.
    case transient
    /// PAY-10 (M3-B2): Canvas rejected Tally's client (`invalid_client`): the school turned off
    /// Tally's developer key. Tokens and saved data kept (they work again if the school turns the
    /// key back on); every refresh until then reports it.
    case schoolDisabled
}

/// Owns one account's tokens. Every refresh is single-flight, and the rotated
/// credential is saved before any waiter resumes, because public-client refresh
/// tokens rotate and a second refresh with the old one would fail.
public actor TokenCoordinator {
    /// A 401 on a token refreshed this recently means refreshing won't help (no loop).
    public static let refreshLoopGuard: Duration = .seconds(30)

    private let store: any CredentialStore
    private let refresher: any TokenRefreshing
    private let clock: any DateProviding
    private var current: CanvasCredential?
    private var lastRefreshAt: Date?
    private var inFlight: Task<CanvasCredential, any Error>?
    public private(set) var needsReauth = false

    public init(initial: CanvasCredential?, store: any CredentialStore, refresher: any TokenRefreshing, clock: any DateProviding) {
        current = initial; self.store = store; self.refresher = refresher; self.clock = clock
        needsReauth = initial == nil
    }

    /// A usable access token, refreshing first if it is about to expire.
    public func accessToken() async throws(AuthError) -> String {
        guard !needsReauth, let credential = current else { throw .reauthRequired }
        if credential.isAccessTokenUsable(now: clock.now()) { return credential.accessToken }
        return try await refreshed().accessToken
    }

    /// Call on a 401 that carried `WWW-Authenticate` (a token rejection, not a scope error).
    /// Returns the token to retry with, once.
    public func tokenAfterRejection(of rejected: String) async throws(AuthError) -> String {
        guard !needsReauth, let credential = current else { throw .reauthRequired }
        if credential.accessToken != rejected { return credential.accessToken } // already refreshed by someone else
        if let last = lastRefreshAt, clock.now().timeIntervalSince(last) < Self.refreshLoopGuard.timeInterval {
            // LIVE-FIX-2 (EB-26, live2-security's "school-disabled: binding OFF, key still
            // active" finding): a token this fresh being rejected again is never an ordinary
            // sign-in problem -- a refresh that recently succeeded proves Canvas still considers
            // this client known and the student's own sign-in valid. The one case the live
            // server actually produces this in is the school switching the account binding off
            // while the developer key stays active: the refresh grant keeps succeeding (binding
            // is never consulted there, `base_type.rb`'s `has_valid_key?`), but the account no
            // longer accepts the resulting token. Reporting `.schoolDisabled` here (not
            // `.reauthRequired`) keeps the tokens and the saved data, the same as the
            // `isClientRejected` branch in `refreshed()` below, and -- critically -- does not
            // refresh again: this guard already stops at one refresh per `refreshLoopGuard`
            // window, so the "without looping refreshes" requirement holds for free.
            throw .schoolDisabled
        }
        return try await refreshed().accessToken
    }

    private func refreshed() async throws(AuthError) -> CanvasCredential {
        if inFlight == nil, let credential = current {
            let (store, refresher) = (self.store, self.refresher)
            inFlight = Task {
                let next = try await refresher.refresh(credential)
                try await store.save(next) // persisted before any waiter resumes
                return next
            }
        }
        guard let task = inFlight else { throw .reauthRequired }
        do {
            let next = try await task.value
            if inFlight == task { inFlight = nil; current = next; lastRefreshAt = clock.now() }
            return next
        } catch {
            if inFlight == task { inFlight = nil }
            if Self.isTransient(error) { throw .transient }
            if Self.isClientRejected(error) { throw .schoolDisabled }
            await dropTokens()
            throw .reauthRequired
        }
    }

    /// Network trouble, server errors, throttling and cancellation keep the tokens.
    /// invalid_grant, other 4xx and a user mismatch mean sign in again; invalid_client means the
    /// school turned Tally off (`isClientRejected`), which keeps them too.
    static func isTransient(_ error: any Error) -> Bool {
        if error is TransportError || error is CancellationError { return true }
        switch error as? TokenEndpointError {
        case .rejected(let status)?: return status >= 500 || status == 429
        // SEC1-07: a response shape Canvas's own types never produce, same as `.malformed` --
        // not the student's problem, and not fixed by a re-auth either.
        case .malformed?, .unsupportedTokenType?: return true
        case .invalidGrant?, .userMismatch?, .invalidClient?, nil: return false
        }
    }

    /// PAY-10: the school turned off Tally's developer key. Not a sign-in problem: the tokens stay.
    static func isClientRejected(_ error: any Error) -> Bool {
        error as? TokenEndpointError == .invalidClient
    }

    private func dropTokens() async {
        needsReauth = true
        current = nil
        await store.delete()
    }
}
