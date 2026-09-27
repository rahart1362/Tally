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
        .target(
            name: "TallyPlatform",
            dependencies: [
                .product(name: "TallyDomain", package: "TallyCore"),
            ]
        ),

        // SwiftUI screens + @Observable models. MainActor by default
        // (SE-0466 / architecture.md §3.1: "TallyFeatures ... .defaultIsolation(MainActor.self)").
        // Deliberately does NOT depend on TallyPlatform: "Features never
        // import TallyPlatform; the app's composition root injects adapters
        // through protocols" (architecture.md §3.1).
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
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // AppIntents + AppEntity types, shared by the app and the widget.
        .target(
            name: "TallyIntents",
            dependencies: [
                .product(name: "TallyDomain", package: "TallyCore"),
            ]
        ),
    ]
)
