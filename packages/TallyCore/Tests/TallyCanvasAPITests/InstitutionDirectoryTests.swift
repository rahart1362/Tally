import Foundation
import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("InstitutionDirectory and ClientRegistry (WP-B08)")
struct InstitutionDirectoryTests {
    @Test func parsesTheNorthfieldSearchFixture() throws {
        let matches = try InstitutionDirectory.search(Fixtures.data("scenarios/accounts_search/northfield.json"))
        #expect(matches.count == 2)
        let state = try #require(matches.first { $0.id == "1017" })
        #expect(state.name == "Northfield State University")
        #expect(state.host == "canvas.northfield.example") // already-normalized host passes through unchanged
        #expect(state.authenticationProvider == "saml")
        #expect(matches.first { $0.id == "2231" }?.host == "northfieldcc.instructure.example")
    }

    @Test func parsesAuthenticationProviderAsAPlainStringEvenWhenNumeric() throws {
        let matches = try InstitutionDirectory.search(Fixtures.data("scenarios/accounts_search/lakeshore.json"))
        #expect(matches.first?.authenticationProvider == "38")
    }

    @Test func widerNorthSearchFindsFourSchools() throws {
        let matches = try InstitutionDirectory.search(Fixtures.data("scenarios/accounts_search/north.json"))
        #expect(matches.count == 4)
        #expect(Set(matches.map(\.host)).isSuperset(of: ["canvas.northfield.example", "northgate.instructure.example"]))
    }

    @Test func noMatchYieldsAnEmptyArrayNotAnError() throws {
        #expect(try InstitutionDirectory.search(Fixtures.data("scenarios/accounts_search/no-match.json")).isEmpty)
    }

    @Test func rowsWithoutAUsableHostOrNameAreDroppedNotFatal() throws {
        let json = #"""
        [
          {"id":"1","name":"No domain"},
          {"id":"2","domain":"canvas.example"},
          {"id":"3","name":"Bad host","domain":"localhost"},
          {"id":"4","name":"Good","domain":"canvas.good.example"}
        ]
        """#
        let matches = try InstitutionDirectory.search(Data(json.utf8))
        #expect(matches.map(\.id) == ["4"])
    }

    @Test func registeredHostResolvesToItsRegistration() throws {
        let registry = ClientRegistry([
            ClientRegistration(host: "canvas.northfield.example", clientID: "tally-northfield-1", familyCapable: true),
        ])
        let match = InstitutionMatch(id: "1017", name: "Northfield State University",
                                     host: "canvas.northfield.example", authenticationProvider: "saml")
        let registration = try InstitutionDirectory.registration(for: match, in: registry)
        #expect(registration.clientID == "tally-northfield-1")
        #expect(registration.clientType == .publicPKCE)
        #expect(registration.familyCapable)
    }

    @Test func registryLookupIsCaseInsensitiveOnHost() {
        let registry = ClientRegistry([ClientRegistration(host: "canvas.northfield.example", clientID: "x")])
        #expect(registry.registration(for: "Canvas.Northfield.Example") != nil)
    }

    @Test func familyCapableDefaultsToFalse() {
        let registration = ClientRegistration(host: "canvas.example", clientID: "x")
        #expect(!registration.familyCapable && registration.clientType == .publicPKCE)
    }

    /// Plan 08 L10N-02: the error names the school as data (the app phrases it); it carries no
    /// English of its own.
    @Test func unknownHostYieldsNotEnabledNamingTheSchool() throws {
        let registry = ClientRegistry([ClientRegistration(host: "canvas.northfield.example", clientID: "x")])
        let match = InstitutionMatch(id: "9", name: "Unregistered Academy", host: "canvas.unregistered.example", authenticationProvider: nil)
        #expect(throws: InstitutionEnablementError.notEnabled(school: "Unregistered Academy")) {
            try InstitutionDirectory.registration(for: match, in: registry)
        }
        do {
            _ = try InstitutionDirectory.registration(for: match, in: registry)
            Issue.record("expected notEnabled to throw")
        } catch {
            switch error {
            case .notEnabled(let school): #expect(school == "Unregistered Academy")
            }
        }
    }

    @Test func emptyRegistryRejectsEveryHost() throws {
        let registry = ClientRegistry([])
        #expect(registry.isEmpty && registry.count == 0)
        let match = InstitutionMatch(id: "1", name: "Any School", host: "canvas.any.example", authenticationProvider: nil)
        #expect(throws: InstitutionEnablementError.self) {
            try InstitutionDirectory.registration(for: match, in: registry)
        }
    }
}
