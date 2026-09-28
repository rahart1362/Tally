import Foundation

/// How Tally authenticates at an institution. Only the public-PKCE shape is implemented;
/// a confidential-client-via-broker shape is a later decision (architecture §4, D1).
public enum ClientType: String, Sendable, Equatable, Codable {
    case publicPKCE
}

/// One institution's OAuth registration (architecture §3.5): "Tally configuration, not
/// Canvas data. How it is distributed is D2." `familyCapable` gates the parent/observer
/// flow (family-linking.md) per institution, since observation may be disabled by the school
/// (family-linking.md §2.6) or the registration simply not yet extended to cover it.
public struct ClientRegistration: Sendable, Equatable, Codable {
    public let host: String
    public let clientID: String
    public let clientType: ClientType
    public let familyCapable: Bool

    public init(host: String, clientID: String, clientType: ClientType = .publicPKCE, familyCapable: Bool = false) {
        self.host = host
        self.clientID = clientID
        self.clientType = clientType
        self.familyCapable = familyCapable
    }
}

/// Maps a normalized host to its `ClientRegistration`. An institution with no entry here
/// shows "Tally isn't enabled at <school> yet" (`InstitutionDirectory`), never a broken login.
public struct ClientRegistry: Sendable {
    private let byHost: [String: ClientRegistration]

    /// Hosts are normalized (lowercased) as the key, matching `InstitutionHost.normalize`'s output.
    public init(_ registrations: [ClientRegistration]) {
        byHost = Dictionary(registrations.map { ($0.host.lowercased(), $0) }, uniquingKeysWith: { _, latest in latest })
    }

    public func registration(for host: String) -> ClientRegistration? {
        byHost[host.lowercased()]
    }

    public var isEmpty: Bool { byHost.isEmpty }
    public var count: Int { byHost.count }
}
