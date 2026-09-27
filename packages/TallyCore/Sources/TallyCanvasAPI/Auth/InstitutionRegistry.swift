import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Tally's own signed institution registry (security.md §3.2.1, WP-SEC-12): the host
/// allow-list, shipped bundled and refreshed from a static CDN. A signature — not TLS or
/// the CDN — is what makes it trustworthy, so a compromised CDN or a network attacker can
/// at worst withhold updates, never inject or roll back one.
///
/// One entry per institution. `familyCapable` mirrors `ClientRegistration.familyCapable`
/// (family-linking.md §2.6, §4.4): whether this institution's key has the observer/family
/// scopes, so the parent-linking flow can be gated per school without a network round trip.
public struct InstitutionRegistryEntry: Sendable, Equatable, Codable {
    public let host: String
    public let clientID: String
    public let clientType: ClientType
    public let familyCapable: Bool

    public init(host: String, clientID: String, clientType: ClientType, familyCapable: Bool) {
        self.host = host; self.clientID = clientID; self.clientType = clientType; self.familyCapable = familyCapable
    }
}

/// The signed document (the bytes that are actually hashed and signed are this struct's
/// exact JSON encoding — see `InstitutionRegistryCodec`). `version` is a plain monotonically
/// increasing counter (security.md §3.2.1 "monotonically increasing version to block
/// rollback"): the verifier's job, not this type's.
public struct SignedInstitutionRegistry: Sendable, Equatable, Codable {
    public let version: Int
    public let issuedAt: Date
    public let expiresAt: Date
    /// Dotted, e.g. "1.4.0" (`SemanticVersion`). Below this, the app must not trust the
    /// registry at all (WP-SEC-12 "insufficient minAppVersion").
    public let minAppVersion: String
    public let entries: [InstitutionRegistryEntry]

    public init(version: Int, issuedAt: Date, expiresAt: Date, minAppVersion: String, entries: [InstitutionRegistryEntry]) {
        self.version = version; self.issuedAt = issuedAt; self.expiresAt = expiresAt
        self.minAppVersion = minAppVersion; self.entries = entries
    }
}

/// What is actually fetched or bundled: the exact signed bytes plus the signature over
/// them, never the parsed object. Verifying the signature over a *re-encoded* JSON object
/// is a classic bug (key order, spacing, float formatting can all differ) — storing the
/// signed bytes verbatim in `payload` sidesteps that entirely.
public struct InstitutionRegistryEnvelope: Sendable, Equatable, Codable {
    /// Exact UTF-8 JSON bytes of a `SignedInstitutionRegistry` — the signed message.
    public let payload: Data
    /// Raw (r || s) ECDSA P-256 signature over `payload`, 64 bytes.
    public let signature: Data

    public init(payload: Data, signature: Data) { self.payload = payload; self.signature = signature }
}

/// The codec every signer and verifier must share, so a byte produced by one is read back
/// identically by the other. `.secondsSince1970` sidesteps ISO-8601 formatting entirely
/// (unlike Canvas's dates — `CanvasJSON.swift` — this is a Tally-only format with no
/// external format to match).
public enum InstitutionRegistryCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys] // deterministic bytes: reproducible signing, easy diffs
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// A dotted `major.minor.patch` version (missing components default to 0; a pre-release
/// or build suffix is ignored — this only ever compares Tally's own release versions).
public struct SemanticVersion: Sendable, Equatable, Comparable, Codable, CustomStringConvertible {
    public let major, minor, patch: Int

    public init(major: Int, minor: Int, patch: Int) { self.major = major; self.minor = minor; self.patch = patch }

