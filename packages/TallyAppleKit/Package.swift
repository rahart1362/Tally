// swift-tools-version: 6.2
// TallyAppleKit: the iOS-only half of Tally (architecture.md §3.1, WP-E01).
// Everything that decides something lives in TallyCore (Linux-testable);
// this package is thin adapters, SwiftUI screens and App Intents. Nothing
// here may be imported by TallyCore.
import PackageDescription

let package = Package(
    name: "TallyAppleKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TallyDesignSystem", targets: ["TallyDesignSystem"]),
        .library(name: "TallyPlatform", targets: ["TallyPlatform"]),
        .library(name: "TallyFeatures", targets: ["TallyFeatures"]),
        .library(name: "TallyIntents", targets: ["TallyIntents"]),
    ],
    dependencies: [
        .package(path: "../TallyCore"),
    ],
    targets: [
        // Tokens + components. No TallyCore dependency: pure presentation.
        .target(
            name: "TallyDesignSystem",
            resources: [.process("Resources")]
        ),

        // Platform adapters (architecture.md §3.1). Depends on TallyDomain
        // for TallyConfig, so every tunable still has exactly one source.
        // Also depends on TallyCanvasAPI (HTTPTransport/CredentialStore ports,
        // for URLSessionTransport/KeychainCredentialStore) and TallyStore
        // (VaultKeyStore/SnapshotSealer, for KeychainVaultKeyStore) — both
        // Foundation-only ports that this package's Apple-only adapters
        // conform to (M2 platform-adapters batch). Also depends on
        // TallyFeatures (UX-WP-09): `WebAuthPresenter` conforms to
        // `WebAuthPresenting`, a port TallyFeatures declares. This is the
        // direction architecture.md §3.1 permits — "Features never import
        // TallyPlatform" says nothing against the reverse.
        .target(
            name: "TallyPlatform",
            dependencies: [
                .product(name: "TallyDomain", package: "TallyCore"),
                .product(name: "TallyCanvasAPI", package: "TallyCore"),
                .product(name: "TallyStore", package: "TallyCore"),
                "TallyFeatures",
            ]
        ),

        // SwiftUI screens + @Observable models. MainActor by default
        // (SE-0466 / architecture.md §3.1: "TallyFeatures ... .defaultIsolation(MainActor.self)").
        // Deliberately does NOT depend on TallyPlatform: "Features never
        // import TallyPlatform; the app's composition root injects adapters
        // through protocols" (architecture.md §3.1).
        //
        // Dependency graph (architecture.md §3.1): "TallyStore <- TallySync <-
        // TallyPlatform/TallyFeatures/TallyIntents" — TallyCanvasAPI, TallyStore
        // and TallySync are therefore expected edges, not a deviation.
        //
        // TallyTestSupport is the one addition beyond that graph (disclosed,
        // WP ASC-14): "Explore with Sample Data" needs a replay-backed
        // CanvasGateway over the bundled flagship persona, and
        // `TallyTestSupport.ReplayTransport`/`RouteFixture` are the already-
        // merged, already-tested pieces that do exactly that (architecture.md
        // §3.1 lists `ReplayTransport` under `TallyTestSupport` precisely for
        // Linux/demo replay). The app never ships `TallyTestSupport`'s fixture
        // *loader* (`Fixtures.root()`, which resolves a source-tree path that
        // does not exist on a device) — only `ReplayTransport` itself, driven
        // by routes and a root URL the sample-data code resolves via
        // `Bundle.module` from this target's own `CanvasFixtures` resource
        // (below), not the app's `project.yml`.
        .target(
            name: "TallyFeatures",
            dependencies: [
                "TallyDesignSystem",
                .product(name: "TallyDomain", package: "TallyCore"),
                // UX-WP-08/09: InstitutionDirectory, ClientRegistry, AuthorizationRequest,
                // OAuthCallback, TokenEndpoint, TokenCoordinator, CanvasClient. This is the
                // shared, Linux-testable Canvas layer (part of "TallyCore" per architecture.md
                // §3.1), not a platform adapter, so features depending on it directly is the
                // same shape as the existing TallyDomain dependency above.
                .product(name: "TallyCanvasAPI", package: "TallyCore"),
                .product(name: "TallyStore", package: "TallyCore"),
                .product(name: "TallySync", package: "TallyCore"),
                .product(name: "TallyTestSupport", package: "TallyCore"),
            ],
            // A single top-level directory under this target's source root, deliberately —
            // `.copy(_:)` places a resource "as-is... at the top level of the resulting bundle"
            // (Apple's package-resources documentation), so naming it one level deep here avoids
            // any ambiguity about whether an intermediate path prefix survives into the bundle.
            resources: [.copy("CanvasFixtures")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // AppIntents + AppEntity types, shared by the app and the widget.
        // Depends on TallySync (architecture.md §3.1 graph) so "Refresh Tally"
        // can reach the same `RefreshCoordinator` the app uses (WP E04/E06).
        .target(
            name: "TallyIntents",
            dependencies: [
                .product(name: "TallyDomain", package: "TallyCore"),
                .product(name: "TallySync", package: "TallyCore"),
            ]
        ),
    ]
)
