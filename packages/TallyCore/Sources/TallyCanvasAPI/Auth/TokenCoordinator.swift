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
            await dropTokens()
            throw .reauthRequired
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
            await dropTokens()
            throw .reauthRequired
        }
    }

    /// Network trouble, server errors, throttling and cancellation keep the tokens.
    /// invalid_grant, other 4xx and a user mismatch mean sign in again.
    static func isTransient(_ error: any Error) -> Bool {
        if error is TransportError || error is CancellationError { return true }
        switch error as? TokenEndpointError {
        case .rejected(let status)?: return status >= 500 || status == 429
        case .malformed?: return true
        case .invalidGrant?, .userMismatch?, nil: return false
        }
    }

    private func dropTokens() async {
        needsReauth = true
        current = nil
        await store.delete()
    }
}