    public init?(_ text: String) {
        let core = text.split(separator: "-", maxSplits: 1).first.map(String.init) ?? text
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let numbers = parts.map { Int($0) }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        let values = numbers.map { $0! }
        major = values[0]
        minor = values.count > 1 ? values[1] : 0
        patch = values.count > 2 ? values[2] : 0
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum InstitutionRegistryError: Error, Sendable, Equatable {
    /// The envelope isn't even well-formed JSON, or `minAppVersion` doesn't parse.
    case malformed
    /// The signature doesn't match `payload` under the pinned public key (WP-SEC-12
    /// "rejects a tampered payload").
    case badSignature
    /// `version` is not greater than the cached one (WP-SEC-12 "a rollback").
    case rollback(cached: Int, incoming: Int)
    /// `now >= expiresAt` (WP-SEC-12 "an expired registry").
    case expired(expiresAt: Date)
    /// The running app is older than `minAppVersion` (WP-SEC-12 "insufficient minAppVersion").
    case appTooOld(required: SemanticVersion, current: SemanticVersion)
}

/// Verifies one envelope. Never trusts TLS or the CDN — only the signature and the
/// embedded version/dates/`minAppVersion` decide whether a registry is usable.
public enum InstitutionRegistryVerifier {
    /// - Parameters:
    ///   - cachedVersion: the previously accepted registry's `version`, or `nil` to skip
    ///     the rollback check entirely (the bundled fallback has no "previous" of its own —
    ///     it predates whatever was last fetched, and that is not an attack).
    ///   - enforceExpiry: `false` for the bundled fallback (security.md §3.2.1 "falls back
    ///     to the bundled copy" — a stale-but-genuine bundled registry must still work when
    ///     there has been no successful fetch in a long time, rather than leaving the
    ///     student with no institutions at all).
    public static func verify(_ envelopeData: Data, publicKey: P256.Signing.PublicKey, now: Date,
                              cachedVersion: Int? = nil, enforceExpiry: Bool = true,
                              currentAppVersion: SemanticVersion) throws(InstitutionRegistryError) -> SignedInstitutionRegistry {
        guard let envelope = try? InstitutionRegistryCodec.decoder().decode(InstitutionRegistryEnvelope.self, from: envelopeData),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: envelope.signature) else {
            throw .malformed
        }
        guard publicKey.isValidSignature(signature, for: envelope.payload) else { throw .badSignature }
        guard let registry = try? InstitutionRegistryCodec.decoder().decode(SignedInstitutionRegistry.self, from: envelope.payload),
              let required = SemanticVersion(registry.minAppVersion) else {
            throw .malformed
        }
        if let cachedVersion, registry.version <= cachedVersion {
            throw .rollback(cached: cachedVersion, incoming: registry.version)
        }
        if enforceExpiry, now >= registry.expiresAt {
            throw .expired(expiresAt: registry.expiresAt)
        }
        guard currentAppVersion >= required else {
            throw .appTooOld(required: required, current: currentAppVersion)
        }
        return registry
    }
}

/// Signs a payload (offline signing script, tests with an ephemeral key — never a real
/// key in-process on a student's device: only the *public* key is compiled into the app).
public enum InstitutionRegistrySigner {
    public static func sign(_ registry: SignedInstitutionRegistry, privateKey: P256.Signing.PrivateKey) throws -> InstitutionRegistryEnvelope {
        let payload = try InstitutionRegistryCodec.encoder().encode(registry)
        let signature = try privateKey.signature(for: payload)
        return InstitutionRegistryEnvelope(payload: payload, signature: signature.rawRepresentation)
    }

    /// The envelope as the bytes that ship in the app bundle or over the wire.
    public static func encode(_ envelope: InstitutionRegistryEnvelope) throws -> Data {
        try InstitutionRegistryCodec.encoder().encode(envelope)
    }
}

/// Chooses between a freshly fetched envelope and the bundled fallback (security.md
/// §3.2.1). The fetched candidate must pass every check, including rollback against
/// `cachedVersion`; the bundled copy only needs a valid signature and `minAppVersion` — see
/// `InstitutionRegistryVerifier.verify`'s `enforceExpiry`/`cachedVersion` doc.
public enum InstitutionRegistryLoader {
    public struct Loaded: Sendable, Equatable { public let registry: SignedInstitutionRegistry; public let usedBundledFallback: Bool }

    /// - Throws: only if the **bundled** copy itself fails to verify — that copy ships
    ///   inside the signed app binary, so this should never happen outside a corrupted
    ///   build; callers should treat it as "the app has no institution list at all".
    public static func load(fetched: Data?, bundled: Data, publicKey: P256.Signing.PublicKey, now: Date,
                            cachedVersion: Int?, currentAppVersion: SemanticVersion) throws(InstitutionRegistryError) -> Loaded {
        if let fetched, let registry = try? InstitutionRegistryVerifier.verify(
            fetched, publicKey: publicKey, now: now, cachedVersion: cachedVersion, currentAppVersion: currentAppVersion
        ) {
            return Loaded(registry: registry, usedBundledFallback: false)
        }
        let bundledRegistry = try InstitutionRegistryVerifier.verify(
            bundled, publicKey: publicKey, now: now, cachedVersion: nil, enforceExpiry: false, currentAppVersion: currentAppVersion
        )
        return Loaded(registry: bundledRegistry, usedBundledFallback: true)
    }
}

extension ClientRegistry {
    /// Adapter (WP-SEC-12 "integrate with the existing `ClientRegistry`"): builds the
    /// in-memory lookup table `CanvasClient`/`InstitutionDirectory` already use from a
    /// verified registry, so nothing downstream of sign-in needs to know the registry is
    /// signed at all.
    public init(_ registry: SignedInstitutionRegistry) {
        self.init(registry.entries.map {
            ClientRegistration(host: $0.host, clientID: $0.clientID, clientType: $0.clientType, familyCapable: $0.familyCapable)
        })
    }
}
