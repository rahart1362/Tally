import Foundation
import TallyCanvasAPI
import TallyReplay

/// Parses `manifest.json`'s route tables: one persona (or one parent-observer
/// sub-account), or one edge-case scenario.
public enum CanvasManifest {
    public enum ManifestError: Error, Sendable, Equatable {
        case unknownPersona(String), unknownAccount(persona: String, host: String), unknownScenario(String)
    }

    private struct File: Decodable {
        struct Persona: Decodable { let routes: [RouteFixture]?; let accounts: [Account]? }
        struct Account: Decodable { let host: String; let routes: [RouteFixture] }
        struct Scenario: Decodable { let id: String; let routes: [RouteFixture] }
        let personas: [String: Persona]
        let scenarios: [Scenario]
    }

    private static let file: File = {
        let data = try! Data(contentsOf: Fixtures.root().appendingPathComponent("manifest.json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(File.self, from: data)
    }()

    /// Every route for a persona. For a multi-account persona (`parent-observer`),
    /// every sub-account's routes, combined (they use different hosts, so there is
    /// no ambiguity replaying both in the same transport).
    public static func personaRoutes(_ persona: String) throws -> [RouteFixture] {
        guard let entry = file.personas[persona] else { throw ManifestError.unknownPersona(persona) }
        if let routes = entry.routes { return routes }
        return (entry.accounts ?? []).flatMap(\.routes)
    }

    /// One sub-account's routes for a multi-account persona, e.g.
    /// `personaAccountRoutes("parent-observer", host: "canvas.northfield.example")`.
    public static func personaAccountRoutes(_ persona: String, host: String) throws -> [RouteFixture] {
        guard let account = file.personas[persona]?.accounts?.first(where: { $0.host == host }) else {
            throw ManifestError.unknownAccount(persona: persona, host: host)
        }
        return account.routes
    }

    public static func scenarioRoutes(_ id: String) throws -> [RouteFixture] {
        guard let scenario = file.scenarios.first(where: { $0.id == id }) else { throw ManifestError.unknownScenario(id) }
        return scenario.routes
    }
}

/// The source-tree factories (plan 06 A1): `TallyReplay.ReplayTransport` always takes its fixture
/// root; tests read `fixtures/canvas` in this repository through `Fixtures.root()`.
extension ReplayTransport {
    public init(routes: [RouteFixture]) {
        self.init(routes: routes, root: Fixtures.root())
    }

    public static func persona(_ name: String) throws -> ReplayTransport {
        ReplayTransport(routes: try CanvasManifest.personaRoutes(name))
    }

    public static func personaAccount(_ name: String, host: String) throws -> ReplayTransport {
        ReplayTransport(routes: try CanvasManifest.personaAccountRoutes(name, host: host))
    }

    public static func scenario(_ id: String) throws -> ReplayTransport {
        ReplayTransport(routes: try CanvasManifest.scenarioRoutes(id))
    }

    /// One of the canned bodies in `fixtures/canvas/errors/<name>.json|.txt` plus its
    /// `.headers.json` sidecar (401 with/without `WWW-Authenticate`, 429, both 403 shapes, 5xx).
    public static func errorResponse(_ name: String) throws -> HTTPResponse {
        try errorResponse(name, root: Fixtures.root())
    }
}
