// Offline signing tool for Tally's institution registry (docs/pmo/reviews/security.md
// §3.2.1, WP-SEC-12). Run by hand on the maintainer's own machine — never in CI, and the
// private key is never committed to the repo (only the public key is compiled into the app).
//
// Usage:
//   sign-institution-registry generate-key <path-prefix>
//       Writes <path-prefix>.private.pem (keep offline, e.g. in a password manager) and
//       <path-prefix>.public.pem (compile this one into the app).
//
//   sign-institution-registry sign --key <private-key.pem> --in <registry.json> --out <signed.json>
//       <registry.json> is the *unsigned* payload: {"version", "issuedAt", "expiresAt"
//       (both Unix seconds), "minAppVersion", "entries": [{"host","clientID","clientType"
//       ("publicPKCE"),"familyCapable"}]}. Writes the signed envelope to <signed.json> —
//       this is the file that ships bundled in the app and is served from the CDN.
//
//   sign-institution-registry verify --key <public-key.pem> --in <signed.json> --app-version <X.Y.Z>
//       A self-check before publishing: confirms the envelope verifies (signature, not
//       expired, `minAppVersion` satisfied) against the given public key, with no rollback
//       check (there is no "cached" version at this point).

import Foundation
import TallyCanvasAPI
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case io(String)

    var description: String {
        switch self {
        case .usage(let message), .io(let message): message
        }
    }
}

func readFile(_ path: String) throws -> Data {
    guard let data = FileManager.default.contents(atPath: path) else {
        throw ToolError.io("Can't read \(path)")
    }
    return data
}

func writeFile(_ data: Data, to path: String) throws {
    guard FileManager.default.createFile(atPath: path, contents: data) else {
        throw ToolError.io("Can't write \(path)")
    }
}

func flagValue(_ name: String, in arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
        throw ToolError.usage("Missing \(name) <value>")
    }
    return arguments[index + 1]
}

func generateKey(prefix: String) throws {
    let privateKey = P256.Signing.PrivateKey()
    try privateKey.pemRepresentation.write(toFile: "\(prefix).private.pem", atomically: true, encoding: .utf8)
    try privateKey.publicKey.pemRepresentation.write(toFile: "\(prefix).public.pem", atomically: true, encoding: .utf8)
    print("Wrote \(prefix).private.pem (keep this offline) and \(prefix).public.pem (compile into the app).")
}

func sign(keyPath: String, inputPath: String, outputPath: String) throws {
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let registry = try InstitutionRegistryCodec.decoder().decode(SignedInstitutionRegistry.self, from: try readFile(inputPath))
    let envelope = try InstitutionRegistrySigner.sign(registry, privateKey: privateKey)
    try writeFile(try InstitutionRegistrySigner.encode(envelope), to: outputPath)
    print("Signed version \(registry.version) (\(registry.entries.count) entries) -> \(outputPath)")
}

func verify(keyPath: String, inputPath: String, appVersionText: String) throws {
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let publicKey = try P256.Signing.PublicKey(pemRepresentation: pem)
    guard let appVersion = SemanticVersion(appVersionText) else {
        throw ToolError.usage("--app-version must look like 1.2.3")
    }
    let registry = try InstitutionRegistryVerifier.verify(
        try readFile(inputPath), publicKey: publicKey, now: Date(), currentAppVersion: appVersion)
    print("OK: version \(registry.version), \(registry.entries.count) entries, expires \(registry.expiresAt).")
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "generate-key":
        guard arguments.count == 2 else { throw ToolError.usage("generate-key <path-prefix>") }
        try generateKey(prefix: arguments[1])
    case "sign":
        try sign(keyPath: try flagValue("--key", in: arguments),
                 inputPath: try flagValue("--in", in: arguments),
                 outputPath: try flagValue("--out", in: arguments))
    case "verify":
        try verify(keyPath: try flagValue("--key", in: arguments),
                   inputPath: try flagValue("--in", in: arguments),
                   appVersionText: try flagValue("--app-version", in: arguments))
    default:
        throw ToolError.usage("Usage: sign-institution-registry <generate-key|sign|verify> ...")
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}
