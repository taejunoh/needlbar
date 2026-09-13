// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Needlbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Needlbar", targets: ["Needlbar"]),
        .executable(name: "NeedlbarSettingsStudioReview", targets: ["NeedlbarSettingsStudioReview"]),
        .executable(name: "NeedlbarClaudeAPIBalanceFeasibility", targets: ["NeedlbarClaudeAPIBalanceFeasibility"]),
        .library(name: "NeedlbarCore", targets: ["NeedlbarCore"]),
        .library(name: "NeedlbarApp", targets: ["NeedlbarApp"]),
    ],
    targets: [
        .target(
            name: "CNeedlbar",
            path: "Sources/CNeedlbar",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(
                    ["-L", "target/release", "-lneedlbar_bridge"],
                    .when(platforms: [.macOS])
                )
            ]
        ),
        .target(
            name: "NeedlbarCore",
            dependencies: ["CNeedlbar", "NeedlbarWidgetSupport"],
            linkerSettings: [.linkedFramework("IOKit", .when(platforms: [.macOS]))]
        ),
        .target(
            name: "NeedlbarApp",
            dependencies: ["NeedlbarCore", "CNeedlbar"],
            path: "Sources/Needlbar",
            resources: [.copy("Resources/ProviderBrands")]
        ),
        .target(name: "NeedlbarWidgetSupport"),
        .target(name: "NeedlbarSettingsStudioReviewSupport", dependencies: ["NeedlbarApp", "NeedlbarCore"]),
        .target(name: "NeedlbarClaudeAPIBalanceFeasibilitySupport"),
        .executableTarget(name: "Needlbar", dependencies: ["NeedlbarApp"], path: "Sources/NeedlbarMain"),
        .executableTarget(name: "NeedlbarSettingsStudioReview", dependencies: ["NeedlbarApp", "NeedlbarCore", "NeedlbarSettingsStudioReviewSupport"], path: "Sources/NeedlbarSettingsStudioReview"),
        .executableTarget(
            name: "NeedlbarClaudeAPIBalanceFeasibility",
            dependencies: ["NeedlbarClaudeAPIBalanceFeasibilitySupport"],
            path: "Sources/NeedlbarClaudeAPIBalanceFeasibility",
            linkerSettings: [.linkedFramework("WebKit", .when(platforms: [.macOS]))]
        ),
        .testTarget(name: "NeedlbarCoreTests", dependencies: ["NeedlbarCore", "NeedlbarWidgetSupport"]),
        .testTarget(name: "NeedlbarTests", dependencies: ["NeedlbarApp", "NeedlbarSettingsStudioReviewSupport"]),
        .testTarget(name: "NeedlbarWidgetSupportTests", dependencies: ["NeedlbarWidgetSupport"]),
        .testTarget(name: "NeedlbarClaudeAPIBalanceFeasibilitySupportTests", dependencies: ["NeedlbarClaudeAPIBalanceFeasibilitySupport"]),
    ]
)
