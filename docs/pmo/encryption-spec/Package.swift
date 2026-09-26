// swift-tools-version: 6.0
// ASSESSMENT HARNESS ONLY. In the real repo, replace the local "Crypto" shim target with
// .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
import PackageDescription
let package = Package(
    name: "VaultSpec",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "CLibCrypto", linkerSettings: [.linkedLibrary("crypto")]),
        .target(name: "Crypto", dependencies: ["CLibCrypto"]),
        .target(name: "TallyVault", dependencies: [.target(name: "Crypto", condition: .when(platforms: [.linux]))]),
        .testTarget(name: "TallyVaultTests", dependencies: ["TallyVault", .target(name: "Crypto", condition: .when(platforms: [.linux]))]),
    ]
)
