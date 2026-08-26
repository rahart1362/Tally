// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TallyPackages",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TallyAppFeature", targets: ["TallyAppFeature"]),
        .library(name: "TallyDesignSystem", targets: ["TallyDesignSystem"]),
        .library(name: "TallyDomain", targets: ["TallyDomain"]),
        .library(name: "TallyData", targets: ["TallyData"]),
        .library(name: "TallyCanvasKit", targets: ["TallyCanvasKit"]),
        .library(name: "TallyCalendarSync", targets: ["TallyCalendarSync"]),
        .library(name: "TallyNotifications", targets: ["TallyNotifications"]),
        .library(name: "TallyCache", targets: ["TallyCache"]),
        .library(name: "TallyObservability", targets: ["TallyObservability"]),
        .library(name: "TallySecurity", targets: ["TallySecurity"]),
        .library(name: "TallyTestingKit", targets: ["TallyTestingKit"])
    ],
    dependencies: [],
    targets: [
        .target(name: "TallyDesignSystem", path: "packages/TallyDesignSystem/Sources"),
        .target(name: "TallyDomain", path: "packages/TallyDomain/Sources"),
        .target(name: "TallySecurity", path: "packages/TallySecurity/Sources"),
        .target(name: "TallyObservability", path: "packages/TallyObservability/Sources"),
        .target(name: "TallyCache", dependencies: ["TallySecurity", "TallyObservability"], path: "packages/TallyCache/Sources"),
        .target(name: "TallyCanvasKit", dependencies: ["TallyDomain", "TallySecurity", "TallyObservability"], path: "packages/TallyCanvasKit/Sources"),
        .target(name: "TallyData", dependencies: ["TallyDomain", "TallyCache", "TallyCanvasKit", "TallyObservability"], path: "packages/TallyData/Sources"),
        .target(name: "TallyCalendarSync", dependencies: ["TallyDomain", "TallyObservability"], path: "packages/TallyCalendarSync/Sources"),
        .target(name: "TallyNotifications", dependencies: ["TallyDomain", "TallyObservability"], path: "packages/TallyNotifications/Sources"),
        .target(name: "TallyAppFeature", dependencies: [
            "TallyDesignSystem", "TallyDomain", "TallyData", "TallyCalendarSync", "TallyNotifications", "TallyObservability"
        ], path: "packages/TallyAppFeature/Sources"),
        .target(name: "TallyTestingKit", dependencies: ["TallyDomain"], path: "packages/TallyTestingKit/Sources")
    ]
)
