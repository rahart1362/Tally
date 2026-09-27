import Foundation
import Testing
import TallyCanvasAPI
import TallyTestSupport
@testable import TallyFeatures

/// UX-WP-08. Hosted (TallyFeatures is SwiftUI/iOS-only), driven entirely
/// through fakes and the same synthetic fixtures the Linux `InstitutionDirectoryTests`
/// suite uses (`fixtures/canvas/scenarios/accounts_search/`), never the network.
@MainActor
@Suite("School search (UX-WP-08)")
struct SchoolSearchViewModelTests {
    private func matches(_ scenario: String) throws -> [InstitutionMatch] {
        try InstitutionDirectory.search(Fixtures.data("scenarios/accounts_search/\(scenario).json"))
    }

    private func makeViewModel(
        result: Result<[InstitutionMatch], Error> = .success([]),
        registry: ClientRegistry = ClientRegistry([]),
        online: Bool = true,
        recentSchool: InstitutionMatch? = nil
    ) -> (SchoolSearchViewModel, FakeInstitutionSearch) {
        let search = FakeInstitutionSearch(result: result)
        let viewModel = SchoolSearchViewModel(
            search: search, registry: registry,
            reachability: FakeReachability(isOnline: online),
            recentSchool: recentSchool,
            debounce: .milliseconds(20)
        )
        return (viewModel, search)
    }

    @Test("Below the 2-character minimum stays idle and never searches")
    func idleBelowMinimumLength() async {
        let (viewModel, search) = makeViewModel()
        viewModel.query = "a"
        try? await Task.sleep(for: .milliseconds(80))
        #expect(viewModel.state == .idle)
        #expect(search.queries.isEmpty)
    }

    @Test("A 2+ character query debounces, then shows results")
    func debouncedSearchReturnsResults() async throws {
        let found = try matches("northfield")
        let (viewModel, search) = makeViewModel(result: .success(found))
        viewModel.query = "north"
        #expect(viewModel.state == .searching) // synchronous: didSet sets this before the debounce fires
        try await Task.sleep(for: .milliseconds(120))
        #expect(viewModel.state == .results(found))
        #expect(search.queries == ["north"])
    }

    @Test("An empty result set is noMatch, never an error")
    func emptyResultIsNoMatch() async throws {
        let (viewModel, _) = makeViewModel(result: .success(try matches("no-match")))
        viewModel.query = "zzzznotaschool"
        try await Task.sleep(for: .milliseconds(120))
        #expect(viewModel.state == .noMatch)
    }

    @Test("A query shaped like an address never touches the network")
    func addressShapedQuerySkipsSearch() async {
        let (viewModel, search) = makeViewModel()
        viewModel.query = "  HTTPS://Canvas.Northfield.Example/login/canvas?x=1 "
        #expect(viewModel.state == .addressTyped(host: "canvas.northfield.example"))
        try? await Task.sleep(for: .milliseconds(80))
        #expect(search.queries.isEmpty)
    }

    @Test("Offline shows the offline state and never calls the service")
    func offlineNeverSearches() async {
        let (viewModel, search) = makeViewModel(online: false)
        viewModel.query = "northfield"
        #expect(viewModel.state == .offline)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(search.queries.isEmpty)
    }

    @Test("A failed search reports searchFailed, and retry() runs it again")
    func searchFailureIsRecoverable() async throws {
        let search = FakeInstitutionSearch(result: .failure(InstitutionSearchError.rejected(status: 500)))
        let viewModel = SchoolSearchViewModel(search: search, registry: ClientRegistry([]),
                                              reachability: FakeReachability(isOnline: true), debounce: .milliseconds(20))
        viewModel.query = "northfield"
        try await Task.sleep(for: .milliseconds(120))
        #expect(viewModel.state == .searchFailed)

        let found = try matches("northfield")
        search.result = .success(found)
        viewModel.retry()
        try await Task.sleep(for: .milliseconds(120))
        #expect(viewModel.state == .results(found))
    }

    @Test("Selecting a registered school resolves to .enabled")
    func selectingARegisteredSchoolIsEnabled() throws {
        let registry = ClientRegistry([ClientRegistration(host: "canvas.northfield.example", clientID: "c1")])
        let (viewModel, _) = makeViewModel(registry: registry)
        let match = try #require(try matches("northfield").first { $0.host == "canvas.northfield.example" })
        guard case .enabled(_, let registration) = viewModel.selection(for: match) else {
            Issue.record("expected .enabled")
            return
        }
        #expect(registration.clientID == "c1")
    }

    @Test("Selecting an unregistered school resolves to .notEnabled, naming the school")
    func selectingAnUnregisteredSchoolIsNotEnabled() throws {
        let (viewModel, _) = makeViewModel(registry: ClientRegistry([]))
        let match = try #require(try matches("northfield").first)
        guard case .notEnabled(let school) = viewModel.selection(for: match) else {
            Issue.record("expected .notEnabled")
            return
        }
        #expect(school == match.name)
    }

    @Test("A typed address resolving to a registered host is enabled")
    func typedAddressCanBeEnabled() {
        let registry = ClientRegistry([ClientRegistration(host: "canvas.myschool.edu", clientID: "c2")])
        let (viewModel, _) = makeViewModel(registry: registry)
        guard case .enabled(let match, let registration) = viewModel.selectionForTypedAddress("canvas.myschool.edu") else {
            Issue.record("expected .enabled")
            return
        }
        #expect(match.host == "canvas.myschool.edu")
        #expect(registration.clientID == "c2")
    }
}

private final class FakeInstitutionSearch: InstitutionSearching, @unchecked Sendable {
    var result: Result<[InstitutionMatch], Error>
    private(set) var queries: [String] = []

    init(result: Result<[InstitutionMatch], Error>) {
        self.result = result
    }

    func search(name: String) async throws -> [InstitutionMatch] {
        queries.append(name)
        return try result.get()
    }
}

private struct FakeReachability: NetworkReachabilityChecking {
    let isOnline: Bool
}
