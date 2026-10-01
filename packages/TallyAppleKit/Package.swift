// swift-tools-version: 6.2
// TallyAppleKit: the iOS-only half of Tally (architecture.md §3.1, WP-E01).
// Everything that decides something lives in TallyCore (Linux-testable);
// this package is thin adapters, SwiftUI screens and App Intents. Nothing
// here may be imported by TallyCore.
import PackageDescription

let package = Package(
    name: "TallyAppleKit",
    // Plan 08 L10N-01: SwiftPM requires a default localization once a target has localized
    // resources (TallyStrings' String Catalog). English is the development language.
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "TallyDesignSystem", targets: ["TallyDesignSystem"]),
        .library(name: "TallyPlatform", targets: ["TallyPlatform"]),
        .library(name: "TallyFeatures", targets: ["TallyFeatures"]),
        .library(name: "TallyIntents", targets: ["TallyIntents"]),
        .library(name: "TallyGlance", targets: ["TallyGlance"]),
        .library(name: "TallyStrings", targets: ["TallyStrings"]),
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
                // Plan 06 A4: `UNNotificationScheduler` conforms to TallySync's
                // `NotificationScheduling`, the port `NotificationReconciler` drives
                // (architecture.md §3.1: TallySync <- TallyPlatform is an expected edge).
                .product(name: "TallySync", package: "TallyCore"),
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
        // TallyReplay (plan 06 A1): "Explore with Sample Data" (ASC-14) needs a replay-backed
        // CanvasGateway over the bundled flagship persona. `TallyReplay.ReplayTransport` is that
        // transport and nothing more: routes plus a root URL, which the sample-data code gets from
        // `TallySampleFixtures` (below). It replaced the TallyTestSupport dependency, so no test
        // code (fixture loaders, `try!`, `#filePath`, fakes) links into the shipping app; CI's
        // link-map gate checks that.
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
                .product(name: "TallyReplay", package: "TallyCore"),
                "TallySampleFixtures",
                // perf-app-runtime.md §7 step 1: `AppModel` sets and clears
                // `RefreshIntentBridge` when it attaches to or detaches from an account's
                // coordinator, instead of `TallyApp.body` doing it as a side effect. The widget
                // links TallyIntents only, so this edge never pulls TallyFeatures into it.
                "TallyIntents",
                // Plan 08 L10N-01: every user-facing string (L10n), the locale-aware formatters.
                "TallyStrings",
            ],
            // No resources here (plan 06 A2): the accessor SwiftPM and Xcode generate for a target
            // with resources declares a class, which this module's default isolation turned into
            // an isolated deinit (`swift_task_deinitOnExecutor`, CI run 36390172728). The sample
            // fixtures live in `TallySampleFixtures` instead.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // ASC-14's bundled sample fixtures (the flagship persona and the 404 fallback) and the
        // one function that finds them. Swift's default isolation (nonisolated), deliberately: see
        // the note on TallyFeatures above. `CanvasFixtures` is one top-level directory, because
        // `.copy(_:)` places a resource "as-is... at the top level of the resulting bundle"
        // (Apple's package-resources documentation), so no intermediate path prefix is in doubt.
        .target(
            name: "TallySampleFixtures",
            resources: [.copy("CanvasFixtures")]
        ),

        // Plan 06 step 11 (M2-C2): the widgets' glance reader, timeline and views. It reads
        // `glance.v1.sealed` and nothing else, through TallyStore, with a widget-audience key it
        // may not create (perf-app-runtime.md §2.4 W1-W3). Deliberately none of TallyFeatures,
        // TallyPlatform, TallySync, TallyCanvasAPI or TallyIntents: nothing here can decode the
        // snapshot, fetch, refresh or read a credential. CI checks the Release widget's link map
        // and the Debug widget's load commands (scripts/ci/check_widget_isolation.py). Default
        // isolation (nonisolated): WidgetKit calls the provider off the main thread.
        .target(
            name: "TallyGlance",
            dependencies: [
                "TallyDesignSystem",
                .product(name: "TallyDomain", package: "TallyCore"),
                .product(name: "TallyStore", package: "TallyCore"),
                // Plan 08 L10N-01: the shared strings and formatters (Foundation only; the widget
                // isolation gate allows it).
                "TallyStrings",
            ]
        ),

        // AppIntents + AppEntity types, shared by the app and the widget.
        // Depends on TallySync (architecture.md §3.1 graph) so "Refresh Tally"
        // can reach the same `RefreshCoordinator` the app uses (WP E04/E06).
        .target(
            name: "TallyIntents",
            dependencies: [
                .product(name: "TallyDomain", package: "TallyCore"),
                .product(name: "TallySync", package: "TallyCore"),
                // Plan 08 L10N-01: the shared strings (intent titles and phrases move here).
                "TallyStrings",
            ]
        ),

        // Plan 08 §3.1 (L10N-01): the one String Catalog shared by the app, the widget and the
        // intents (`Resources/Localizable.xcstrings`), the public `L10n` wrappers over its keys,
        // `TallyFormat` (locale-aware number, time and list formatting) and `TallyLocale` (the
        // formatting locale). Foundation and TallyDomain only (plan 08 §3.2, L10N-02: the
        // renderers in `Render/` phrase TallyDomain's structured values, such as
        // `NotificationMessage`), so the widget may link it: TallyDomain is in the widget already
        // (TallyGlance), and neither is on scripts/ci/check_widget_isolation.py's forbidden list.
        // Default isolation (nonisolated), deliberately, like TallySampleFixtures: the resource
        // accessor SwiftPM generates declares a class, which under TallyFeatures' MainActor
        // default isolation gained an isolated deinit (plan 06 A2). The only allowed source of
        // UI strings: scripts/ci/check_localizable_literals.py does not scan it.
        .target(
            name: "TallyStrings",
            dependencies: [
                .product(name: "TallyDomain", package: "TallyCore"),
            ],
            resources: [.process("Resources")]
        ),
    ]
)
