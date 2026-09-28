// swift-tools-version: 6.2
// Offline signing tool for the institution registry (security.md WP-SEC-12). Run by hand,
// on the maintainer's own machine, never in CI: the private key never touches the repo or
// a CI runner (only the *public* key is compiled into the app). A sibling package rather
// than a target inside `packages/TallyCore/Package.swift`, so shipping this tool never
// touches that package's manifest — it depends on it only by local path, to reuse the
// exact signing/verification code (`InstitutionRegistrySigner`, `SignedInstitutionRegistry`)
// instead of a second, hand-rolled implementation that could drift from the verifier.
import PackageDescription

let package = Package(
    name: "sign-institution-registry",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../packages/TallyCore"),
    ],
    targets: [
        .executableTarget(name: "sign-institution-registry", dependencies: [
            .product(name: "TallyCanvasAPI", package: "TallyCore"),
        ]),
    ]
)
