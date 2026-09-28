import Foundation
import TallyCanvasAPI

/// Every state the school-search screen can show (ux-ui.md §3.2.1's table).
public enum SchoolSearchState: Equatable, Sendable {
    /// Fewer than 2 characters, or the field is empty.
    case idle
    /// A search is debouncing or in flight.
    case searching
    case results([InstitutionMatch])
    /// The student typed something containing "." — treated as a Canvas address,
    /// already normalized (`InstitutionHost.normalize`), never a free-text OAuth host.
    case addressTyped(host: String)
    case noMatch
    case offline
    /// A search request failed for a reason other than being offline (e.g. a 5xx).
    case searchFailed
}

/// What selecting a result (or a typed address) resolves to, once checked
/// against the `ClientRegistry` (ux-ui.md §3.2.1 "not enabled" row).
public enum SchoolSelectionOutcome: Equatable, Sendable {
    case enabled(match: InstitutionMatch, registration: ClientRegistration)
    case notEnabled(school: String)
}

/// Drives the school-search screen (UX-WP-08). Built over `InstitutionSearching`
/// (network) and `ClientRegistry` (the bundled enablement list), both behind
/// protocols/plain data so UI tests can inject fixtures (implementation brief).
///
/// `TallyFeatures` is `.defaultIsolation(MainActor.self)` (architecture.md
/// §3.1), so this type — like every other type in the module — is
/// main-actor isolated by default; the `Task` started in `queryChanged()`
/// inherits that isolation, so its body can update `state` directly.
/// Explicitly `@MainActor` (plan 06 A2): a class that only inherits the module's default
/// isolation took the isolated-deinit path that crashes iOS 26.0-26.3 runtimes
/// (swiftlang/swift#88036); the explicit annotation keeps `deinit` nonisolated.
@MainActor
@Observable
public final class SchoolSearchViewModel {
    /// Debounce and minimum length per ux-ui.md §3.2.1: "debounce 300 ms, minimum 2 characters".
    public static let debounceDefault: Duration = .milliseconds(300)
    static let minimumCharacters = 2

    public var query: String = "" {
        didSet {
            guard oldValue != query else { return }
            queryChanged()
        }
    }

    public private(set) var state: SchoolSearchState = .idle

    /// Shown above the idle helper text after sign-out (ux-ui.md: "Recently
    /// used school on top"). No persistence is wired yet — the composition
    /// root supplies this once account/sign-out state exists; `nil` today
    /// is simply "no recent school", not a bug.
    public let recentSchool: InstitutionMatch?

    private let search: any InstitutionSearching
    private let registry: ClientRegistry
    private let reachability: any NetworkReachabilityChecking
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    public init(
        search: any InstitutionSearching,
        registry: ClientRegistry,
        reachability: any NetworkReachabilityChecking,
        recentSchool: InstitutionMatch? = nil,
        debounce: Duration = SchoolSearchViewModel.debounceDefault
    ) {
        self.search = search
        self.registry = registry
        self.reachability = reachability
        self.recentSchool = recentSchool
        self.debounce = debounce
    }

    private func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { state = .idle; return }

        // "Address typed (contains '.')" (ux-ui.md §3.2.1): normalized here,
        // never sent to OAuth as free-text — `selection(forTypedAddress:)`
        // still resolves it through the registry below.
        if text.contains("."), let host = try? InstitutionHost.normalize(text) {
            state = .addressTyped(host: host)
            return
        }

        guard text.count >= Self.minimumCharacters else { state = .idle; return }
        guard reachability.isOnline else { state = .offline; return }

        state = .searching
        let debounce = self.debounce
        searchTask = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let matches = try await search.search(name: text)
                guard !Task.isCancelled else { return }
                state = matches.isEmpty ? .noMatch : .results(matches)
            } catch {
                guard !Task.isCancelled else { return }
                state = .searchFailed
            }
        }
    }

    /// Retries the current query from a failed or offline state (ux-ui.md's "Retry" action).
    public func retry() {
        let current = query
        query = ""
        query = current
    }

    public func selection(for match: InstitutionMatch) -> SchoolSelectionOutcome {
        do {
            let registration = try InstitutionDirectory.registration(for: match, in: registry)
            return .enabled(match: match, registration: registration)
        } catch {
            // `registration(for:in:)` is `throws(InstitutionEnablementError)`, so `error`
            // here is that concrete type, not `any Error` — this switch is exhaustive.
            switch error {
            case .notEnabled(let school): return .notEnabled(school: school)
            }
        }
    }

    /// Selecting the "Use <host>" row: there is no display name yet (the student typed
    /// an address, not a search result), so the host doubles as the name until sign-in.
    public func selectionForTypedAddress(_ host: String) -> SchoolSelectionOutcome {
        selection(for: InstitutionMatch(id: host, name: host, host: host, authenticationProvider: nil))
    }
}
