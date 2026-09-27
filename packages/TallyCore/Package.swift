// swift-tools-version: 6.2
// TallyCore: platform-agnostic core of Tally (PMO ruling R1).
// Foundation only; builds and tests on Linux (swift:6.4 container) and on
// Xcode 26.6+. Nothing here may import UIKit, SwiftUI, or any Apple-only
// framework. Those adapters live in the iOS-only TallyAppleKit package.
import PackageDescription

let package = Package(
    name: "TallyCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "TallyDomain", targets: ["TallyDomain"]),
        .library(name: "TallyCanvasAPI", targets: ["TallyCanvasAPI"]),
        .library(name: "TallyStore", targets: ["TallyStore"]),
        .library(name: "TallySync", targets: ["TallySync"]),
        .library(name: "TallyTestSupport", targets: ["TallyTestSupport"]),
    ],
    dependencies: [
        // Linux test lane only: Apple's swift-crypto mirrors CryptoKit's API.
        // iOS/macOS builds use the system CryptoKit (encryption.md, WP-ENC-07).
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        // Dependency direction (architecture.md §3.1):
        // TallyDomain <- TallyCanvasAPI, TallyStore <- TallySync
        .target(name: "TallyDomain"),
        .target(name: "TallyCanvasAPI", dependencies: [
            "TallyDomain",
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
        ]),
        .target(name: "TallyStore", dependencies: ["TallyDomain"]),
        .target(name: "TallySync", dependencies: ["TallyDomain", "TallyCanvasAPI", "TallyStore"]),
        .target(name: "TallyTestSupport", dependencies: ["TallyDomain", "TallyCanvasAPI", "TallyStore"]),

        .testTarget(name: "TallyDomainTests", dependencies: ["TallyDomain", "TallyTestSupport"]),
        .testTarget(name: "TallyCanvasAPITests", dependencies: ["TallyCanvasAPI", "TallyTestSupport"]),
        .testTarget(name: "TallyStoreTests", dependencies: ["TallyStore", "TallyTestSupport"]),
        .testTarget(name: "TallySyncTests", dependencies: ["TallySync", "TallyTestSupport"]),
    ]
)
